import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

/// Telegram 统一 API 服务
/// - 公开频道：t.me/s/username HTML接口 → 提取消息ID → Bot copyMessage 无引用转发
/// - 私有频道：Bot已加入 → 直接 copyMessages 转发
class TelegramApiService {
  static TelegramApiService? _instance;
  static TelegramApiService get instance =>
      _instance ??= TelegramApiService._();
  TelegramApiService._();

  bool _ignoreSsl = true;
  void setIgnoreSsl(bool v) => _ignoreSsl = v;

  http.Client _client() {
    if (kIsWeb) return http.Client();
    final hc = HttpClient()
      ..badCertificateCallback = (cert, host, port) => _ignoreSsl;
    return http_io.IOClient(hc);
  }

  // ======================================================================
  // 公开频道：通过 t.me/s/USERNAME 抓取消息ID
  // ======================================================================
  Future<List<int>> getPublicChannelMsgIds({
    required String username,
    required int startId,
    required int endId,
    int maxCount = 500,
    void Function(String)? onLog,
  }) async {
    final cleanName = _cleanUsername(username);
    final allIds = <int>{};
    int? cursor;
    int attempts = 0;
    const maxAttempts = 25;

    onLog?.call('🔍 扫描公开频道 @$cleanName 消息 [ID:$startId~$endId]...');

    cursor = endId + 20;

    while (attempts < maxAttempts && allIds.length < maxCount) {
      attempts++;
      final msgs = await _fetchPublicPage(cleanName, beforeId: cursor);
      if (msgs.isEmpty) break;

      bool reachedStart = false;
      for (final id in msgs) {
        if (id >= startId && id <= endId) {
          allIds.add(id);
          if (allIds.length >= maxCount) break;
        }
        if (id < startId) reachedStart = true;
      }

      if (reachedStart || allIds.length >= maxCount) break;
      cursor = msgs.last;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    final result = allIds.toList()..sort();
    onLog?.call('📋 扫描完成，找到 ${result.length} 条消息ID');
    return result;
  }

  // ======================================================================
  // 从公开频道网页抓取消息文案（用于AI润色）
  // ======================================================================
  Future<Map<int, String>> getPublicChannelCaptions({
    required String username,
    required List<int> messageIds,
  }) async {
    if (messageIds.isEmpty) return {};
    final cleanName = _cleanUsername(username);
    final captions = <int, String>{};

    // 按消息ID范围分批抓取（每次页面最多约20条）
    final sortedIds = messageIds.toList()..sort();
    int cursor = sortedIds.last + 5;
    int attempts = 0;
    const maxAttempts = 30;
    final remaining = Set<int>.from(sortedIds);

    while (remaining.isNotEmpty && attempts < maxAttempts) {
      attempts++;
      final html = await _fetchPublicPageHtml(cleanName, beforeId: cursor);
      if (html.isEmpty) break;

      // 提取消息ID和文案
      final extracted = _extractCaptionsFromHtml(html, cleanName);
      bool anyInRange = false;
      for (final entry in extracted.entries) {
        if (remaining.contains(entry.key)) {
          captions[entry.key] = entry.value;
          remaining.remove(entry.key);
          anyInRange = true;
        }
      }

      // 找页面中最小的ID作为下一个cursor
      final pageIds = extracted.keys.toList()..sort();
      if (pageIds.isEmpty) break;
      if (pageIds.first <= sortedIds.first) break;
      cursor = pageIds.first;

      if (!anyInRange && pageIds.last < sortedIds.first) break;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    return captions;
  }

  Future<String> _fetchPublicPageHtml(String username, {int? beforeId}) async {
    var url = 'https://t.me/s/$username';
    if (beforeId != null) url += '?before=$beforeId';
    final client = _client();
    try {
      final resp = await client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      }).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return resp.body;
    } catch (_) {
    } finally {
      client.close();
    }
    return '';
  }

  Map<int, String> _extractCaptionsFromHtml(String html, String username) {
    final result = <int, String>{};

    // 找所有消息块
    // 格式: <div class="tgme_widget_message_wrap..." data-post="channelname/123">...</div>
    final msgBlockRegex = RegExp(
      r'data-post="[^/]+/(\d+)".*?class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>',
      dotAll: true,
    );

    for (final m in msgBlockRegex.allMatches(html)) {
      final id = int.tryParse(m.group(1) ?? '');
      final rawHtml = m.group(2) ?? '';
      if (id == null) continue;

      // 清理HTML标签，保留文本
      final text = rawHtml
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .trim();

      if (text.isNotEmpty) result[id] = text;
    }

    return result;
  }

  // ======================================================================
  // 获取公开频道最新N条消息ID（不需要指定范围，适合"从最新开始克隆"）
  // ======================================================================
  Future<List<int>> getLatestPublicMsgIds({
    required String username,
    int count = 100,
    void Function(String)? onLog,
  }) async {
    final cleanName = _cleanUsername(username);
    final allIds = <int>{};
    int? cursor;
    int attempts = 0;
    const maxAttempts = 15;

    onLog?.call('🔍 获取 @$cleanName 最新 $count 条消息...');

    while (attempts < maxAttempts && allIds.length < count) {
      attempts++;
      final msgs = await _fetchPublicPage(cleanName, beforeId: cursor);
      if (msgs.isEmpty) break;
      for (final id in msgs) {
        allIds.add(id);
        if (allIds.length >= count) break;
      }
      cursor = msgs.last;
      await Future.delayed(const Duration(milliseconds: 400));
    }

    final result = allIds.toList()..sort();
    onLog?.call('📋 获取到 ${result.length} 条最新消息ID');
    return result;
  }

  // ======================================================================
  // 抓取公开频道一页消息ID（从指定ID之前开始）
  // ======================================================================
  Future<List<int>> _fetchPublicPage(String username, {int? beforeId}) async {
    var url = 'https://t.me/s/$username';
    if (beforeId != null) url += '?before=$beforeId';

    final client = _client();
    try {
      final resp = await client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      }).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final postRegex = RegExp(r'data-post="[^/]+/(\d+)"');
        final matches = postRegex.allMatches(resp.body);
        final ids = <int>{};
        for (final m in matches) {
          final id = int.tryParse(m.group(1) ?? '');
          if (id != null) ids.add(id);
        }
        final result = ids.toList()..sort((a, b) => b.compareTo(a));
        return result;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('fetchPublicPage error: $e');
    } finally {
      client.close();
    }
    return [];
  }

  String _cleanUsername(String input) {
    return input
        .replaceFirst(RegExp(r'^@'), '')
        .replaceFirst('https://t.me/', '')
        .replaceFirst('http://t.me/', '')
        .split('/').first
        .trim();
  }

  // ======================================================================
  // 判断是否为公开频道（有username格式）
  // ======================================================================
  bool looksLikePublicChannel(String chatId) {
    final clean = chatId.startsWith('@') ? chatId.substring(1) : chatId;
    final cleaned = clean
        .replaceFirst('https://t.me/', '')
        .replaceFirst('http://t.me/', '')
        .split('/').first;
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{3,}$').hasMatch(cleaned);
  }

  // ======================================================================
  // 通过Bot API 查询频道信息（判断是否有username/是否公开）
  // ======================================================================
  Future<ChannelAccessInfo> checkChannelAccess({
    required String token,
    required String chatId,
  }) async {
    final client = _client();
    try {
      final resp = await client.post(
        Uri.parse('https://api.telegram.org/bot$token/getChat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chat_id': chatId}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          final r = data['result'] as Map<String, dynamic>;
          final username = r['username'] as String?;
          final title = r['title'] as String? ?? username ?? chatId;
          return ChannelAccessInfo(
            canAccess: true,
            isPublic: username != null && username.isNotEmpty,
            username: username,
            title: title,
          );
        } else {
          final desc = data['description'] as String? ?? '';
          return ChannelAccessInfo(
            canAccess: false,
            isPublic: false,
            errorMsg: desc,
            isPrivateNoAccess: desc.contains('CHANNEL_PRIVATE') ||
                desc.contains('not found'),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('checkChannelAccess: $e');
    } finally {
      client.close();
    }
    return ChannelAccessInfo(canAccess: false, isPublic: false, errorMsg: '网络错误');
  }

  // ======================================================================
  // 批量无引用复制（copyMessages）
  // ======================================================================
  Future<bool> copyMessagesBatch({
    required String token,
    required String fromChatId,
    required String toChatId,
    required List<int> messageIds,
    bool removeCaption = false,
  }) async {
    if (messageIds.isEmpty) return false;
    final client = _client();
    try {
      final params = <String, dynamic>{
        'chat_id': toChatId,
        'from_chat_id': fromChatId,
        'message_ids': messageIds,
      };
      if (removeCaption) params['remove_caption'] = true;

      final resp = await client.post(
        Uri.parse('https://api.telegram.org/bot$token/copyMessages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(params),
      ).timeout(const Duration(seconds: 90));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['ok'] == true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('copyMessagesBatch: $e');
    } finally {
      client.close();
    }
    return false;
  }

  // ======================================================================
  // 单条无引用复制（copyMessage）
  // ======================================================================
  Future<int?> copySingleMessage({
    required String token,
    required String fromChatId,
    required String toChatId,
    required int messageId,
    bool removeCaption = false,
    String? caption,
  }) async {
    final client = _client();
    try {
      final params = <String, dynamic>{
        'chat_id': toChatId,
        'from_chat_id': fromChatId,
        'message_id': messageId,
      };
      if (removeCaption) {
        params['caption'] = '';
      } else if (caption != null) {
        params['caption'] = caption;
        params['parse_mode'] = 'HTML';
      }
      final resp = await client.post(
        Uri.parse('https://api.telegram.org/bot$token/copyMessage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(params),
      ).timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          final result = data['result'] as Map<String, dynamic>?;
          return result?['message_id'] as int?;
        }
        if (kDebugMode) debugPrint('copyMessage failed: ${resp.body}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('copySingleMessage: $e');
    } finally {
      client.close();
    }
    return null;
  }
}

class ChannelAccessInfo {
  final bool canAccess;
  final bool isPublic;
  final String? username;
  final String? title;
  final String? errorMsg;
  final bool isPrivateNoAccess;

  ChannelAccessInfo({
    required this.canAccess,
    required this.isPublic,
    this.username,
    this.title,
    this.errorMsg,
    this.isPrivateNoAccess = false,
  });
}
