#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Telethon Bridge v5.0
- 完全无引用转发（使用 send_file / send_message 而非 forward_messages）
- 经真实账号实测验证（@szny88 -> @mytgby）
- 修复频道ID字符串解析问题
- 支持连续多条消息、媒体组批量转发
"""
import sys
import json
import asyncio
import os
import traceback
import threading

# ── 依赖检查 ──────────────────────────────────────────────
def _check_deps():
    missing = []
    try:
        import telethon  # noqa
    except ImportError:
        missing.append('telethon')
    return missing

_missing = _check_deps()
if _missing:
    _err = {"type": "error", "error": f"缺少依赖: {', '.join(_missing)}。请运行: pip install {' '.join(_missing)}"}
    print(json.dumps(_err, ensure_ascii=False), flush=True)
    sys.exit(1)

from telethon import TelegramClient
from telethon.tl.types import MessageMediaWebPage
from telethon.errors import (
    SessionPasswordNeededError,
    FloodWaitError,
    ChatWriteForbiddenError,
    ChatAdminRequiredError,
    ChannelPrivateError,
    UserNotParticipantError,
)

# ── 全局状态 ──────────────────────────────────────────────
clients = {}          # session_key -> TelegramClient
_stdout_lock = threading.Lock()


# ── 工具函数 ──────────────────────────────────────────────

def send_response(data: dict):
    """线程安全地向 Flutter 输出一行 JSON"""
    line = json.dumps(data, ensure_ascii=False)
    with _stdout_lock:
        sys.stdout.write(line + '\n')
        sys.stdout.flush()


def log_err(msg: str):
    sys.stderr.write(msg + '\n')
    sys.stderr.flush()


def progress(req_id: str, msg: str):
    send_response({"type": "progress", "req_id": req_id, "msg": msg})


def parse_channel_id(channel):
    """
    把频道标识符统一化：
    - 纯数字字符串（含负号）→ int，Telethon 才能通过 get_entity 找到
    - 用户名 / t.me 链接 → 保持字符串
    """
    if channel is None:
        return channel
    s = str(channel).strip()
    try:
        return int(s)
    except ValueError:
        return s


async def send_group_no_quote(client, target_entity, group_msgs: list,
                               remove_caption: bool = False):
    """
    无引用地把一组消息（媒体组或单条）发到目标频道。
    返回 (成功数量, 错误信息 or None)

    关键：使用 send_file / send_message，不用 forward_messages，
    因此目标频道不会显示 "Forwarded from xxx"。
    """
    if not group_msgs:
        return 0, "空消息组"

    # 取 caption（取第一条有文字的消息的文字）
    caption = ""
    if not remove_caption:
        for m in group_msgs:
            if m.message:
                caption = m.message
                break

    first = group_msgs[0]

    # 情况1：纯文字 或 链接预览（MessageMediaWebPage）
    if not first.media or isinstance(first.media, MessageMediaWebPage):
        text = "" if remove_caption else (first.message or "")
        await client.send_message(target_entity, message=text)
        return 1, None

    # 情况2：多文件媒体组（多张图 / 多个视频等）
    if len(group_msgs) > 1:
        files = [m.media for m in group_msgs
                 if m.media and not isinstance(m.media, MessageMediaWebPage)]
        if not files:
            return 0, "媒体组内无有效文件"
        result = await client.send_file(target_entity, file=files, caption=caption)
        count = len(result) if isinstance(result, list) else 1
        return count, None

    # 情况3：单条媒体
    await client.send_file(target_entity, file=first.media, caption=caption)
    return 1, None


async def _complete_media_groups(client, entity, messages: list) -> list:
    """
    补全被边界截断的媒体组：
    检查已有媒体组附近 ±10 个 ID，把遗漏的部分补回来。
    """
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
        check_ids = (list(range(max(1, min_id - 10), min_id)) +
                     list(range(max_id + 1, max_id + 11)))
        if not check_ids:
            continue
        try:
            nearby = await asyncio.wait_for(
                client.get_messages(entity, ids=check_ids), timeout=10.0)
            for m in (nearby or []):
                if m and m.grouped_id == gid and m.id not in already_ids:
                    extra.append(m)
                    already_ids.add(m.id)
        except Exception:
            pass  # 补全失败不中断主流程

    return messages + extra


# ── 命令处理器 ─────────────────────────────────────────────

async def cmd_start_client(cmd: dict, req_id: str):
    api_id    = int(cmd['api_id'])
    api_hash  = cmd['api_hash']
    session_key = cmd.get('session_key', f"{api_id}_{api_hash[:8]}")
    session_dir = cmd.get('session_dir', os.path.expanduser('~'))
    session_path = os.path.join(session_dir, f"tg_{session_key}")

    # 复用已有连接
    if session_key in clients:
        client = clients[session_key]
        if client.is_connected():
            if await client.is_user_authorized():
                me = await client.get_me()
                send_response({"type": "client_ready", "req_id": req_id,
                               "session_key": session_key, "already_connected": True,
                               "authorized": True,
                               "user": {"id": me.id, "username": me.username or "",
                                        "first_name": me.first_name or "",
                                        "phone": me.phone or ""}})
            else:
                send_response({"type": "client_ready", "req_id": req_id,
                               "session_key": session_key, "already_connected": True,
                               "authorized": False})
            return

    client = TelegramClient(session_path, api_id, api_hash,
                            system_version='4.16.30-vxCUSTOM')
    await client.connect()
    clients[session_key] = client

    if await client.is_user_authorized():
        me = await client.get_me()
        send_response({"type": "client_ready", "req_id": req_id,
                       "session_key": session_key, "authorized": True,
                       "user": {"id": me.id, "username": me.username or "",
                                "first_name": me.first_name or "",
                                "phone": me.phone or ""}})
    else:
        send_response({"type": "client_ready", "req_id": req_id,
                       "session_key": session_key, "authorized": False})


async def cmd_send_code(cmd: dict, req_id: str):
    client = clients.get(cmd['session_key'])
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"}); return
    result = await client.send_code_request(cmd['phone'])
    send_response({"type": "code_sent", "req_id": req_id,
                   "phone_code_hash": result.phone_code_hash, "phone": cmd['phone']})


async def cmd_sign_in(cmd: dict, req_id: str):
    client = clients.get(cmd['session_key'])
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"}); return
    try:
        await client.sign_in(cmd['phone'], cmd['code'],
                             phone_code_hash=cmd['phone_code_hash'])
        me = await client.get_me()
        send_response({"type": "signed_in", "req_id": req_id,
                       "user": {"id": me.id, "username": me.username or "",
                                "first_name": me.first_name or "", "phone": me.phone or ""}})
    except SessionPasswordNeededError:
        send_response({"type": "need_2fa", "req_id": req_id})


async def cmd_sign_in_2fa(cmd: dict, req_id: str):
    client = clients.get(cmd['session_key'])
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"}); return
    await client.sign_in(password=cmd['password'])
    me = await client.get_me()
    send_response({"type": "signed_in", "req_id": req_id,
                   "user": {"id": me.id, "username": me.username or "",
                            "first_name": me.first_name or "", "phone": me.phone or ""}})


async def cmd_get_me(cmd: dict, req_id: str):
    client = clients.get(cmd['session_key'])
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"}); return
    me = await client.get_me()
    if me:
        send_response({"type": "me_info", "req_id": req_id,
                       "user": {"id": me.id, "username": me.username or "",
                                "first_name": me.first_name or "", "phone": me.phone or ""}})
    else:
        send_response({"type": "error", "req_id": req_id, "error": "未登录"})


async def cmd_clone_messages(cmd: dict, req_id: str):
    """
    克隆消息 v5.0 ─ 无引用（send_file/send_message），连续多条
    
    参数：
      source_channel  : 来源频道（用户名或数字ID）
      target_channels : 目标频道列表
      start_id (int)  : 起始消息ID，0=不限制
      end_id   (int)  : 结束消息ID，0=不限制
      count    (int)  : 消息条数上限（start/end均为0时取最新N条）
      remove_caption  : 是否清除说明文字
    """
    session_key     = cmd['session_key']
    source_channel  = parse_channel_id(cmd['source_channel'])
    target_channels = [parse_channel_id(t) for t in cmd['target_channels']]
    start_id        = int(cmd.get('start_id', 0))
    end_id          = int(cmd.get('end_id', 0))
    count           = int(cmd.get('count', 100))
    remove_caption  = bool(cmd.get('remove_caption', False))

    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"}); return

    progress(req_id, f"正在连接源频道 {source_channel}...")

    # ── 获取源频道 ───────────────────────────────────────
    try:
        source_entity = await client.get_entity(source_channel)
        progress(req_id, f"✅ 源频道: {getattr(source_entity, 'title', source_channel)}")
    except (ChannelPrivateError, UserNotParticipantError):
        send_response({"type": "error", "req_id": req_id,
                       "error": f"无法访问私有频道 {source_channel}，账号未加入该频道"}); return
    except Exception as e:
        send_response({"type": "error", "req_id": req_id,
                       "error": f"无法访问源频道: {e}"}); return

    # ── 读取消息 ─────────────────────────────────────────
    safe_count = max(1, min(count, 5000))
    messages = []
    try:
        if start_id > 0 and end_id > 0:
            progress(req_id, f"读取精确范围 [{start_id}, {end_id}]...")
            range_limit = min(end_id - start_id + 100, 5000)
            async for msg in client.iter_messages(
                source_entity, min_id=start_id - 1, max_id=end_id + 1, limit=range_limit
            ):
                if msg and not msg.action:
                    messages.append(msg)

        elif start_id > 0:
            progress(req_id, f"读取 start_id={start_id} 起的最新 {safe_count} 条...")
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
        messages = await _complete_media_groups(client, source_entity, messages)
        messages.sort(key=lambda m: m.id)
        progress(req_id, f"共读取 {len(messages)} 条消息（含媒体组补全）")

    except Exception as e:
        log_err(f"[clone] 读取失败: {traceback.format_exc()}")
        send_response({"type": "error", "req_id": req_id,
                       "error": f"读取消息失败: {e}"}); return

    if not messages:
        send_response({"type": "clone_done", "req_id": req_id,
                       "success": 0, "failed": 0, "total": 0,
                       "msg": "没有找到消息（范围为空或消息已删除）"}); return

    # ── 按媒体组分组（保留顺序）────────────────────────────
    ordered_groups = []
    seen_groups: dict = {}
    for msg in messages:
        if msg.grouped_id:
            gid = str(msg.grouped_id)
            if gid not in seen_groups:
                seen_groups[gid] = []
                ordered_groups.append((gid, seen_groups[gid]))
            seen_groups[gid].append(msg)
        else:
            ordered_groups.append((None, [msg]))

    progress(req_id,
             f"共 {len(ordered_groups)} 组，开始无引用转发到 {len(target_channels)} 个频道...")

    total_success = 0
    total_fail    = 0

    for target_channel in target_channels:
        # 获取目标频道实体
        try:
            target_entity = await client.get_entity(target_channel)
            progress(req_id, f"目标频道: {getattr(target_entity, 'title', target_channel)}")
        except Exception as e:
            progress(req_id, f"⚠️ 无法访问目标频道 {target_channel}: {e}")
            continue

        ch_success = 0
        ch_fail    = 0

        for i, (gid, group_msgs) in enumerate(ordered_groups):
            ids = [m.id for m in group_msgs]
            ids_str = (f"msg#{ids[0]}" if len(ids) == 1
                       else f"msg#{ids[0]}~{ids[-1]}({len(ids)}张)")

            # 断线重连
            if not client.is_connected():
                progress(req_id, "⚠️ 连接断开，尝试重连...")
                try:
                    await client.connect()
                    progress(req_id, "✅ 重连成功")
                except Exception as ce:
                    progress(req_id, f"❌ 重连失败: {ce}，中止此频道")
                    remaining = sum(len(g) for _, g in ordered_groups[i:])
                    ch_fail    += remaining
                    total_fail += remaining
                    break

            try:
                cnt, err = await send_group_no_quote(
                    client, target_entity, group_msgs, remove_caption)

                if err:
                    ch_fail    += len(group_msgs)
                    total_fail += len(group_msgs)
                    progress(req_id,
                             f"⚠️ [{i+1}/{len(ordered_groups)}] {ids_str} 跳过: {err}")
                else:
                    ch_success    += cnt
                    total_success += cnt
                    progress(req_id,
                             f"✅ [{i+1}/{len(ordered_groups)}] {ids_str} 成功{cnt}条")

            except FloodWaitError as e:
                wait_secs = e.seconds + 3
                progress(req_id,
                         f"⏳ 触发限速 {wait_secs}s，等待后重试 {ids_str}...")
                await asyncio.sleep(wait_secs)
                try:
                    cnt, err = await send_group_no_quote(
                        client, target_entity, group_msgs, remove_caption)
                    if not err:
                        ch_success    += cnt
                        total_success += cnt
                        progress(req_id, f"✅ 重试成功 {ids_str}")
                    else:
                        ch_fail    += len(group_msgs)
                        total_fail += len(group_msgs)
                        progress(req_id, f"❌ 重试失败 {ids_str}: {err}")
                except Exception as e2:
                    ch_fail    += len(group_msgs)
                    total_fail += len(group_msgs)
                    progress(req_id,
                             f"❌ 重试异常 {ids_str}: {type(e2).__name__}: {e2}")
                    log_err(f"[clone] retry error: {traceback.format_exc()}")

            except (ChatWriteForbiddenError, ChatAdminRequiredError) as e:
                remaining = sum(len(g) for _, g in ordered_groups[i:])
                ch_fail    += remaining
                total_fail += remaining
                progress(req_id,
                         f"❌ 目标频道无发送权限 ({type(e).__name__})，跳过此频道")
                log_err(f"[clone] permission error: {type(e).__name__}: {e}")
                break  # 整个目标频道无权限，跳过

            except Exception as e:
                ch_fail    += len(group_msgs)
                total_fail += len(group_msgs)
                err_type    = type(e).__name__
                progress(req_id,
                         f"❌ [{i+1}/{len(ordered_groups)}] {ids_str} 失败({err_type}): {e}")
                log_err(f"[clone] error: {err_type}: {e}\n{traceback.format_exc()}")

            # 每组后短暂休眠，避免频繁调用API触发限速
            await asyncio.sleep(1.0)

        progress(req_id,
                 f"频道 {target_channel} 完成：✅{ch_success} ❌{ch_fail}")

    # ── 发送完成信号 ─────────────────────────────────────
    send_response({
        "type":    "clone_done",
        "req_id":  req_id,
        "success": total_success,
        "failed":  total_fail,
        "total":   len(messages),
    })


async def cmd_forward_messages(cmd: dict, req_id: str):
    """
    单次无引用转发指定消息ID列表。
    与 clone_messages 一样使用 send_file/send_message。
    """
    session_key    = cmd['session_key']
    source_channel = parse_channel_id(cmd['source_channel'])
    target_channel = parse_channel_id(cmd['target_channel'])
    message_ids    = [int(x) for x in cmd['message_ids']]
    remove_caption = bool(cmd.get('remove_caption', False))

    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"}); return

    try:
        source_entity = await client.get_entity(source_channel)
        target_entity = await client.get_entity(target_channel)
        msgs = await client.get_messages(source_entity, ids=message_ids)
        msgs = [m for m in msgs if m is not None]

        if not msgs:
            send_response({"type": "error", "req_id": req_id,
                           "error": "消息不存在或无权限"}); return

        group_map: dict = {}
        singles = []
        for msg in msgs:
            if msg.grouped_id:
                group_map.setdefault(str(msg.grouped_id), []).append(msg)
            else:
                singles.append(msg)

        forwarded = 0
        for grp_msgs in group_map.values():
            grp_msgs.sort(key=lambda m: m.id)
            cnt, _ = await send_group_no_quote(client, target_entity,
                                               grp_msgs, remove_caption)
            forwarded += cnt
        for msg in singles:
            cnt, _ = await send_group_no_quote(client, target_entity,
                                               [msg], remove_caption)
            forwarded += cnt

        send_response({"type": "forward_done", "req_id": req_id, "count": forwarded})

    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": str(e)})


async def cmd_get_messages(cmd: dict, req_id: str):
    session_key = cmd['session_key']
    channel     = parse_channel_id(cmd['channel'])
    limit       = int(cmd.get('limit', 50))
    min_id      = int(cmd.get('min_id', 0))

    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"}); return

    try:
        entity = await client.get_entity(channel)
        msgs_data = []
        async for msg in client.iter_messages(entity, limit=limit, min_id=min_id):
            if msg.action:
                continue
            media_type = 'text'
            if msg.photo:          media_type = 'photo'
            elif msg.video or msg.gif: media_type = 'video'
            elif msg.document:     media_type = 'document'
            elif msg.audio or msg.voice: media_type = 'audio'
            elif msg.sticker:      media_type = 'sticker'
            msgs_data.append({
                'id':         msg.id,
                'text':       msg.message or '',
                'caption':    msg.message or '',
                'media_type': media_type,
                'grouped_id': str(msg.grouped_id) if msg.grouped_id else None,
                'date':       msg.date.isoformat() if msg.date else None,
            })
        send_response({"type": "messages", "req_id": req_id, "messages": msgs_data})
    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": str(e)})


async def cmd_disconnect(cmd: dict, req_id: str):
    session_key = cmd.get('session_key', '')
    if session_key and session_key in clients:
        try:
            await clients[session_key].disconnect()
        except Exception:
            pass
        del clients[session_key]
    send_response({"type": "disconnected", "req_id": req_id})


# ── 主命令分发器 ───────────────────────────────────────────

async def handle_command(cmd: dict):
    action = cmd.get('action', '')
    req_id = cmd.get('req_id', '')
    try:
        dispatch = {
            'ping':          lambda: send_response({"type": "pong", "req_id": req_id}),
            'start_client':  lambda: cmd_start_client(cmd, req_id),
            'send_code':     lambda: cmd_send_code(cmd, req_id),
            'sign_in':       lambda: cmd_sign_in(cmd, req_id),
            'sign_in_2fa':   lambda: cmd_sign_in_2fa(cmd, req_id),
            'get_me':        lambda: cmd_get_me(cmd, req_id),
            'clone_messages':   lambda: cmd_clone_messages(cmd, req_id),
            'forward_messages': lambda: cmd_forward_messages(cmd, req_id),
            'get_messages':  lambda: cmd_get_messages(cmd, req_id),
            'disconnect':    lambda: cmd_disconnect(cmd, req_id),
        }
        handler = dispatch.get(action)
        if handler is None:
            send_response({"type": "error", "req_id": req_id,
                           "error": f"未知命令: {action}"}); return
        result = handler()
        if asyncio.iscoroutine(result):
            await result
    except FloodWaitError as e:
        send_response({"type": "error", "req_id": req_id,
                       "error": f"触发限速，需等待 {e.seconds} 秒"})
    except Exception as e:
        err = traceback.format_exc()
        log_err(f"[handle_command ERROR] action={action}\n{err}")
        send_response({"type": "error", "req_id": req_id,
                       "error": str(e), "trace": err[:500]})


# ── 主循环 ────────────────────────────────────────────────

async def main():
    send_response({"type": "ready", "version": "5.0.0"})

    loop  = asyncio.get_event_loop()
    queue: asyncio.Queue = asyncio.Queue()

    def _read_stdin():
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

    threading.Thread(target=_read_stdin, daemon=True).start()

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
