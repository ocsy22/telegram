import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/app_models.dart';
import '../widgets/common_widgets.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('克隆任务', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateDialog(context, provider),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建任务'),
                ),
              ),
            ],
          ),
          body: provider.tasks.isEmpty
              ? _buildEmpty(context, provider)
              : _buildTaskList(context, provider),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context, AppProvider provider) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.copy_all_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text('还没有创建任务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('新建一个克隆任务开始搬运内容', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showCreateDialog(context, provider),
            icon: const Icon(Icons.add),
            label: const Text('新建任务'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, AppProvider provider) {
    return Row(
      children: [
        // 任务列表
        SizedBox(
          width: 320,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: provider.tasks.length,
            itemBuilder: (context, i) {
              final task = provider.tasks[i];
              return _TaskListItem(
                task: task,
                onTap: () => _showTaskDetail(context, provider, task),
                onStart: () => provider.startTask(task.id),
                onStop: () => provider.stopTask(task.id),
                onDelete: () => _confirmDelete(context, provider, task),
              );
            },
          ),
        ),
        // 分隔线
        VerticalDivider(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
        // 任务详情/统计
        Expanded(child: _TaskSummaryPanel(provider: provider)),
      ],
    );
  }

  Future<void> _showCreateDialog(BuildContext context, AppProvider provider) async {
    final task = provider.createTask();
    await showDialog(
      context: context,
      builder: (ctx) => _TaskEditDialog(
        task: task,
        isNew: true,
        provider: provider,
        onSave: (t) => provider.addTask(t),
      ),
    );
  }

  Future<void> _showTaskDetail(BuildContext context, AppProvider provider, CloneTask task) async {
    await showDialog(
      context: context,
      builder: (ctx) => _TaskEditDialog(
        task: task,
        isNew: false,
        provider: provider,
        onSave: (t) => provider.updateTask(t),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppProvider provider, CloneTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确认删除任务「${task.name}」？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.removeTask(task.id);
  }
}

// ===== 任务列表项 =====
class _TaskListItem extends StatelessWidget {
  final CloneTask task;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onDelete;

  const _TaskListItem({
    required this.task,
    required this.onTap,
    required this.onStart,
    required this.onStop,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isRunning = task.status == TaskStatus.running;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (task.mode == TaskMode.monitor
                          ? const Color(0xFF00B4D8)
                          : primary).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      task.mode == TaskMode.monitor
                          ? Icons.wifi_tethering_rounded
                          : Icons.copy_all_rounded,
                      color: task.mode == TaskMode.monitor ? const Color(0xFF00B4D8) : primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          task.mode == TaskMode.clone ? '克隆模式' : '监听模式',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(status: task.status),
                ],
              ),
              if (task.status == TaskStatus.running) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.mode == TaskMode.monitor ? null : task.progress,
                    backgroundColor: primary.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(primary),
                    minHeight: 4,
                  ),
                ),
                if (task.mode == TaskMode.clone)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${task.processedCount}/${task.totalCount}',
                      style: TextStyle(color: primary, fontSize: 11),
                    ),
                  ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${task.sourceChannels.length}源 → ${task.targetChannels.length}目标',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                  if (isRunning)
                    _ActionChip(
                      label: '停止',
                      icon: Icons.stop_rounded,
                      color: const Color(0xFFFF5252),
                      onTap: onStop,
                    )
                  else
                    _ActionChip(
                      label: '启动',
                      icon: Icons.play_arrow_rounded,
                      color: const Color(0xFF00E676),
                      onTap: onStart,
                    ),
                  const SizedBox(width: 4),
                  _ActionChip(
                    label: '删除',
                    icon: Icons.delete_outline_rounded,
                    color: Colors.red.withValues(alpha: 0.7),
                    onTap: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ===== 任务统计面板 =====
class _TaskSummaryPanel extends StatelessWidget {
  final AppProvider provider;
  const _TaskSummaryPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final total = provider.tasks.length;
    final running = provider.tasks.where((t) => t.status == TaskStatus.running).length;
    final completed = provider.tasks.where((t) => t.status == TaskStatus.completed).length;
    final totalRecords = provider.records.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('任务总览', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: InfoCard(icon: Icons.list_alt_rounded, title: '$total', subtitle: '任务总数')),
              const SizedBox(width: 12),
              Expanded(child: InfoCard(icon: Icons.play_circle_rounded, title: '$running', subtitle: '运行中', color: const Color(0xFF00E676))),
              const SizedBox(width: 12),
              Expanded(child: InfoCard(icon: Icons.check_circle_rounded, title: '$completed', subtitle: '已完成', color: const Color(0xFF6C63FF))),
              const SizedBox(width: 12),
              Expanded(child: InfoCard(icon: Icons.forward_to_inbox_rounded, title: '$totalRecords', subtitle: '已转发', color: const Color(0xFF00E5FF))),
            ],
          ),
          const SizedBox(height: 20),
          const Text('最近转发记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (provider.records.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text('暂无转发记录', style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: provider.records.length > 20 ? 20 : provider.records.length,
                itemBuilder: (context, i) {
                  final idx = provider.records.length - 1 - i;
                  final rec = provider.records[idx];
                  return _RecordItem(record: rec);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordItem extends StatelessWidget {
  final TransferRecord record;
  const _RecordItem({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(_mediaIcon(record.mediaType), size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${record.sourceChannel} → ${record.targetChannel}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (record.aiRewritten)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('AI', style: TextStyle(color: Color(0xFF6C63FF), fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 8),
          Text(
            _formatTime(record.transferredAt),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  IconData _mediaIcon(String type) {
    switch (type) {
      case 'photo': return Icons.image_outlined;
      case 'video': return Icons.videocam_outlined;
      case 'document': return Icons.attach_file_rounded;
      case 'audio': return Icons.audiotrack_rounded;
      default: return Icons.text_snippet_outlined;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${dt.month}/${dt.day}';
  }
}

// ===== 任务编辑对话框 =====
class _TaskEditDialog extends StatefulWidget {
  final CloneTask task;
  final bool isNew;
  final AppProvider provider;
  final Future<void> Function(CloneTask) onSave;

  const _TaskEditDialog({
    required this.task,
    required this.isNew,
    required this.provider,
    required this.onSave,
  });

  @override
  State<_TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<_TaskEditDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late final _nameCtrl = TextEditingController(text: widget.task.name);
  late final _srcCtrl = TextEditingController(text: widget.task.sourceChannels.join('\n'));
  late final _tgtCtrl = TextEditingController(text: widget.task.targetChannels.join('\n'));
  late final _promptCtrl = TextEditingController(text: widget.task.aiPrompt);
  late final _adKeywordsCtrl = TextEditingController(text: widget.task.adKeywords);

  late TaskMode _mode;
  late TransferMode _transferMode;
  late int _startId;
  late int _endId;
  late int _cloneCount;
  late int _monitorInterval;
  late int _delayMin;
  late int _delayMax;
  late bool _removeCaption;
  late bool _aiRewrite;
  late bool _filterAds;
  late bool _includeText;
  late bool _includePhoto;
  late bool _includeVideo;
  late bool _includeDocument;
  late bool _includeAudio;
  late bool _includeSticker;

  String _srcAccountId = '';
  String _tgtAccountId = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _mode = widget.task.mode;
    _transferMode = widget.task.transferMode;
    _startId = widget.task.startMessageId;
    _endId = widget.task.endMessageId;
    _cloneCount = widget.task.cloneCount;
    _monitorInterval = widget.task.monitorIntervalSec;
    _delayMin = widget.task.delayMin;
    _delayMax = widget.task.delayMax;
    _removeCaption = widget.task.removeCaption;
    _aiRewrite = widget.task.aiRewrite;
    _filterAds = widget.task.filterAds;
    _includeText = widget.task.includeText;
    _includePhoto = widget.task.includePhoto;
    _includeVideo = widget.task.includeVideo;
    _includeDocument = widget.task.includeDocument;
    _includeAudio = widget.task.includeAudio;
    _includeSticker = widget.task.includeSticker;
    _srcAccountId = widget.task.sourceAccountId;
    _tgtAccountId = widget.task.targetAccountId;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _srcCtrl.dispose();
    _tgtCtrl.dispose();
    _promptCtrl.dispose();
    _adKeywordsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 620,
        height: 580,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Icon(Icons.copy_all_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    widget.isNew ? '新建任务' : '编辑任务',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: '基本配置'),
                  Tab(text: '内容过滤'),
                  Tab(text: 'AI改写'),
                ],
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: Colors.white54,
                indicatorColor: theme.colorScheme.primary,
                dividerColor: Colors.transparent,
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildBasicTab(),
                  _buildFilterTab(),
                  _buildAiTab(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('保存任务'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicTab() {
    final accounts = widget.provider.accounts;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: '任务名称'),
          ),
          const SizedBox(height: 16),
          // 模式选择
          Row(
            children: [
              const Text('任务模式：', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 12),
              _ModeChip(
                label: '克隆模式',
                icon: Icons.copy_all_rounded,
                selected: _mode == TaskMode.clone,
                onTap: () => setState(() => _mode = TaskMode.clone),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                label: '监听模式',
                icon: Icons.wifi_tethering_rounded,
                selected: _mode == TaskMode.monitor,
                onTap: () => setState(() => _mode = TaskMode.monitor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 账号选择
          if (accounts.isNotEmpty) ...[
            _buildAccountDropdown('发送账号（Bot Token）', _srcAccountId, (v) {
              setState(() => _srcAccountId = v);
              _tgtAccountId = v; // 同账号即可用于接收
            }, accounts),
            const SizedBox(height: 12),
          ],
          // 来源频道
          TextField(
            controller: _srcCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '来源频道（每行一个）',
              hintText: '@channelname 或 -1001234567890',
            ),
          ),
          const SizedBox(height: 12),
          // 目标频道
          TextField(
            controller: _tgtCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '目标频道（每行一个）',
              hintText: '@mychannel 或 -1001234567890',
            ),
          ),
          const SizedBox(height: 16),
          // 克隆模式专属设置
          if (_mode == TaskMode.clone) ...[
            _sectionLabel('消息范围'),
            Row(
              children: [
                Expanded(
                  child: _numField('起始消息ID（0=从头）', _startId, (v) => _startId = v),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _numField('结束消息ID（0=不限）', _endId, (v) => _endId = v),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _numField('数量限制（0=不限）', _cloneCount, (v) => _cloneCount = v),
                ),
              ],
            ),
          ],
          if (_mode == TaskMode.monitor) ...[
            _sectionLabel('监听设置'),
            _slider('轮询间隔', _monitorInterval.toDouble(), 5, 300, (v) => setState(() => _monitorInterval = v.round()),
                unit: '秒'),
          ],
          const SizedBox(height: 12),
          _sectionLabel('转发延迟'),
          Row(
            children: [
              Expanded(child: _numField('最小延迟(秒)', _delayMin, (v) => _delayMin = v)),
              const SizedBox(width: 12),
              Expanded(child: _numField('最大延迟(秒)', _delayMax, (v) => _delayMax = v)),
            ],
          ),
          const SizedBox(height: 12),
          _toggleRow('去除原始文案', _removeCaption, (v) => setState(() => _removeCaption = v)),
        ],
      ),
    );
  }

  Widget _buildFilterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选择要转发的内容类型', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          _toggleRow('文字消息', _includeText, (v) => setState(() => _includeText = v)),
          _toggleRow('图片', _includePhoto, (v) => setState(() => _includePhoto = v)),
          _toggleRow('视频', _includeVideo, (v) => setState(() => _includeVideo = v)),
          _toggleRow('文件/文档', _includeDocument, (v) => setState(() => _includeDocument = v)),
          _toggleRow('音频', _includeAudio, (v) => setState(() => _includeAudio = v)),
          _toggleRow('贴纸', _includeSticker, (v) => setState(() => _includeSticker = v)),
          const Divider(height: 28),
          // ===== 广告过滤 =====
          Row(
            children: [
              const Icon(Icons.block_rounded, size: 16, color: Color(0xFFFF5252)),
              const SizedBox(width: 6),
              const Text('广告自动过滤', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '自动跳过含链接、@用户名、招募/推广词的消息',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _toggleRow('启用广告过滤', _filterAds, (v) => setState(() => _filterAds = v)),
          if (_filterAds) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _adKeywordsCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '自定义过滤关键词（每行一个，精确匹配）',
                hintText: '例如：\n加群\n点击链接\n免费领取',
                helperText: '自定义关键词与内置广告规则叠加使用',
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.2)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('内置过滤规则（已包含）：', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('• 含 t.me/ 或 telegram.me/ 链接', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text('• 含 http:// / https:// 链接', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text('• 含 @用户名（5字符以上）', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text('• 含招募/加群/推广等广告词', style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiTab() {
    final aiEnabled = widget.provider.settings.aiConfig.enabled &&
        widget.provider.settings.aiConfig.apiKey.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!aiEnabled)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFAB00).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFAB00).withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFFAB00), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '请先在「设置」页面配置并启用AI服务',
                      style: TextStyle(color: Color(0xFFFFAB00), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          _toggleRow('AI改写文案', _aiRewrite, (v) => setState(() => _aiRewrite = v)),
          if (_aiRewrite) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _promptCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '改写提示词（可选）',
                hintText: '例如：语气活泼、加入emoji、保持标题不变...',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountDropdown(String label, String value, Function(String) onChanged,
      List<TelegramAccount> accounts) {
    final botAccounts = accounts.where((a) => a.type == AccountType.bot).toList();
    if (botAccounts.isEmpty) return const SizedBox.shrink();
    String? current = botAccounts.any((a) => a.id == value) ? value : null;
    return DropdownButtonFormField<String>(
      value: current,
      decoration: InputDecoration(labelText: label),
      items: botAccounts.map((a) => DropdownMenuItem(
        value: a.id,
        child: Text(a.name.isNotEmpty ? a.name : a.username ?? a.id),
      )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
      dropdownColor: Theme.of(context).colorScheme.surface,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String unit = ''}) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        Text('${value.round()}$unit', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _numField(String label, int initVal, Function(int) onChanged) {
    return TextFormField(
      initialValue: initVal.toString(),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => onChanged(int.tryParse(v) ?? initVal),
    );
  }

  void _save() {
    widget.task.name = _nameCtrl.text.trim();
    widget.task.sourceChannels = _srcCtrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    widget.task.targetChannels = _tgtCtrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    widget.task.mode = _mode;
    widget.task.transferMode = _transferMode;
    widget.task.startMessageId = _startId;
    widget.task.endMessageId = _endId;
    widget.task.cloneCount = _cloneCount;
    widget.task.monitorIntervalSec = _monitorInterval;
    widget.task.delayMin = _delayMin;
    widget.task.delayMax = _delayMax;
    widget.task.removeCaption = _removeCaption;
    widget.task.aiRewrite = _aiRewrite;
    widget.task.aiPrompt = _promptCtrl.text.trim();
    widget.task.filterAds = _filterAds;
    widget.task.adKeywords = _adKeywordsCtrl.text.trim();
    widget.task.includeText = _includeText;
    widget.task.includePhoto = _includePhoto;
    widget.task.includeVideo = _includeVideo;
    widget.task.includeDocument = _includeDocument;
    widget.task.includeAudio = _includeAudio;
    widget.task.includeSticker = _includeSticker;
    widget.task.sourceAccountId = _srcAccountId;
    widget.task.targetAccountId = _tgtAccountId;
    widget.onSave(widget.task);
    Navigator.pop(context);
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? primary : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? primary : Colors.white54),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: selected ? primary : Colors.white54, fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
