import 'package:flutter/material.dart';

// ==================== 枚举 ====================

enum AccountType { userApi, bot }
enum AccountStatus { disconnected, connecting, connected, error }
enum TaskStatus { idle, running, paused, completed, failed }
enum TaskMode { clone, monitor }
enum TransferMode { oneToOne, manyToMany }
enum LoginStep { idle, phoneInput, codeInput, passwordInput, scanQr, connected }

// ==================== TelegramAccount ====================
class TelegramAccount {
  final String id;
  String name;
  String phone;       // 手机号（userApi 模式）
  String apiId;       // Telegram App api_id
  String apiHash;     // Telegram App api_hash
  String botToken;    // Bot Token（bot 模式）
  AccountType type;
  AccountStatus status;
  String? username;
  String? avatar;
  String? sessionString; // MTProto session 序列化字符串（保留兼容性）
  bool telethonAuthorized; // 是否已通过Telethon登录（Python桥接模式）
  String? errorMessage;
  DateTime addedAt;

  TelegramAccount({
    required this.id,
    this.name = '',
    this.phone = '',
    this.apiId = '',
    this.apiHash = '',
    this.botToken = '',
    this.type = AccountType.userApi,
    this.status = AccountStatus.disconnected,
    this.username,
    this.avatar,
    this.sessionString,
    this.telethonAuthorized = false,
    this.errorMessage,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Telethon session key（用于Python桥接中识别此账号的session文件）
  String get sessionKey => 'acc_${id.replaceAll('-', '')}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'apiId': apiId,
    'apiHash': apiHash,
    'botToken': botToken,
    'type': type.name,
    'username': username ?? '',
    'sessionString': sessionString ?? '',
    'telethonAuthorized': telethonAuthorized,
    'addedAt': addedAt.toIso8601String(),
  };

  factory TelegramAccount.fromJson(Map<String, dynamic> j) => TelegramAccount(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    phone: j['phone'] ?? '',
    apiId: j['apiId'] ?? '',
    apiHash: j['apiHash'] ?? '',
    botToken: j['botToken'] ?? '',
    type: j['type'] == 'bot' ? AccountType.bot : AccountType.userApi,
    username: j['username'],
    sessionString: j['sessionString'],
    telethonAuthorized: j['telethonAuthorized'] ?? false,
    addedAt: DateTime.tryParse(j['addedAt'] ?? '') ?? DateTime.now(),
  );
}

// ==================== CloneTask ====================
class CloneTask {
  final String id;
  String name;

  // 来源频道（支持多个）
  List<String> sourceChannels;
  // 目标频道（支持多个）
  List<String> targetChannels;

  // 账号映射：source -> target
  String sourceAccountId;
  String targetAccountId;

  TaskMode mode;           // 克隆 or 监听
  TransferMode transferMode; // 1对1 or 多对多

  // 克隆范围
  int startMessageId;      // 起始消息 ID（0表示从头）
  int endMessageId;        // 结束消息 ID（0表示到最新）
  int cloneCount;          // 克隆数量限制（0=不限）

  // 过滤选项
  bool includeText;
  bool includePhoto;
  bool includeVideo;
  bool includeDocument;
  bool includeAudio;
  bool includeSticker;
  bool includeForwarded; // 是否包含原始转发内容

  // 转发选项
  bool removeCaption;     // 去除原始文案
  bool removeForwardTag;  // 无引用（不显示来源）
  bool aiRewrite;         // AI 改写文案
  String aiPrompt;        // AI 改写提示词

  // AI 润色（轻度修改，避免内容完全一致）
  bool aiPolish;          // 开启AI润色
  int aiPolishStyle;      // 润色风格：0=轻度 1=中度 2=重度

  // 广告过滤
  bool filterAds;         // 开启广告过滤
  String adKeywords;      // 自定义过滤关键词（每行一个）

  // 视频MD5修改
  bool modifyVideoMd5;    // 转发时随机修改视频MD5（防重复检测）

  // 监听选项
  int monitorIntervalSec; // 监听轮询间隔（秒）

  // 延迟配置
  int delayMin;           // 每条最小延迟（秒）
  int delayMax;           // 每条最大延迟（秒）

  TaskStatus status;
  double progress;
  int processedCount;
  int totalCount;
  String? errorMessage;
  DateTime createdAt;
  DateTime? lastRunAt;

  // 日志
  List<String> logs;

  CloneTask({
    required this.id,
    this.name = '',
    List<String>? sourceChannels,
    List<String>? targetChannels,
    this.sourceAccountId = '',
    this.targetAccountId = '',
    this.mode = TaskMode.clone,
    this.transferMode = TransferMode.oneToOne,
    this.startMessageId = 0,
    this.endMessageId = 0,
    this.cloneCount = 100,
    this.includeText = true,
    this.includePhoto = true,
    this.includeVideo = true,
    this.includeDocument = true,
    this.includeAudio = true,
    this.includeSticker = false,
    this.includeForwarded = true,
    this.removeCaption = false,
    this.removeForwardTag = true,
    this.aiRewrite = false,
    this.aiPrompt = '',
    this.aiPolish = false,
    this.aiPolishStyle = 0,
    this.filterAds = false,
    this.adKeywords = '',
    this.modifyVideoMd5 = false,
    this.monitorIntervalSec = 15,
    this.delayMin = 1,
    this.delayMax = 5,
    this.status = TaskStatus.idle,
    this.progress = 0,
    this.processedCount = 0,
    this.totalCount = 0,
    this.errorMessage,
    DateTime? createdAt,
    this.lastRunAt,
    List<String>? logs,
  })  : sourceChannels = sourceChannels ?? [],
        targetChannels = targetChannels ?? [],
        createdAt = createdAt ?? DateTime.now(),
        logs = logs ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourceChannels': sourceChannels,
    'targetChannels': targetChannels,
    'sourceAccountId': sourceAccountId,
    'targetAccountId': targetAccountId,
    'mode': mode.name,
    'transferMode': transferMode.name,
    'startMessageId': startMessageId,
    'endMessageId': endMessageId,
    'cloneCount': cloneCount,
    'includeText': includeText,
    'includePhoto': includePhoto,
    'includeVideo': includeVideo,
    'includeDocument': includeDocument,
    'includeAudio': includeAudio,
    'includeSticker': includeSticker,
    'includeForwarded': includeForwarded,
    'removeCaption': removeCaption,
    'removeForwardTag': removeForwardTag,
    'aiRewrite': aiRewrite,
    'aiPrompt': aiPrompt,
    'aiPolish': aiPolish,
    'aiPolishStyle': aiPolishStyle,
    'filterAds': filterAds,
    'adKeywords': adKeywords,
    'modifyVideoMd5': modifyVideoMd5,
    'monitorIntervalSec': monitorIntervalSec,
    'delayMin': delayMin,
    'delayMax': delayMax,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CloneTask.fromJson(Map<String, dynamic> j) {
    List<String> toStringList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : [];
    return CloneTask(
      id: j['id'] ?? '',
      name: j['name'] ?? '',
      sourceChannels: toStringList(j['sourceChannels']),
      targetChannels: toStringList(j['targetChannels']),
      sourceAccountId: j['sourceAccountId'] ?? '',
      targetAccountId: j['targetAccountId'] ?? '',
      mode: j['mode'] == 'monitor' ? TaskMode.monitor : TaskMode.clone,
      transferMode: j['transferMode'] == 'manyToMany'
          ? TransferMode.manyToMany
          : TransferMode.oneToOne,
      startMessageId: j['startMessageId'] ?? 0,
      endMessageId: j['endMessageId'] ?? 0,
      cloneCount: j['cloneCount'] ?? 100,
      includeText: j['includeText'] ?? true,
      includePhoto: j['includePhoto'] ?? true,
      includeVideo: j['includeVideo'] ?? true,
      includeDocument: j['includeDocument'] ?? true,
      includeAudio: j['includeAudio'] ?? true,
      includeSticker: j['includeSticker'] ?? false,
      includeForwarded: j['includeForwarded'] ?? true,
      removeCaption: j['removeCaption'] ?? false,
      removeForwardTag: j['removeForwardTag'] ?? true,
      aiRewrite: j['aiRewrite'] ?? false,
      aiPrompt: j['aiPrompt'] ?? '',
      aiPolish: j['aiPolish'] ?? false,
      aiPolishStyle: j['aiPolishStyle'] ?? 0,
      filterAds: j['filterAds'] ?? false,
      adKeywords: j['adKeywords'] ?? '',
      modifyVideoMd5: j['modifyVideoMd5'] ?? false,
      monitorIntervalSec: j['monitorIntervalSec'] ?? 15,
      delayMin: j['delayMin'] ?? 1,
      delayMax: j['delayMax'] ?? 5,
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

// ==================== AiConfig ====================
class AiConfig {
  /// provider 支持：
  ///   openai / deepseek / qianwen / zhipu / moonshot / gemini / openrouter /
  ///   pollinations（免费，无需Key）/ custom
  String provider;
  String apiKey;
  String model;
  String baseUrl;      // 自定义API地址
  bool enabled;

  AiConfig({
    this.provider = 'pollinations',
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
    this.enabled = false,
  });

  /// 是否为免费服务（不需要API Key）
  bool get isFreeProvider =>
      provider == 'pollinations';

  String get effectiveBaseUrl {
    if (baseUrl.isNotEmpty && provider != 'gemini') return baseUrl;
    switch (provider) {
      case 'openai':       return 'https://api.openai.com/v1';
      case 'deepseek':     return 'https://api.deepseek.com/v1';
      case 'qianwen':      return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
      case 'zhipu':        return 'https://open.bigmodel.cn/api/paas/v4';
      case 'moonshot':     return 'https://api.moonshot.cn/v1';
      case 'gemini':       return 'https://generativelanguage.googleapis.com/v1beta';
      case 'openrouter':   return 'https://openrouter.ai/api/v1';
      case 'pollinations': return 'https://text.pollinations.ai';
      default:             return 'https://api.openai.com/v1';
    }
  }

  String get defaultModel {
    switch (provider) {
      case 'deepseek':     return 'deepseek-chat';
      case 'qianwen':      return 'qwen-turbo';
      case 'zhipu':        return 'glm-4-flash';
      case 'moonshot':     return 'moonshot-v1-8k';
      case 'gemini':       return 'gemini-2.0-flash-exp';
      case 'openrouter':   return 'meta-llama/llama-3.1-8b-instruct:free';
      case 'pollinations': return 'openai';
      default:             return 'gpt-3.5-turbo';
    }
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'apiKey': apiKey,
    'model': model,
    'baseUrl': baseUrl,
    'enabled': enabled,
  };

  factory AiConfig.fromJson(Map<String, dynamic> j) => AiConfig(
    provider: j['provider'] ?? 'pollinations',
    apiKey: j['apiKey'] ?? '',
    model: j['model'] ?? '',
    baseUrl: j['baseUrl'] ?? '',
    enabled: j['enabled'] ?? false,
  );

  AiConfig copyWith({
    String? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
    bool? enabled,
  }) => AiConfig(
    provider: provider ?? this.provider,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    baseUrl: baseUrl ?? this.baseUrl,
    enabled: enabled ?? this.enabled,
  );
}

// ==================== AppSettings ====================
class AppSettings {
  bool ignoreSsl;
  AiConfig aiConfig;
  int globalDelayMin;
  int globalDelayMax;
  bool lightTheme;   // 白色/浅色主题

  AppSettings({
    this.ignoreSsl = true,
    AiConfig? aiConfig,
    this.globalDelayMin = 1,
    this.globalDelayMax = 5,
    this.lightTheme = false,
  }) : aiConfig = aiConfig ?? AiConfig();

  Map<String, dynamic> toJson() => {
    'ignoreSsl': ignoreSsl,
    'aiConfig': aiConfig.toJson(),
    'globalDelayMin': globalDelayMin,
    'globalDelayMax': globalDelayMax,
    'lightTheme': lightTheme,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    ignoreSsl: j['ignoreSsl'] ?? true,
    aiConfig: j['aiConfig'] != null
        ? AiConfig.fromJson(j['aiConfig'])
        : AiConfig(),
    globalDelayMin: j['globalDelayMin'] ?? 1,
    globalDelayMax: j['globalDelayMax'] ?? 5,
    lightTheme: j['lightTheme'] ?? false,
  );

  AppSettings copyWith({
    bool? ignoreSsl,
    AiConfig? aiConfig,
    int? globalDelayMin,
    int? globalDelayMax,
    bool? lightTheme,
  }) => AppSettings(
    ignoreSsl: ignoreSsl ?? this.ignoreSsl,
    aiConfig: aiConfig ?? this.aiConfig,
    globalDelayMin: globalDelayMin ?? this.globalDelayMin,
    globalDelayMax: globalDelayMax ?? this.globalDelayMax,
    lightTheme: lightTheme ?? this.lightTheme,
  );
}

// ==================== TransferRecord ====================
class TransferRecord {
  final String id;
  final String taskId;
  final String taskName;
  final String sourceChannel;
  final String targetChannel;
  final int messageId;
  final String mediaType;
  final bool aiRewritten;
  final DateTime transferredAt;

  TransferRecord({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.sourceChannel,
    required this.targetChannel,
    required this.messageId,
    required this.mediaType,
    required this.aiRewritten,
    required this.transferredAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'taskName': taskName,
    'sourceChannel': sourceChannel,
    'targetChannel': targetChannel,
    'messageId': messageId,
    'mediaType': mediaType,
    'aiRewritten': aiRewritten,
    'transferredAt': transferredAt.toIso8601String(),
  };

  factory TransferRecord.fromJson(Map<String, dynamic> j) => TransferRecord(
    id: j['id'] ?? '',
    taskId: j['taskId'] ?? '',
    taskName: j['taskName'] ?? '',
    sourceChannel: j['sourceChannel'] ?? '',
    targetChannel: j['targetChannel'] ?? '',
    messageId: j['messageId'] ?? 0,
    mediaType: j['mediaType'] ?? 'text',
    aiRewritten: j['aiRewritten'] ?? false,
    transferredAt: DateTime.tryParse(j['transferredAt'] ?? '') ?? DateTime.now(),
  );
}

// ==================== 扩展 ====================
extension AccountStatusExt on AccountStatus {
  Color get color {
    switch (this) {
      case AccountStatus.disconnected: return const Color(0xFF666699);
      case AccountStatus.connecting:   return const Color(0xFFFFAB00);
      case AccountStatus.connected:    return const Color(0xFF00E676);
      case AccountStatus.error:        return const Color(0xFFFF5252);
    }
  }
  String get label {
    switch (this) {
      case AccountStatus.disconnected: return '未连接';
      case AccountStatus.connecting:   return '连接中';
      case AccountStatus.connected:    return '已连接';
      case AccountStatus.error:        return '错误';
    }
  }
}

extension TaskStatusExt on TaskStatus {
  Color get color {
    switch (this) {
      case TaskStatus.idle:      return const Color(0xFF666699);
      case TaskStatus.running:   return const Color(0xFF6C63FF);
      case TaskStatus.paused:    return const Color(0xFFFFAB00);
      case TaskStatus.completed: return const Color(0xFF00E676);
      case TaskStatus.failed:    return const Color(0xFFFF5252);
    }
  }
  String get label {
    switch (this) {
      case TaskStatus.idle:      return '待运行';
      case TaskStatus.running:   return '运行中';
      case TaskStatus.paused:    return '已暂停';
      case TaskStatus.completed: return '已完成';
      case TaskStatus.failed:    return '失败';
    }
  }
  IconData get icon {
    switch (this) {
      case TaskStatus.idle:      return Icons.hourglass_empty_rounded;
      case TaskStatus.running:   return Icons.play_circle_rounded;
      case TaskStatus.paused:    return Icons.pause_circle_rounded;
      case TaskStatus.completed: return Icons.check_circle_rounded;
      case TaskStatus.failed:    return Icons.error_rounded;
    }
  }
}
