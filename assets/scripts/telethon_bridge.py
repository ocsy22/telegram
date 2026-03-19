#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Telethon Bridge v3.0 - 完全重写，彻底修复转发停止问题
"""
import sys
import json
import asyncio
import os
import traceback
import threading

# 先检查依赖
def check_deps():
    missing = []
    try:
        import telethon
    except ImportError:
        missing.append('telethon')
    return missing

missing = check_deps()
if missing:
    resp = {"type": "error", "error": f"缺少依赖: {', '.join(missing)}。请运行: pip install {' '.join(missing)}"}
    print(json.dumps(resp, ensure_ascii=False), flush=True)
    sys.exit(1)

from telethon import TelegramClient
from telethon.errors import (
    SessionPasswordNeededError, PhoneCodeInvalidError,
    PhoneNumberInvalidError, FloodWaitError, AuthKeyError,
    ChatWriteForbiddenError, UserNotParticipantError,
    ChannelPrivateError, ChatAdminRequiredError
)

# 存储活跃的客户端
clients = {}  # session_key -> TelegramClient

# 全局锁，保护 stdout 写入
_stdout_lock = threading.Lock()

def send_response(data: dict):
    """线程安全地发送JSON响应到Flutter"""
    line = json.dumps(data, ensure_ascii=False)
    with _stdout_lock:
        sys.stdout.write(line + '\n')
        sys.stdout.flush()

def log_err(msg: str):
    """写到stderr，Flutter会捕获显示"""
    sys.stderr.write(msg + '\n')
    sys.stderr.flush()

def progress(req_id, msg):
    """发送进度消息"""
    send_response({"type": "progress", "req_id": req_id, "msg": msg})


# ==================== 命令处理 ====================

async def handle_command(cmd: dict):
    action = cmd.get('action', '')
    req_id = cmd.get('req_id', '')
    try:
        if action == 'ping':
            send_response({"type": "pong", "req_id": req_id})
        elif action == 'start_client':
            await cmd_start_client(cmd, req_id)
        elif action == 'send_code':
            await cmd_send_code(cmd, req_id)
        elif action == 'sign_in':
            await cmd_sign_in(cmd, req_id)
        elif action == 'sign_in_2fa':
            await cmd_sign_in_2fa(cmd, req_id)
        elif action == 'get_me':
            await cmd_get_me(cmd, req_id)
        elif action == 'clone_messages':
            await cmd_clone_messages(cmd, req_id)
        elif action == 'forward_messages':
            await cmd_forward_messages(cmd, req_id)
        elif action == 'get_messages':
            await cmd_get_messages(cmd, req_id)
        elif action == 'disconnect':
            await cmd_disconnect(cmd, req_id)
        else:
            send_response({"type": "error", "req_id": req_id, "error": f"未知命令: {action}"})
    except FloodWaitError as e:
        send_response({"type": "error", "req_id": req_id, "error": f"触发限速，需等待{e.seconds}秒"})
    except Exception as e:
        err = traceback.format_exc()
        log_err(f"[handle_command ERROR] action={action}\n{err}")
        send_response({"type": "error", "req_id": req_id, "error": str(e), "trace": err[:500]})


async def cmd_start_client(cmd, req_id):
    api_id = int(cmd['api_id'])
    api_hash = cmd['api_hash']
    session_key = cmd.get('session_key', f"{api_id}_{api_hash[:8]}")
    session_dir = cmd.get('session_dir', os.path.expanduser('~'))
    session_path = os.path.join(session_dir, f"tg_{session_key}")

    if session_key in clients:
        client = clients[session_key]
        if client.is_connected():
            if await client.is_user_authorized():
                me = await client.get_me()
                send_response({"type": "client_ready", "req_id": req_id,
                               "session_key": session_key, "already_connected": True,
                               "authorized": True,
                               "user": {"id": me.id, "username": me.username or "",
                                        "first_name": me.first_name or "", "phone": me.phone or ""}})
            else:
                send_response({"type": "client_ready", "req_id": req_id,
                               "session_key": session_key, "already_connected": True, "authorized": False})
            return

    client = TelegramClient(session_path, api_id, api_hash, system_version='4.16.30-vxCUSTOM')
    await client.connect()
    clients[session_key] = client

    if await client.is_user_authorized():
        me = await client.get_me()
        send_response({"type": "client_ready", "req_id": req_id, "session_key": session_key,
                       "authorized": True,
                       "user": {"id": me.id, "username": me.username or "",
                                "first_name": me.first_name or "", "phone": me.phone or ""}})
    else:
        send_response({"type": "client_ready", "req_id": req_id,
                       "session_key": session_key, "authorized": False})


async def cmd_send_code(cmd, req_id):
    session_key = cmd['session_key']
    phone = cmd['phone']
    client = clients.get(session_key)
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"})
        return
    result = await client.send_code_request(phone)
    send_response({"type": "code_sent", "req_id": req_id,
                   "phone_code_hash": result.phone_code_hash, "phone": phone})


async def cmd_sign_in(cmd, req_id):
    session_key = cmd['session_key']
    client = clients.get(session_key)
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"})
        return
    try:
        await client.sign_in(cmd['phone'], cmd['code'], phone_code_hash=cmd['phone_code_hash'])
        me = await client.get_me()
        send_response({"type": "signed_in", "req_id": req_id,
                       "user": {"id": me.id, "username": me.username or "",
                                "first_name": me.first_name or "", "phone": me.phone or ""}})
    except SessionPasswordNeededError:
        send_response({"type": "need_2fa", "req_id": req_id})


async def cmd_sign_in_2fa(cmd, req_id):
    session_key = cmd['session_key']
    client = clients.get(session_key)
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"})
        return
    await client.sign_in(password=cmd['password'])
    me = await client.get_me()
    send_response({"type": "signed_in", "req_id": req_id,
                   "user": {"id": me.id, "username": me.username or "",
                            "first_name": me.first_name or "", "phone": me.phone or ""}})


async def cmd_get_me(cmd, req_id):
    session_key = cmd['session_key']
    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"})
        return
    me = await client.get_me()
    if me:
        send_response({"type": "me_info", "req_id": req_id,
                       "user": {"id": me.id, "username": me.username or "",
                                "first_name": me.first_name or "", "phone": me.phone or ""}})
    else:
        send_response({"type": "error", "req_id": req_id, "error": "未登录"})


async def cmd_clone_messages(cmd, req_id):
    """克隆消息主函数 v3.1 - 彻底修复转发逻辑"""
    session_key = cmd['session_key']
    source_channel = cmd['source_channel']
    target_channels = cmd['target_channels']
    start_id = int(cmd.get('start_id', 0))
    end_id = int(cmd.get('end_id', 0))
    count = int(cmd.get('count', 100))
    remove_caption = cmd.get('remove_caption', False)

    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"})
        return

    progress(req_id, f"正在读取源频道 {source_channel}...")

    # 获取源频道实体
    try:
        source_entity = await client.get_entity(source_channel)
    except ChannelPrivateError:
        send_response({"type": "error", "req_id": req_id,
                       "error": f"无法访问私有频道 {source_channel}，账号未加入"})
        return
    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": f"无法访问源频道: {e}"})
        return

    # ─────────────────── 读取消息 ───────────────────
    # 场景说明：
    # 1. start_id>0 且 end_id>0：精确范围 [start_id, end_id]，不受count限制
    # 2. start_id>0 且 end_id==0：从start_id开始取count条（ID升序）
    # 3. start_id==0 且 end_id>0：取end_id之前最新的count条
    # 4. 两者均为0：取最新的count条
    safe_count = max(1, min(count, 5000))  # 防止count<=0或过大

    messages = []
    try:
        if start_id > 0 and end_id > 0:
            progress(req_id, f"读取精确范围 [{start_id}, {end_id}]...")
            # 精确范围：获取所有在 [start_id, end_id] 内的消息
            # 不用count限制，因为用户明确指定了范围
            # 但加5000的安全上限防止意外
            range_max = min(end_id - start_id + 100, 5000)
            async for msg in client.iter_messages(
                source_entity,
                min_id=start_id - 1,
                max_id=end_id + 1,
                limit=range_max,
            ):
                if msg and not msg.action:
                    messages.append(msg)
        elif start_id > 0:
            progress(req_id, f"读取 start_id={start_id} 起的 {safe_count} 条...")
            # 从start_id开始，iter_messages默认倒序，需要反转
            # 用min_id过滤，取safe_count条（会是最新的safe_count条且ID >= start_id）
            async for msg in client.iter_messages(
                source_entity, min_id=start_id - 1, limit=safe_count
            ):
                if msg and not msg.action:
                    messages.append(msg)
        elif end_id > 0:
            progress(req_id, f"读取 end_id={end_id} 之前的 {safe_count} 条...")
            async for msg in client.iter_messages(
                source_entity, max_id=end_id + 1, limit=safe_count
            ):
                if msg and not msg.action:
                    messages.append(msg)
        else:
            progress(req_id, f"读取最新 {safe_count} 条...")
            async for msg in client.iter_messages(source_entity, limit=safe_count):
                if msg and not msg.action:
                    messages.append(msg)

        messages.sort(key=lambda m: m.id)

        # 补全被截断的媒体组（在消息获取后始终执行）
        messages = await _complete_media_groups(client, source_entity, messages)
        messages.sort(key=lambda m: m.id)

        progress(req_id, f"共 {len(messages)} 条消息（含媒体组补全）")

    except Exception as e:
        log_err(f"[clone] 读取消息失败: {traceback.format_exc()}")
        send_response({"type": "error", "req_id": req_id, "error": f"读取消息失败: {e}"})
        return

    if not messages:
        send_response({"type": "clone_done", "req_id": req_id,
                       "success": 0, "failed": 0, "total": 0,
                       "msg": "没有找到消息（范围为空或消息已删除）"})
        return

    progress(req_id, f"读取到 {len(messages)} 条，开始转发...")

    # 按媒体组分组（保留原始顺序）
    ordered_groups = []
    seen_groups = {}
    for msg in messages:
        if msg.grouped_id:
            gid = str(msg.grouped_id)
            if gid not in seen_groups:
                seen_groups[gid] = []
                ordered_groups.append((gid, seen_groups[gid]))
            seen_groups[gid].append(msg)
        else:
            ordered_groups.append((None, [msg]))

    progress(req_id, f"共 {len(ordered_groups)} 组，开始向 {len(target_channels)} 个目标频道转发...")

    total_success = 0
    total_fail = 0

    for target_channel in target_channels:
        try:
            target_entity = await client.get_entity(target_channel)
        except Exception as e:
            progress(req_id, f"⚠️ 无法访问目标频道 {target_channel}: {e}")
            continue

        ch_success = 0
        ch_fail = 0

        for i, (gid, group_msgs) in enumerate(ordered_groups):
            ids = [m.id for m in group_msgs]
            ids_str = f"msg#{ids[0]}" if len(ids) == 1 else f"msg#{ids[0]}~{ids[-1]}({len(ids)}张)"

            # 检查连接状态
            if not client.is_connected():
                progress(req_id, f"⚠️ 连接断开，尝试重连...")
                try:
                    await client.connect()
                    progress(req_id, "✅ 重连成功")
                except Exception as ce:
                    progress(req_id, f"❌ 重连失败: {ce}，跳过剩余消息")
                    ch_fail += sum(len(g) for _, g in ordered_groups[i:])
                    total_fail += ch_fail
                    break

            try:
                result = await client.forward_messages(
                    target_entity,
                    messages=ids,
                    from_peer=source_entity,
                )
                # forward_messages 返回 list，空列表表示失败（如禁止转发）
                if result:
                    ch_success += len(group_msgs)
                    total_success += len(group_msgs)
                    progress(req_id, f"✅ [{i+1}/{len(ordered_groups)}] {ids_str} → {target_channel}")
                else:
                    # 返回空列表通常是频道禁止转发，尝试用copy方式
                    progress(req_id, f"⚠️ {ids_str} forward返回空，频道可能禁止转发")
                    ch_fail += len(group_msgs)
                    total_fail += len(group_msgs)

            except FloodWaitError as e:
                wait_secs = e.seconds + 3
                progress(req_id, f"⏳ 触发限速，等待 {wait_secs}s 后重试 {ids_str}...")
                await asyncio.sleep(wait_secs)
                try:
                    result = await client.forward_messages(
                        target_entity, messages=ids, from_peer=source_entity)
                    if result:
                        ch_success += len(group_msgs)
                        total_success += len(group_msgs)
                        progress(req_id, f"✅ 重试成功 {ids_str}")
                    else:
                        ch_fail += len(group_msgs)
                        total_fail += len(group_msgs)
                        progress(req_id, f"❌ 重试返回空 {ids_str}")
                except Exception as e2:
                    ch_fail += len(group_msgs)
                    total_fail += len(group_msgs)
                    progress(req_id, f"❌ 重试失败 {ids_str}: {type(e2).__name__}: {e2}")
                    log_err(f"[clone] retry error: {traceback.format_exc()}")

            except (ChatWriteForbiddenError, ChatAdminRequiredError) as e:
                ch_fail += len(group_msgs)
                total_fail += len(group_msgs)
                err_type = type(e).__name__
                progress(req_id, f"❌ 目标频道 {target_channel} 无发送权限({err_type})，跳过剩余")
                log_err(f"[clone] permission error: {err_type}: {e}")
                break  # 该目标频道没有权限，跳过整个频道

            except Exception as e:
                ch_fail += len(group_msgs)
                total_fail += len(group_msgs)
                err_type = type(e).__name__
                progress(req_id, f"❌ [{i+1}/{len(ordered_groups)}] {ids_str} 失败({err_type}): {e}")
                log_err(f"[clone] forward error {i+1}/{len(ordered_groups)}: {err_type}: {e}\n{traceback.format_exc()}")

            # 每组转发后短暂延迟（1秒，给Telegram API足够缓冲）
            await asyncio.sleep(1.0)

        progress(req_id, f"频道 {target_channel} 完成：✅{ch_success} ❌{ch_fail}")

    # ★★★ 发送完成信号 ★★★
    send_response({
        "type": "clone_done",
        "req_id": req_id,
        "success": total_success,
        "failed": total_fail,
        "total": len(messages),
    })


async def _complete_media_groups(client, entity, messages: list) -> list:
    """补全边界处被截断的媒体组"""
    if not messages:
        return messages

    already_ids = {m.id for m in messages}
    grouped = {}
    for m in messages:
        if m.grouped_id:
            grouped.setdefault(m.grouped_id, []).append(m)

    if not grouped:
        return messages

    extra = []
    for gid, grp in grouped.items():
        min_id = min(m.id for m in grp)
        max_id = max(m.id for m in grp)
        check_ids = list(range(max(1, min_id - 10), min_id)) + \
                    list(range(max_id + 1, max_id + 11))
        if not check_ids:
            continue
        try:
            nearby = await asyncio.wait_for(
                client.get_messages(entity, ids=check_ids), timeout=10)
            for m in (nearby or []):
                if m and m.grouped_id == gid and m.id not in already_ids:
                    extra.append(m)
                    already_ids.add(m.id)
        except Exception:
            pass

    return messages + extra


async def cmd_forward_messages(cmd, req_id):
    session_key = cmd['session_key']
    source_channel = cmd['source_channel']
    target_channel = cmd['target_channel']
    message_ids = [int(x) for x in cmd['message_ids']]

    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"})
        return

    try:
        source_entity = await client.get_entity(source_channel)
        target_entity = await client.get_entity(target_channel)
        msgs = await client.get_messages(source_entity, ids=message_ids)
        msgs = [m for m in msgs if m is not None]

        if not msgs:
            send_response({"type": "error", "req_id": req_id, "error": "消息不存在或无权限"})
            return

        forwarded_count = 0
        group_map = {}
        single_msgs = []
        for msg in msgs:
            if msg.grouped_id:
                group_map.setdefault(str(msg.grouped_id), []).append(msg)
            else:
                single_msgs.append(msg)

        for gid, group_msgs in group_map.items():
            group_msgs.sort(key=lambda m: m.id)
            result = await client.forward_messages(
                target_entity, messages=[m.id for m in group_msgs], from_peer=source_entity)
            if result:
                forwarded_count += len(group_msgs)

        for msg in single_msgs:
            result = await client.forward_messages(
                target_entity, messages=[msg.id], from_peer=source_entity)
            if result:
                forwarded_count += 1

        send_response({"type": "forward_done", "req_id": req_id, "count": forwarded_count})

    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": str(e)})


async def cmd_get_messages(cmd, req_id):
    session_key = cmd['session_key']
    channel = cmd['channel']
    limit = int(cmd.get('limit', 50))
    min_id = int(cmd.get('min_id', 0))

    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"})
        return

    try:
        entity = await client.get_entity(channel)
        msgs_data = []
        async for msg in client.iter_messages(entity, limit=limit, min_id=min_id):
            if msg.action:
                continue
            media_type = 'text'
            if msg.photo:
                media_type = 'photo'
            elif msg.video or msg.gif:
                media_type = 'video'
            elif msg.document:
                media_type = 'document'
            elif msg.audio or msg.voice:
                media_type = 'audio'
            elif msg.sticker:
                media_type = 'sticker'
            msgs_data.append({
                'id': msg.id, 'text': msg.message or '',
                'caption': msg.message or '', 'media_type': media_type,
                'grouped_id': str(msg.grouped_id) if msg.grouped_id else None,
                'date': msg.date.isoformat() if msg.date else None,
            })
        send_response({"type": "messages", "req_id": req_id, "messages": msgs_data})
    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": str(e)})


async def cmd_disconnect(cmd, req_id):
    session_key = cmd.get('session_key', '')
    if session_key and session_key in clients:
        try:
            await clients[session_key].disconnect()
        except Exception:
            pass
        del clients[session_key]
    send_response({"type": "disconnected", "req_id": req_id})


# ==================== 主循环 ====================

async def main():
    send_response({"type": "ready", "version": "3.0.0"})

    loop = asyncio.get_event_loop()
    queue: asyncio.Queue = asyncio.Queue()

    def _read_stdin():
        """独立线程读stdin，不阻塞事件循环"""
        while True:
            try:
                line = sys.stdin.readline()
                if not line:
                    loop.call_soon_threadsafe(queue.put_nowait, None)
                    break
                line = line.strip()
                if line:
                    loop.call_soon_threadsafe(queue.put_nowait, line)
            except Exception as ex:
                log_err(f"[stdin thread error] {ex}")
                loop.call_soon_threadsafe(queue.put_nowait, None)
                break

    t = threading.Thread(target=_read_stdin, daemon=True)
    t.start()

    while True:
        line = await queue.get()
        if line is None:
            break
        try:
            cmd = json.loads(line)
            asyncio.ensure_future(handle_command(cmd))
        except json.JSONDecodeError as e:
            send_response({"type": "error", "error": f"JSON解析失败: {e}"})

    for client in clients.values():
        try:
            await client.disconnect()
        except Exception:
            pass


if __name__ == '__main__':
    asyncio.run(main())
