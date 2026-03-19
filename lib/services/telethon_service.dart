import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Telethon桥接服务 - 通过Python子进程实现MTProto用户账号操作
/// 支持：读取任意已加入频道、无引用转发、媒体组保持
class TelethonService {
  static TelethonService? _instance;
  static TelethonService get instance => _instance ??= TelethonService._();
  TelethonService._();

  Process? _process;
  bool _ready = false;
  bool get isReady => _ready;

  final Map<String, Completer<Map<String, dynamic>>> _pendingReqs = {};
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  // ===== 启动Python桥接进程 =====
  Future<bool> start() async {
    if (_ready && _process != null) return true;
    if (kIsWeb) return false;

    try {
      // 1. 提取Python脚本到临时目录
      final scriptPath = await _extractScript();
      if (scriptPath == null) {
        debugPrint('[Telethon] 无法提取脚本文件');
        return false;
      }

      // 2. 检查Python是否可用
      final pythonPath = await _findPython();
      if (pythonPath == null) {
        debugPrint('[Telethon] 未找到Python，跳过MTProto支持');
        return false;
      }

      // 3. 检查telethon是否安装
      final hasLib = await _checkTelethon(pythonPath);
      if (!hasLib) {
        debugPrint('[Telethon] telethon未安装，尝试安装...');
        final installed = await _installTelethon(pythonPath);
        if (!installed) {
          debugPrint('[Telethon] telethon安装失败');
          return false;
        }
      }

      // 4. 启动Python进程
      _process = await Process.start(pythonPath, [scriptPath],
          mode: ProcessStartMode.normal);

      // 5. 监听输出
      _process!.stdout
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .listen(_onOutput, onDone: _onProcessDone, onError: _onProcessError);

      _process!.stderr
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .listen((line) {
        if (line.isNotEmpty) debugPrint('[Telethon STDERR] $line');
      });

      // 6. 等待ready信号（最多10秒）
      final completer = Completer<bool>();
      late StreamSubscription sub;
      sub = _eventController.stream.listen((evt) {
        if (evt['type'] == 'ready') {
          _ready = true;
          completer.complete(true);
          sub.cancel();
        }
      });

      Future.delayed(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          sub.cancel();
          completer.complete(false);
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('[Telethon] 启动失败: $e');
      return false;
    }
  }

  void _onOutput(String line) {
    if (line.isEmpty) return;
    try {
      final data = jsonDecode(line) as Map<String, dynamic>;
      final msgType = data['type'] as String?;
      final reqId = data['req_id'] as String?;

      // progress消息始终走eventController，不能提前结束pendingReqs
      // 只有最终响应（非progress类型）才能完成pendingReqs中的completer
      if (reqId != null &&
          _pendingReqs.containsKey(reqId) &&
          msgType != 'progress') {
        // 最终响应：完成 pendingReqs 中的 completer
        _pendingReqs.remove(reqId)?.complete(data);
        // 同时也广播到 eventController（让cloneMessages的stream监听收到）
        _eventController.add(data);
      } else {
        // progress消息或无req_id的消息都走eventController
        _eventController.add(data);
      }
    } catch (e) {
      debugPrint('[Telethon Output] $line');
    }
  }

  void _onProcessDone() {
    _ready = false;
    _process = null;
    // 通知所有等待中的请求
    for (final c in _pendingReqs.values) {
      if (!c.isCompleted) {
        c.complete({'type': 'error', 'error': 'Python进程已退出'});
      }
    }
    _pendingReqs.clear();
  }

  void _onProcessError(dynamic error) {
    debugPrint('[Telethon ProcessError] $error');
  }

  // ===== 发送命令 =====
  Future<Map<String, dynamic>> _sendCmd(Map<String, dynamic> cmd,
      {Duration timeout = const Duration(seconds: 60)}) async {
    if (!_ready || _process == null) {
      return {'type': 'error', 'error': '桥接服务未启动'};
    }
    final reqId = '${cmd['action']}_${DateTime.now().millisecondsSinceEpoch}';
    cmd['req_id'] = reqId;
    final completer = Completer<Map<String, dynamic>>();
    _pendingReqs[reqId] = completer;

    try {
      _process!.stdin.writeln(jsonEncode(cmd));
      await _process!.stdin.flush();
    } catch (e) {
      _pendingReqs.remove(reqId);
      return {'type': 'error', 'error': '发送命令失败: $e'};
    }

    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        _pendingReqs.remove(reqId);
        completer.complete({'type': 'error', 'error': '请求超时'});
      }
    });

    return completer.future;
  }

  // ===== 公开API =====

  /// 初始化客户端（检查是否已登录）
  Future<Map<String, dynamic>> startClient({
    required String apiId,
    required String apiHash,
    required String sessionKey,
  }) async {
    final sessionDir = await _getSessionDir();
    return _sendCmd({
      'action': 'start_client',
      'api_id': apiId,
      'api_hash': apiHash,
      'session_key': sessionKey,
      'session_dir': sessionDir,
    }, timeout: const Duration(seconds: 30));
  }

  /// 发送验证码
  Future<Map<String, dynamic>> sendCode({
    required String sessionKey,
    required String phone,
  }) async {
    return _sendCmd({
      'action': 'send_code',
      'session_key': sessionKey,
      'phone': phone,
    }, timeout: const Duration(seconds: 30));
  }

  /// 验证码登录
  Future<Map<String, dynamic>> signIn({
    required String sessionKey,
    required String phone,
    required String code,
    required String phoneCodeHash,
  }) async {
    return _sendCmd({
      'action': 'sign_in',
      'session_key': sessionKey,
      'phone': phone,
      'code': code,
      'phone_code_hash': phoneCodeHash,
    }, timeout: const Duration(seconds: 30));
  }

  /// 两步验证
  Future<Map<String, dynamic>> signIn2FA({
    required String sessionKey,
    required String password,
  }) async {
    return _sendCmd({
      'action': 'sign_in_2fa',
      'session_key': sessionKey,
      'password': password,
    }, timeout: const Duration(seconds: 30));
  }

  /// 克隆消息（完整克隆，支持私有频道）
  /// 通过进度回调实时报告进度
  Future<Map<String, dynamic>> cloneMessages({
    required String sessionKey,
    required String sourceChannel,
    required List<String> targetChannels,
    int startId = 0,
    int endId = 0,
    int count = 100,
    bool removeCaption = false,
    bool modifyMd5 = false,
    void Function(String msg)? onProgress,
  }) async {
    if (!_ready || _process == null) {
      return {'type': 'error', 'error': '桥接服务未启动'};
    }

    final reqId = 'clone_${DateTime.now().millisecondsSinceEpoch}';
    final cmd = {
      'action': 'clone_messages',
      'req_id': reqId,
      'session_key': sessionKey,
      'source_channel': sourceChannel,
      'target_channels': targetChannels,
      'start_id': startId,
      'end_id': endId,
      'count': count,
      'remove_caption': removeCaption,
      'modify_md5': modifyMd5,
    };

    final completer = Completer<Map<String, dynamic>>();

    // ★★★ 核心修复：只用 eventController 监听 ★★★
    // 绝对不能注册 _pendingReqs[reqId]，否则 _onOutput 收到第一条 progress 就会
    // 调用 _pendingReqs.remove(reqId)?.complete(data) 提前终止整个克隆任务！
    // progress 消息通过回调通知，clone_done/error 才完成 completer。
    late StreamSubscription sub;
    sub = _eventController.stream.listen((evt) {
      if (evt['req_id'] != reqId) return;
      final t = evt['type'] as String?;
      if (t == 'progress') {
        onProgress?.call(evt['msg'] as String? ?? '');
      } else if (t == 'clone_done' || t == 'error') {
        if (!completer.isCompleted) {
          completer.complete(evt);
          sub.cancel();
        }
      }
    });

    try {
      _process!.stdin.writeln(jsonEncode(cmd));
      await _process!.stdin.flush();
    } catch (e) {
      sub.cancel();
      return {'type': 'error', 'error': '发送命令失败: $e'};
    }

    // 超时（克隆可能很久）
    Future.delayed(const Duration(hours: 2), () {
      if (!completer.isCompleted) {
        sub.cancel();
        _pendingReqs.remove(reqId);
        completer.complete({'type': 'error', 'error': '克隆超时'});
      }
    });

    return completer.future;
  }

  /// 转发指定消息ID列表（无引用，保持媒体组）
  Future<Map<String, dynamic>> forwardMessages({
    required String sessionKey,
    required String sourceChannel,
    required String targetChannel,
    required List<int> messageIds,
    bool removeCaption = false,
  }) async {
    return _sendCmd({
      'action': 'forward_messages',
      'session_key': sessionKey,
      'source_channel': sourceChannel,
      'target_channel': targetChannel,
      'message_ids': messageIds,
      'remove_caption': removeCaption,
    }, timeout: const Duration(minutes: 5));
  }

  /// 获取最新消息（监听模式）
  Future<Map<String, dynamic>> getMessages({
    required String sessionKey,
    required String channel,
    int limit = 50,
    int minId = 0,
  }) async {
    return _sendCmd({
      'action': 'get_messages',
      'session_key': sessionKey,
      'channel': channel,
      'limit': limit,
      'min_id': minId,
    }, timeout: const Duration(seconds: 30));
  }

  // ===== 辅助方法 =====

  Future<String?> _extractScript() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final scriptDir = Directory(p.join(appDir.path, 'tg_bridge'));
      if (!await scriptDir.exists()) {
        await scriptDir.create(recursive: true);
      }
      final scriptFile = File(p.join(scriptDir.path, 'telethon_bridge.py'));

      // 从assets中读取脚本
      final content = await rootBundle.loadString('assets/scripts/telethon_bridge.py');
      await scriptFile.writeAsString(content);
      return scriptFile.path;
    } catch (e) {
      debugPrint('[Telethon] 提取脚本失败: $e');
      return null;
    }
  }

  Future<String?> _findPython() async {
    final candidates = Platform.isWindows
        ? ['python', 'python3', 'py']
        : ['python3', 'python'];
    for (final cmd in candidates) {
      try {
        final result = await Process.run(cmd, ['--version'],
            runInShell: true);
        if (result.exitCode == 0) return cmd;
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _checkTelethon(String pythonPath) async {
    try {
      final result = await Process.run(
          pythonPath, ['-c', 'import telethon; print("ok")'],
          runInShell: true);
      return result.exitCode == 0 &&
          result.stdout.toString().contains('ok');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _installTelethon(String pythonPath) async {
    try {
      final result = await Process.run(
          pythonPath, ['-m', 'pip', 'install', 'telethon', '--quiet'],
          runInShell: true)
          .timeout(const Duration(minutes: 3));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String> _getSessionDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final sessionDir = Directory(p.join(appDir.path, 'tg_sessions'));
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    return sessionDir.path;
  }

  Future<void> stop() async {
    _ready = false;
    _process?.kill();
    _process = null;
  }
}
