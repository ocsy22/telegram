import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_models.dart';
import '../services/telegram_bot_service.dart';
import '../services/ai_service.dart';
import '../services/telethon_service.dart';

class AppProvider extends ChangeNotifier {
  static const String _accountsKey = 'tg_accounts';
  static const String _tasksKey = 'tg_tasks';
  static const String _settingsKey = 'tg_settings';
  static const String _recordsKey = 'tg_records';

  final _uuid = const Uuid();

  List<TelegramAccount> accounts = [];
  List<CloneTask> tasks = [];
  List<TransferRecord> records = [];
  AppSettings settings = AppSettings();

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  bool _initialized = false;
  bool get initialized => _initialized;

  final Map<String, _TaskRunner> _runners = {};
  final List<LogEntry> _logs = [];
  List<LogEntry> get logs => List.unmodifiable(_logs);

  // Telethon服务状态
  bool _telethonReady = false;
  bool get telethonReady => _telethonReady;

  // ===== 初始化 =====
  Future<void> init() async {
    await _loadAll();
    _initialized = true;
    notifyListeners();

    // 非阻塞启动Telethon桥接服务（Windows桌面端）
    if (!kIsWeb) {
      _initTelethon();
    }
  }

  Future<void> _initTelethon() async {
    try {
      final ready = await TelethonService.instance.start();
      _telethonReady = ready;
      if (ready) {
        addLog('✅ MTProto桥接服务就绪（支持用户账号读取私有频道）',
            level: LogLevel.success);
      } else {
        addLog('ℹ️ MTProto桥接服务未启动（需要Python+Telethon环境）\n'
            '   用户API账号将使用Bot API降级模式',
            level: LogLevel.info);
      }
      notifyListeners();
    } catch (e) {
      addLog('⚠️ 桥接服务启动异常: $e', level: LogLevel.warning);
    }
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final aRaw = prefs.getString(_accountsKey);
    if (aRaw != null) {
      try {
        final list = jsonDecode(aRaw) as List;
        accounts = list
            .map((e) => TelegramAccount.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final tRaw = prefs.getString(_tasksKey);
    if (tRaw != null) {
      try {
        final list = jsonDecode(tRaw) as List;
        tasks = list
            .map((e) => CloneTask.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final sRaw = prefs.getString(_settingsKey);
    if (sRaw != null) {
      try {
        settings =
            AppSettings.fromJson(jsonDecode(sRaw) as Map<String, dynamic>);
      } catch (_) {}
    }
    final rRaw = prefs.getString(_recordsKey);
    if (rRaw != null) {
      try {
        final list = jsonDecode(rRaw) as List;
        records = list
            .map((e) => TransferRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
    await prefs.setString(
        _tasksKey, jsonEncode(tasks.map((t) => t.toJson()).toList()));
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    final recent = records.length > 200
        ? records.sublist(records.length - 200)
        : records;
    await prefs.setString(
        _recordsKey, jsonEncode(recent.map((r) => r.toJson()).toList()));
  }

  void setCurrentIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  // ===== 日志 =====
  void addLog(String msg,
      {LogLevel level = LogLevel.info, String? taskId}) {
    _logs.add(LogEntry(
      id: _uuid.v4(),
      message: msg,
      level: level,
      taskId: taskId,
      time: DateTime.now(),
    ));
    if (_logs.length > 500) _logs.removeAt(0);
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  // ===== 账号管理 =====
  TelegramAccount createAccount({AccountType type = AccountType.bot}) {
    return TelegramAccount(
      id: _uuid.v4(),
      type: type,
      name: type == AccountType.bot ? '新Bot账号' : '新用户账号',
    );
  }

  Future<void> addAccount(TelegramAccount account) async {
    accounts.add(account);
    await _saveAll();
    notifyListeners();
  }

  Future<void> updateAccount(TelegramAccount account) async {
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      accounts[idx] = account;
      await _saveAll();
      notifyListeners();
    }
  }

  Future<void> removeAccount(String id) async {
    accounts.removeWhere((a) => a.id == id);
    await _saveAll();
    notifyListeners();
  }

  /// 测试账号连接
  Future<bool> testBotAccount(TelegramAccount account) async {
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx < 0) return false;
    accounts[idx].status = AccountStatus.connecting;
    notifyListeners();

    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);

    if (account.type == AccountType.bot) {
      final info = await TelegramBotService.instance.getMe(account.botToken);
      if (info != null) {
        accounts[idx].status = AccountStatus.connected;
        accounts[idx].username = info.username;
        if (info.firstName.isNotEmpty) accounts[idx].name = info.firstName;
        addLog('✅ Bot @${info.username} 连接成功', level: LogLevel.success);
        await _saveAll();
        notifyListeners();
        return true;
      } else {
        accounts[idx].status = AccountStatus.error;
        accounts[idx].errorMessage = 'Token无效或网络错误';
        addLog('❌ Bot连接失败：Token无效或网络超时', level: LogLevel.error);
        await _saveAll();
        notifyListeners();
        return false;
      }
    } else {
      // 用户API模式
      final hasPhone = account.phone.isNotEmpty;
      final hasApiId = account.apiId.isNotEmpty;
      final hasApiHash = account.apiHash.isNotEmpty;

      if (hasApiId && hasApiHash) {
        // 尝试通过Telethon验证
        if (_telethonReady) {
          addLog('🔗 正在通过MTProto验证用户账号...', level: LogLevel.info);
          final result = await TelethonService.instance.startClient(
            apiId: account.apiId,
            apiHash: account.apiHash,
            sessionKey: account.sessionKey,
          );
          if (result['type'] == 'client_ready') {
            if (result['authorized'] == true) {
              final userInfo = result['user'] as Map<String, dynamic>?;
              accounts[idx].status = AccountStatus.connected;
              accounts[idx].telethonAuthorized = true;
              accounts[idx].errorMessage = null;
              if (userInfo != null) {
                final username = userInfo['username'] as String? ?? '';
                final firstName = userInfo['first_name'] as String? ?? '';
                if (username.isNotEmpty) accounts[idx].username = username;
                if (firstName.isNotEmpty && accounts[idx].name.startsWith('新用户')) {
                  accounts[idx].name = firstName;
                }
              }
              addLog('✅ 用户账号已通过MTProto验证：${userInfo?['first_name'] ?? account.phone}',
                  level: LogLevel.success);
              addLog('   ✅ 可以读取该账号加入的所有频道（公开+私有）',
                  level: LogLevel.success);
            } else {
              accounts[idx].status = AccountStatus.error;
              accounts[idx].errorMessage = '未登录，需要手机号验证码';
              addLog('⚠️ 账号未登录，请在账号页面点击登录进行验证码登录',
                  level: LogLevel.warning);
              addLog('   填写手机号后点击「验证/登录」按钮', level: LogLevel.info);
            }
          } else {
            accounts[idx].status = AccountStatus.error;
            accounts[idx].errorMessage = result['error'] as String? ?? 'MTProto连接失败';
            addLog('❌ MTProto连接失败：${result['error']}', level: LogLevel.error);
          }
        } else {
          // Telethon未启动，仅配置验证
          accounts[idx].status = AccountStatus.connected;
          accounts[idx].errorMessage = null;
          final phoneInfo = hasPhone ? '手机号 ${account.phone}' : '（未填手机号）';
          addLog(
            '✅ 用户API账号已配置：API ID=${account.apiId}，$phoneInfo\n'
            '   ⚠️ MTProto桥接未启动，将使用Bot API降级模式（仅支持Bot已加入的频道）\n'
            '   💡 安装Python+Telethon可解锁完整功能',
            level: LogLevel.warning,
          );
        }
      } else {
        accounts[idx].status = AccountStatus.error;
        final missing = [
          if (!hasApiId) 'API ID',
          if (!hasApiHash) 'API Hash',
        ].join('、');
        accounts[idx].errorMessage = '缺少：$missing';
        addLog('❌ 用户API配置不完整，请填写 $missing', level: LogLevel.error);
        addLog('   👉 前往 https://my.telegram.org/apps 获取 API ID 和 API Hash',
            level: LogLevel.info);
      }
      await _saveAll();
      notifyListeners();
      return accounts[idx].status == AccountStatus.connected;
    }
  }

  /// 用户账号手机号登录流程
  Future<UserLoginState> startUserLogin({
    required String accountId,
    required String phone,
  }) async {
    final idx = accounts.indexWhere((a) => a.id == accountId);
    if (idx < 0) return UserLoginState(step: 'error', error: '账号不存在');
    final account = accounts[idx];

    if (!_telethonReady) {
      return UserLoginState(
          step: 'error', error: 'MTProto桥接未启动，需要安装Python+Telethon');
    }

    // 先初始化客户端
    await TelethonService.instance.startClient(
      apiId: account.apiId,
      apiHash: account.apiHash,
      sessionKey: account.sessionKey,
    );

    // 发送验证码
    final result = await TelethonService.instance.sendCode(
      sessionKey: account.sessionKey,
      phone: phone,
    );

    if (result['type'] == 'code_sent') {
      accounts[idx].phone = phone;
      await _saveAll();
      notifyListeners();
      return UserLoginState(
        step: 'code_input',
        phoneCodeHash: result['phone_code_hash'] as String? ?? '',
        phone: phone,
      );
    } else {
      return UserLoginState(
          step: 'error', error: result['error'] as String? ?? '发送验证码失败');
    }
  }

  Future<UserLoginState> confirmLoginCode({
    required String accountId,
    required String phone,
    required String code,
    required String phoneCodeHash,
  }) async {
    final idx = accounts.indexWhere((a) => a.id == accountId);
    if (idx < 0) return UserLoginState(step: 'error', error: '账号不存在');
    final account = accounts[idx];

    final result = await TelethonService.instance.signIn(
      sessionKey: account.sessionKey,
      phone: phone,
      code: code,
      phoneCodeHash: phoneCodeHash,
    );

    if (result['type'] == 'signed_in') {
      accounts[idx].status = AccountStatus.connected;
      accounts[idx].telethonAuthorized = true;
      final userInfo = result['user'] as Map<String, dynamic>?;
      if (userInfo != null) {
        final username = userInfo['username'] as String? ?? '';
        final firstName = userInfo['first_name'] as String? ?? '';
        if (username.isNotEmpty) accounts[idx].username = username;
        if (firstName.isNotEmpty) accounts[idx].name = firstName;
      }
      await _saveAll();
      notifyListeners();
      addLog('✅ 用户账号登录成功！可以读取该账号加入的所有频道',
          level: LogLevel.success);
      return UserLoginState(step: 'done');
    } else if (result['type'] == 'need_2fa') {
      return UserLoginState(step: 'password_input');
    } else {
      return UserLoginState(
          step: 'error', error: result['error'] as String? ?? '验证码错误');
    }
  }

  Future<UserLoginState> confirmLogin2FA({
    required String accountId,
    required String password,
  }) async {
    final idx = accounts.indexWhere((a) => a.id == accountId);
    if (idx < 0) return UserLoginState(step: 'error', error: '账号不存在');
    final account = accounts[idx];

    final result = await TelethonService.instance.signIn2FA(
      sessionKey: account.sessionKey,
      password: password,
    );

    if (result['type'] == 'signed_in') {
      accounts[idx].status = AccountStatus.connected;
      accounts[idx].telethonAuthorized = true;
      final userInfo = result['user'] as Map<String, dynamic>?;
      if (userInfo != null) {
        final username = userInfo['username'] as String? ?? '';
        final firstName = userInfo['first_name'] as String? ?? '';
        if (username.isNotEmpty) accounts[idx].username = username;
        if (firstName.isNotEmpty) accounts[idx].name = firstName;
      }
      await _saveAll();
      notifyListeners();
      addLog('✅ 两步验证成功，用户账号已登录', level: LogLevel.success);
      return UserLoginState(step: 'done');
    } else {
      return UserLoginState(
          step: 'error', error: result['error'] as String? ?? '密码错误');
    }
  }

  // ===== 任务管理 =====
  CloneTask createTask() {
    return CloneTask(
      id: _uuid.v4(),
      name: '新任务_${tasks.length + 1}',
    );
  }

  Future<void> addTask(CloneTask task) async {
    tasks.add(task);
    await _saveAll();
    notifyListeners();
  }

  Future<void> updateTask(CloneTask task) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      tasks[idx] = task;
      await _saveAll();
      notifyListeners();
    }
  }

  Future<void> removeTask(String id) async {
    stopTask(id);
    tasks.removeWhere((t) => t.id == id);
    await _saveAll();
    notifyListeners();
  }

  // ===== 任务执行 =====
  Future<void> startTask(String taskId) async {
    final idx = tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = tasks[idx];

    // 找配置的账号
    TelegramAccount? account;
    if (task.sourceAccountId.isNotEmpty) {
      try {
        account = accounts.firstWhere((a) => a.id == task.sourceAccountId);
      } catch (_) {}
    }

    // 如果没找到，自动选第一个已连接的账号
    if (account == null) {
      try {
        account = accounts.firstWhere(
            (a) => a.status == AccountStatus.connected);
      } catch (_) {}
    }
    // 降级：选第一个Bot账号
    if (account == null) {
      try {
        account = accounts.firstWhere(
            (a) => a.type == AccountType.bot && a.botToken.isNotEmpty);
      } catch (_) {}
    }

    if (account == null) {
      addLog('❌ 任务[${task.name}]：请先在账号管理中添加账号并选择',
          level: LogLevel.error, taskId: taskId);
      return;
    }

    if (account.type == AccountType.bot && account.botToken.isEmpty) {
      addLog('❌ 任务[${task.name}]：Bot账号Token为空，请重新配置',
          level: LogLevel.error, taskId: taskId);
      return;
    }

    if (_runners.containsKey(taskId)) stopTask(taskId);

    tasks[idx].status = TaskStatus.running;
    tasks[idx].lastRunAt = DateTime.now();
    final accountType = account.type == AccountType.userApi ? '[用户API]' : '[Bot]';
    addLog('▶️ 任务[${task.name}]已启动，账号：${account.name} $accountType',
        level: LogLevel.info, taskId: taskId);
    notifyListeners();

    final runner = _TaskRunner(taskId: taskId, cancelled: false);
    _runners[taskId] = runner;

    if (task.mode == TaskMode.clone) {
      _runCloneTask(task, account, runner);
    } else {
      _runMonitorTask(task, account, runner);
    }
  }

  void stopTask(String taskId) {
    final runner = _runners[taskId];
    if (runner != null) {
      runner.cancelled = true;
      runner.timer?.cancel();
      _runners.remove(taskId);
    }
    final idx = tasks.indexWhere((t) => t.id == taskId);
    if (idx >= 0 && tasks[idx].status == TaskStatus.running) {
      tasks[idx].status = TaskStatus.paused;
      addLog('⏸️ 任务[${tasks[idx].name}]已暂停', taskId: taskId);
      notifyListeners();
    }
  }

  // ===== 广告过滤 =====
  bool _isAdvertisement(CloneTask task, String? text, String? caption) {
    if (!task.filterAds) return false;
    final content = (text ?? '') + (caption ?? '');
    if (content.isEmpty) return false;

    final customKeywords = task.adKeywords
        .split('\n')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();

    final lowerContent = content.toLowerCase();

    for (final kw in customKeywords) {
      if (lowerContent.contains(kw)) return true;
    }

    if (content.contains('t.me/') || content.contains('telegram.me/')) {
      return true;
    }

    const builtinKeywords = [
      '招募', '招收', '入群', '拉群', '邀请码',
      '限时优惠', '折扣', '秒杀', '抢购',
      '推广合作', '赞助商', '广告位',
    ];
    for (final kw in builtinKeywords) {
      if (content.contains(kw)) return true;
    }

    final urlRegex = RegExp(r'https?://\S+', caseSensitive: false);
    if (urlRegex.hasMatch(content)) return true;

    final atRegex = RegExp(r'@[a-zA-Z][a-zA-Z0-9_]{4,}');
    if (atRegex.hasMatch(content)) return true;

    return false;
  }

  // ===== AI文案处理（润色/改写）=====
  Future<String?> _processCaption(
    CloneTask task,
    AiService aiService,
    String? originalCaption,
  ) async {
    if (originalCaption == null || originalCaption.trim().isEmpty) return null;
    // 免费服务商（Pollinations）不需要API Key也能工作
    if (!settings.aiConfig.enabled) return null;
    if (!settings.aiConfig.isFreeProvider && settings.aiConfig.apiKey.isEmpty) return null;

    // 优先使用润色（轻度修改）
    if (task.aiPolish) {
      final style = PolishStyle.values[task.aiPolishStyle.clamp(0, 2)];
      final result = await aiService.polishCaption(
        originalCaption: originalCaption,
        style: style,
      );
      if (result != null && result.isNotEmpty && result != originalCaption) {
        return result;
      }
    }

    // 完整改写
    if (task.aiRewrite) {
      final result = await aiService.rewriteCaption(
        originalCaption: originalCaption,
        prompt: task.aiPrompt,
      );
      if (result != null && result.isNotEmpty) return result;
    }

    return null;
  }

  // ===== 视频MD5修改 =====
  Future<String?> modifyVideoMd5ForFile(String videoFilePath) async {
    if (kIsWeb) return null;
    try {
      final file = File(videoFilePath);
      if (!await file.exists()) return null;

      final originalBytes = await file.readAsBytes();
      final rng = Random();
      final extra = List<int>.generate(
          16 + rng.nextInt(16), (_) => rng.nextInt(256));
      final modifiedBytes = Uint8List(originalBytes.length + extra.length)
        ..setRange(0, originalBytes.length, originalBytes)
        ..setRange(originalBytes.length, originalBytes.length + extra.length, extra);

      final tmpDir = Directory.systemTemp;
      final ext = p.extension(videoFilePath);
      final tmpFile = File('${tmpDir.path}/tg_md5mod_${_uuid.v4()}$ext');
      await tmpFile.writeAsBytes(modifiedBytes);
      return tmpFile.path;
    } catch (e) {
      if (kDebugMode) debugPrint('modifyVideoMd5 error: $e');
      return null;
    }
  }

  http.Client makeHttpClient(bool ignoreSsl) {
    if (kIsWeb) return http.Client();
    final hc = HttpClient()
      ..badCertificateCallback = (cert, host, port) => ignoreSsl;
    return http_io.IOClient(hc);
  }

  // ===== 克隆任务执行 =====
  Future<void> _runCloneTask(
      CloneTask task, TelegramAccount account, _TaskRunner runner) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);

    final int start = task.startMessageId > 0 ? task.startMessageId : 1;
    final int end = task.endMessageId > 0
        ? task.endMessageId
        : (task.cloneCount > 0 ? start + task.cloneCount - 1 : start + 99);

    tasks[idx].totalCount = end - start + 1;
    tasks[idx].processedCount = 0;

    final sources = task.sourceChannels.isNotEmpty ? task.sourceChannels : [''];
    final targets = task.targetChannels.isNotEmpty ? task.targetChannels : [''];

    // ★★★ 核心逻辑：判断是否使用Telethon（用户API账号）★★★
    final useUserApi = account.type == AccountType.userApi &&
        _telethonReady &&
        account.telethonAuthorized;

    if (useUserApi) {
      // ===== 用户API模式：通过MTProto克隆 =====
      addLog('▶️ 使用MTProto用户账号克隆（可访问私有频道）',
          level: LogLevel.info, taskId: task.id);
      await _runCloneTaskWithTelethon(task, account, runner, sources, targets, start, end, idx);
    } else {
      // ===== Bot API模式：通过Bot Token克隆 =====
      final botToken = account.type == AccountType.bot
          ? account.botToken
          : _findBotToken(); // 用户API降级时使用任意可用Bot

      if (botToken == null || botToken.isEmpty) {
        addLog(
          '❌ 无可用Bot Token。\n'
          '   用户API账号克隆需要：\n'
          '   方案A：安装Python+Telethon启用MTProto模式\n'
          '   方案B：同时添加一个Bot账号（Bot需加入源频道）',
          level: LogLevel.error,
          taskId: task.id,
        );
        tasks[idx].status = TaskStatus.failed;
        notifyListeners();
        return;
      }

      if (account.type == AccountType.userApi) {
        addLog(
          '⚠️ 用户API账号降级为Bot API模式（需要Bot已加入源频道）\n'
          '   如需真正读取私有频道，请安装Python+Telethon',
          level: LogLevel.warning,
          taskId: task.id,
        );
      }

      addLog('▶️ 开始克隆 msg[$start..$end]，共${end - start + 1}条（媒体组自动检测）',
          level: LogLevel.info, taskId: task.id);

      await _runCloneTaskWithBot(task, botToken, runner, sources, targets, start, end, idx);
    }
  }

  /// 查找任何可用的Bot Token（用于降级模式）
  String? _findBotToken() {
    for (final acc in accounts) {
      if (acc.type == AccountType.bot && acc.botToken.isNotEmpty) {
        return acc.botToken;
      }
    }
    return null;
  }

  // ===== Telethon克隆（MTProto模式）=====
  Future<void> _runCloneTaskWithTelethon(
    CloneTask task,
    TelegramAccount account,
    _TaskRunner runner,
    List<String> sources,
    List<String> targets,
    int start,
    int end,
    int idx,
  ) async {
    int totalSuccess = 0;
    int totalFailed = 0;

    for (final src in sources) {
      if (runner.cancelled) break;

      final result = await TelethonService.instance.cloneMessages(
        sessionKey: account.sessionKey,
        sourceChannel: src,
        targetChannels: targets,
        startId: start,
        endId: end,
        count: task.cloneCount > 0 ? task.cloneCount : 1000,
        removeCaption: task.removeCaption,
        modifyMd5: task.modifyVideoMd5,
        onProgress: (msg) {
          addLog(msg, taskId: task.id,
              level: msg.startsWith('✅') ? LogLevel.success
                  : msg.startsWith('❌') ? LogLevel.error
                  : msg.startsWith('⚠️') ? LogLevel.warning
                  : LogLevel.info);
          notifyListeners();
        },
      );

      if (result['type'] == 'clone_done') {
        totalSuccess += (result['success'] as int? ?? 0);
        totalFailed += (result['failed'] as int? ?? 0);

        if (idx < tasks.length) {
          tasks[idx].processedCount = totalSuccess;
          tasks[idx].progress = 1.0;
        }
      } else if (result['type'] == 'error') {
        addLog('❌ 克隆失败: ${result['error']}',
            level: LogLevel.error, taskId: task.id);
      }
    }

    if (!runner.cancelled) {
      if (idx < tasks.length) {
        tasks[idx].status = TaskStatus.completed;
        tasks[idx].progress = 1.0;
      }
      addLog('🎉 任务[${task.name}]完成！成功$totalSuccess条，失败$totalFailed条',
          level: LogLevel.success, taskId: task.id);
    }
    _runners.remove(task.id);
    await _saveAll();
    notifyListeners();
  }

  // ===== Bot API克隆（原有逻辑）=====
  Future<void> _runCloneTaskWithBot(
    CloneTask task,
    String botToken,
    _TaskRunner runner,
    List<String> sources,
    List<String> targets,
    int start,
    int end,
    int idx,
  ) async {
    int processed = 0;
    int skipped = 0;
    const scanBatch = 50;

    int msgCursor = start;
    while (msgCursor <= end && !runner.cancelled) {
      final scanEnd = min(msgCursor + scanBatch - 1, end);
      final scanIds = List.generate(scanEnd - msgCursor + 1, (i) => msgCursor + i);

      for (final src in sources) {
        if (runner.cancelled) break;
        for (final tgt in targets) {
          if (runner.cancelled) break;

          for (int batchStart = 0; batchStart < scanIds.length; batchStart += 10) {
            if (runner.cancelled) break;
            final batchEnd = min(batchStart + 10, scanIds.length);
            final batchIds = scanIds.sublist(batchStart, batchEnd);

            try {
              final ok = await TelegramBotService.instance.copyMessages(
                token: botToken,
                fromChatId: src,
                toChatId: tgt,
                messageIds: batchIds,
                removeCaption: task.removeCaption,
              );

              if (ok) {
                processed += batchIds.length;
                addLog(
                  '✅ 批量转发 msg[${batchIds.first}~${batchIds.last}] (${batchIds.length}条) $src → $tgt',
                  level: LogLevel.success,
                  taskId: task.id,
                );
                _addRecord(task, src, tgt, batchIds.first, 'batch', false);
              } else {
                // 批量失败 → 逐条尝试
                for (final mid in batchIds) {
                  if (runner.cancelled) break;

                  final newMsgId = await TelegramBotService.instance.copyMessage(
                    token: botToken,
                    fromChatId: src,
                    toChatId: tgt,
                    messageId: mid,
                    removeCaption: task.removeCaption,
                  );
                  if (newMsgId != null) {
                    processed++;
                    addLog('✅ msg[$mid] $src → $tgt',
                        level: LogLevel.success, taskId: task.id);
                    _addRecord(task, src, tgt, mid, 'media', false);
                  } else {
                    skipped++;
                    if (skipped <= 30) {
                      addLog('⚪ msg[$mid] 跳过（消息不存在/Bot无权限）',
                          taskId: task.id);
                    }
                  }
                  await Future.delayed(const Duration(milliseconds: 500));
                }
              }
            } catch (e) {
              addLog('❌ 批量转发 msg[${batchIds.first}~${batchIds.last}] 错误: $e',
                  level: LogLevel.error, taskId: task.id);
            }

            if (!runner.cancelled) {
              await Future.delayed(const Duration(milliseconds: 800));
            }
          }
        }
      }

      if (idx < tasks.length) {
        tasks[idx].processedCount = processed;
        tasks[idx].progress = (scanEnd - start + 1) / max(1, end - start + 1);
      }
      notifyListeners();
      msgCursor = scanEnd + 1;

      if (msgCursor <= end && !runner.cancelled) {
        final delay = task.delayMin +
            Random().nextInt(max(1, task.delayMax - task.delayMin + 1));
        await Future.delayed(Duration(seconds: delay));
      }
    }

    if (!runner.cancelled) {
      if (idx < tasks.length) {
        tasks[idx].status = TaskStatus.completed;
        tasks[idx].progress = 1.0;
      }
      addLog('🎉 任务[${task.name}]完成！成功$processed条，跳过$skipped条',
          level: LogLevel.success, taskId: task.id);
    }
    _runners.remove(task.id);
    await _saveAll();
    notifyListeners();
  }

  // ===== 监听任务（支持 media_group 聚合 + 广告过滤 + AI润色）=====
  Future<void> _runMonitorTask(
      CloneTask task, TelegramAccount account, _TaskRunner runner) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);
    final aiService = AiService(config: settings.aiConfig);

    // 确定使用哪个Bot Token
    String? botToken;
    if (account.type == AccountType.bot) {
      botToken = account.botToken;
    } else {
      botToken = _findBotToken();
    }

    if (botToken == null || botToken.isEmpty) {
      addLog('❌ 监听模式需要Bot账号（用于接收更新）', level: LogLevel.error, taskId: task.id);
      tasks[idx].status = TaskStatus.failed;
      notifyListeners();
      return;
    }

    int lastUpdateId = 0;
    final Map<String, List<TgMessage>> groupBuffer = {};
    final Map<String, Timer> groupTimers = {};

    addLog('🔍 任务[${task.name}]开始监听... 每${task.monitorIntervalSec}秒轮询',
        taskId: task.id);

    Future<void> flushGroup(String groupId) async {
      final msgs = groupBuffer.remove(groupId);
      groupTimers.remove(groupId)?.cancel();
      if (msgs == null || msgs.isEmpty) return;

      final anyAd = msgs.any((m) => _isAdvertisement(task, m.text, m.caption));
      if (anyAd) {
        addLog('🚫 媒体组[$groupId] 检测为广告，已跳过 (${msgs.length}条)',
            level: LogLevel.warning, taskId: task.id);
        return;
      }

      final mediaMsg = msgs.firstWhere(
        (m) => m.mediaType != 'text',
        orElse: () => msgs.first,
      );
      if (!_shouldInclude(task, mediaMsg.mediaType)) return;

      final targets = task.targetChannels.isNotEmpty ? task.targetChannels : [''];
      final msgIds = msgs.map((m) => m.messageId).toList()..sort();
      final srcChatId = msgs.first.chatId;

      // AI处理文案
      String? newCaption;
      final origCaption = msgs
          .map((m) => m.caption ?? m.text ?? '')
          .where((s) => s.isNotEmpty)
          .firstOrNull;
      newCaption = await _processCaption(task, aiService, origCaption);

      for (final tgt in targets) {
        if (runner.cancelled) break;
        bool anySuccess = false;
        for (int i = 0; i < msgIds.length; i += 10) {
          final batch = msgIds.sublist(i, min(i + 10, msgIds.length));
          final ok = await TelegramBotService.instance.copyMessages(
            token: botToken ?? '',
            fromChatId: srcChatId,
            toChatId: tgt,
            messageIds: batch,
            removeCaption: task.removeCaption,
          );
          if (ok) anySuccess = true;
        }

        if (anySuccess) {
          final taskIdx = tasks.indexWhere((t) => t.id == task.id);
          if (taskIdx >= 0) tasks[taskIdx].processedCount++;
          addLog('📨 媒体组[${msgs.length}条，ID:${msgIds.first}~${msgIds.last}] → $tgt ✅',
              level: LogLevel.success, taskId: task.id);
          _addRecord(task, srcChatId, tgt, msgIds.first, mediaMsg.mediaType,
              newCaption != null);
        } else {
          addLog('❌ 媒体组转发失败 → $tgt', level: LogLevel.error, taskId: task.id);
        }
      }
      notifyListeners();
    }

    void schedule() {
      if (runner.cancelled) return;
      runner.timer =
          Timer(Duration(seconds: task.monitorIntervalSec), () async {
        if (runner.cancelled) return;
        try {
          final updates = await TelegramBotService.instance.getUpdates(
            botToken ?? '',
            offset: lastUpdateId + 1,
            limit: 100,
          );

          for (final msg in updates) {
            if (runner.cancelled) break;
            if (msg.updateId > lastUpdateId) lastUpdateId = msg.updateId;

            if (_isAdvertisement(task, msg.text, msg.caption)) {
              addLog('🚫 消息#${msg.messageId} 检测为广告，跳过',
                  level: LogLevel.warning, taskId: task.id);
              continue;
            }

            if (!_shouldInclude(task, msg.mediaType)) continue;

            if (msg.isInMediaGroup) {
              final gid = msg.mediaGroupId!;
              groupBuffer.putIfAbsent(gid, () => []).add(msg);
              groupTimers[gid]?.cancel();
              groupTimers[gid] = Timer(const Duration(milliseconds: 2000), () {
                flushGroup(gid);
              });
            } else {
              final targets =
                  task.targetChannels.isNotEmpty ? task.targetChannels : [''];

              String? captionText =
                  await _processCaption(task, aiService, msg.caption ?? msg.text);

              for (final tgt in targets) {
                if (runner.cancelled) break;
                final newId = await TelegramBotService.instance.copyMessage(
                  token: botToken ?? '',
                  fromChatId: msg.chatId,
                  toChatId: tgt,
                  messageId: msg.messageId,
                  caption: task.removeCaption ? '' : captionText,
                  removeCaption: task.removeCaption,
                );
                if (newId != null) {
                  final taskIdx = tasks.indexWhere((t) => t.id == task.id);
                  if (taskIdx >= 0) tasks[taskIdx].processedCount++;
                  addLog('📨 msg#${msg.messageId} → $tgt ✅',
                      level: LogLevel.success, taskId: task.id);
                  _addRecord(task, msg.chatId, tgt, msg.messageId,
                      msg.mediaType, captionText != null);
                }
              }
            }
          }
        } catch (e) {
          addLog('⚠️ 轮询错误: $e', level: LogLevel.warning, taskId: task.id);
        }
        notifyListeners();
        if (!runner.cancelled) schedule();
      });
    }

    schedule();
  }

  bool _shouldInclude(CloneTask task, String mediaType) {
    switch (mediaType) {
      case 'text':
        return task.includeText;
      case 'photo':
        return task.includePhoto;
      case 'video':
        return task.includeVideo;
      case 'document':
        return task.includeDocument;
      case 'audio':
        return task.includeAudio;
      case 'sticker':
        return task.includeSticker;
      default:
        return true;
    }
  }

  void _addRecord(CloneTask task, String src, String tgt, int msgId,
      String mediaType, bool aiRewritten) {
    records.add(TransferRecord(
      id: _uuid.v4(),
      taskId: task.id,
      taskName: task.name,
      sourceChannel: src,
      targetChannel: tgt,
      messageId: msgId,
      mediaType: mediaType,
      aiRewritten: aiRewritten,
      transferredAt: DateTime.now(),
    ));
    if (records.length > 500) records.removeAt(0);
  }

  // ===== 设置 =====
  Future<void> updateSettings(AppSettings newSettings) async {
    settings = newSettings;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);
    await _saveAll();
    notifyListeners();
  }

  Future<void> clearRecords() async {
    records.clear();
    await _saveAll();
    notifyListeners();
  }
}

// ===== 辅助类 =====
class _TaskRunner {
  final String taskId;
  bool cancelled;
  Timer? timer;
  _TaskRunner({required this.taskId, required this.cancelled});
}

/// 用户登录状态
class UserLoginState {
  final String step; // idle / code_input / password_input / done / error
  final String? phoneCodeHash;
  final String? phone;
  final String? error;

  UserLoginState({
    required this.step,
    this.phoneCodeHash,
    this.phone,
    this.error,
  });
}

enum LogLevel { info, success, warning, error }

class LogEntry {
  final String id;
  final String message;
  final LogLevel level;
  final String? taskId;
  final DateTime time;
  LogEntry({
    required this.id,
    required this.message,
    required this.level,
    this.taskId,
    required this.time,
  });

  Color get color {
    switch (level) {
      case LogLevel.info:
        return const Color(0xFF9999CC);
      case LogLevel.success:
        return const Color(0xFF00E676);
      case LogLevel.warning:
        return const Color(0xFFFFAB00);
      case LogLevel.error:
        return const Color(0xFFFF5252);
    }
  }
}
