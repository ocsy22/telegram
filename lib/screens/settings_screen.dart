import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/app_models.dart';
import '../services/ai_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _aiKeyCtrl;
  late TextEditingController _aiBaseUrlCtrl;
  late TextEditingController _customModelCtrl; // 自定义模型输入框

  bool _showApiKey = false;
  bool _testingAi = false;
  String? _aiTestResult;
  String? _selectedModel; // 当前选中的模型

  // 各提供商的可选模型列表
  static const Map<String, List<String>> _providerModels = {
    // ===== 免费服务（无需API Key）=====
    'pollinations': [
      'openai',           // GPT-4o-mini（免费）
      'mistral',          // Mistral Large（免费）
      'claude-hybridspace', // Claude（免费）
      'qwen-coder',       // 通义千问Coder（免费）
      'deepseek-r1',      // DeepSeek R1（免费）
      'llamascout',       // Llama Scout（免费）
      'gemini',           // Gemini（免费）
    ],
    // ===== OpenRouter（有免费模型，需免费注册Key）=====
    'openrouter': [
      'meta-llama/llama-3.1-8b-instruct:free',
      'meta-llama/llama-3.2-3b-instruct:free',
      'google/gemma-3-12b-it:free',
      'microsoft/phi-3-mini-128k-instruct:free',
      'qwen/qwen-2-7b-instruct:free',
      'mistralai/mistral-7b-instruct:free',
      'nousresearch/hermes-3-llama-3.1-405b:free',
    ],
    // ===== 付费服务 =====
    'openai': [
      'gpt-3.5-turbo',
      'gpt-4',
      'gpt-4-turbo',
      'gpt-4o',
      'gpt-4o-mini',
    ],
    'deepseek': [
      'deepseek-chat',
      'deepseek-reasoner',
    ],
    'qianwen': [
      'qwen-turbo',
      'qwen-plus',
      'qwen-max',
      'qwen-long',
    ],
    'zhipu': [
      'glm-4-flash',
      'glm-4',
      'glm-4-plus',
      'glm-3-turbo',
    ],
    'moonshot': [
      'moonshot-v1-8k',
      'moonshot-v1-32k',
      'moonshot-v1-128k',
    ],
    'gemini': [
      'gemini-2.0-flash-exp',
      'gemini-1.5-flash',
      'gemini-1.5-pro',
    ],
    'custom': [],
  };

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppProvider>().settings;
    _aiKeyCtrl = TextEditingController(text: settings.aiConfig.apiKey);
    _aiBaseUrlCtrl = TextEditingController(text: settings.aiConfig.baseUrl);
    // 初始化选中模型
    final savedModel = settings.aiConfig.model;
    final models = _providerModels[settings.aiConfig.provider] ?? [];
    if (settings.aiConfig.provider == 'custom') {
      _selectedModel = savedModel;
      _customModelCtrl = TextEditingController(text: savedModel);
    } else {
      _selectedModel = models.contains(savedModel)
          ? savedModel
          : (models.isNotEmpty ? models.first : null);
      _customModelCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _aiKeyCtrl.dispose();
    _aiBaseUrlCtrl.dispose();
    _customModelCtrl.dispose();
    super.dispose();
  }

  List<String> _currentModels(String provider) {
    return _providerModels[provider] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final settings = provider.settings;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('全局设置',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ElevatedButton.icon(
                  onPressed: () => _saveAll(provider),
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('保存设置'),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== 通用设置 =====
                _section('通用设置', Icons.settings_rounded, [
                  _toggleRow(
                    context,
                    '白色主题',
                    '切换为白色/浅色界面风格',
                    settings.lightTheme,
                    (v) => provider.updateSettings(settings.copyWith(lightTheme: v)),
                  ),
                  const Divider(),
                  _toggleRow(
                    context,
                    '忽略SSL证书错误',
                    '绕过SSL验证，解决网络连接问题（推荐开启）',
                    settings.ignoreSsl,
                    (v) => provider.updateSettings(settings.copyWith(ignoreSsl: v)),
                  ),
                  const Divider(),
                  _delayRow(context, settings, provider),
                ]),
                const SizedBox(height: 20),

                // ===== AI 配置 =====
                _section('AI 文案改写', Icons.auto_awesome_rounded, [
                  _toggleRow(
                    context,
                    '启用AI功能',
                    '开启后可在任务中使用AI自动改写转发内容的文案',
                    settings.aiConfig.enabled,
                    (v) => provider.updateSettings(
                        settings.copyWith(aiConfig: settings.aiConfig.copyWith(enabled: v))),
                  ),
                  const Divider(),
                  const SizedBox(height: 12),

                  // 免费服务商提示
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: Color(0xFF00E676), size: 15),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '💡 推荐：Pollinations AI 完全免费，无需注册，直接开启即可使用文案润色！\n'
                            'OpenRouter 也提供免费模型（注册后获取免费Key）',
                            style: TextStyle(color: Color(0xFF00E676), fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 服务商选择
                  _sectionLabel('AI 服务商'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _providerModels.keys.map((key) {
                      const labels = {
                        'pollinations': '🆓 Pollinations(免费)',
                        'openrouter': '🆓 OpenRouter(免费模型)',
                        'openai': 'OpenAI',
                        'deepseek': 'DeepSeek',
                        'qianwen': '通义千问',
                        'zhipu': '智谱GLM',
                        'moonshot': 'Kimi',
                        'gemini': 'Google Gemini',
                        'custom': '自定义',
                      };
                      return _providerChip(
                          context, settings, provider, key, labels[key] ?? key);
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // 模型选择（下拉）
                  _sectionLabel('模型选择'),
                  const SizedBox(height: 8),
                  _buildModelSelector(context, settings, provider),
                  const SizedBox(height: 16),

                  // API Key（免费服务商不需要）
                  if (!settings.aiConfig.isFreeProvider) ...[
                    _sectionLabel('API Key'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _aiKeyCtrl,
                      obscureText: !_showApiKey,
                      decoration: InputDecoration(
                        hintText: _keyHint(settings.aiConfig.provider),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                  _showApiKey
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18),
                              onPressed: () =>
                                  setState(() => _showApiKey = !_showApiKey),
                            ),
                            IconButton(
                              icon: const Icon(Icons.save_rounded, size: 18),
                              tooltip: '快速保存Key',
                              onPressed: () => _quickSaveKey(provider, settings),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, 
                              color: Color(0xFF00E676), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              settings.aiConfig.provider == 'pollinations'
                                  ? 'Pollinations AI 完全免费，无需API Key，直接开启使用！'
                                  : '此服务商提供免费模型，请从 openrouter.ai 注册获取免费API Key',
                              style: const TextStyle(color: Color(0xFF00E676), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (settings.aiConfig.provider == 'openrouter') ...[
                      _sectionLabel('API Key（OpenRouter免费Key）'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _aiKeyCtrl,
                        obscureText: !_showApiKey,
                        decoration: InputDecoration(
                          hintText: 'sk-or-v1-... (openrouter.ai 免费注册获取)',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                    _showApiKey
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    size: 18),
                                onPressed: () =>
                                    setState(() => _showApiKey = !_showApiKey),
                              ),
                              IconButton(
                                icon: const Icon(Icons.save_rounded, size: 18),
                                tooltip: '快速保存Key',
                                onPressed: () => _quickSaveKey(provider, settings),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],

                  // 自定义 API 地址（所有服务商都可以覆盖，custom必填）
                  _sectionLabel(settings.aiConfig.provider == 'custom'
                      ? '自定义 API 地址（必填）'
                      : '自定义 API 地址（可选，留空则用默认地址）'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _aiBaseUrlCtrl,
                    decoration: InputDecoration(
                      hintText: settings.aiConfig.effectiveBaseUrl,
                      helperText:
                          '当前: ${_aiBaseUrlCtrl.text.isNotEmpty ? _aiBaseUrlCtrl.text : settings.aiConfig.effectiveBaseUrl}',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 测试连接按钮
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed:
                            _testingAi ? null : () => _testAI(provider, settings),
                        icon: _testingAi
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.science_rounded, size: 18),
                        label: Text(_testingAi ? '测试中...' : '测试AI连接'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF00E5FF).withValues(alpha: 0.2),
                          foregroundColor: const Color(0xFF00E5FF),
                        ),
                      ),
                      if (_aiTestResult != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _aiTestResult!,
                            style: TextStyle(
                              color: _aiTestResult!.contains('✅')
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFFFF5252),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ]),
                const SizedBox(height: 20),

                // ===== 关于 =====
                _section('关于', Icons.info_outline_rounded, [
                  _infoRow('版本', 'v1.2.0'),
                  _infoRow('名称', 'Channel Cloner'),
                  _infoRow('描述', 'Telegram频道克隆工具，无引用转发、媒体组、AI改写'),
                  const SizedBox(height: 12),
                  _featureCard(),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModelSelector(
      BuildContext context, AppSettings settings, AppProvider provider) {
    final models = _currentModels(settings.aiConfig.provider);

    if (settings.aiConfig.provider == 'custom') {
      // 自定义模式：手动输入，使用持久化controller
      return TextField(
        controller: _customModelCtrl,
        decoration: const InputDecoration(
          hintText: '输入模型名称，如 gpt-4o、claude-3-5-sonnet',
          helperText: '请输入您的自定义API所支持的模型名称',
        ),
        onChanged: (v) {
          _selectedModel = v;
        },
      );
    }

    // 标准模式：下拉选择
    // 确保当前值在列表中
    String? dropdownValue = _selectedModel;
    if (dropdownValue == null || !models.contains(dropdownValue)) {
      dropdownValue = models.isNotEmpty ? models.first : null;
      if (dropdownValue != null) {
        _selectedModel = dropdownValue;
      }
    }

    if (models.isEmpty) {
      return const Text('无可用模型', style: TextStyle(color: Colors.white38));
    }

    return DropdownButtonFormField<String>(
      initialValue: dropdownValue,
      decoration: InputDecoration(
        hintText: '选择模型',
        helperText: '推荐: ${settings.aiConfig.defaultModel}',
      ),
      dropdownColor: Theme.of(context).colorScheme.surface,
      items: models
          .map((m) => DropdownMenuItem(
                value: m,
                child: Text(m, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _selectedModel = v);
      },
    );
  }

  Widget _providerChip(BuildContext context, AppSettings settings,
      AppProvider provider, String value, String label) {
    final selected = settings.aiConfig.provider == value;
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 免费服务商用特殊颜色标识
    final isFree = value == 'pollinations' || value == 'openrouter';
    final accentColor = isFree ? const Color(0xFF00E676) : primary;
    return InkWell(
      onTap: () {
        final newModels = _providerModels[value] ?? [];
        final newDefaultModel = newModels.isNotEmpty ? newModels.first : '';
        setState(() {
          _selectedModel = newModels.isNotEmpty ? newModels.first : null;
          if (value == 'custom') {
            _customModelCtrl.text = '';
          }
        });
        provider.updateSettings(settings.copyWith(
          aiConfig: settings.aiConfig.copyWith(
            provider: value,
            model: newDefaultModel,
          ),
        ));
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accentColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? accentColor
                  : (isDark ? Colors.white24 : Colors.black26)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? accentColor
                : (isDark ? Colors.white54 : Colors.black54),
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _toggleRow(BuildContext context, String label, String subtitle,
      bool value, ValueChanged<bool> onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 12)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _delayRow(
      BuildContext context, AppSettings settings, AppProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('全局默认延迟',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    '任务每条消息之间的等待时间 '
                    '${settings.globalDelayMin}~${settings.globalDelayMax}秒',
                    style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 12)),
              ],
            ),
          ),
          _numChip(settings.globalDelayMin, '最小',
              (v) => provider.updateSettings(settings.copyWith(globalDelayMin: v))),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('~', style: TextStyle(color: Colors.white38)),
          ),
          _numChip(settings.globalDelayMax, '最大',
              (v) => provider.updateSettings(settings.copyWith(globalDelayMax: v))),
        ],
      ),
    );
  }

  Widget _numChip(int value, String label, ValueChanged<int> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => onChanged(value > 0 ? value - 1 : 0),
            icon: const Icon(Icons.remove, size: 14),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
          ),
          SizedBox(
            width: 38,
            child: Text('$value$label',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add, size: 14),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
            fontSize: 13));
  }

  Widget _infoRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 60,
              child: Text(label,
                  style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _featureCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.2)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('功能特色',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          SizedBox(height: 8),
          _Feature('✅ 无引用转发 - 转发内容不显示来源频道'),
          _Feature('✅ 媒体组整组转发 - 多视频/多图保持一条消息'),
          _Feature('✅ 用户账号MTProto模式 - 读取私有/他人频道'),
          _Feature('✅ 手机号验证码登录 - 完整MTProto授权'),
          _Feature('✅ 一对一/多对多克隆模式'),
          _Feature('✅ 多账号管理（Bot Token/用户API+MTProto）'),
          _Feature('✅ 自由选择消息范围（起止ID）'),
          _Feature('✅ 24小时自动监听，实时转发新内容'),
          _Feature('✅ 广告过滤 - 自动跳过含链接/联系方式消息'),
          _Feature('✅ AI文案润色 - Pollinations免费可用，无需Key'),
          _Feature('✅ AI改写支持：Pollinations/OpenRouter/Gemini等'),
          _Feature('✅ 内容类型过滤（图片/视频/文档等）'),
          _Feature('✅ 视频MD5修改（防重复检测）'),
          _Feature('✅ 白色/深色主题切换'),
          _Feature('✅ 转发记录和运行日志'),
        ],
      ),
    );
  }

  String _keyHint(String provider) {
    switch (provider) {
      case 'openai':
        return 'sk-xxxxxxxxxxxxxxxx';
      case 'deepseek':
        return 'sk-xxxxxxxxxxxxxxxx';
      case 'qianwen':
        return 'sk-xxxxxxxxxxxxxxxx';
      case 'zhipu':
        return 'xxxxxxxx.xxxxxxxx';
      case 'moonshot':
        return 'sk-xxxxxxxxxxxxxxxx';
      case 'gemini':
        return 'AIzaSyxxxxxxxxxxxxxxxxx';
      case 'openrouter':
        return 'sk-or-v1-xxxxxxxxxx (openrouter.ai 免费注册)';
      default:
        return '输入您的API Key';
    }
  }

  Future<void> _quickSaveKey(AppProvider provider, AppSettings settings) async {
    final newKey = _aiKeyCtrl.text.trim();
    if (newKey.isEmpty && !settings.aiConfig.isFreeProvider) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key 不能为空'), backgroundColor: Colors.orange),
      );
      return;
    }
    await provider.updateSettings(
        settings.copyWith(aiConfig: settings.aiConfig.copyWith(apiKey: newKey)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('API Key 已保存'),
            backgroundColor: Color(0xFF00E676)),
      );
    }
  }

  Future<void> _testAI(AppProvider provider, AppSettings settings) async {
    setState(() {
      _testingAi = true;
      _aiTestResult = null;
    });

    // 获取当前有效模型：优先用户选择，其次provider默认
    final String model;
    if (settings.aiConfig.provider == 'custom') {
      model = _customModelCtrl.text.trim();
      if (model.isEmpty) {
        setState(() {
          _testingAi = false;
          _aiTestResult = '❌ 自定义模式请先填写模型名称';
        });
        return;
      }
    } else {
      model = _selectedModel ?? settings.aiConfig.defaultModel;
    }

    final apiKey = _aiKeyCtrl.text.trim();
    // 免费服务商不需要Key检查
    if (apiKey.isEmpty && !settings.aiConfig.isFreeProvider && settings.aiConfig.provider != 'openrouter') {
      setState(() {
        _testingAi = false;
        _aiTestResult = '❌ 请先填写 API Key';
      });
      return;
    }

    final baseUrl = _aiBaseUrlCtrl.text.trim();

    final testConfig = AiConfig(
      provider: settings.aiConfig.provider,
      apiKey: apiKey,
      model: model,
      baseUrl: baseUrl,
      enabled: true,
    );

    final service = AiService(config: testConfig);
    final success = await service.testConnection();
    setState(() {
      _testingAi = false;
      _aiTestResult = success
          ? '✅ 连接成功！模型：$model'
          : '❌ 连接失败，请检查 API Key、模型名称或网络连通性';
    });
  }

  Future<void> _saveAll(AppProvider provider) async {
    final settings = provider.settings;
    // 根据提供商选择正确的模型值
    final String model;
    if (settings.aiConfig.provider == 'custom') {
      model = _customModelCtrl.text.trim();
    } else {
      model = _selectedModel ?? settings.aiConfig.defaultModel;
    }
    await provider.updateSettings(settings.copyWith(
      aiConfig: settings.aiConfig.copyWith(
        apiKey: _aiKeyCtrl.text.trim(),
        model: model,
        baseUrl: _aiBaseUrlCtrl.text.trim(),
      ),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('设置已保存'),
            backgroundColor: Color(0xFF00E676)),
      );
    }
  }
}

class _Feature extends StatelessWidget {
  final String text;
  const _Feature(this.text);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54)),
    );
  }
}
