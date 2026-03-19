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
