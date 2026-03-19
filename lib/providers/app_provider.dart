import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_models.dart';
import '../services/telegram_bot_service.dart';
import '../services/ai_service.dart';

class AppProvider extends ChangeNotifier {
  static const String _accountsKey = 'tg_accounts';
  static const String _tasksKey = 'tg_tasks';
  static const String _settingsKey = 'tg_settings';
  static const String _recordsKey = 'tg_records';

  final _uuid = const Uuid();

  // ===== 状态 =====
  List<TelegramAccount> accounts = [];
  List<CloneTask> tasks = [];
  List<TransferRecord> records = [];
  AppSettings settings = AppSettings();

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  bool _initialized = false;
  bool get initialized => _initialized;

  // 每个任务的运行状态（taskId -> Timer/cancel flag）
  final Map<String, _TaskRunner> _runners = {};

  // 日志（最多500条）
  final List<LogEntry> _logs = [];
  List<LogEntry> get logs => List.unmodifiable(_logs);

  // ===== 初始化 =====
  Future<void> init() async {
    await _loadAll();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    // accounts
    final aRaw = prefs.getString(_accountsKey);
    if (aRaw != null) {
      try {
        final list = jsonDecode(aRaw) as List;
        accounts = list.map((e) => TelegramAccount.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    // tasks
    final tRaw = prefs.getString(_tasksKey);
    if (tRaw != null) {
      try {
        final list = jsonDecode(tRaw) as List;
        tasks = list.map((e) => CloneTask.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    // settings
    final sRaw = prefs.getString(_settingsKey);
    if (sRaw != null) {
      try {
        settings = AppSettings.fromJson(jsonDecode(sRaw) as Map<String, dynamic>);
      } catch (_) {}
    }
    // records (最近200条)
    final rRaw = prefs.getString(_recordsKey);
    if (rRaw != null) {
      try {
        final list = jsonDecode(rRaw) as List;
        records = list.map((e) => TransferRecord.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
    await prefs.setString(_tasksKey, jsonEncode(tasks.map((t) => t.toJson()).toList()));
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    final recentRecords = records.length > 200 ? records.sublist(records.length - 200) : records;
    await prefs.setString(_recordsKey, jsonEncode(recentRecords.map((r) => r.toJson()).toList()));
  }

  void setCurrentIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  // ===== 日志 =====
  void addLog(String msg, {LogLevel level = LogLevel.info, String? taskId}) {
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

  /// 测试 Bot 账号连接
  Future<bool> testBotAccount(TelegramAccount account) async {
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx < 0) return false;
    accounts[idx].status = AccountStatus.connecting;
    notifyListeners();

    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);
    final info = await TelegramBotService.instance.getMe(account.botToken);
    if (info != null) {
      accounts[idx].status = AccountStatus.connected;
      accounts[idx].username = info.username;
      accounts[idx].name = info.firstName.isNotEmpty ? info.firstName : accounts[idx].name;
      addLog('✅ Bot @${info.username} 连接成功', level: LogLevel.success);
    } else {
      accounts[idx].status = AccountStatus.error;
      accounts[idx].errorMessage = 'Token无效或网络错误';
      addLog('❌ Bot连接失败：Token无效或网络超时', level: LogLevel.error);
    }
    await _saveAll();
    notifyListeners();
    return info != null;
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

    // 检查账号
    final account = accounts.firstWhere(
      (a) => a.id == task.sourceAccountId,
      orElse: () => TelegramAccount(id: '', botToken: ''),
    );
    if (account.id.isEmpty || account.botToken.isEmpty) {
      addLog('❌ 任务[${task.name}]：未找到有效账号', level: LogLevel.error, taskId: taskId);
      return;
    }

    if (_runners.containsKey(taskId)) {
      stopTask(taskId);
    }

    tasks[idx].status = TaskStatus.running;
    tasks[idx].lastRunAt = DateTime.now();
    addLog('▶️ 任务[${task.name}]已启动', level: LogLevel.info, taskId: taskId);
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

  Future<void> _runCloneTask(CloneTask task, TelegramAccount account, _TaskRunner runner) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);
    final aiService = AiService(config: settings.aiConfig);

    int start = task.startMessageId > 0 ? task.startMessageId : 1;
    int end = task.endMessageId > 0 ? task.endMessageId : start + task.cloneCount - 1;
    if (task.cloneCount > 0 && end == 0) end = start + task.cloneCount - 1;

    int processed = 0;
    int failed = 0;
    tasks[idx].totalCount = end - start + 1;
    tasks[idx].processedCount = 0;

    for (int msgId = start; msgId <= end; msgId++) {
      if (runner.cancelled) break;

      final sources = task.sourceChannels.isNotEmpty ? task.sourceChannels : [''];
      final targets = task.targetChannels.isNotEmpty ? task.targetChannels : [''];

      for (final src in sources) {
        for (final tgt in targets) {
          if (runner.cancelled) break;
          try {
            String? caption;
            if (task.aiRewrite && settings.aiConfig.enabled && settings.aiConfig.apiKey.isNotEmpty) {
              caption = await aiService.rewriteCaption(
                originalCaption: null,
                prompt: task.aiPrompt,
              );
            }
            final newMsgId = await TelegramBotService.instance.copyMessage(
              token: account.botToken,
              fromChatId: src,
              toChatId: tgt,
              messageId: msgId,
              caption: task.removeCaption ? '' : caption,
              removeCaption: task.removeCaption,
            );
            if (newMsgId != null) {
              processed++;
              addLog('✅ 消息[$msgId] $src → $tgt 成功', level: LogLevel.success, taskId: task.id);
              _addRecord(task, src, tgt, msgId, 'unknown', caption != null);
            } else {
              failed++;
              addLog('⚠️ 消息[$msgId] 复制失败（可能不存在）', level: LogLevel.warning, taskId: task.id);
            }
          } catch (e) {
            failed++;
            addLog('❌ 消息[$msgId] 错误: $e', level: LogLevel.error, taskId: task.id);
          }
        }
      }

      tasks[idx].processedCount = processed;
      tasks[idx].progress = (msgId - start + 1) / max(1, end - start + 1);
      notifyListeners();

      // 延迟
      if (msgId < end && !runner.cancelled) {
        final delay = task.delayMin + Random().nextInt(max(1, task.delayMax - task.delayMin + 1));
        await Future.delayed(Duration(seconds: delay));
      }
    }

    if (!runner.cancelled) {
      tasks[idx].status = TaskStatus.completed;
      tasks[idx].progress = 1.0;
      addLog('🎉 任务[${task.name}]完成！成功$processed条，失败$failed条', level: LogLevel.success, taskId: task.id);
    }
    _runners.remove(task.id);
    await _saveAll();
    notifyListeners();
  }

  Future<void> _runMonitorTask(CloneTask task, TelegramAccount account, _TaskRunner runner) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);
    final aiService = AiService(config: settings.aiConfig);

    int lastUpdateId = 0;
    addLog('🔍 任务[${task.name}]开始监听...', taskId: task.id);

    void schedule() {
      if (runner.cancelled) return;
      runner.timer = Timer(Duration(seconds: task.monitorIntervalSec), () async {
        if (runner.cancelled) return;
        try {
          final updates = await TelegramBotService.instance.getUpdates(
            account.botToken,
            offset: lastUpdateId + 1,
            limit: 100,
          );
          for (final msg in updates) {
            if (runner.cancelled) break;
            if (msg.updateId > lastUpdateId) lastUpdateId = msg.updateId;

            // 过滤媒体类型
            if (!_shouldInclude(task, msg.mediaType)) continue;

            String? caption;
            if (task.aiRewrite && settings.aiConfig.enabled && settings.aiConfig.apiKey.isNotEmpty) {
              caption = await aiService.rewriteCaption(
                originalCaption: msg.caption ?? msg.text,
                prompt: task.aiPrompt,
              );
            }

            final targets = task.targetChannels.isNotEmpty ? task.targetChannels : [''];
            for (final tgt in targets) {
              if (runner.cancelled) break;
              try {
                final newId = await TelegramBotService.instance.copyMessage(
                  token: account.botToken,
                  fromChatId: msg.chatId,
                  toChatId: tgt,
                  messageId: msg.messageId,
                  caption: task.removeCaption ? '' : caption,
                  removeCaption: task.removeCaption,
                );
                if (newId != null) {
                  tasks[idx].processedCount++;
                  addLog('📨 监听转发: msg#${msg.messageId} → $tgt', level: LogLevel.success, taskId: task.id);
                  _addRecord(task, msg.chatId, tgt, msg.messageId, msg.mediaType, caption != null);
                }
              } catch (e) {
                addLog('❌ 监听转发失败: $e', level: LogLevel.error, taskId: task.id);
              }
            }
          }
        } catch (e) {
          addLog('⚠️ 监听轮询错误: $e', level: LogLevel.warning, taskId: task.id);
        }
        notifyListeners();
        if (!runner.cancelled) schedule();
      });
    }

    schedule();
  }

  bool _shouldInclude(CloneTask task, String mediaType) {
    switch (mediaType) {
      case 'text':     return task.includeText;
      case 'photo':    return task.includePhoto;
      case 'video':    return task.includeVideo;
      case 'document': return task.includeDocument;
      case 'audio':    return task.includeAudio;
      case 'sticker':  return task.includeSticker;
      default:         return true;
    }
  }

  void _addRecord(CloneTask task, String src, String tgt, int msgId, String mediaType, bool aiRewritten) {
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
      case LogLevel.info:    return const Color(0xFF9999CC);
      case LogLevel.success: return const Color(0xFF00E676);
      case LogLevel.warning: return const Color(0xFFFFAB00);
      case LogLevel.error:   return const Color(0xFFFF5252);
    }
  }
}
