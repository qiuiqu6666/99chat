import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';

class AndroidKeepAliveService {
  AndroidKeepAliveService._();

  static final AndroidKeepAliveService instance = AndroidKeepAliveService._();
  static const MethodChannel _channel = MethodChannel('android_keep_alive');

  bool _started = false;
  Future<void>? _runningTask;
  int _commandGeneration = 0;
  bool? _debugAndroidOverride;

  bool get _isAndroid => _debugAndroidOverride ?? Platform.isAndroid;

  @visibleForTesting
  void debugSetAndroidOverride(bool? value) => _debugAndroidOverride = value;

  Future<void> applyFromSettings(LocalSetting settings) async {
    if (!IMDemoConfig.androidKeepAliveEnabled || !_isAndroid) {
      await stop(reason: 'disabled');
      return;
    }

    final shouldRun = settings.notifySystemMessage ||
        settings.notifyVoiceVideoCall ||
        settings.notifyCallQuickAnswerPopup;
    if (!shouldRun) {
      await stop(reason: 'notification_off');
      return;
    }
    await start(reason: 'settings');
  }

  Future<void> start({String reason = 'manual'}) {
    final running = _runningTask;
    if (running != null) return running;

    final generation = ++_commandGeneration;
    late final Future<void> task;
    task = _start(reason: reason, generation: generation).whenComplete(() {
      if (identical(_runningTask, task)) {
        _runningTask = null;
      }
    });
    _runningTask = task;
    return _runningTask!;
  }

  Future<void> ensureRunning({String reason = 'ensure'}) async {
    if (!_isAndroid || !IMDemoConfig.androidKeepAliveEnabled) {
      return;
    }
    if (!_started) {
      await start(reason: reason);
      return;
    }
    final running = await isRunning();
    if (!running) {
      _started = false;
      await start(reason: '$reason-restart');
    }
  }

  Future<bool> isRunning() async {
    if (!_isAndroid) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _start({
    required String reason,
    required int generation,
  }) async {
    if (!_isAndroid || _started) {
      return;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('start', <String, dynamic>{
        'reason': reason,
      });
      if (generation == _commandGeneration) _started = ok ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AndroidKeepAlive: start failed ($e)');
      }
      if (generation == _commandGeneration) _started = false;
    }
  }

  Future<void> stop({String reason = 'manual'}) async {
    if (!_isAndroid) {
      return;
    }
    final generation = ++_commandGeneration;
    _runningTask = null;
    try {
      await _channel.invokeMethod<bool>('stop', <String, dynamic>{
        'reason': reason,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AndroidKeepAlive: stop failed ($e)');
      }
    } finally {
      if (generation == _commandGeneration) _started = false;
    }
  }
}
