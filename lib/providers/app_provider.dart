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
          '   ℹ️ 用户API账号可访问任意公开/已加入的频道历史消息',
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

    // ★ 支持 Bot 和用户API两种账号
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

    // 没有账号
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

    // @ 用户名检测
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
    if (!settings.aiConfig.enabled || settings.aiConfig.apiKey.isEmpty) return null;

    // 优先使用润色（轻度修改）
    if (task.aiPolish) {
      final style = PolishStyle.values[task.aiPolishStyle.clamp(0, 2)];
      final result = await aiService.polishCaption(
        originalCaption: originalCaption,
        style: style,
      );
      if (result != null && result.isNotEmpty) return result;
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

  // ===== 视频MD5修改（Windows版本）=====
  /// 下载视频并在末尾追加随机字节，改变MD5哈希值（不影响视频播放）
  /// 注意：Bot API限制，只能获取≤20MB的文件
  Future<String?> modifyVideoMd5ForFile(String videoFilePath) async {
    if (kIsWeb) return null;
    try {
      final file = File(videoFilePath);
      if (!await file.exists()) return null;

      final originalBytes = await file.readAsBytes();
      final rng = Random();
      // 追加16~31个随机字节到末尾（改变MD5，对视频播放无影响）
      final extra = List<int>.generate(
          16 + rng.nextInt(16),
          (_) => rng.nextInt(256));
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

  /// MD5修改辅助：创建HTTP客户端
  http.Client makeHttpClient(bool ignoreSsl) {
    if (kIsWeb) return http.Client();
    final hc = HttpClient()
      ..badCertificateCallback = (cert, host, port) => ignoreSsl;
    return http_io.IOClient(hc);
  }

  // ===== 克隆任务执行（支持 media_group 批量转发）=====
  Future<void> _runCloneTask(
      CloneTask task, TelegramAccount account, _TaskRunner runner) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);

    final int start = task.startMessageId > 0 ? task.startMessageId : 1;
    final int end = task.endMessageId > 0
        ? task.endMessageId
        : (task.cloneCount > 0 ? start + task.cloneCount - 1 : start + 99);

    int processed = 0;
    int skipped = 0;
    tasks[idx].totalCount = end - start + 1;
    tasks[idx].processedCount = 0;

    final sources = task.sourceChannels.isNotEmpty ? task.sourceChannels : [''];
    final targets = task.targetChannels.isNotEmpty ? task.targetChannels : [''];

    // ★ 关键：先预扫描媒体组，再按组批量转发
    // copyMessages 一次最多10条，Bot API自动保持同media_group_id的消息为一组
    const scanBatch = 50; // 每次预扫描50条消息，检测media_group

    addLog('▶️ 开始克隆 msg[$start..$end]，共${end - start + 1}条（自动检测媒体组）',
        level: LogLevel.info, taskId: task.id);

    // 使用分段扫描+批量发送策略
    int msgCursor = start;
    while (msgCursor <= end && !runner.cancelled) {
      final scanEnd = min(msgCursor + scanBatch - 1, end);
      final scanIds = List.generate(scanEnd - msgCursor + 1, (i) => msgCursor + i);

      // ★★★ 对于克隆模式，直接使用 copyMessages 批量转发
      // Bot API 7.0+ 的 copyMessages 会自动识别并保持 media_group
      // 同一 media_group_id 的消息即使在同批次中也会被合并发送
      
      for (final src in sources) {
        if (runner.cancelled) break;
        for (final tgt in targets) {
          if (runner.cancelled) break;
          
          // 分批次（每批最多10条）执行 copyMessages
          for (int batchStart = 0; batchStart < scanIds.length; batchStart += 10) {
            if (runner.cancelled) break;
            final batchEnd = min(batchStart + 10, scanIds.length);
            final batchIds = scanIds.sublist(batchStart, batchEnd);

            try {
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
                // 批量失败 → 逐条尝试
                for (final mid in batchIds) {
                  if (runner.cancelled) break;

                  String? captionText;
                  if ((task.aiPolish || task.aiRewrite) &&
                      settings.aiConfig.enabled &&
                      settings.aiConfig.apiKey.isNotEmpty) {
                    // 单条逐个处理时，caption只能用空
                    // 因为Bot API的copyMessage不能获取原始caption
                    captionText = null;
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
                    _addRecord(task, src, tgt, mid, 'media', false);
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

            // 批次间延迟
            if (!runner.cancelled) {
              await Future.delayed(const Duration(milliseconds: 800));
            }
          }
        }
      }

      tasks[idx].processedCount = processed;
      tasks[idx].progress = (scanEnd - start + 1) / max(1, end - start + 1);
      notifyListeners();

      msgCursor = scanEnd + 1;

      // 段落间延迟
      if (msgCursor <= end && !runner.cancelled) {
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

  // ===== 监听任务（支持 media_group 聚合 + 广告过滤 + AI润色）=====
  Future<void> _runMonitorTask(
      CloneTask task, TelegramAccount account, _TaskRunner runner) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    TelegramBotService.instance.setIgnoreSsl(settings.ignoreSsl);
    final aiService = AiService(config: settings.aiConfig);

    int lastUpdateId = 0;
    // media_group 缓冲区：groupId -> List<TgMessage>
    final Map<String, List<TgMessage>> groupBuffer = {};
    final Map<String, Timer> groupTimers = {};

    addLog('🔍 任务[${task.name}]开始24h监听... 每${task.monitorIntervalSec}秒轮询',
        taskId: task.id);

    Future<void> flushGroup(String groupId) async {
      final msgs = groupBuffer.remove(groupId);
      groupTimers.remove(groupId)?.cancel();
      if (msgs == null || msgs.isEmpty) return;

      // 广告过滤
      final anyAd = msgs.any((m) => _isAdvertisement(task, m.text, m.caption));
      if (anyAd) {
        addLog('🚫 媒体组[$groupId] 检测为广告，已跳过 (${msgs.length}条)',
            level: LogLevel.warning, taskId: task.id);
        return;
      }

      // 过滤媒体类型（检查组内第一条非文字媒体类型）
      final mediaMsg = msgs.firstWhere(
        (m) => m.mediaType != 'text',
        orElse: () => msgs.first,
      );
      if (!_shouldInclude(task, mediaMsg.mediaType)) return;

      final targets = task.targetChannels.isNotEmpty ? task.targetChannels : [''];
      final msgIds = msgs.map((m) => m.messageId).toList()..sort();
      final srcChatId = msgs.first.chatId;

      // AI处理（取第一条的文案）
      String? newCaption;
      final origCaption = msgs
          .map((m) => m.caption ?? m.text ?? '')
          .where((s) => s.isNotEmpty)
          .firstOrNull;
      newCaption = await _processCaption(task, aiService, origCaption);

      for (final tgt in targets) {
        if (runner.cancelled) break;
        // ★ 使用 copyMessages 批量转发整个媒体组（最多10条）
        // 分批处理（每批10条）
        bool anySuccess = false;
        for (int i = 0; i < msgIds.length; i += 10) {
          final batch = msgIds.sublist(i, min(i + 10, msgIds.length));
          final ok = await TelegramBotService.instance.copyMessages(
            token: account.botToken,
            fromChatId: srcChatId,
            toChatId: tgt,
            messageIds: batch,
            removeCaption: task.removeCaption,
          );
          if (ok) anySuccess = true;
        }

        if (anySuccess) {
          if (idx < tasks.length) tasks[idx].processedCount++;
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
              // ★ 媒体组：收集同 groupId 的所有消息，延迟2s后统一转发
              final gid = msg.mediaGroupId!;
              groupBuffer.putIfAbsent(gid, () => []).add(msg);

              // 重置计时器（等待同组更多消息）
              groupTimers[gid]?.cancel();
              groupTimers[gid] = Timer(const Duration(milliseconds: 2000), () {
                flushGroup(gid);
              });
            } else {
              // 单条消息：直接转发
              final targets =
                  task.targetChannels.isNotEmpty ? task.targetChannels : [''];

              // AI处理文案
              String? captionText = await _processCaption(
                  task, aiService, msg.caption ?? msg.text);

              for (final tgt in targets) {
                if (runner.cancelled) break;
                final newId = await TelegramBotService.instance.copyMessage(
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
