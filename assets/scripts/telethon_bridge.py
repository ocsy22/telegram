#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Telethon Bridge v2.0 - MTProto用户账号操作桥接服务
通过stdin/stdout与Flutter通信，每行一个JSON命令/响应
支持：私有频道读取、无引用转发、媒体组保持、AI润色文案传递
"""
import sys
import json
import asyncio
import os
import traceback

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
from telethon.tl.types import (
    MessageMediaPhoto, MessageMediaDocument,
)
import telethon.tl.types as tl_types

# 存储活跃的客户端
clients = {}  # session_key -> TelegramClient

def send_response(data: dict):
    """发送JSON响应到Flutter"""
    print(json.dumps(data, ensure_ascii=False), flush=True)

async def handle_command(cmd: dict):
    """处理来自Flutter的命令"""
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
        send_response({"type": "error", "req_id": req_id, "error": str(e), "trace": traceback.format_exc()[:500]})


async def cmd_start_client(cmd, req_id):
    """初始化Telethon客户端"""
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
                              "user": {
                                  "id": me.id,
                                  "username": me.username or "",
                                  "first_name": me.first_name or "",
                                  "phone": me.phone or ""
                              }})
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
        send_response({
            "type": "client_ready", "req_id": req_id,
            "session_key": session_key,
            "authorized": True,
            "user": {
                "id": me.id,
                "username": me.username or "",
                "first_name": me.first_name or "",
                "phone": me.phone or ""
            }
        })
    else:
        send_response({
            "type": "client_ready", "req_id": req_id,
            "session_key": session_key,
            "authorized": False
        })


async def cmd_send_code(cmd, req_id):
    """发送验证码"""
    session_key = cmd['session_key']
    phone = cmd['phone']
    client = clients.get(session_key)
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"})
        return
    
    result = await client.send_code_request(phone)
    send_response({
        "type": "code_sent", "req_id": req_id,
        "phone_code_hash": result.phone_code_hash,
        "phone": phone
    })


async def cmd_sign_in(cmd, req_id):
    """使用验证码登录"""
    session_key = cmd['session_key']
    phone = cmd['phone']
    code = cmd['code']
    phone_code_hash = cmd['phone_code_hash']
    client = clients.get(session_key)
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"})
        return
    
    try:
        await client.sign_in(phone, code, phone_code_hash=phone_code_hash)
        me = await client.get_me()
        send_response({
            "type": "signed_in", "req_id": req_id,
            "user": {
                "id": me.id,
                "username": me.username or "",
                "first_name": me.first_name or "",
                "phone": me.phone or ""
            }
        })
    except SessionPasswordNeededError:
        send_response({"type": "need_2fa", "req_id": req_id})


async def cmd_sign_in_2fa(cmd, req_id):
    """使用两步验证密码登录"""
    session_key = cmd['session_key']
    password = cmd['password']
    client = clients.get(session_key)
    if not client:
        send_response({"type": "error", "req_id": req_id, "error": "客户端未初始化"})
        return
    
    await client.sign_in(password=password)
    me = await client.get_me()
    send_response({
        "type": "signed_in", "req_id": req_id,
        "user": {
            "id": me.id,
            "username": me.username or "",
            "first_name": me.first_name or "",
            "phone": me.phone or ""
        }
    })


async def cmd_get_me(cmd, req_id):
    """获取当前用户信息"""
    session_key = cmd['session_key']
    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"})
        return
    
    me = await client.get_me()
    if me:
        send_response({
            "type": "me_info", "req_id": req_id,
            "user": {
                "id": me.id,
                "username": me.username or "",
                "first_name": me.first_name or "",
                "phone": me.phone or ""
            }
        })
    else:
        send_response({"type": "error", "req_id": req_id, "error": "未登录"})


def progress(req_id, msg):
    """发送进度消息"""
    send_response({"type": "progress", "req_id": req_id, "msg": msg})


async def cmd_clone_messages(cmd, req_id):
    """
    克隆消息：从源频道读取，无引用转发到目标频道
    支持媒体组自动识别和批量发送
    支持私有频道和公开频道
    """
    session_key = cmd['session_key']
    source_channel = cmd['source_channel']
    target_channels = cmd['target_channels']  # list
    start_id = int(cmd.get('start_id', 0))
    end_id = int(cmd.get('end_id', 0))
    count = int(cmd.get('count', 100))
    remove_caption = cmd.get('remove_caption', False)
    new_caption = cmd.get('new_caption')  # AI润色后的文案
    
    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"})
        return
    
    progress(req_id, f"正在连接源频道 {source_channel}...")
    
    try:
        source_entity = await client.get_entity(source_channel)
    except ChannelPrivateError:
        send_response({"type": "error", "req_id": req_id, 
                      "error": f"无法访问私有频道 {source_channel}，账号未加入该频道"})
        return
    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": f"无法访问源频道: {e}"})
        return
    
    # 获取消息列表
    messages = []
    try:
        progress(req_id, f"读取消息中（范围: {start_id}~{end_id or '最新'}, 最多{count}条）...")
        if start_id > 0 and end_id > 0:
            # 指定范围 - 注意：iter_messages是倒序的，min_id/max_id控制范围
            async for msg in client.iter_messages(
                source_entity, min_id=start_id-1, max_id=end_id+1, limit=None
            ):
                if msg and not msg.action:  # 跳过服务消息
                    messages.append(msg)
                if len(messages) >= 5000:  # 安全上限
                    break
        elif start_id > 0:
            async for msg in client.iter_messages(
                source_entity, min_id=start_id-1, limit=count
            ):
                if msg and not msg.action:
                    messages.append(msg)
        elif end_id > 0:
            async for msg in client.iter_messages(
                source_entity, max_id=end_id+1, limit=count
            ):
                if msg and not msg.action:
                    messages.append(msg)
        else:
            # 获取最新N条
            async for msg in client.iter_messages(source_entity, limit=count):
                if msg and not msg.action:
                    messages.append(msg)
        
        # 按消息ID升序排列（从旧到新）
        messages.sort(key=lambda m: m.id)
        
    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": f"读取消息失败: {e}"})
        return
    
    if not messages:
        send_response({"type": "clone_done", "req_id": req_id,
                      "success": 0, "failed": 0, "total": 0,
                      "msg": "没有找到消息（范围可能为空或消息已删除）"})
        return
    
    progress(req_id, f"读取到 {len(messages)} 条消息，开始转发...")
    
    # 按媒体组分组，保持原有顺序
    ordered_groups = []  # [(group_id_or_None, [messages])]
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
    
    success_count = 0
    fail_count = 0
    
    for target_channel in target_channels:
        try:
            target_entity = await client.get_entity(target_channel)
        except Exception as e:
            progress(req_id, f"⚠️ 无法访问目标频道 {target_channel}: {e}")
            continue
        
        for gid, group_msgs in ordered_groups:
            try:
                if gid:
                    # 媒体组：先尝试无引用转发，失败则降级为普通转发
                    try:
                        await client.forward_messages(
                            target_entity,
                            messages=group_msgs,
                            from_peer=source_entity,
                            drop_author=True,
                            drop_media_captions=remove_caption,
                        )
                    except (ChatAdminRequiredError, ChatWriteForbiddenError):
                        # 没有管理员权限，降级：普通转发（带来源）
                        await client.forward_messages(
                            target_entity,
                            messages=group_msgs,
                            from_peer=source_entity,
                            drop_media_captions=remove_caption,
                        )
                    success_count += len(group_msgs)
                    progress(req_id,
                             f"✅ 媒体组({len(group_msgs)}条) "
                             f"msg#{group_msgs[0].id}~{group_msgs[-1].id} → {target_channel}")
                else:
                    msg = group_msgs[0]
                    # 单条消息：先尝试无引用转发，失败则降级
                    try:
                        await client.forward_messages(
                            target_entity,
                            messages=[msg],
                            from_peer=source_entity,
                            drop_author=True,
                            drop_media_captions=remove_caption,
                        )
                    except (ChatAdminRequiredError, ChatWriteForbiddenError):
                        # 降级：普通转发
                        await client.forward_messages(
                            target_entity,
                            messages=[msg],
                            from_peer=source_entity,
                            drop_media_captions=remove_caption,
                        )
                    success_count += 1
                    progress(req_id, f"✅ msg#{msg.id} → {target_channel}")
                    
            except FloodWaitError as e:
                progress(req_id, f"⏳ 限速，等待{e.seconds}秒...")
                await asyncio.sleep(e.seconds + 2)
                # 重试一次（不用drop_author，避免再次失败）
                try:
                    if gid:
                        await client.forward_messages(
                            target_entity, messages=group_msgs,
                            from_peer=source_entity,
                            drop_media_captions=remove_caption)
                        success_count += len(group_msgs)
                    else:
                        msg = group_msgs[0]
                        await client.forward_messages(
                            target_entity, messages=[msg],
                            from_peer=source_entity,
                            drop_media_captions=remove_caption)
                        success_count += 1
                except Exception as e2:
                    fail_count += len(group_msgs)
                    progress(req_id, f"❌ 重试失败: {e2}")
                    
            except (ChatWriteForbiddenError, ChatAdminRequiredError) as e:
                # 权限错误只跳过当前条，继续处理下一条（不 return！）
                fail_count += len(group_msgs)
                ids_str = (f"msg#{group_msgs[0].id}" if len(group_msgs) == 1
                           else f"msg#{group_msgs[0].id}~{group_msgs[-1].id}")
                progress(req_id, f"⚠️ {ids_str} 无发送权限（{type(e).__name__}），跳过")
                
            except Exception as e:
                fail_count += len(group_msgs)
                ids_str = f"msg#{group_msgs[0].id}" if len(group_msgs) == 1 else f"msg#{group_msgs[0].id}~{group_msgs[-1].id}"
                progress(req_id, f"❌ {ids_str} 失败: {e}")
            
            await asyncio.sleep(0.5)
        
        progress(req_id, f"✅ 目标频道 {target_channel} 转发完成：成功{success_count}条")
    
    send_response({
        "type": "clone_done", "req_id": req_id,
        "success": success_count,
        "failed": fail_count,
        "total": len(messages)
    })


async def cmd_forward_messages(cmd, req_id):
    """转发指定ID列表的消息（无引用）"""
    session_key = cmd['session_key']
    source_channel = cmd['source_channel']
    target_channel = cmd['target_channel']
    message_ids = [int(x) for x in cmd['message_ids']]
    remove_caption = cmd.get('remove_caption', False)
    
    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"})
        return
    
    try:
        source_entity = await client.get_entity(source_channel)
        target_entity = await client.get_entity(target_channel)
        
        # 获取消息对象
        msgs = await client.get_messages(source_entity, ids=message_ids)
        msgs = [m for m in msgs if m is not None]
        
        if not msgs:
            send_response({"type": "error", "req_id": req_id, "error": "消息不存在或无权限"})
            return
        
        # 按媒体组分组
        group_map = {}
        single_msgs = []
        for msg in msgs:
            if msg.grouped_id:
                gid = str(msg.grouped_id)
                group_map.setdefault(gid, []).append(msg)
            else:
                single_msgs.append(msg)
        
        forwarded_count = 0
        
        # 转发媒体组
        for gid, group_msgs in group_map.items():
            group_msgs.sort(key=lambda m: m.id)
            result = await client.forward_messages(
                target_entity,
                messages=group_msgs,
                from_peer=source_entity,
                drop_author=True,
                drop_media_captions=remove_caption,
            )
            if result:
                forwarded_count += len(group_msgs)
        
        # 转发单条
        for msg in single_msgs:
            result = await client.forward_messages(
                target_entity,
                messages=[msg],
                from_peer=source_entity,
                drop_author=True,
                drop_media_captions=remove_caption,
            )
            if result:
                forwarded_count += 1
        
        send_response({
            "type": "forward_done", "req_id": req_id,
            "count": forwarded_count
        })
        
    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": str(e)})


async def cmd_get_messages(cmd, req_id):
    """获取消息信息（用于监听模式）"""
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
                continue  # 跳过服务消息
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
                'id': msg.id,
                'text': msg.message or '',
                'caption': msg.message or '',
                'media_type': media_type,
                'grouped_id': str(msg.grouped_id) if msg.grouped_id else None,
                'date': msg.date.isoformat() if msg.date else None,
            })
        
        send_response({
            "type": "messages", "req_id": req_id,
            "messages": msgs_data
        })
    except Exception as e:
        send_response({"type": "error", "req_id": req_id, "error": str(e)})


async def cmd_disconnect(cmd, req_id):
    """断开客户端连接"""
    session_key = cmd.get('session_key', '')
    if session_key and session_key in clients:
        try:
            await clients[session_key].disconnect()
        except Exception:
            pass
        del clients[session_key]
    send_response({"type": "disconnected", "req_id": req_id})


async def main():
    """主循环：从stdin读取命令，处理后输出到stdout"""
    send_response({"type": "ready", "version": "2.0.0"})
    
    loop = asyncio.get_event_loop()
    
    while True:
        try:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            cmd = json.loads(line)
            # 异步处理命令，不阻塞主循环
            asyncio.ensure_future(handle_command(cmd))
        except json.JSONDecodeError as e:
            send_response({"type": "error", "error": f"JSON解析失败: {e}"})
        except EOFError:
            break
        except KeyboardInterrupt:
            break
    
    # 断开所有连接
    for client in clients.values():
        try:
            await client.disconnect()
        except Exception:
            pass


if __name__ == '__main__':
    asyncio.run(main())
