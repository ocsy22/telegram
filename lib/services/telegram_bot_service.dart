import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

/// Telegram Bot API 服务（用于 Bot Token 模式的发送/接收）
class TelegramBotService {
  static TelegramBotService? _instance;
  static TelegramBotService get instance => _instance ??= TelegramBotService._();
  TelegramBotService._();

  bool _ignoreSsl = true;
  void setIgnoreSsl(bool v) => _ignoreSsl = v;

  http.Client _client() {
    if (kIsWeb) return http.Client();
    final hc = HttpClient()
      ..badCertificateCallback = (cert, host, port) => _ignoreSsl;
    return http_io.IOClient(hc);
  }

  Future<Map<String, dynamic>?> _apiCall(
      String token, String method, Map<String, dynamic> params) async {
    final url = 'https://api.telegram.org/bot$token/$method';
    final client = _client();
    try {
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(params),
          )
          .timeout(const Duration(seconds: 45));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) return data['result'] as Map<String, dynamic>?;
      }
      if (kDebugMode) {
        debugPrint('TG API $method error ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 300))}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('TG API $method exception: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// getMe - 验证 Bot Token
  Future<BotInfo?> getMe(String token) async {
    if (token.isEmpty) return null;
    final result = await _apiCall(token, 'getMe', {});
    if (result != null) {
      return BotInfo(
        id: result['id'] as int? ?? 0,
        username: result['username'] as String? ?? '',
        firstName: result['first_name'] as String? ?? '',
      );
    }
    return null;
  }

  /// getUpdates - 获取最新消息（监听用）
  Future<List<TgMessage>> getUpdates(String token,
      {int offset = 0, int limit = 100, int timeout = 0}) async {
    final client = _client();
    try {
      final url = 'https://api.telegram.org/bot$token/getUpdates';
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'offset': offset,
              'limit': limit,
              'timeout': timeout,
            }),
          )
          .timeout(Duration(seconds: timeout + 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['ok'] == true) {
          final updates = data['result'] as List? ?? [];
          return updates
              .map((u) => TgMessage.fromUpdate(u as Map<String, dynamic>))
              .where((m) => m.messageId > 0)
              .toList();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('getUpdates error: $e');
    } finally {
      client.close();
    }
    return [];
  }

  /// copyMessage - 无引用转发核心方法
  Future<int?> copyMessage({
    required String token,
    required String fromChatId,
    required String toChatId,
    required int messageId,
    String? caption,          // null = 保留原始文案；'' = 去除文案；其他 = 替换
    bool removeCaption = false,
    String parseMode = 'HTML',
  }) async {
    final params = <String, dynamic>{
      'chat_id': toChatId,
      'from_chat_id': fromChatId,
      'message_id': messageId,
    };
    if (removeCaption) {
      params['caption'] = '';
    } else if (caption != null) {
      params['caption'] = caption;
      params['parse_mode'] = parseMode;
    }
    final client = _client();
    try {
      final url = 'https://api.telegram.org/bot$token/copyMessage';
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(params),
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          final result = data['result'] as Map<String, dynamic>?;
          return result?['message_id'] as int?;
        }
        if (kDebugMode) debugPrint('copyMessage failed: ${resp.body}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('copyMessage exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// sendMessage - 发送文本消息
  Future<int?> sendMessage({
    required String token,
    required String chatId,
    required String text,
    String parseMode = 'HTML',
  }) async {
    final client = _client();
    try {
      final url = 'https://api.telegram.org/bot$token/sendMessage';
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': chatId,
              'text': text,
              'parse_mode': parseMode,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          final result = data['result'] as Map<String, dynamic>?;
          return result?['message_id'] as int?;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('sendMessage exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// forwardMessage - 带引用转发（用于对比测试）
  Future<int?> forwardMessage({
    required String token,
    required String fromChatId,
    required String toChatId,
    required int messageId,
  }) async {
    final client = _client();
    try {
      final url = 'https://api.telegram.org/bot$token/forwardMessage';
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': toChatId,
              'from_chat_id': fromChatId,
              'message_id': messageId,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          final result = data['result'] as Map<String, dynamic>?;
          return result?['message_id'] as int?;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('forwardMessage exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// getChannelInfo - 获取频道/群组信息
  Future<ChannelInfo?> getChannelInfo(String token, String chatId) async {
    final client = _client();
    try {
      final url = 'https://api.telegram.org/bot$token/getChat';
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'chat_id': chatId}),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          final r = data['result'] as Map<String, dynamic>;
          return ChannelInfo(
            id: r['id'].toString(),
            title: r['title'] as String? ?? r['username'] as String? ?? chatId,
            username: r['username'] as String?,
            memberCount: r['member_count'] as int? ?? 0,
          );
        }
        throw Exception(data['description'] ?? '获取频道信息失败');
      }
    } catch (e) {
      rethrow;
    } finally {
      client.close();
    }
    return null;
  }
}

// ==================== 数据类 ====================
class BotInfo {
  final int id;
  final String username;
  final String firstName;
  BotInfo({required this.id, required this.username, required this.firstName});
}

class ChannelInfo {
  final String id;
  final String title;
  final String? username;
  final int memberCount;
  ChannelInfo({required this.id, required this.title, this.username, this.memberCount = 0});
}

class TgMessage {
  final int updateId;
  final int messageId;
  final String chatId;
  final String? text;
  final String mediaType; // text / photo / video / document / audio / sticker
  final String? caption;
  final DateTime date;

  TgMessage({
    required this.updateId,
    required this.messageId,
    required this.chatId,
    this.text,
    required this.mediaType,
    this.caption,
    required this.date,
  });

  factory TgMessage.fromUpdate(Map<String, dynamic> update) {
    final msg = update['message'] as Map<String, dynamic>? ??
        update['channel_post'] as Map<String, dynamic>? ??
        {};
    final chatId = (msg['chat'] as Map<String, dynamic>?)?['id']?.toString() ?? '';
    final ts = msg['date'] as int? ?? 0;

    String mediaType = 'text';
    if (msg.containsKey('photo')) mediaType = 'photo';
    else if (msg.containsKey('video')) mediaType = 'video';
    else if (msg.containsKey('document')) mediaType = 'document';
    else if (msg.containsKey('audio')) mediaType = 'audio';
    else if (msg.containsKey('sticker')) mediaType = 'sticker';
    else if (msg.containsKey('voice')) mediaType = 'audio';
    else if (msg.containsKey('animation')) mediaType = 'video';

    return TgMessage(
      updateId: update['update_id'] as int? ?? 0,
      messageId: msg['message_id'] as int? ?? 0,
      chatId: chatId,
      text: msg['text'] as String?,
      mediaType: mediaType,
      caption: msg['caption'] as String?,
      date: ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts * 1000) : DateTime.now(),
    );
  }
}
