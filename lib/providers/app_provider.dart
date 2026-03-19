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

  // ===== 初始化 =====
  Future<void> init() async {
    await _loadAll();
    _initialized = true;
    notifyListeners();
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

  /// 测试账号连接（Bot Token 模式）
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
      // 用户API模式：验证三要素（手机号、API ID、API Hash）是否都已填写
      final hasPhone = account.phone.isNotEmpty;
      final hasApiId = account.apiId.isNotEmpty;
      final hasApiHash = account.apiHash.isNotEmpty;

      if (hasApiId && hasApiHash) {
        accounts[idx].status = AccountStatus.connected;
        accounts[idx].errorMessage = null;
        final phoneInfo = hasPhone ? '手机号 ${account.phone}' : '（未填手机号）';
        addLog(
          '✅ 用户API账号已配置：API ID=${account.apiId}，$phoneInfo\n'
          '   ⚠️ 注意：用户API账号用于读取频道历史消息（需Bot配合转发）',
          level: LogLevel.success,
        );
        if (!hasPhone) {
          addLog('⚠️ 建议填写手机号以便识别账号', level: LogLevel.warning);
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

    // ★ 修复：支持 Bot 和用户API两种账号，用户API账号不需要 botToken
    TelegramAccount? account;

    // 优先找配置的账号
    if (task.sourceAccountId.isNotEmpty) {
      try {
        account = accounts.firstWhere((a) => a.id == task.sourceAccountId);
      } catch (_) {}
    }

    // 如果没找到，自动选第一个 Bot 账号
    if (account == null) {
      try {
        account = accounts.firstWhere((a) =>
            a.type == AccountType.bot && a.botToken.isNotEmpty);
      } catch (_) {}
    }

    // 用户API账号允许使用（即使没有 botToken）
    if (account == null) {
      addLog('❌ 任务[${task.name}]：请先在账号管理中添加账号并选择', 
          level: LogLevel.error, taskId: taskId);
      return;
    }

    // Bot 账号必须有 token
    if (account.type == AccountType.bot && account.botToken.isEmpty) {
      addLog('❌ 任务[${task.name}]：Bot账号Token为空，请重新配置',
          level: LogLevel.error, taskId: taskId);
      return;
    }

    if (_runners.containsKey(taskId)) stopTask(taskId);

    tasks[idx].status = TaskStatus.running;
    tasks[idx].lastRunAt = DateTime.now();
    addLog('▶️ 任务[${task.name}]已启动，账号：${account.name}',
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
  /// 检测文本是否是广告内容
  bool _isAdvertisement(CloneTask task, String? text, String? caption) {
    if (!task.filterAds) return false;
    final content = (text ?? '') + (caption ?? '');
    if (content.isEmpty) return false;

    // 自定义过滤词（每行一个，精确包含匹配）
    final customKeywords = task.adKeywords
        .split('\n')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();

    final lowerContent = content.toLowerCase();

    // 检查自定义关键词（精确匹配）
    for (final kw in customKeywords) {
      if (lowerContent.contains(kw)) return true;
    }

    // 链接/联系方式检测（高准确率广告特征）
    if (content.contains('t.me/') || content.contains('telegram.me/')) {
      return true;
    }

    // 常用广告词检测
    const builtinKeywords = [
      '招募', '招收', '入群', '拉群', '邀请码',
      '限时优惠', '折扣', '秒杀', '抢购',
      '推广合作', '赞助商', '广告位',
    ];
    for (final kw in builtinKeywords) {
      if (content.contains(kw)) return true;
    }

    // URL 检测
    final urlRegex = RegExp(r'https?://\S+', caseSensitive: false);
    if (urlRegex.hasMatch(content)) return true;

    // @ 用户名检测（如 @username 联系）
    final atRegex = RegExp(r'@[a-zA-Z][a-zA-Z0-9_]{4,}');
    if (atRegex.hasMatch(content)) return true;

    return false;
  }

  // ===== 克隆任务执行（支持 media_group 批量转发）=====
  Future<void> _runCloneTask(
      CloneTask task, TelegramAccount account, _TaskRunner runner) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);
    final aiService = AiService(config: settings.aiConfig);

    final int start = task.startMessageId > 0 ? task.startMessageId : 1;
    final int end = task.endMessageId > 0
        ? task.endMessageId
        : (task.cloneCount > 0 ? start + task.cloneCount - 1 : start + 99);

    int processed = 0;
    int skipped = 0;
    tasks[idx].totalCount = end - start + 1;
    tasks[idx].processedCount = 0;

    final sources =
        task.sourceChannels.isNotEmpty ? task.sourceChannels : [''];
    final targets =
        task.targetChannels.isNotEmpty ? task.targetChannels : [''];

    // ★ 关键：使用 copyMessages 批量转发，每次最多发10条
    // Bot API 会自动保持 media_group 分组（同 media_group_id 的消息会合并为一条）
    const batchSize = 10;

    addLog('▶️ 开始批量克隆 msg[$start..$end]，共${end - start + 1}条',
        level: LogLevel.info, taskId: task.id);

    for (int msgId = start; msgId <= end; msgId += batchSize) {
      if (runner.cancelled) break;

      final batchEnd = (msgId + batchSize - 1).clamp(msgId, end);
      final batchIds = List.generate(batchEnd - msgId + 1, (i) => msgId + i);

      for (final src in sources) {
        if (runner.cancelled) break;
        for (final tgt in targets) {
          if (runner.cancelled) break;
          try {
            // 使用 copyMessages 批量转发（保持媒体组）
            final ok = await TelegramBotService.instance.copyMessages(
              token: account.botToken,
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
              // 批量失败 → 逐条尝试（处理部分消息不存在的情况）
              for (final mid in batchIds) {
                if (runner.cancelled) break;

                // 广告过滤（仅能通过后续 caption 判断，对克隆模式限制较多）
                String? captionText;
                if (task.aiRewrite &&
                    settings.aiConfig.enabled &&
                    settings.aiConfig.apiKey.isNotEmpty) {
                  captionText = await _buildCaption(task, aiService, null);
                }

                final newMsgId = await TelegramBotService.instance.copyMessage(
                  token: account.botToken,
                  fromChatId: src,
                  toChatId: tgt,
                  messageId: mid,
                  caption: task.removeCaption ? '' : captionText,
                  removeCaption: task.removeCaption,
                );
                if (newMsgId != null) {
                  processed++;
                  addLog('✅ msg[$mid] $src → $tgt',
                      level: LogLevel.success, taskId: task.id);
                  _addRecord(task, src, tgt, mid, 'media', captionText != null);
                } else {
                  skipped++;
                  if (skipped <= 20) {
                    addLog('⚪ msg[$mid] 跳过（消息不存在/无权限）',
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
        }
      }

      tasks[idx].processedCount = processed;
      tasks[idx].progress =
          (batchEnd - start + 1) / max(1, end - start + 1);
      notifyListeners();

      if (batchEnd < end && !runner.cancelled) {
        final delay = task.delayMin +
            Random().nextInt(max(1, task.delayMax - task.delayMin + 1));
        await Future.delayed(Duration(seconds: delay));
      }
    }

    if (!runner.cancelled) {
      tasks[idx].status = TaskStatus.completed;
      tasks[idx].progress = 1.0;
      addLog('🎉 任务[${task.name}]完成！成功$processed条，跳过$skipped条',
          level: LogLevel.success, taskId: task.id);
    }
    _runners.remove(task.id);
    await _saveAll();
    notifyListeners();
  }

  // ===== 监听任务（支持 media_group 聚合 + 广告过滤）=====
  Future<void> _runMonitorTask(
      CloneTask task, TelegramAccount account, _TaskRunner runner) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);
    final aiService = AiService(config: settings.aiConfig);

    int lastUpdateId = 0;
    // media_group 缓冲区：groupId -> List<TgMessage>
    final Map<String, List<TgMessage>> groupBuffer = {};
    // 每个 group 的延迟发送 timer（等待同组消息收集完毕再一起发）
    final Map<String, Timer> groupTimers = {};

    addLog('🔍 任务[${task.name}]开始24h监听... 每${task.monitorIntervalSec}秒轮询',
        taskId: task.id);

    Future<void> flushGroup(String groupId) async {
      final msgs = groupBuffer.remove(groupId);
      groupTimers.remove(groupId)?.cancel();
      if (msgs == null || msgs.isEmpty) return;

      // 广告过滤
      final anyAd = msgs.any((m) =>
          _isAdvertisement(task, m.text, m.caption));
      if (anyAd) {
        addLog('🚫 媒体组[$groupId] 检测为广告，已跳过 (${msgs.length}条)',
            level: LogLevel.warning, taskId: task.id);
        return;
      }

      // 过滤媒体类型
      if (!_shouldInclude(task, msgs.first.mediaType)) return;

      final targets = task.targetChannels.isNotEmpty
          ? task.targetChannels
          : [''];

      final msgIds = msgs.map((m) => m.messageId).toList()..sort();
      final srcChatId = msgs.first.chatId;

      // AI改写（取第一条的文案）
      String? newCaption;
      if (task.aiRewrite &&
          settings.aiConfig.enabled &&
          settings.aiConfig.apiKey.isNotEmpty) {
        final origCaption = msgs
            .map((m) => m.caption ?? m.text ?? '')
            .where((s) => s.isNotEmpty)
            .firstOrNull;
        newCaption = await aiService.rewriteCaption(
          originalCaption: origCaption,
          prompt: task.aiPrompt,
        );
      }

      for (final tgt in targets) {
        if (runner.cancelled) break;
        // 使用 copyMessages 批量转发整个媒体组
        final ok = await TelegramBotService.instance.copyMessages(
          token: account.botToken,
          fromChatId: srcChatId,
          toChatId: tgt,
          messageIds: msgIds,
          removeCaption: task.removeCaption,
        );
        if (ok) {
          if (idx < tasks.length) tasks[idx].processedCount++;
          addLog('📨 媒体组[${msgs.length}条] → $tgt ✅',
              level: LogLevel.success, taskId: task.id);
          _addRecord(task, srcChatId, tgt, msgIds.first, msgs.first.mediaType,
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
            account.botToken,
            offset: lastUpdateId + 1,
            limit: 100,
          );

          for (final msg in updates) {
            if (runner.cancelled) break;
            if (msg.updateId > lastUpdateId) lastUpdateId = msg.updateId;

            // 广告过滤（单条消息）
            if (_isAdvertisement(task, msg.text, msg.caption)) {
              addLog('🚫 消息#${msg.messageId} 检测为广告，跳过',
                  level: LogLevel.warning, taskId: task.id);
              continue;
            }

            // 媒体类型过滤
            if (!_shouldInclude(task, msg.mediaType)) continue;

            if (msg.isInMediaGroup) {
              // ★ 媒体组：收集同 groupId 的所有消息，延迟1.5s后统一转发
              final gid = msg.mediaGroupId!;
              groupBuffer.putIfAbsent(gid, () => []).add(msg);

              // 重置计时器（等待同组更多消息）
              groupTimers[gid]?.cancel();
              groupTimers[gid] = Timer(const Duration(milliseconds: 1500), () {
                flushGroup(gid);
              });
            } else {
              // 单条消息：直接转发
              final targets = task.targetChannels.isNotEmpty
                  ? task.targetChannels
                  : [''];

              String? captionText;
              if (task.aiRewrite &&
                  settings.aiConfig.enabled &&
                  settings.aiConfig.apiKey.isNotEmpty) {
                captionText = await aiService.rewriteCaption(
                  originalCaption: msg.caption ?? msg.text,
                  prompt: task.aiPrompt,
                );
              }

              for (final tgt in targets) {
                if (runner.cancelled) break;
                final newId =
                    await TelegramBotService.instance.copyMessage(
                  token: account.botToken,
                  fromChatId: msg.chatId,
                  toChatId: tgt,
                  messageId: msg.messageId,
                  caption: task.removeCaption ? '' : captionText,
                  removeCaption: task.removeCaption,
                );
                if (newId != null) {
                  if (idx < tasks.length) tasks[idx].processedCount++;
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

  Future<String?> _buildCaption(
      CloneTask task, AiService aiService, String? original) async {
    if (!task.aiRewrite) return null;
    if (!settings.aiConfig.enabled || settings.aiConfig.apiKey.isEmpty) {
      return null;
    }
    return aiService.rewriteCaption(
      originalCaption: original,
      prompt: task.aiPrompt,
    );
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
