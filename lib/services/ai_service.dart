import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import '../models/app_models.dart';

/// AI 润色/改写服务
/// 支持多家 AI 服务商：
///   - Pollinations AI（免费，无需Key，直接可用）
///   - Groq（免费额度，注册获取Key，速度极快）
///   - OpenRouter（有免费模型，需注册Key）
///   - Gemini（需Key，有免费额度）
///   - OpenAI/DeepSeek/通义千问/智谱GLM/Kimi（需付费Key）
class AiService {
  final AiConfig config;
  AiService({required this.config});

  http.Client _client() {
    if (kIsWeb) return http.Client();
    final hc = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return http_io.IOClient(hc);
  }

  // ===== 核心调用 =====
  Future<String?> _callAI({
    required String prompt,
    required String systemPrompt,
    int maxTokens = 500,
    double temperature = 0.8,
  }) async {
    // 免费服务不需要检查API Key
    if (!config.enabled) return null;
    if (!config.isFreeProvider && config.apiKey.isEmpty) return null;

    switch (config.provider) {
      case 'pollinations':
        return _callPollinations(
          systemPrompt: systemPrompt,
          prompt: prompt,
          maxTokens: maxTokens,
          temperature: temperature,
        );
      case 'groq':
        return _callGroq(
          prompt: prompt,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          temperature: temperature,
        );
      case 'openrouter':
        return _callOpenRouter(
          prompt: prompt,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          temperature: temperature,
        );
      case 'gemini':
        return _callGemini(
          prompt: '$systemPrompt\n\n$prompt',
          maxTokens: maxTokens,
          temperature: temperature,
        );
      default:
        // OpenAI兼容接口（openai/deepseek/qianwen/zhipu/moonshot/custom）
        return _callOpenAICompatible(
          prompt: prompt,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          temperature: temperature,
        );
    }
  }

  // ===== Pollinations AI（完全免费，无需注册）=====
  /// Pollinations.AI 免费文本生成API
  /// 文档：https://text.pollinations.ai
  Future<String?> _callPollinations({
    required String systemPrompt,
    required String prompt,
    int maxTokens = 500,
    double temperature = 0.8,
  }) async {
    final model = config.model.isNotEmpty ? config.model : 'openai';
    final client = _client();
    try {
      // 先尝试GET请求（简单模式）
      final resp = await client
          .get(Uri.parse('https://text.pollinations.ai/${Uri.encodeComponent(prompt)}'
              '?model=$model'
              '&system=${Uri.encodeComponent(systemPrompt)}'
              '&temperature=$temperature'))
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final text = resp.body.trim();
        if (text.isNotEmpty && !text.startsWith('<') && !text.startsWith('{')) {
          return text;
        }
      }

      // 降级：POST JSON格式（OpenAI兼容）
      final postResp = await client
          .post(
            Uri.parse('https://text.pollinations.ai/openai'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': prompt},
              ],
              'max_tokens': maxTokens,
              'temperature': temperature,
              'seed': DateTime.now().millisecondsSinceEpoch % 9999,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (postResp.statusCode == 200) {
        final data = jsonDecode(postResp.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final msg = choices[0]['message'] as Map<String, dynamic>?;
          return (msg?['content'] as String?)?.trim();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Pollinations exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  // ===== Groq API（免费额度，速度极快）=====
  /// Groq: https://console.groq.com/keys
  /// 免费模型：llama-3.1-8b-instant, llama3-70b-8192, gemma2-9b-it, mixtral-8x7b-32768
  Future<String?> _callGroq({
    required String prompt,
    required String systemPrompt,
    int maxTokens = 500,
    double temperature = 0.8,
  }) async {
    final model = config.model.isNotEmpty ? config.model : 'llama-3.1-8b-instant';
    final client = _client();
    try {
      final resp = await client
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
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
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final msg = choices[0]['message'] as Map<String, dynamic>?;
          return (msg?['content'] as String?)?.trim();
        }
      } else {
        if (kDebugMode) {
          debugPrint('Groq error ${resp.statusCode}: '
              '${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Groq exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  // ===== OpenRouter（有免费模型）=====
  Future<String?> _callOpenRouter({
    required String prompt,
    required String systemPrompt,
    int maxTokens = 500,
    double temperature = 0.8,
  }) async {
    final model = config.model.isNotEmpty
        ? config.model
        : 'meta-llama/llama-3.1-8b-instruct:free';
    final client = _client();
    try {
      final resp = await client
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
              'HTTP-Referer': 'https://github.com/channelcloner',
              'X-Title': 'Channel Cloner',
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
          debugPrint('OpenRouter error ${resp.statusCode}: '
              '${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('OpenRouter exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  // ===== Gemini API =====
  Future<String?> _callGemini({
    required String prompt,
    int maxTokens = 500,
    double temperature = 0.8,
  }) async {
    final model = config.model.isNotEmpty ? config.model : 'gemini-2.0-flash-exp';
    final baseUrl = config.baseUrl.isNotEmpty
        ? config.baseUrl
        : 'https://generativelanguage.googleapis.com/v1beta';
    final url = '$baseUrl/models/$model:generateContent?key=${config.apiKey}';
    final client = _client();
    try {
      final body = {
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': temperature,
          'maxOutputTokens': maxTokens,
        },
        'safetySettings': [
          {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_NONE'},
        ],
      };
      final resp = await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return (parts[0]['text'] as String?)?.trim();
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('Gemini error ${resp.statusCode}: '
              '${resp.body.substring(0, resp.body.length.clamp(0, 300))}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Gemini exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  // ===== OpenAI兼容接口 =====
  Future<String?> _callOpenAICompatible({
    required String prompt,
    required String systemPrompt,
    int maxTokens = 500,
    double temperature = 0.8,
  }) async {
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
          debugPrint('AI API error ${resp.statusCode}: '
              '${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AI API exception: $e');
    } finally {
      client.close();
    }
    return null;
  }

  // ===== 润色功能 =====

  /// 轻度润色文案（保持原意，稍作修改避免重复）
  Future<String?> polishCaption({
    required String originalCaption,
    String? customPrompt,
    PolishStyle style = PolishStyle.light,
  }) async {
    if (originalCaption.trim().isEmpty) return null;

    final styleDesc = _getStyleDescription(style);
    final systemPrompt = '''你是一个专业的内容润色助手，专门处理Telegram频道的内容文案。

核心规则：
1. 保持原文的核心含义和语气
2. $styleDesc
3. 不要添加任何解释、前缀或后缀说明
4. 直接输出润色后的文本，不要说"润色后："等前缀
5. 保留原文中的表情符号，可以适当调整位置或数量
6. 如果原文很短（少于10字），保持简短风格
7. 涉及成人内容时，保持原有尺度，用更生动的词汇替换
8. 语言：保持和原文相同的语言

${customPrompt != null && customPrompt.isNotEmpty ? "额外要求：$customPrompt" : ""}''';

    final userMsg = '请润色以下内容：\n\n$originalCaption';

    return _callAI(
      prompt: userMsg,
      systemPrompt: systemPrompt,
      maxTokens: originalCaption.length * 2 + 200,
      temperature: style == PolishStyle.light ? 0.6 : 0.85,
    );
  }

  /// 完全改写文案
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
5. 涉及成人/18+内容时保持尺度，用更吸引人的描述
6. 语言：保持和原文相同的语言
${prompt != null && prompt.isNotEmpty ? "7. 额外要求：$prompt" : ""}''';

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

  String _getStyleDescription(PolishStyle style) {
    switch (style) {
      case PolishStyle.light:
        return '轻度润色：只修改5-20%的词汇，保持原文结构，让内容看起来像原创但内容基本一致';
      case PolishStyle.medium:
        return '中度改写：修改30-50%的表达，保持核心意思，但句式和词汇有明显变化';
      case PolishStyle.heavy:
        return '大幅改写：全面重新表达，只保留核心主题，语言风格可以完全不同';
    }
  }

  /// 测试 AI 连接
  Future<bool> testConnection() async {
    if (config.provider == 'groq') {
      final result = await _callGroq(
        prompt: '请只回复数字"1"',
        systemPrompt: '你是一个AI助手。',
        maxTokens: 10,
        temperature: 0.1,
      );
      return result != null && result.isNotEmpty;
    }
    if (config.provider == 'pollinations') {
      final result = await _callPollinations(
        systemPrompt: '你是一个AI助手。',
        prompt: '请只回复数字"1"',
        maxTokens: 10,
        temperature: 0.1,
      );
      return result != null && result.isNotEmpty;
    }
    if (config.provider == 'gemini') {
      final result = await _callGemini(
        prompt: '请只回复数字"1"，不要其他任何内容。',
        maxTokens: 10,
        temperature: 0.1,
      );
      return result != null && result.isNotEmpty;
    }
    if (config.provider == 'openrouter') {
      final result = await _callOpenRouter(
        prompt: '请回复"ok"两个字',
        systemPrompt: '你是一个AI助手。',
        maxTokens: 10,
        temperature: 0.1,
      );
      return result != null && result.isNotEmpty;
    }
    final result = await _callOpenAICompatible(
      prompt: '请回复"连接成功"四个字',
      systemPrompt: '你是一个AI助手。',
      maxTokens: 20,
      temperature: 0.1,
    );
    return result != null && result.isNotEmpty;
  }
}

/// 润色风格
enum PolishStyle {
  light,   // 轻度（仅替换部分词汇）
  medium,  // 中度（句式重组）
  heavy,   // 重度（完全改写）
}
