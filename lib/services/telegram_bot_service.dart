import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

/// Telegram Bot API 服务（Bot Token 模式）
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
        debugPrint('TG API $method error ${resp.statusCode}: '
            '${resp.body.substring(0, resp.body.length.clamp(0, 300))}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('TG API $method exception: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// 带错误详情的API调用，返回完整响应
  Future<Map<String, dynamic>> _apiCallWithError(
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
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {'ok': false, 'description': '网络异常: $e', 'error_code': -1};
    } finally {
      client.close();
    }
  }

  /// 验证 Bot Token
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

  /// getUpdates - 轮询获取新消息（监听模式用）
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

  /// copyMessage - 无引用转发单条消息（返回详细错误信息）
  Future<CopyResult> copyMessageWithDetail({
    required String token,
    required String fromChatId,
    required String toChatId,
    required int messageId,
    String? caption,
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
    } else if (caption != null && caption.isNotEmpty) {
      params['caption'] = caption;
      params['parse_mode'] = parseMode;
    }

    final data = await _apiCallWithError(token, 'copyMessage', params);
    if (data['ok'] == true) {
      final result = data['result'] as Map<String, dynamic>?;
      final newId = result?['message_id'] as int?;
      return CopyResult(success: true, newMessageId: newId);
    }

    final errorCode = data['error_code'] as int? ?? 0;
    final description = data['description'] as String? ?? '未知错误';
    return CopyResult(
      success: false,
      errorCode: errorCode,
      errorDescription: description,
    );
  }

  /// copyMessage - 无引用转发单条消息（兼容旧接口）
  Future<int?> copyMessage({
    required String token,
    required String fromChatId,
    required String toChatId,
    required int messageId,
    String? caption,
    bool removeCaption = false,
    String parseMode = 'HTML',
  }) async {
    final r = await copyMessageWithDetail(
      token: token,
      fromChatId: fromChatId,
      toChatId: toChatId,
      messageId: messageId,
      caption: caption,
      removeCaption: removeCaption,
      parseMode: parseMode,
    );
    return r.success ? r.newMessageId : null;
  }

  /// copyMessages - 无引用批量转发，返回详细结果
  Future<CopyMessagesResult> copyMessagesWithDetail({
    required String token,
    required String fromChatId,
    required String toChatId,
    required List<int> messageIds,
    bool removeCaption = false,
  }) async {
    if (messageIds.isEmpty) {
      return CopyMessagesResult(success: false, errorDescription: '消息列表为空');
    }

    final params = <String, dynamic>{
      'chat_id': toChatId,
      'from_chat_id': fromChatId,
      'message_ids': messageIds,
    };
    if (removeCaption) {
      params['remove_caption'] = true;
    }

    final client = _client();
    try {
      final url = 'https://api.telegram.org/bot$token/copyMessages';
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(params),
          )
          .timeout(const Duration(seconds: 90));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        return CopyMessagesResult(success: true);
      }

      final errorCode = data['error_code'] as int? ?? 0;
      final description = data['description'] as String? ?? '未知错误';

      // 批量失败时，逐条尝试
      client.close();
      int successCount = 0;
      final errors = <String>[];
      for (final mid in messageIds) {
        final r = await copyMessageWithDetail(
          token: token,
          fromChatId: fromChatId,
          toChatId: toChatId,
          messageId: mid,
          removeCaption: removeCaption,
        );
        if (r.success) {
          successCount++;
        } else {
          errors.add('msg[$mid]: ${r.errorDescription}');
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return CopyMessagesResult(
        success: successCount > 0,
        successCount: successCount,
        errorCode: errorCode,
        errorDescription: successCount > 0
            ? '批量API不支持，逐条转发: $successCount/${messageIds.length}成功'
            : description,
        singleErrors: errors,
      );
    } catch (e) {
      client.close();
      // 异常时逐条重试
      int successCount = 0;
      final errors = <String>[];
      for (final mid in messageIds) {
        final r = await copyMessageWithDetail(
          token: token,
          fromChatId: fromChatId,
          toChatId: toChatId,
          messageId: mid,
          removeCaption: removeCaption,
        );
        if (r.success) {
          successCount++;
        } else {
          errors.add('msg[$mid]: ${r.errorDescription}');
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return CopyMessagesResult(
        success: successCount > 0,
        successCount: successCount,
        errorDescription: successCount > 0
            ? '网络异常后逐条重试: $successCount/${messageIds.length}成功'
            : '网络异常: $e',
        singleErrors: errors,
      );
    }
  }

  /// copyMessages - 无引用批量转发一组消息（兼容旧接口）
  Future<bool> copyMessages({
    required String token,
    required String fromChatId,
    required String toChatId,
    required List<int> messageIds,
    bool removeCaption = false,
  }) async {
    final r = await copyMessagesWithDetail(
      token: token,
      fromChatId: fromChatId,
      toChatId: toChatId,
      messageIds: messageIds,
      removeCaption: removeCaption,
    );
    return r.success;
  }

  /// 获取一批连续消息（含 media_group_id），用于分组检测
  Future<List<TgRawMessage>> getMessagesInfo(
      String token, String chatId, List<int> messageIds) async {
    return [];
  }

  /// 获取文件信息
  Future<Map<String, dynamic>?> getFileInfo({
    required String token,
    required String chatId,
    required int messageId,
  }) async {
    return null;
  }

  /// sendMessage - 发文本
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

  /// getChannelInfo - 获取频道信息
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

// ==================== 结果数据类 ====================

class CopyResult {
  final bool success;
  final int? newMessageId;
  final int errorCode;
  final String? errorDescription;

  CopyResult({
    required this.success,
    this.newMessageId,
    this.errorCode = 0,
    this.errorDescription,
  });

  /// 是否是"消息不存在"错误（通常意味着Bot没有访问权限）
  bool get isNotFound =>
      errorCode == 400 &&
      (errorDescription?.contains('message to copy not found') == true ||
          errorDescription?.contains('MESSAGE_ID_INVALID') == true);

  /// 是否是权限错误
  bool get isPermissionError =>
      errorCode == 400 &&
      (errorDescription?.contains('CHANNEL_PRIVATE') == true ||
          errorDescription?.contains('chat not found') == true ||
          errorDescription?.contains('bot is not a member') == true ||
          errorDescription?.contains('Not Found') == true);

  /// 是否是限流错误
  bool get isRateLimited =>
      errorCode == 429;
}

class CopyMessagesResult {
  final bool success;
  final int successCount;
  final int errorCode;
  final String? errorDescription;
  final List<String> singleErrors;

  CopyMessagesResult({
    required this.success,
    this.successCount = 0,
    this.errorCode = 0,
    this.errorDescription,
    this.singleErrors = const [],
  });
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
  ChannelInfo({
    required this.id,
    required this.title,
    this.username,
    this.memberCount = 0,
  });
}

class TgRawMessage {
  final int messageId;
  final String? mediaGroupId;
  final String mediaType;
  final String? caption;
  final String? text;
  TgRawMessage({
    required this.messageId,
    this.mediaGroupId,
    required this.mediaType,
    this.caption,
    this.text,
  });
}

class TgMessage {
  final int updateId;
  final int messageId;
  final String chatId;
  final String? text;
  final String mediaType;
  final String? caption;
  final String? mediaGroupId; // 媒体组ID，同一组多图/多视频共享此ID
  final DateTime date;

  TgMessage({
    required this.updateId,
    required this.messageId,
    required this.chatId,
    this.text,
    required this.mediaType,
    this.caption,
    this.mediaGroupId,
    required this.date,
  });

  bool get isInMediaGroup => mediaGroupId != null && mediaGroupId!.isNotEmpty;

  factory TgMessage.fromUpdate(Map<String, dynamic> update) {
    final msg = update['message'] as Map<String, dynamic>? ??
        update['channel_post'] as Map<String, dynamic>? ??
        {};
    final chatId =
        (msg['chat'] as Map<String, dynamic>?)?['id']?.toString() ?? '';
    final ts = msg['date'] as int? ?? 0;

    String mediaType = 'text';
    if (msg.containsKey('photo')) {
      mediaType = 'photo';
    } else if (msg.containsKey('video')) {
      mediaType = 'video';
    } else if (msg.containsKey('document')) {
      mediaType = 'document';
    } else if (msg.containsKey('audio')) {
      mediaType = 'audio';
    } else if (msg.containsKey('sticker')) {
      mediaType = 'sticker';
    } else if (msg.containsKey('voice')) {
      mediaType = 'audio';
    } else if (msg.containsKey('animation')) {
      mediaType = 'video';
    }

    return TgMessage(
      updateId: update['update_id'] as int? ?? 0,
      messageId: msg['message_id'] as int? ?? 0,
      chatId: chatId,
      text: msg['text'] as String?,
      mediaType: mediaType,
      caption: msg['caption'] as String?,
      mediaGroupId: msg['media_group_id'] as String?,
      date: ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
          : DateTime.now(),
    );
  }
}
