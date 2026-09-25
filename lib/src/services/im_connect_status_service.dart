import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_receipt_outbox_recovery_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_outbox_recovery_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_trust.dart';
import 'package:tencent_cloud_chat_demo/src/services/reconnect_recovery_epoch.dart';
import 'package:tencent_cloud_chat_sdk/enum/login_status.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

enum ImConnectionDiagnosticState {
  connected,
  connecting,
  reconnecting,
  offline,
  unknown,
}

/// 根据 IM SDK 长连接回调同步 UI 连接状态。
///
/// 冷启动 / 回前台 / 网络恢复进入首页后先展示连接中，直到 SDK 再次上报成功或
/// 确认已在线并满足本次握手的最短展示时长（800ms–2s）。
class ImConnectStatusService extends ChangeNotifier {
  ImConnectStatusService._();

  static final ImConnectStatusService instance = ImConnectStatusService._();

  static const Duration _handshakeVisibleMin = Duration(milliseconds: 800);
  static const Duration _handshakeVisibleMax = Duration(seconds: 2);
  static const Duration _handshakeTimeout = Duration(seconds: 12);
  static final Random _handshakeRandom = Random();

  bool _sdkSocketConnected = false;
  bool _handshakePending = false;

  /// 曾连上后断线：下次 onConnectSuccess 必须补拉会话/前台历史。
  bool _needsHistoryCatchUp = false;

  /// 真正的「曾连上→断线→再次成功」计数；握手展示期不计。
  final ReconnectRecoveryEpoch _recoveryEpoch = ReconnectRecoveryEpoch();
  DateTime? _handshakeStartedAt;
  Duration _handshakeMinVisible = _handshakeVisibleMin;
  Timer? _handshakeTimer;
  Timer? _handshakeDeadlineTimer;
  int _handshakeGeneration = 0;

  /// 预绑定的 LocalSetting：SDK 回调路径（无 BuildContext）下兜底写入。
  ///
  /// 由 [main] 在 Provider 容器创建后通过 [attach] 注入；让
  /// `markSocketConnected` / `markSocketDisconnected` / `onSdkConnecting`
  /// 这类无 context 的入口也能更新 UI 状态（之前仅靠 Provider.of 拿，
  /// context 为 null 时静默 return，导致 IM 真实已连但标题仍 stuck failed）。
  LocalSetting? _localSetting;

  @visibleForTesting
  static Future<bool> Function()? debugIsImLoggedInOverride;

  /// 注入 LocalSetting 单例，让 SDK 回调路径在无 BuildContext 时仍可写状态。
  void attach(LocalSetting localSetting) {
    _localSetting = localSetting;
  }

  /// 本次进程是否已收到过 IM SDK [onConnectSuccess]（含登录阶段）。
  static bool get socketConnectedThisLaunch => instance._sdkSocketConnected;

  /// UI 是否可认为 IM 长连接已就绪。
  ///
  /// Web 与原生一致：必须以真实 [onConnectSuccess] / 断线回调为准。
  /// 旧逻辑 `kIsWeb || …` 会把断线后的 WebSocket 仍当成已连接，漏消息且不补拉。
  static bool get isSocketReady =>
      instance._sdkSocketConnected && !instance._handshakePending;

  /// 是否处于冷启动 / 回前台 / 网络恢复后的连接握手展示周期。
  static bool get isHandshakePending => instance._handshakePending;

  /// SDK 长连接是否已建立（忽略握手最短展示期）。云端请求资格看这个；
  /// 「结果能否认证为最新」由 server sync 状态与 provenance 另行决定。
  static bool get isTransportReady => instance._sdkSocketConnected;

  /// Read-only transport snapshot. A minimum UI handshake display time does
  /// not turn an already connected socket into a network recovery interval.
  static ImConnectionDiagnosticState get diagnosticState {
    if (instance._sdkSocketConnected) {
      return ImConnectionDiagnosticState.connected;
    }
    if (instance._handshakePending) {
      return instance._needsHistoryCatchUp
          ? ImConnectionDiagnosticState.reconnecting
          : ImConnectionDiagnosticState.connecting;
    }
    if (instance._needsHistoryCatchUp ||
        instance._localSetting?.connectStatusForUi == ConnectStatus.failed) {
      return ImConnectionDiagnosticState.offline;
    }
    return ImConnectionDiagnosticState.unknown;
  }

  /// 当前真实重连纪元；OpenViewportCache / latest-window trust 以此判过期。
  static int get recoveryEpoch => instance._recoveryEpoch.epoch;

  /// 取出并清除「断线后需补历史」标记（供 connect_success 决定 recovery reason）。
  static bool consumeNeedsHistoryCatchUp() {
    final needs = instance._needsHistoryCatchUp;
    instance._needsHistoryCatchUp = false;
    return needs;
  }

  static void resetLaunchSession() {
    instance._handshakeGeneration++;
    instance._resetHandshakeTimers();
    instance._sdkSocketConnected = false;
    instance._handshakePending = false;
    instance._needsHistoryCatchUp = false;
    instance._handshakeStartedAt = null;
    instance._handshakeMinVisible = _handshakeVisibleMin;
    instance._recoveryEpoch.resetLaunchSession();
    ChatLatestWindowTrust.instance.clear();
    ImSdkRelationshipReconcileService.instance.onSessionInvalidated();
    instance.notifyListeners();
  }

  static void markSocketConnected() {
    instance._onSdkConnectSuccess();
  }

  static void markSocketDisconnected() {
    if (instance._sdkSocketConnected) {
      instance._needsHistoryCatchUp = true;
      instance._recoveryEpoch.onDisconnectedAfterConnected();
      ImSdkRelationshipReconcileService.instance
          .onSocketDisconnectedAfterConnected();
    }
    instance._sdkSocketConnected = false;
    instance._handshakeGeneration++;
    instance._handshakePending = false;
    instance._handshakeStartedAt = null;
    instance._resetHandshakeTimers();
    _setConnectStatus(null, ConnectStatus.failed);
    instance.notifyListeners();
  }

  /// 冷启动 / 回前台 / 网络恢复：进入等待 IM 长连接握手周期。
  static void beginSocketHandshake({BuildContext? context}) {
    instance._beginHandshake(context: context);
  }

  /// 回前台/网络通知不等于 SDK 断线；已有成功回调时保留连接状态。
  static void refreshSocketStatus({BuildContext? context}) {
    if (isSocketReady) {
      _setConnectStatus(context, ConnectStatus.success);
      return;
    }
    beginSocketHandshake(context: context);
  }

  /// 冷启动进首页：长连接尚未在 UI 层完成握手时保持「连接中」可见。
  static void applyForColdStartHome(BuildContext context) {
    if (!context.mounted) {
      return;
    }
    beginSocketHandshake(context: context);
  }

  static void onSdkConnecting({BuildContext? context}) {
    if (instance._sdkSocketConnected) {
      instance._needsHistoryCatchUp = true;
      instance._recoveryEpoch.onDisconnectedAfterConnected();
      ImSdkRelationshipReconcileService.instance
          .onSocketDisconnectedAfterConnected();
    }
    instance._sdkSocketConnected = false;
    // Reconnecting can arrive while the success display timer is pending.
    // Cancel that completion, but preserve the attempt's original deadline.
    instance._handshakeTimer?.cancel();
    instance._handshakeTimer = null;
    instance._beginHandshake(context: context);
  }

  static void onSdkConnectSuccess({BuildContext? context}) {
    instance._onSdkConnectSuccess(context: context);
  }

  void _onSdkConnectSuccess({BuildContext? context}) {
    _sdkSocketConnected = true;
    if (_recoveryEpoch.onConnectSuccess()) {
      if (kDebugMode) {
        debugPrint('IM recovery epoch bumped epoch=${_recoveryEpoch.epoch}');
      }
      ChatLatestWindowTrust.instance.onRecoveryEpochChanged(
        _recoveryEpoch.epoch,
      );
    }
    ImSdkRelationshipReconcileService.instance.onSocketConnectSuccess();
    unawaited(
      ConversationUnreadClearService.recoverPendingReadOutbox(
              afterReconnect: true)
          .catchError(
        (Object error) => debugPrint(
          'recover conversation read outbox failed '
          'errorType=${error.runtimeType}',
        ),
      ),
    );
    unawaited(
      ReadReceiptOutboxRecoveryService.instance.recoverPending().catchError(
            (Object error) => debugPrint(
              'recover read receipt outbox failed '
              'errorType=${error.runtimeType}',
            ),
          ),
    );
    unawaited(
      OutgoingOutboxRecoveryService.instance.recoverPending().catchError(
            (Object error) => debugPrint(
              'recover outgoing outbox failed errorType=${error.runtimeType}',
            ),
          ),
    );
    if (_handshakePending) {
      _scheduleHandshakeComplete(context: context);
    } else {
      _setConnectStatus(context, ConnectStatus.success);
    }
    notifyListeners();
  }

  void _beginHandshake({BuildContext? context}) {
    // Repeated home/network callbacks must not extend one pending handshake
    // indefinitely. The first owner keeps the deadline for this attempt.
    if (_handshakePending) {
      _setConnectStatus(context, ConnectStatus.connecting);
      notifyListeners();
      return;
    }
    _resetHandshakeTimers();
    final generation = ++_handshakeGeneration;
    _handshakePending = true;
    _handshakeStartedAt = DateTime.now();
    _handshakeMinVisible = _pickHandshakeMinVisible();
    // Every attempt owns a timeout, including one begun with a live socket.
    // SDK callbacks and minimum-display timers must never cancel this guard.
    _handshakeDeadlineTimer = Timer(_handshakeTimeout, () {
      if (generation != _handshakeGeneration || !_handshakePending) return;
      if (_sdkSocketConnected) {
        _completeHandshake(context: context);
      } else {
        _failHandshake(
          context: context,
          generation: generation,
          reason: 'sdk_connect_timeout',
        );
      }
    });
    _setConnectStatus(context, ConnectStatus.connecting);
    notifyListeners();

    if (_sdkSocketConnected) {
      _scheduleHandshakeComplete(context: context);
    }
  }

  void _scheduleHandshakeComplete({BuildContext? context}) {
    if (_handshakeTimer?.isActive ?? false) return;
    final started = _handshakeStartedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(started);
    final remaining = _handshakeMinVisible - elapsed;
    if (remaining <= Duration.zero) {
      _completeHandshake(context: context);
      return;
    }
    _handshakeTimer = Timer(remaining, () {
      _completeHandshake(context: context);
    });
  }

  void _completeHandshake({BuildContext? context}) {
    if (!_handshakePending || !_sdkSocketConnected) {
      return;
    }
    _handshakePending = false;
    _handshakeStartedAt = null;
    _resetHandshakeTimers();
    if (_sdkSocketConnected) {
      _setConnectStatus(context, ConnectStatus.success);
    }
    notifyListeners();
  }

  void _failHandshake({
    BuildContext? context,
    int? generation,
    required String reason,
  }) {
    final expectedGeneration = generation ?? _handshakeGeneration;
    if (expectedGeneration != _handshakeGeneration) {
      return;
    }
    if (!_handshakePending || _sdkSocketConnected) {
      return;
    }
    _resetHandshakeTimers();
    unawaited(
      _recoverOrFailHandshake(
        context: context,
        generation: expectedGeneration,
        reason: reason,
      ),
    );
  }

  Future<void> _recoverOrFailHandshake({
    required BuildContext? context,
    required int generation,
    required String reason,
  }) async {
    final loggedIn = await isImLoggedIn();
    if (generation != _handshakeGeneration) {
      return;
    }
    if (!_handshakePending || _sdkSocketConnected) {
      return;
    }
    if (loggedIn) {
      if (kDebugMode) {
        debugPrint(
          'IM connect handshake recovered_logged_in reason=$reason',
        );
      }
      _onSdkConnectSuccess(context: context);
      return;
    }
    _handshakePending = false;
    _handshakeStartedAt = null;
    _setConnectStatus(context, ConnectStatus.failed);
    if (kDebugMode) {
      debugPrint('IM connect handshake failed reason=$reason');
    }
    notifyListeners();
  }

  void _resetHandshakeTimers() {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _handshakeDeadlineTimer?.cancel();
    _handshakeDeadlineTimer = null;
  }

  static Duration _pickHandshakeMinVisible() {
    final minMs = _handshakeVisibleMin.inMilliseconds;
    final maxMs = _handshakeVisibleMax.inMilliseconds;
    final ms = minMs + _handshakeRandom.nextInt(maxMs - minMs + 1);
    return Duration(milliseconds: ms);
  }

  /// 网络恢复后兜底：仅在已收到 [onConnectSuccess] 时清除「连接中」。
  static Future<void> reconcileAfterNetworkOnline(
    BuildContext? context, {
    Duration gracePeriod = const Duration(milliseconds: 800),
  }) async {
    if (gracePeriod > Duration.zero) {
      await Future<void>.delayed(gracePeriod);
    }
    await _applySessionReadyConnectStatus(context);
  }

  static Future<void> _applySessionReadyConnectStatus(
    BuildContext? context,
  ) async {
    if (context == null || !context.mounted) return;
    if (!LoginCoordinator.instance.state.isImReady) {
      if (!await isImLoggedIn()) return;
    }
    try {
      final settings = Provider.of<LocalSetting>(context, listen: false);
      if (isSocketReady && !isHandshakePending) {
        if (settings.connectStatusForUi != ConnectStatus.success) {
          settings.connectStatus = ConnectStatus.success;
        }
        return;
      }
      final uiStatus = settings.connectStatusForUi;
      if (!isHandshakePending) {
        beginSocketHandshake(context: context);
        return;
      }
      final startedAt = instance._handshakeStartedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) >= _handshakeTimeout) {
        instance._failHandshake(
          context: context,
          reason: 'network_reconcile_timeout',
        );
        return;
      }
      if (uiStatus != ConnectStatus.connecting) {
        settings.connectStatus = ConnectStatus.connecting;
      }
    } catch (_) {}
  }

  /// 冷启动进首页后兜底：长时间未收到 onConnectSuccess 时走 [_failHandshake]。
  /// 未登录才标 failed；SDK 已 LOGINED 则补记成功回调，不把未登录写成 ready。
  static Future<void> reconcileStaleConnectingAfterColdStart(
    BuildContext? context, {
    Duration gracePeriod = const Duration(seconds: 12),
  }) async {
    final generation = instance._handshakeGeneration;
    await Future<void>.delayed(gracePeriod);
    if (context == null || !context.mounted) return;
    if (generation != instance._handshakeGeneration) return;
    if (isSocketReady && !isHandshakePending) return;
    // Unlogged-in timeout still lands on ConnectStatus.failed via _failHandshake.
    instance._failHandshake(
      context: context,
      generation: generation,
      reason: 'cold_start_timeout',
    );
  }

  static Future<bool> isImLoggedIn() async {
    final override = debugIsImLoggedInOverride;
    if (override != null) {
      return override();
    }
    if (kIsWeb) {
      return true;
    }
    try {
      final status = await TencentImSDKPlugin.v2TIMManager.getLoginStatus();
      if (status.code == 0 && status.data == LoginStatus.V2TIM_STATUS_LOGINED) {
        return true;
      }
    } catch (_) {}
    final res = await TencentImSDKPlugin.v2TIMManager.getLoginUser();
    final userId = res.data?.trim() ?? '';
    return res.code == 0 && userId.isNotEmpty;
  }

  /// 等待 IM SDK 登录完成（回前台/重连后补拉历史前调用）。
  static Future<bool> waitForImLoggedIn({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (kIsWeb) {
      return true;
    }
    if (await isImLoggedIn()) {
      return true;
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await isImLoggedIn()) {
        return true;
      }
    }
    return isImLoggedIn();
  }

  /// 仅在 bootstrap 阶段且长连接已就绪时清除 stale 的「连接中」。
  static Future<void> syncToLocalSetting(BuildContext? context) async {
    if (context == null || !context.mounted) return;
    try {
      if (!await isImLoggedIn()) return;
      final phase = LoginCoordinator.instance.state.phase;
      final bootstrapPhase = phase == LoginPhase.imConnecting ||
          phase == LoginPhase.homeEnteredSyncingIm;
      if (!bootstrapPhase || !isSocketReady || isHandshakePending) return;

      final settings = Provider.of<LocalSetting>(context, listen: false);
      if (settings.connectStatus == ConnectStatus.connecting) {
        settings.connectStatus = ConnectStatus.success;
      }
    } catch (_) {}
  }

  static void _setConnectStatus(BuildContext? context, ConnectStatus status) {
    // 优先用 context 取 LocalSetting（UI 路径）。
    if (context != null && context.mounted) {
      try {
        Provider.of<LocalSetting>(context, listen: false).connectStatus =
            status;
        return;
      } catch (_) {}
    }
    // 兜底：context 不可用时用 [attach] 预绑定的 LocalSetting（SDK 回调路径）。
    // 之前 context 为 null 时直接 return，导致 `markSocketConnected` /
    // `markSocketDisconnected` 这类无 context 入口写了 IM SDK 内部状态
    // 却没同步 UI 的 connectStatus，标题一直 stuck failed。
    final settings = instance._localSetting;
    if (settings != null) {
      settings.connectStatus = status;
    }
  }

  @override
  void dispose() {
    _resetHandshakeTimers();
    super.dispose();
  }
}
