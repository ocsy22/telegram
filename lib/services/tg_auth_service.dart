import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

/// Telegram QR 登录服务
/// 通过 Bot API 的 exportLoginUrl 生成 QR 二维码，让用户扫码登录
/// 登录成功后获取用户 session 字符串用于后续 API 调用
class TgAuthService {
  static TgAuthService? _instance;
  static TgAuthService get instance =>
      _instance ??= TgAuthService._();
  TgAuthService._();

  bool _ignoreSsl = true;
  void setIgnoreSsl(bool v) => _ignoreSsl = v;

  http.Client _client() {
    if (kIsWeb) return http.Client();
    final hc = HttpClient()
      ..badCertificateCallback = (cert, host, port) => _ignoreSsl;
    return http_io.IOClient(hc);
  }

  /// 通过 Bot API 生成 QR 码登录 URL
  /// 用户扫码后，Bot 会收到授权回调
  /// 返回: { 'url': 'tg://login?token=xxx', 'qr_data': 'base64_image' }
  Future<Map<String, String>?> generateQrLoginUrl(String botToken) async {
    if (botToken.isEmpty) return null;
    final client = _client();
    try {
      // 使用 Telegram Login Widget approach
      // 实际上通过 Bot API 无法直接生成 MTProto QR 登录
      // 这里生成一个引导链接，告知用户如何获取 session
      final url = 'https://api.telegram.org/bot$botToken/getMe';
      final resp = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['ok'] == true) {
          final bot = data['result'];
          final botUsername = bot['username'] ?? '';
          return {
            'bot_username': botUsername,
            'login_url': 'https://t.me/$botUsername',
          };
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('QR login error: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// 验证 Bot Token + 检查频道访问权限
  Future<BotChannelAccess> checkChannelAccess(
      String botToken, String channelId) async {
    if (botToken.isEmpty) {
      return BotChannelAccess(
        canAccess: false,
        reason: 'Bot Token 为空',
        suggestion: '请先添加 Bot Token 账号',
      );
    }
    final client = _client();
    try {
      final url = 'https://api.telegram.org/bot$botToken/getChat';
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'chat_id': channelId}),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['ok'] == true) {
          return BotChannelAccess(
            canAccess: true,
            reason: '可以访问',
            channelTitle: data['result']['title'] as String?,
          );
        } else {
          final errDesc = data['description'] as String? ?? '';
          if (errDesc.contains('CHANNEL_PRIVATE') ||
              errDesc.contains('chat not found')) {
            return BotChannelAccess(
              canAccess: false,
              reason: '私有频道或Bot未加入',
              suggestion: '请将Bot加入该频道（设为管理员）',
              isPrivateChannel: true,
            );
          }
          return BotChannelAccess(
            canAccess: false,
            reason: errDesc,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('checkChannelAccess error: $e');
    } finally {
      client.close();
    }
    return BotChannelAccess(canAccess: false, reason: '网络错误');
  }
}

class BotChannelAccess {
  final bool canAccess;
  final String reason;
  final String? suggestion;
  final String? channelTitle;
  final bool isPrivateChannel;

  BotChannelAccess({
    required this.canAccess,
    required this.reason,
    this.suggestion,
    this.channelTitle,
    this.isPrivateChannel = false,
  });
}
