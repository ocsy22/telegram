import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import '../models/app_models.dart';

/// AI 改写服务（支持多家 AI 服务商）
class AiService {
  final AiConfig config;
  AiService({required this.config});

  http.Client _client() {
    if (kIsWeb) return http.Client();
    final hc = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return http_io.IOClient(hc);
  }

  Future<String?> _callAI({
    required String prompt,
    required String systemPrompt,
    int maxTokens = 500,
    double temperature = 0.8,
  }) async {
    if (!config.enabled || config.apiKey.isEmpty) return null;
    final baseUrl = config.effectiveBaseUrl;
    final model = config.model.isNotEmpty ? config.model : config.defaultModel;
    final url = '$baseUrl/chat/completions';
    final client = _client();
    try {
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': prompt},
              ],
              'max_tokens': maxTokens,
              'temperature': temperature,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final msg = choices[0]['message'] as Map<String, dynamic>?;
          return (msg?['content'] as String?)?.trim();
        }
      } else {
        if (kDebugMode) {
          debugPrint('AI API error ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AI API exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// 改写文案（无原始文案时生成通用内容）
  Future<String?> rewriteCaption({
    String? originalCaption,
    String? prompt,
  }) async {
    final systemPrompt = '''你是一个专业的Telegram频道内容改写助手。
改写要求：
1. 保持原意但改变表达方式
2. 语言自然流畅，吸引眼球
3. 可以适当添加emoji
4. 不要添加多余解释，直接输出改写内容
${prompt != null && prompt.isNotEmpty ? "5. 额外要求：$prompt" : ""}''';

    final userMsg = originalCaption != null && originalCaption.isNotEmpty
        ? '请改写以下Telegram内容：\n\n$originalCaption'
        : '请生成一段简短有趣的Telegram频道内容，10-30字。';

    return _callAI(
      prompt: userMsg,
      systemPrompt: systemPrompt,
      maxTokens: 300,
      temperature: 0.85,
    );
  }

  /// 测试 AI 连接
  Future<bool> testConnection() async {
    final result = await _callAI(
      prompt: '请回复"连接成功"四个字',
      systemPrompt: '你是一个AI助手。',
      maxTokens: 20,
      temperature: 0.1,
    );
    return result != null && result.isNotEmpty;
  }
}
