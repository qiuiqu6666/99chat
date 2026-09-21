import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/api/platform_api.dart';

/// 启动阶段统一检查客户端版本；结果只负责通知 UI，不阻塞登录。
class StartupVersionCheckService with WidgetsBindingObserver {
  StartupVersionCheckService._();
  static final instance = StartupVersionCheckService._();

  PlatformContactInfo? latest;
  bool checked = false;
  Future<PlatformContactInfo?>? _inFlight;

  /// 后台恢复重新拉取的最小间隔（platform-and-feedback.md §2）。
  static const Duration _foregroundRescanInterval = Duration(hours: 1);

  DateTime? _lastSuccessfulFetchAt;
  bool _attachedLifecycleObserver = false;

  Future<void> check() async {
    await fetch();
  }

  /// Shares the startup request with the first automatic update check. Manual
  /// checks may force a fresh response, but never create concurrent requests.
  Future<PlatformContactInfo?> fetch({bool force = false}) async {
    if (checked && !force) return latest;
    final pending = _inFlight;
    if (pending != null) return pending;
    late final Future<PlatformContactInfo?> task;
    task = () async {
      try {
        latest = await PlatformApi.instance.fetchContact();
        return latest;
      } catch (_) {
        return null;
      } finally {
        checked = true;
        if (identical(_inFlight, task)) _inFlight = null;
        _lastSuccessfulFetchAt = DateTime.now();
      }
    }();
    _inFlight = task;
    return task;
  }

  /// 注册 App 生命周期监听：进入前台时如果距离上次成功拉取超过 1 小时，
  /// 自动失效缓存并触发一次重新拉取（不阻塞 UI）。
  void attachLifecycleObserver() {
    if (_attachedLifecycleObserver) return;
    _attachedLifecycleObserver = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detachLifecycleObserver() {
    if (!_attachedLifecycleObserver) return;
    _attachedLifecycleObserver = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastSuccessfulFetchAt;
    final stale = last == null ||
        DateTime.now().difference(last) > _foregroundRescanInterval;
    if (!stale) return;
    // 失效缓存 + 静默重拉
    checked = false;
    unawaited(fetch(force: true));
  }

  void resetForTesting() {
    latest = null;
    checked = false;
    _inFlight = null;
    _lastSuccessfulFetchAt = null;
  }
}
