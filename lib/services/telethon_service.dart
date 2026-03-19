import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Telethon桥接服务 - 通过Python子进程实现MTProto用户账号操作
class TelethonService {
  static TelethonService? _instance;
  static TelethonService get instance => _instance ??= TelethonService._();
  TelethonService._();

  Process? _process;
  bool _ready = false;
  bool get isReady => _ready;

  // 普通请求（期望单次响应）
  final Map<String, Completer<Map<String, dynamic>>> _pendingReqs = {};

  // 进度回调（clone任务期间持续接收progress消息）
  final Map<String, void Function(String)> _progressCallbacks = {};

  // ready信号的completer（只在启动时使用一次）
  Completer<bool>? _startCompleter;

  Stream<Map<String, dynamic>> get events =>
      _eventController.stream;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();

  // ===== 启动Python桥接进程 =====
  Future<bool> start() async {
    if (_ready && _process != null) return true;
    if (kIsWeb) return false;

    try {
      final scriptPath = await _extractScript();
      if (scriptPath == null) return false;

      final pythonPath = await _findPython();
      if (pythonPath == null) return false;

      final hasLib = await _checkTelethon(pythonPath);
      if (!hasLib) {
        final installed = await _installTelethon(pythonPath);
        if (!installed) return false;
      }

      _process = await Process.start(pythonPath, [scriptPath],
          mode: ProcessStartMode.normal);

      _process!.stdout
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .listen(_onOutput, onDone: _onProcessDone, onError: _onProcessError);

      _process!.stderr
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .listen((line) {
        if (line.isNotEmpty) {
          debugPrint('[Telethon STDERR] $line');
          // 把Python stderr也显示在UI日志里
          _eventController.add({
            'type': 'progress',
            'req_id': '__stderr__',
            'msg': '[Python错误] $line',
          });
        }
      });

      _startCompleter = Completer<bool>();
      Future.delayed(const Duration(seconds: 15), () {
        if (_startCompleter != null && !_startCompleter!.isCompleted) {
          _startCompleter!.complete(false);
        }
      });

      return await _startCompleter!.future;
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

      // 处理 ready 信号
      if (msgType == 'ready') {
        _ready = true;
        _startCompleter?.complete(true);
        _startCompleter = null;
        return;
      }

      // 处理 progress 消息：通过回调通知，不完成 completer
      if (msgType == 'progress') {
        if (reqId != null) {
          final cb = _progressCallbacks[reqId];
          if (cb != null) {
            cb(data['msg'] as String? ?? '');
            return;
          }
        }
        // 没有回调就广播（如stderr等）
        _eventController.add(data);
        return;
      }

      // 处理最终响应（clone_done / error / 其他）
      if (reqId != null && _pendingReqs.containsKey(reqId)) {
        final completer = _pendingReqs.remove(reqId)!;
        _progressCallbacks.remove(reqId); // 清理回调
        if (!completer.isCompleted) {
          completer.complete(data);
        }
        return;
      }

      // 兜底：广播到eventController
      _eventController.add(data);
    } catch (e) {
      debugPrint('[Telethon Output parse error] $line | $e');
    }
  }

  void _onProcessDone() {
    _ready = false;
    _process = null;
    _startCompleter?.complete(false);
    _startCompleter = null;
    for (final c in _pendingReqs.values) {
      if (!c.isCompleted) {
        c.complete({'type': 'error', 'error': 'Python进程已退出'});
      }
    }
    _pendingReqs.clear();
    _progressCallbacks.clear();
  }

  void _onProcessError(dynamic error) {
    debugPrint('[Telethon ProcessError] $error');
  }

  // ===== 发送命令（单次响应） =====
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

  /// 克隆消息 — 用 _pendingReqs 等待 clone_done，用 _progressCallbacks 接收进度
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

    // 注册 completer 等待 clone_done/error
    final completer = Completer<Map<String, dynamic>>();
    _pendingReqs[reqId] = completer;

    // 注册进度回调（同时更新最后活动时间）
    DateTime lastActivity = DateTime.now();
    _progressCallbacks[reqId] = (msg) {
      lastActivity = DateTime.now();
      onProgress?.call(msg);
    };

    try {
      _process!.stdin.writeln(jsonEncode(cmd));
      await _process!.stdin.flush();
    } catch (e) {
      _pendingReqs.remove(reqId);
      _progressCallbacks.remove(reqId);
      return {'type': 'error', 'error': '发送命令失败: $e'};
    }

    // 活动超时检测：90秒无任何进度消息则视为卡住
    void checkActivity() {
      if (completer.isCompleted) return;
      final idle = DateTime.now().difference(lastActivity);
      if (idle > const Duration(seconds: 120)) {
        debugPrint('[Telethon] 克隆任务 $reqId 超过120秒无响应，视为超时');
        _pendingReqs.remove(reqId);
        _progressCallbacks.remove(reqId);
        completer.complete({'type': 'error', 'error': '克隆超时（120秒无响应）'});
      } else {
        // 继续检测
        Future.delayed(const Duration(seconds: 30), checkActivity);
      }
    }
    // 首次检测在30秒后开始（给Python足够时间启动）
    Future.delayed(const Duration(seconds: 30), checkActivity);

    // 绝对超时：2小时
    Future.delayed(const Duration(hours: 2), () {
      if (!completer.isCompleted) {
        _pendingReqs.remove(reqId);
        _progressCallbacks.remove(reqId);
        completer.complete({'type': 'error', 'error': '克隆超时（2小时上限）'});
      }
    });

    return completer.future;
  }

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
      final content =
          await rootBundle.loadString('assets/scripts/telethon_bridge.py');
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
        final result =
            await Process.run(cmd, ['--version'], runInShell: true);
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
      return result.exitCode == 0 && result.stdout.toString().contains('ok');
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
