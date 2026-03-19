import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/app_models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        var records = [...provider.records].reversed.toList();
        if (_filter.isNotEmpty) {
          records = records.where((r) =>
              r.sourceChannel.contains(_filter) ||
              r.targetChannel.contains(_filter) ||
              r.taskName.contains(_filter)).toList();
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('转发记录', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: TextButton.icon(
                  onPressed: () => _confirmClear(context, provider),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text('清空记录'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // 搜索栏
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  onChanged: (v) => setState(() => _filter = v),
                  decoration: const InputDecoration(
                    hintText: '搜索频道或任务名...',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              // 统计行
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _StatChip(label: '总记录', value: '${provider.records.length}', color: const Color(0xFF6C63FF)),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'AI改写',
                      value: '${provider.records.where((r) => r.aiRewritten).length}',
                      color: const Color(0xFF00E5FF),
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: '今日',
                      value: '${provider.records.where((r) => _isToday(r.transferredAt)).length}',
                      color: const Color(0xFF00E676),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 列表
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_rounded, size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            Text(
                              _filter.isNotEmpty ? '没有匹配的记录' : '暂无转发记录',
                              style: const TextStyle(color: Colors.white38),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: records.length,
                        itemBuilder: (context, i) => _RecordCard(record: records[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  Future<void> _confirmClear(BuildContext context, AppProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空记录'),
        content: const Text('确认清空所有转发记录？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.clearRecords();
  }
}

class _RecordCard extends StatelessWidget {
  final TransferRecord record;
  const _RecordCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _mediaColor(record.mediaType).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_mediaIcon(record.mediaType), color: _mediaColor(record.mediaType), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(record.taskName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 8),
                      if (record.aiRewritten)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('AI改写', style: TextStyle(color: theme.colorScheme.primary, fontSize: 10)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.sourceChannel,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.white38),
                      ),
                      Expanded(
                        child: Text(
                          record.targetChannel,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'ID: ${record.messageId}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(record.transferredAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _mediaIcon(String type) {
    switch (type) {
      case 'photo': return Icons.image_rounded;
      case 'video': return Icons.videocam_rounded;
      case 'document': return Icons.attach_file_rounded;
      case 'audio': return Icons.audiotrack_rounded;
      case 'sticker': return Icons.sticky_note_2_rounded;
      default: return Icons.text_snippet_rounded;
    }
  }

  Color _mediaColor(String type) {
    switch (type) {
      case 'photo': return const Color(0xFF00B4D8);
      case 'video': return const Color(0xFF6C63FF);
      case 'document': return const Color(0xFF00E5FF);
      case 'audio': return const Color(0xFFFF6B9D);
      default: return const Color(0xFF9999CC);
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12)),
        ],
      ),
    );
  }
}
