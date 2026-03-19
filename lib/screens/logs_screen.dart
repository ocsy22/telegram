import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;
  String _levelFilter = 'all';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        // 过滤日志
        var logs = provider.logs;
        if (_levelFilter != 'all') {
          logs = logs.where((l) => l.level.name == _levelFilter).toList();
        }

        // 自动滚到底部
        if (_autoScroll && logs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('运行日志', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    // 过滤器
                    _buildFilter(),
                    const SizedBox(width: 8),
                    // 自动滚动
                    _ToggleIconButton(
                      icon: Icons.vertical_align_bottom_rounded,
                      label: '自动滚动',
                      active: _autoScroll,
                      onTap: () => setState(() => _autoScroll = !_autoScroll),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => provider.clearLogs(),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // 统计条
              _buildStatBar(context, provider),
              // 日志列表
              Expanded(
                child: logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.list_alt_rounded, size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            const Text('暂无日志', style: TextStyle(color: Colors.white38)),
                          ],
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF1E1E3A)),
                        ),
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: logs.length,
                          itemBuilder: (context, i) {
                            final log = logs[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatTime(log.time),
                                    style: const TextStyle(
                                      color: Color(0xFF555577),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 4,
                                    height: 16,
                                    margin: const EdgeInsets.only(top: 1),
                                    decoration: BoxDecoration(
                                      color: log.color,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      log.message,
                                      style: TextStyle(
                                        color: log.color,
                                        fontSize: 12.5,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilter() {
    final options = ['all', 'info', 'success', 'warning', 'error'];
    final labels = {'all': '全部', 'info': '信息', 'success': '成功', 'warning': '警告', 'error': '错误'};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: _levelFilter,
        underline: const SizedBox.shrink(),
        isDense: true,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
        dropdownColor: Theme.of(context).colorScheme.surface,
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(labels[o]!))).toList(),
        onChanged: (v) => setState(() => _levelFilter = v ?? 'all'),
      ),
    );
  }

  Widget _buildStatBar(BuildContext context, AppProvider provider) {
    final logs = provider.logs;
    final success = logs.where((l) => l.level == LogLevel.success).length;
    final warning = logs.where((l) => l.level == LogLevel.warning).length;
    final error = logs.where((l) => l.level == LogLevel.error).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          _logStat('${logs.length}', '条记录', const Color(0xFF9999CC)),
          const SizedBox(width: 8),
          _logStat('$success', '成功', const Color(0xFF00E676)),
          const SizedBox(width: 8),
          _logStat('$warning', '警告', const Color(0xFFFFAB00)),
          const SizedBox(width: 8),
          _logStat('$error', '错误', const Color(0xFFFF5252)),
        ],
      ),
    );
  }

  Widget _logStat(String val, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$val $label',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _ToggleIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleIconButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? primary.withValues(alpha: 0.4) : Colors.white24),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: active ? primary : Colors.white38),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: active ? primary : Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
