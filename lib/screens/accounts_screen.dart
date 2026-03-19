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
                onTap: () =>
                    _showAddDialog(context, provider, AccountType.userApi),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, AppProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text('还没有添加账号',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('添加 Bot Token 账号或用户账号来开始使用',
              style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black45)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () =>
                _showAddDialog(context, provider, AccountType.bot),
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
          provider: provider,
          onEdit: () => _showEditDialog(context, provider, account),
          onDelete: () => _confirmDelete(context, provider, account),
          onTest: () => provider.testBotAccount(account),
          onLogin: account.type == AccountType.userApi
              ? () => _showLoginDialog(context, provider, account)
              : null,
        );
      },
    );
  }

  Future<void> _showAddDialog(
      BuildContext context, AppProvider provider, AccountType type) async {
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

  Future<void> _showEditDialog(
      BuildContext context, AppProvider provider, TelegramAccount account) async {
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

  Future<void> _confirmDelete(
      BuildContext context, AppProvider provider, TelegramAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确认删除账号「${account.name}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
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

  /// 显示用户账号登录对话框
  Future<void> _showLoginDialog(
      BuildContext context, AppProvider provider, TelegramAccount account) async {
    await showDialog(
      context: context,
      builder: (ctx) => _UserLoginDialog(account: account, provider: provider),
    );
  }
}

// ===== 账号卡片 =====
class _AccountCard extends StatelessWidget {
  final TelegramAccount account;
  final AppProvider provider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<bool> Function() onTest;
  final VoidCallback? onLogin;

  const _AccountCard({
    required this.account,
    required this.provider,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
    this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
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
                account.type == AccountType.bot
                    ? Icons.smart_toy_rounded
                    : Icons.person_rounded,
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
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      StatusBadge(status: account.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (account.username != null &&
                      account.username!.isNotEmpty)
                    Text('@${account.username}',
                        style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontSize: 12)),
                  if (account.phone.isNotEmpty)
                    Text(account.phone,
                        style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          account.type == AccountType.bot
                              ? 'Bot'
                              : 'User API',
                          style: TextStyle(
                              color: primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (account.type == AccountType.userApi) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (account.telethonAuthorized
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFFFFAB00))
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            account.telethonAuthorized
                                ? '✅ MTProto已授权'
                                : '⚠️ 未登录',
                            style: TextStyle(
                              color: account.telethonAuthorized
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFFFFAB00),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                      if (account.errorMessage != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            account.errorMessage!,
                            style: const TextStyle(
                                color: Color(0xFFFF5252), fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // MTProto状态说明
                  if (account.type == AccountType.userApi) ...[
                    const SizedBox(height: 4),
                    Text(
                      account.telethonAuthorized
                          ? '可读取该账号加入的所有频道（公开+私有）'
                          : provider.telethonReady
                              ? '点击「登录」按钮完成手机号验证码登录'
                              : '需要安装Python+Telethon以启用MTProto',
                      style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            // 操作按钮
            Column(
              children: [
                if (onLogin != null)
                  IconButton(
                    onPressed: onLogin,
                    icon: const Icon(Icons.login_rounded, size: 20),
                    tooltip: '手机号登录（MTProto）',
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFF00B4D8),
                    ),
                  ),
                IconButton(
                  onPressed: onTest,
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 20),
                  tooltip: account.type == AccountType.bot
                      ? '测试Bot连接'
                      : '验证API配置',
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

// ===== 用户账号手机号登录对话框 =====
class _UserLoginDialog extends StatefulWidget {
  final TelegramAccount account;
  final AppProvider provider;

  const _UserLoginDialog(
      {required this.account, required this.provider});

  @override
  State<_UserLoginDialog> createState() => _UserLoginDialogState();
}

class _UserLoginDialogState extends State<_UserLoginDialog> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _step = 'phone'; // phone / code / password / done / error
  String? _phoneCodeHash;
  String? _errorMsg;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.account.phone;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.login_rounded, color: primary),
                  const SizedBox(width: 10),
                  const Text('用户账号登录',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 说明
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B4D8).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF00B4D8).withValues(alpha: 0.2)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MTProto用户账号登录',
                        style: TextStyle(
                            color: Color(0xFF00B4D8),
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    SizedBox(height: 4),
                    Text('• 登录后可读取该手机号加入的所有频道（公开+私有）',
                        style: TextStyle(fontSize: 12, color: Colors.white60)),
                    Text('• 登录信息仅保存在本地，不上传任何服务器',
                        style: TextStyle(fontSize: 12, color: Colors.white60)),
                    Text('• 需要Python+Telethon环境支持',
                        style:
                            TextStyle(fontSize: 12, color: Colors.white60)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_step == 'phone') _buildPhoneStep(),
              if (_step == 'code') _buildCodeStep(),
              if (_step == 'password') _buildPasswordStep(),
              if (_step == 'done') _buildDoneStep(),
              if (_step == 'error') _buildErrorStep(),

              if (_errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(_errorMsg!,
                    style: const TextStyle(
                        color: Color(0xFFFF5252), fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('手机号',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '+86 13800138000',
            prefixIcon: Icon(Icons.phone_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _sendCode,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('发送验证码'),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('验证码已发送到 ${_phoneCtrl.text}',
            style: const TextStyle(fontSize: 13, color: Colors.white60)),
        const SizedBox(height: 8),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '验证码',
            hintText: '输入收到的验证码',
            prefixIcon: Icon(Icons.sms_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => setState(() {
                  _step = 'phone';
                  _errorMsg = null;
                }),
                child: const Text('重新发送'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _loading ? null : _verifyCode,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('验证登录'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('该账号开启了两步验证，请输入密码：',
            style: TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '两步验证密码',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _verify2FA,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('确认密码'),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneStep() {
    return Column(
      children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF00E676), size: 48),
        const SizedBox(height: 12),
        const Text('登录成功！',
            style:
                TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
        const Text('现在可以读取该账号加入的所有频道（公开+私有）',
            style: TextStyle(fontSize: 12, color: Colors.white60),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _buildErrorStep() {
    return Column(
      children: [
        const Icon(Icons.error_outline_rounded,
            color: Color(0xFFFF5252), size: 48),
        const SizedBox(height: 12),
        Text(_errorMsg ?? '登录失败',
            style: const TextStyle(color: Color(0xFFFF5252)),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => setState(() {
                  _step = 'phone';
                  _errorMsg = null;
                }),
                child: const Text('重试'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMsg = '请输入手机号');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final state = await widget.provider.startUserLogin(
      accountId: widget.account.id,
      phone: phone,
    );

    setState(() {
      _loading = false;
      if (state.step == 'code_input') {
        _step = 'code';
        _phoneCodeHash = state.phoneCodeHash;
      } else {
        _errorMsg = state.error ?? '发送验证码失败';
        _step = 'error';
      }
    });
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMsg = '请输入验证码');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final state = await widget.provider.confirmLoginCode(
      accountId: widget.account.id,
      phone: _phoneCtrl.text.trim(),
      code: code,
      phoneCodeHash: _phoneCodeHash ?? '',
    );

    setState(() {
      _loading = false;
      if (state.step == 'done') {
        _step = 'done';
      } else if (state.step == 'password_input') {
        _step = 'password';
      } else {
        _errorMsg = state.error ?? '验证码错误';
      }
    });
  }

  Future<void> _verify2FA() async {
    final pwd = _passwordCtrl.text;
    if (pwd.isEmpty) {
      setState(() => _errorMsg = '请输入两步验证密码');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final state = await widget.provider.confirmLogin2FA(
      accountId: widget.account.id,
      password: pwd,
    );

    setState(() {
      _loading = false;
      if (state.step == 'done') {
        _step = 'done';
      } else {
        _errorMsg = state.error ?? '密码错误';
      }
    });
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                        ? (widget.account.type == AccountType.bot
                            ? '添加Bot账号'
                            : '添加用户账号')
                        : '编辑账号',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _field('账号名称', _nameCtrl, hint: '例如：我的Bot'),
              const SizedBox(height: 12),
              if (widget.account.type == AccountType.userApi) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4D8).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF00B4D8).withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: Color(0xFF00B4D8), size: 15),
                          SizedBox(width: 6),
                          Text('用户账号说明',
                              style: TextStyle(
                                  color: Color(0xFF00B4D8),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('• 填写 API ID + API Hash，保存后点击「登录」按钮完成手机号验证码登录',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54)),
                      Text('• 登录后可读取该账号加入的所有频道（公开+私有频道）',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54)),
                      Text('• 在 my.telegram.org/apps 创建应用获取 API ID 和 Hash',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54)),
                      const SizedBox(height: 4),
                      Text('⚠️ 需要安装Python+Telethon环境（自动检测）',
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFFFFAB00)
                                  : Colors.orange)),
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
                    icon: Icon(
                        _showToken ? Icons.visibility_off : Icons.visibility,
                        size: 18),
                    onPressed: () =>
                        setState(() => _showToken = !_showToken),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '在 @BotFather 创建Bot后获取Token',
                  style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 12),
                ),
              ] else ...[
                _field('手机号（选填）', _phoneCtrl, hint: '+86 13800138000'),
                const SizedBox(height: 12),
                _field('API ID', _apiIdCtrl, hint: '从 my.telegram.org 获取'),
                const SizedBox(height: 12),
                _field('API Hash', _apiHashCtrl,
                    hint: '从 my.telegram.org 获取'),
                const SizedBox(height: 8),
                const Text(
                  '保存后在账号列表点击「登录」按钮，输入手机号完成MTProto验证',
                  style: TextStyle(color: Color(0xFF00B4D8), fontSize: 12),
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
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
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
  const _AddButton(
      {required this.label, required this.icon, required this.onTap});

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
              Text(label,
                  style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
