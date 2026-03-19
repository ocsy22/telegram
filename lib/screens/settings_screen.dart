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
  late TextEditingController _aiModelCtrl;

  bool _showApiKey = false;
  bool _testingAi = false;
  String? _aiTestResult;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppProvider>().settings;
    _aiKeyCtrl = TextEditingController(text: settings.aiConfig.apiKey);
    _aiBaseUrlCtrl = TextEditingController(text: settings.aiConfig.baseUrl);
    _aiModelCtrl = TextEditingController(text: settings.aiConfig.model);
  }

  @override
  void dispose() {
    _aiKeyCtrl.dispose();
    _aiBaseUrlCtrl.dispose();
    _aiModelCtrl.dispose();
    super.dispose();
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
            title: const Text('全局设置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
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
                    '忽略SSL证书错误',
                    '绕过SSL验证，解决网络连接问题（推荐开启）',
                    settings.ignoreSsl,
                    (v) => provider.updateSettings(AppSettings(
                      ignoreSsl: v,
                      aiConfig: settings.aiConfig,
                      globalDelayMin: settings.globalDelayMin,
                      globalDelayMax: settings.globalDelayMax,
                    )),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('全局默认延迟', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('任务每条消息之间的等待时间 ${settings.globalDelayMin}~${settings.globalDelayMax}秒',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _numChip(settings.globalDelayMin, '最小',
                                (v) => provider.updateSettings(AppSettings(
                                      ignoreSsl: settings.ignoreSsl,
                                      aiConfig: settings.aiConfig,
                                      globalDelayMin: v,
                                      globalDelayMax: settings.globalDelayMax,
                                    ))),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('~', style: TextStyle(color: Colors.white38)),
                            ),
                            _numChip(settings.globalDelayMax, '最大',
                                (v) => provider.updateSettings(AppSettings(
                                      ignoreSsl: settings.ignoreSsl,
                                      aiConfig: settings.aiConfig,
                                      globalDelayMin: settings.globalDelayMin,
                                      globalDelayMax: v,
                                    ))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ===== AI 配置 =====
                _section('AI 文案改写', Icons.auto_awesome_rounded, [
                  _toggleRow(
                    context,
                    '启用AI功能',
                    '开启后可在任务中使用AI自动改写转发内容的文案',
                    settings.aiConfig.enabled,
                    (v) {
                      final ai = settings.aiConfig;
                      provider.updateSettings(AppSettings(
                        ignoreSsl: settings.ignoreSsl,
                        aiConfig: AiConfig(
                          provider: ai.provider,
                          apiKey: ai.apiKey,
                          model: ai.model,
                          baseUrl: ai.baseUrl,
                          enabled: v,
                        ),
                        globalDelayMin: settings.globalDelayMin,
                        globalDelayMax: settings.globalDelayMax,
                      ));
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  // AI 提供商选择
                  _sectionLabel('AI 服务商'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _providerChip(context, settings, provider, 'openai', 'OpenAI'),
                      _providerChip(context, settings, provider, 'deepseek', 'DeepSeek'),
                      _providerChip(context, settings, provider, 'qianwen', '通义千问'),
                      _providerChip(context, settings, provider, 'zhipu', '智谱GLM'),
                      _providerChip(context, settings, provider, 'moonshot', 'Kimi'),
                      _providerChip(context, settings, provider, 'custom', '自定义'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // API Key
                  TextField(
                    controller: _aiKeyCtrl,
                    obscureText: !_showApiKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-xxxx...',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility, size: 18),
                            onPressed: () => setState(() => _showApiKey = !_showApiKey),
                          ),
                          IconButton(
                            icon: const Icon(Icons.save_rounded, size: 18),
                            tooltip: '快速保存',
                            onPressed: () {
                              final ai = settings.aiConfig;
                              provider.updateSettings(AppSettings(
                                ignoreSsl: settings.ignoreSsl,
                                aiConfig: AiConfig(
                                  provider: ai.provider,
                                  apiKey: _aiKeyCtrl.text.trim(),
                                  model: ai.model,
                                  baseUrl: ai.baseUrl,
                                  enabled: ai.enabled,
                                ),
                                globalDelayMin: settings.globalDelayMin,
                                globalDelayMax: settings.globalDelayMax,
                              ));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('API Key 已保存'), backgroundColor: Color(0xFF00E676)),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 模型
                  TextField(
                    controller: _aiModelCtrl,
                    decoration: InputDecoration(
                      labelText: '模型',
                      hintText: settings.aiConfig.defaultModel,
                      helperText: '默认：${settings.aiConfig.defaultModel}',
                    ),
                  ),
                  if (settings.aiConfig.provider == 'custom') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _aiBaseUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: '自定义API地址',
                        hintText: 'https://your-api.com/v1',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 测试 AI
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _testingAi ? null : () => _testAI(provider),
                        icon: _testingAi
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.science_rounded, size: 18),
                        label: Text(_testingAi ? '测试中...' : '测试连接'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                          foregroundColor: const Color(0xFF00E5FF),
                        ),
                      ),
                      if (_aiTestResult != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          _aiTestResult!,
                          style: TextStyle(
                            color: _aiTestResult!.contains('✅') ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                          ),
                        ),
                      ],
                    ],
                  ),
                ]),
                const SizedBox(height: 20),

                // ===== 关于 =====
                _section('关于', Icons.info_outline_rounded, [
                  _infoRow('版本', 'v1.0.0'),
                  _infoRow('名称', 'Channel Cloner'),
                  _infoRow('描述', 'Telegram频道克隆工具，支持无引用转发、监听任务、AI改写'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.2)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('功能特色', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        SizedBox(height: 8),
                        _Feature('✅ 无引用转发 - 转发内容不显示来源频道'),
                        _Feature('✅ 一对一/多对多克隆模式'),
                        _Feature('✅ 多账号管理（Bot Token/用户API）'),
                        _Feature('✅ 自由选择消息范围（起止ID）'),
                        _Feature('✅ 24小时自动监听，实时转发新内容'),
                        _Feature('✅ AI文案改写（支持6家AI服务商）'),
                        _Feature('✅ 内容类型过滤（图片/视频/文档等）'),
                        _Feature('✅ 转发记录和运行日志'),
                      ],
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _providerChip(BuildContext context, AppSettings settings, AppProvider provider, String value, String label) {
    final selected = settings.aiConfig.provider == value;
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () {
        final ai = settings.aiConfig;
        provider.updateSettings(AppSettings(
          ignoreSsl: settings.ignoreSsl,
          aiConfig: AiConfig(
            provider: value,
            apiKey: ai.apiKey,
            model: '',
            baseUrl: ai.baseUrl,
            enabled: ai.enabled,
          ),
          globalDelayMin: settings.globalDelayMin,
          globalDelayMax: settings.globalDelayMax,
        ));
        _aiModelCtrl.text = '';
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? primary : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? primary : Colors.white54,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _toggleRow(BuildContext context, String label, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
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
            width: 32,
            child: Text('$value$label', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
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
    return Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 13));
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13))),
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
                Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _testAI(AppProvider provider) async {
    setState(() { _testingAi = true; _aiTestResult = null; });
    final ai = provider.settings.aiConfig;
    final service = AiService(
      config: AiConfig(
        provider: ai.provider,
        apiKey: _aiKeyCtrl.text.trim(),
        model: _aiModelCtrl.text.trim().isNotEmpty ? _aiModelCtrl.text.trim() : ai.defaultModel,
        baseUrl: _aiBaseUrlCtrl.text.trim(),
        enabled: true,
      ),
    );
    final success = await service.testConnection();
    setState(() {
      _testingAi = false;
      _aiTestResult = success ? '✅ AI连接成功' : '❌ 连接失败，请检查API Key或网络';
    });
  }

  Future<void> _saveAll(AppProvider provider) async {
    final settings = provider.settings;
    final ai = settings.aiConfig;
    await provider.updateSettings(AppSettings(
      ignoreSsl: settings.ignoreSsl,
      aiConfig: AiConfig(
        provider: ai.provider,
        apiKey: _aiKeyCtrl.text.trim(),
        model: _aiModelCtrl.text.trim().isNotEmpty ? _aiModelCtrl.text.trim() : ai.model,
        baseUrl: _aiBaseUrlCtrl.text.trim(),
        enabled: ai.enabled,
      ),
      globalDelayMin: settings.globalDelayMin,
      globalDelayMax: settings.globalDelayMax,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存'), backgroundColor: Color(0xFF00E676)),
      );
    }
  }
}

class _Feature extends StatelessWidget {
  final String text;
  const _Feature(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70)),
    );
  }
}
