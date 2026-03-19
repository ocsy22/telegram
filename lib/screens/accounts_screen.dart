import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/app_models.dart';
import '../widgets/common_widgets.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildAppBar(context, provider),
          body: provider.accounts.isEmpty
              ? _buildEmpty(context, provider)
              : _buildList(context, provider),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AppProvider provider) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Text(
        '账号管理',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            children: [
              _AddButton(
                label: 'Bot账号',
                icon: Icons.smart_toy_outlined,
                onTap: () => _showAddDialog(context, provider, AccountType.bot),
              ),
              const SizedBox(width: 8),
              _AddButton(
                label: '用户API',
                icon: Icons.person_outline_rounded,
                onTap: () => _showAddDialog(context, provider, AccountType.userApi),
              ),
            ],
          ),
        ),
      ],
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
              Icons.people_outline_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text('还没有添加账号', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('添加 Bot Token 账号或用户账号来开始使用',
              style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.black45)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddDialog(context, provider, AccountType.bot),
            icon: const Icon(Icons.add),
            label: const Text('添加Bot账号'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, AppProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.accounts.length,
      itemBuilder: (context, i) {
        final account = provider.accounts[i];
        return _AccountCard(
          account: account,
          onEdit: () => _showEditDialog(context, provider, account),
          onDelete: () => _confirmDelete(context, provider, account),
          onTest: () => provider.testBotAccount(account),
        );
      },
    );
  }

  Future<void> _showAddDialog(BuildContext context, AppProvider provider, AccountType type) async {
    final account = provider.createAccount(type: type);
    await showDialog(
      context: context,
      builder: (ctx) => _AccountDialog(
        account: account,
        isNew: true,
        onSave: (acc) async {
          await provider.addAccount(acc);
          if (acc.type == AccountType.bot && acc.botToken.isNotEmpty) {
            await provider.testBotAccount(acc);
          }
        },
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, AppProvider provider, TelegramAccount account) async {
    await showDialog(
      context: context,
      builder: (ctx) => _AccountDialog(
        account: account,
        isNew: false,
        onSave: (acc) async {
          await provider.updateAccount(acc);
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppProvider provider, TelegramAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确认删除账号「${account.name}」？'),
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
    if (confirmed == true) await provider.removeAccount(account.id);
  }
}

// ===== 账号卡片 =====
class _AccountCard extends StatelessWidget {
  final TelegramAccount account;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<bool> Function() onTest;

  const _AccountCard({
    required this.account,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 头像
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: account.type == AccountType.bot
                      ? [const Color(0xFF6C63FF), const Color(0xFF8B5CF6)]
                      : [const Color(0xFF00B4D8), const Color(0xFF0096C7)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                account.type == AccountType.bot ? Icons.smart_toy_rounded : Icons.person_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          account.name.isNotEmpty ? account.name : '未命名',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      StatusBadge(status: account.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (account.username != null && account.username!.isNotEmpty)
                    Text('@${account.username}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          account.type == AccountType.bot ? 'Bot' : 'User API',
                          style: TextStyle(color: primary, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (account.errorMessage != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            account.errorMessage!,
                            style: const TextStyle(color: Color(0xFFFF5252), fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 操作按钮
            Column(
              children: [
                IconButton(
                  onPressed: onTest,
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 20),
                  tooltip: account.type == AccountType.bot ? '测试Bot连接' : '验证API配置',
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: '编辑',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: '删除',
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.red.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===== 添加/编辑账号对话框 =====
class _AccountDialog extends StatefulWidget {
  final TelegramAccount account;
  final bool isNew;
  final Future<void> Function(TelegramAccount) onSave;

  const _AccountDialog({
    required this.account,
    required this.isNew,
    required this.onSave,
  });

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _nameCtrl = TextEditingController(text: widget.account.name);
  late final _tokenCtrl = TextEditingController(text: widget.account.botToken);
  late final _phoneCtrl = TextEditingController(text: widget.account.phone);
  late final _apiIdCtrl = TextEditingController(text: widget.account.apiId);
  late final _apiHashCtrl = TextEditingController(text: widget.account.apiHash);
  bool _showToken = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tokenCtrl.dispose();
    _phoneCtrl.dispose();
    _apiIdCtrl.dispose();
    _apiHashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.account.type == AccountType.bot
                        ? Icons.smart_toy_rounded
                        : Icons.person_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.isNew
                        ? (widget.account.type == AccountType.bot ? '添加Bot账号' : '添加用户账号')
                        : '编辑账号',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _field('账号名称', _nameCtrl, hint: '例如：我的Bot'),
              const SizedBox(height: 12),
              // 用户账号说明（扫码登录）
              if (widget.account.type == AccountType.userApi) ...[                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4D8).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00B4D8).withValues(alpha: 0.2)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Color(0xFF00B4D8), size: 15),
                          SizedBox(width: 6),
                          Text('用户账号说明', style: TextStyle(color: Color(0xFF00B4D8), fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text('• 用户账号可以读取任意已加入的频道（包括他人频道）', style: TextStyle(fontSize: 12, color: Colors.white60)),
                      Text('• 需要在 my.telegram.org/apps 创建应用获取 API ID 和 Hash', style: TextStyle(fontSize: 12, color: Colors.white60)),
                      Text('• 填写手机号用于账号识别（不影响功能）', style: TextStyle(fontSize: 12, color: Colors.white60)),
                      SizedBox(height: 4),
                      Text('⚠️ 注意：用户账号仍通过Bot API转发消息，需配合Bot账号使用', style: TextStyle(fontSize: 11, color: Color(0xFFFFAB00))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.account.type == AccountType.bot) ...[
                _field(
                  'Bot Token',
                  _tokenCtrl,
                  hint: '1234567890:ABCDEFxxxx',
                  obscure: !_showToken,
                  suffix: IconButton(
                    icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility, size: 18),
                    onPressed: () => setState(() => _showToken = !_showToken),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '在 @BotFather 创建Bot后获取Token',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ] else ...[
                _field('手机号', _phoneCtrl, hint: '+86 13800138000'),
                const SizedBox(height: 12),
                _field('API ID', _apiIdCtrl, hint: '从 my.telegram.org 获取'),
                const SizedBox(height: 12),
                _field('API Hash', _apiHashCtrl, hint: '从 my.telegram.org 获取'),
                const SizedBox(height: 8),
                const Text(
                  '配置 API ID + API Hash 后点击验证，可访问您已加入的所有频道',
                  style: TextStyle(color: Color(0xFFFFAB00), fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_saving ? '保存中...' : '保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, bool obscure = false, Widget? suffix}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.account.name = _nameCtrl.text.trim();
    widget.account.botToken = _tokenCtrl.text.trim();
    widget.account.phone = _phoneCtrl.text.trim();
    widget.account.apiId = _apiIdCtrl.text.trim();
    widget.account.apiHash = _apiHashCtrl.text.trim();
    await widget.onSave(widget.account);
    if (mounted) Navigator.pop(context);
  }
}

// ===== 添加按钮 =====
class _AddButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _AddButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: primary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
