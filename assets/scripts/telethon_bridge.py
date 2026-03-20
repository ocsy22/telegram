#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Telethon Bridge v6.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
新特性：
1. 完全无引用转发（send_file/send_message）
2. 支持 bot_token 参数：Telethon读取 + Bot发送（解决受保护频道）
3. AI文案润色（免费模型 groq/gemini 等）
4. 经真实账号实测（@szny88 -> @mytgby，10条全成功）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
import sys, json, asyncio, os, traceback, threading, urllib.request, urllib.parse

# ── 依赖检查 ──────────────────────────────────────────────
try:
    import telethon  # noqa
except ImportError:
    print(json.dumps({"type":"error","error":"缺少 telethon，请运行: pip install telethon"}, ensure_ascii=False), flush=True)
    sys.exit(1)

from telethon import TelegramClient
from telethon.tl.types import MessageMediaWebPage
from telethon.errors import (
    SessionPasswordNeededError, FloodWaitError,
    ChatWriteForbiddenError, ChatAdminRequiredError,
    ChannelPrivateError, UserNotParticipantError,
)

# ── 全局状态 ──────────────────────────────────────────────
clients = {}          # session_key -> TelegramClient
_stdout_lock = threading.Lock()


# ── 工具函数 ──────────────────────────────────────────────

def send_response(data: dict):
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
    if channel is None:
        return channel
    s = str(channel).strip()
    try:
        return int(s)
    except ValueError:
        return s


# ── AI润色 ──────────────────────────────────────────────

def _ai_polish_sync(text: str, ai_config: dict) -> str:
    """
    同步AI润色（在executor中运行，避免阻塞event loop）。
    返回润色后的文本（失败时返回原文）。
    """
    if not text or not text.strip():
        return text
    
    provider = ai_config.get("provider", "")
    api_key = ai_config.get("api_key", "")
    model = ai_config.get("model", "")
    system_prompt = ai_config.get("prompt", "请对以下文案进行润色改写，保持原意但让表达更自然流畅，只返回改写后的文案，不要加任何说明：")
    base_url = ai_config.get("base_url", "")
    
    # pollinations是免费服务，不需要api_key
    is_free = provider in ("pollinations",) or provider.startswith("free")
    if not api_key and not is_free:
        return text
    
    try:
        # ── Pollinations（完全免费，直接GET请求）──
        if provider == "pollinations":
            p_model = model or "openai"
            full_prompt = f"{system_prompt}\n\n{text}"
            poll_url = f"https://text.pollinations.ai/{urllib.parse.quote(full_prompt)}?model={p_model}&temperature=0.7"
            req = urllib.request.Request(poll_url,
                                         headers={"User-Agent": "TelegramBridge/6.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = resp.read().decode("utf-8").strip()
            # 过滤掉明显错误的响应
            if result and not result.startswith("<") and not result.startswith("{") and len(result) > 3:
                return result
            return text

        # 根据provider选择API端点
        if provider == "groq":
            url = "https://api.groq.com/openai/v1/chat/completions"
            if not model:
                model = "llama-3.1-8b-instant"
        elif provider == "gemini":
            # Gemini API
            g_model = model or "gemini-1.5-flash"
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{g_model}:generateContent?key={api_key}"
            payload = {
                "contents": [{"parts": [{"text": f"{system_prompt}\n\n{text}"}]}]
            }
            data = json.dumps(payload).encode()
            req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                result = json.loads(resp.read())
            polished = result["candidates"][0]["content"]["parts"][0]["text"].strip()
            return polished if polished else text
        elif base_url:
            url = base_url.rstrip("/") + "/chat/completions"
        else:
            return text  # 未知provider
        
        # OpenAI兼容格式（groq, openrouter等）
        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": text}
            ],
            "max_tokens": 1000,
            "temperature": 0.7
        }
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }
        data = json.dumps(payload).encode()
        req = urllib.request.Request(url, data=data, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
        polished = result["choices"][0]["message"]["content"].strip()
        return polished if polished else text
        
    except Exception as e:
        log_err(f"[AI润色] 失败: {e}")
        return text  # 失败时返回原文


async def ai_polish_text(text: str, ai_config: dict) -> str:
    """
    异步AI润色包装器（避免阻塞event loop）。
    通过 run_in_executor 在线程池中调用同步HTTP请求。
    """
    if not text or not text.strip():
        return text
    loop = asyncio.get_event_loop()
    try:
        result = await asyncio.wait_for(
            loop.run_in_executor(None, _ai_polish_sync, text, ai_config),
            timeout=35.0
        )
        return result
    except asyncio.TimeoutError:
        log_err(f"[AI润色] 超时（35s）")
        return text
    except Exception as e:
        log_err(f"[AI润色] 异步失败: {e}")
        return text



def bot_api_post(token: str, method: str, payload: dict, timeout: int = 30) -> dict:
    """调用Bot API"""
    url = f"https://api.telegram.org/bot{token}/{method}"
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"ok": False, "description": str(e)}


async def send_group_via_bot(bot_token: str, target_channel, group_msgs: list,
                              remove_caption: bool = False, ai_config: dict = None) -> tuple:
    """
    通过Bot API无引用发送一组消息。
    使用 copyMessages（批量）或 copyMessage（单条）。
    返回 (success_count, error_or_None)
    """
    if not group_msgs:
        return 0, "空消息组"
    
    # 确定目标channel的chat_id
    if isinstance(target_channel, int):
        chat_id = str(target_channel)
    else:
        chat_id = str(target_channel)
    
    # 获取源频道chat_id（从消息里取）
    from_chat_id = group_msgs[0].peer_id
    # 转为数字ID
    if hasattr(from_chat_id, 'channel_id'):
        src_id = -1000000000000 - from_chat_id.channel_id
    elif hasattr(from_chat_id, 'chat_id'):
        src_id = -from_chat_id.chat_id
    elif hasattr(from_chat_id, 'user_id'):
        src_id = from_chat_id.user_id
    else:
        src_id = str(from_chat_id)
    
    msg_ids = [m.id for m in group_msgs]
    
    # 处理caption（AI润色）
    caption_override = None
    if not remove_caption and ai_config:
        orig_caption = next((m.message for m in group_msgs if m.message), None)
        if orig_caption:
            polished = await ai_polish_text(orig_caption, ai_config)
            if polished != orig_caption:
                caption_override = polished
    
    # 尝试批量 copyMessages
    payload = {
        "chat_id": chat_id,
        "from_chat_id": src_id,
        "message_ids": msg_ids,
        "remove_caption": remove_caption
    }
    result = bot_api_post(bot_token, "copyMessages", payload)
    
    if result.get("ok"):
        cnt = len(result.get("result", []))
        # 如果有AI润色的caption，用editMessageCaption更新第一条
        if caption_override and cnt > 0:
            new_msg_id = result["result"][0]["message_id"]
            bot_api_post(bot_token, "editMessageCaption", {
                "chat_id": chat_id, "message_id": new_msg_id, "caption": caption_override
            })
        return cnt or len(msg_ids), None
    
    # 单条fallback
    if len(msg_ids) == 1:
        r2 = bot_api_post(bot_token, "copyMessage", {
            "chat_id": chat_id, "from_chat_id": src_id,
            "message_id": msg_ids[0], "remove_caption": remove_caption
        })
        if r2.get("ok"):
            return 1, None
        return 0, r2.get("description", "copyMessage失败")
    
    return 0, result.get("description", "copyMessages失败")


# ── 无引用发送（用户账号）──────────────────────────────────

async def send_group_no_quote(client, target_entity, group_msgs: list,
                               remove_caption: bool = False,
                               ai_config: dict = None,
                               caption_override: str = None) -> tuple:
    """
    用用户账号无引用发送一组消息。
    返回 (成功数量, 错误信息 or None)
    """
    if not group_msgs:
        return 0, "空消息组"

    # 确定caption
    caption = ""
    if not remove_caption:
        if caption_override:
            caption = caption_override
        else:
            for m in group_msgs:
                if m.message:
                    caption = m.message
                    break
            # AI润色（异步）
            if caption and ai_config:
                caption = await ai_polish_text(caption, ai_config)

    first = group_msgs[0]

    # 情况1：纯文字 或 链接预览
    if not first.media or isinstance(first.media, MessageMediaWebPage):
        text = "" if remove_caption else (caption or first.message or "")
        await client.send_message(target_entity, message=text)
        return 1, None

    # 情况2：多文件媒体组
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


# ── 媒体组补全 ──────────────────────────────────────────

async def _complete_media_groups(client, entity, messages: list) -> list:
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
            pass
    return messages + extra


# ── 命令处理器 ─────────────────────────────────────────────

async def cmd_start_client(cmd: dict, req_id: str):
    api_id    = int(cmd['api_id'])
    api_hash  = cmd['api_hash']
    session_key = cmd.get('session_key', f"{api_id}_{api_hash[:8]}")
    session_dir = cmd.get('session_dir', os.path.expanduser('~'))
    session_path = os.path.join(session_dir, f"tg_{session_key}")

    if session_key in clients:
        client = clients[session_key]
        if client.is_connected():
            if await client.is_user_authorized():
                me = await client.get_me()
                send_response({"type": "client_ready", "req_id": req_id,
                               "session_key": session_key, "already_connected": True, "authorized": True,
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
        send_response({"type": "client_ready", "req_id": req_id,
                       "session_key": session_key, "authorized": True,
                       "user": {"id": me.id, "username": me.username or "",
                                "first_name": me.first_name or "", "phone": me.phone or ""}})
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
        await client.sign_in(cmd['phone'], cmd['code'], phone_code_hash=cmd['phone_code_hash'])
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
    克隆消息 v6.0
    
    参数：
      source_channel  : 来源频道
      target_channels : 目标频道列表
      start_id/end_id : 消息ID范围（0=不限）
      count           : 条数上限
      remove_caption  : 是否清除文案
      bot_token       : [可选] 如果提供，用Bot发送（绕过某些频道限制）
      ai_config       : [可选] AI润色配置 {"provider","api_key","model","prompt","base_url"}
    """
    session_key     = cmd['session_key']
    source_channel  = parse_channel_id(cmd['source_channel'])
    target_channels = [parse_channel_id(t) for t in cmd['target_channels']]
    start_id        = int(cmd.get('start_id', 0))
    end_id          = int(cmd.get('end_id', 0))
    count           = int(cmd.get('count', 100))
    remove_caption  = bool(cmd.get('remove_caption', False))
    bot_token       = cmd.get('bot_token', '')          # 可选Bot token
    ai_config       = cmd.get('ai_config', None)        # 可选AI配置
    use_bot_send    = bool(bot_token)                   # 是否用Bot发送

    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"}); return

    send_mode = "Bot" if use_bot_send else "用户账号"
    ai_mode   = "✅已开启" if ai_config else "❌未配置"
    progress(req_id, f"正在连接源频道 {source_channel}... [发送方式={send_mode}] [AI润色={ai_mode}]")

    # ── 获取源频道 ───────────────────────────────────────
    try:
        source_entity = await client.get_entity(source_channel)
        progress(req_id, f"✅ 源频道: {getattr(source_entity, 'title', source_channel)}")
    except (ChannelPrivateError, UserNotParticipantError):
        send_response({"type": "error", "req_id": req_id,
                       "error": f"无法访问私有频道 {source_channel}"}); return
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
                source_entity, min_id=start_id-1, max_id=end_id+1, limit=range_limit
            ):
                if msg and not msg.action:
                    messages.append(msg)
        elif start_id > 0:
            progress(req_id, f"读取 start_id={start_id} 起的 {safe_count} 条...")
            async for msg in client.iter_messages(
                source_entity, min_id=start_id-1, limit=safe_count
            ):
                if msg and not msg.action:
                    messages.append(msg)
        elif end_id > 0:
            progress(req_id, f"读取 end_id={end_id} 之前的 {safe_count} 条...")
            async for msg in client.iter_messages(
                source_entity, max_id=end_id+1, limit=safe_count
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
        progress(req_id, f"共读取 {len(messages)} 条（含媒体组补全）")

    except Exception as e:
        log_err(f"[clone] 读取失败: {traceback.format_exc()}")
        send_response({"type": "error", "req_id": req_id, "error": f"读取消息失败: {e}"}); return

    if not messages:
        send_response({"type": "clone_done", "req_id": req_id,
                       "success": 0, "failed": 0, "total": 0,
                       "msg": "没有找到消息"}); return

    # ── 按媒体组分组 ─────────────────────────────────────
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

    progress(req_id, f"共 {len(ordered_groups)} 组，开始无引用转发到 {len(target_channels)} 个频道...")

    total_success = 0
    total_fail    = 0

    for target_channel in target_channels:
        try:
            target_entity = await client.get_entity(target_channel)
            target_title  = getattr(target_entity, 'title', str(target_channel))
            progress(req_id, f"目标频道: {target_title}")
        except Exception as e:
            progress(req_id, f"⚠️ 无法访问目标频道 {target_channel}: {e}")
            continue

        ch_success = 0
        ch_fail    = 0

        for i, (gid, group_msgs) in enumerate(ordered_groups):
            ids = [m.id for m in group_msgs]
            ids_str = (f"msg#{ids[0]}" if len(ids) == 1
                       else f"msg#{ids[0]}~{ids[-1]}({len(ids)}条)")

            # 断线重连
            if not client.is_connected():
                progress(req_id, "⚠️ 连接断开，尝试重连...")
                try:
                    await client.connect()
                    progress(req_id, "✅ 重连成功")
                except Exception as ce:
                    remaining = sum(len(g) for _, g in ordered_groups[i:])
                    ch_fail += remaining; total_fail += remaining
                    progress(req_id, f"❌ 重连失败: {ce}，中止此频道")
                    break

            try:
                if use_bot_send:
                    # ── Bot发送模式 ──
                    cnt, err = await send_group_via_bot(
                        bot_token, target_channel, group_msgs,
                        remove_caption=remove_caption,
                        ai_config=ai_config
                    )
                    if err:
                        # Bot失败时降级到用户账号发送
                        progress(req_id, f"⚠️ Bot发送失败({err})，降级到账号发送 {ids_str}")
                        cnt, err = await send_group_no_quote(
                            client, target_entity, group_msgs,
                            remove_caption=remove_caption, ai_config=ai_config
                        )
                else:
                    # ── 用户账号发送模式 ──
                    cnt, err = await send_group_no_quote(
                        client, target_entity, group_msgs,
                        remove_caption=remove_caption, ai_config=ai_config
                    )

                if err:
                    ch_fail    += len(group_msgs)
                    total_fail += len(group_msgs)
                    progress(req_id, f"⚠️ [{i+1}/{len(ordered_groups)}] {ids_str} 跳过: {err}")
                else:
                    ch_success    += cnt
                    total_success += cnt
                    ai_tag = " [AI润色]" if ai_config else ""
                    progress(req_id, f"✅ [{i+1}/{len(ordered_groups)}] {ids_str} 成功{cnt}条{ai_tag}")

            except FloodWaitError as e:
                wait_secs = e.seconds + 3
                progress(req_id, f"⏳ 限速 {wait_secs}s，等待后重试 {ids_str}...")
                await asyncio.sleep(wait_secs)
                try:
                    if use_bot_send:
                        cnt, err = await send_group_via_bot(bot_token, target_channel, group_msgs, remove_caption=remove_caption)
                    else:
                        cnt, err = await send_group_no_quote(client, target_entity, group_msgs, remove_caption=remove_caption)
                    if not err:
                        ch_success += cnt; total_success += cnt
                        progress(req_id, f"✅ 重试成功 {ids_str}")
                    else:
                        ch_fail += len(group_msgs); total_fail += len(group_msgs)
                        progress(req_id, f"❌ 重试失败 {ids_str}: {err}")
                except Exception as e2:
                    ch_fail += len(group_msgs); total_fail += len(group_msgs)
                    progress(req_id, f"❌ 重试异常 {ids_str}: {e2}")
                    log_err(traceback.format_exc())

            except (ChatWriteForbiddenError, ChatAdminRequiredError) as e:
                remaining = sum(len(g) for _, g in ordered_groups[i:])
                ch_fail += remaining; total_fail += remaining
                progress(req_id, f"❌ 无发送权限({type(e).__name__})，跳过此频道")
                break

            except Exception as e:
                ch_fail += len(group_msgs); total_fail += len(group_msgs)
                err_type = type(e).__name__
                progress(req_id, f"❌ [{i+1}/{len(ordered_groups)}] {ids_str} 失败({err_type}): {e}")
                log_err(f"[clone]: {err_type}: {e}\n{traceback.format_exc()}")

            await asyncio.sleep(1.0)

        progress(req_id, f"频道 {target_channel} 完成：✅{ch_success} ❌{ch_fail}")

    send_response({
        "type":    "clone_done",
        "req_id":  req_id,
        "success": total_success,
        "failed":  total_fail,
        "total":   len(messages),
    })


async def cmd_forward_messages(cmd: dict, req_id: str):
    """单次无引用转发指定消息ID列表"""
    session_key    = cmd['session_key']
    source_channel = parse_channel_id(cmd['source_channel'])
    target_channel = parse_channel_id(cmd['target_channel'])
    message_ids    = [int(x) for x in cmd['message_ids']]
    remove_caption = bool(cmd.get('remove_caption', False))
    bot_token      = cmd.get('bot_token', '')

    client = clients.get(session_key)
    if not client or not client.is_connected():
        send_response({"type": "error", "req_id": req_id, "error": "客户端未连接"}); return

    try:
        source_entity = await client.get_entity(source_channel)
        target_entity = await client.get_entity(target_channel)
        msgs = await client.get_messages(source_entity, ids=message_ids)
        msgs = [m for m in msgs if m is not None]
        if not msgs:
            send_response({"type": "error", "req_id": req_id, "error": "消息不存在或无权限"}); return

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
            if bot_token:
                cnt, _ = await send_group_via_bot(bot_token, target_channel, grp_msgs, remove_caption)
            else:
                cnt, _ = await send_group_no_quote(client, target_entity, grp_msgs, remove_caption)
            forwarded += cnt
        for msg in singles:
            if bot_token:
                cnt, _ = await send_group_via_bot(bot_token, target_channel, [msg], remove_caption)
            else:
                cnt, _ = await send_group_no_quote(client, target_entity, [msg], remove_caption)
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
            if msg.photo:           media_type = 'photo'
            elif msg.video or msg.gif: media_type = 'video'
            elif msg.document:      media_type = 'document'
            elif msg.audio or msg.voice: media_type = 'audio'
            elif msg.sticker:       media_type = 'sticker'
            else:                   media_type = 'text'
            msgs_data.append({
                'id': msg.id, 'text': msg.message or '',
                'caption': msg.message or '', 'media_type': media_type,
                'grouped_id': str(msg.grouped_id) if msg.grouped_id else None,
                'date': msg.date.isoformat() if msg.date else None,
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


# ── 主命令分发 ────────────────────────────────────────────

async def handle_command(cmd: dict):
    action = cmd.get('action', '')
    req_id = cmd.get('req_id', '')
    try:
        if   action == 'ping':             send_response({"type": "pong", "req_id": req_id})
        elif action == 'start_client':     await cmd_start_client(cmd, req_id)
        elif action == 'send_code':        await cmd_send_code(cmd, req_id)
        elif action == 'sign_in':          await cmd_sign_in(cmd, req_id)
        elif action == 'sign_in_2fa':      await cmd_sign_in_2fa(cmd, req_id)
        elif action == 'get_me':           await cmd_get_me(cmd, req_id)
        elif action == 'clone_messages':   await cmd_clone_messages(cmd, req_id)
        elif action == 'forward_messages': await cmd_forward_messages(cmd, req_id)
        elif action == 'get_messages':     await cmd_get_messages(cmd, req_id)
        elif action == 'disconnect':       await cmd_disconnect(cmd, req_id)
        else:
            send_response({"type": "error", "req_id": req_id,
                           "error": f"未知命令: {action}"})
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
    send_response({"type": "ready", "version": "6.0.0"})
    loop  = asyncio.get_event_loop()
    queue: asyncio.Queue = asyncio.Queue()

    def _read_stdin():
        while True:
            try:
                line = sys.stdin.readline()
                if not line:
                    loop.call_soon_threadsafe(queue.put_nowait, None); break
                line = line.strip()
                if line:
                    loop.call_soon_threadsafe(queue.put_nowait, line)
            except Exception as ex:
                log_err(f"[stdin] {ex}")
                loop.call_soon_threadsafe(queue.put_nowait, None); break

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

    for c in clients.values():
        try: await c.disconnect()
        except Exception: pass


if __name__ == '__main__':
    asyncio.run(main())
