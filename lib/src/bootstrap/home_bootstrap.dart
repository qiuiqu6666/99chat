import 'dart:async';

import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/provider/user_sticker_provider.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/push_registration_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reason.dart';

import 'package:tencent_cloud_chat_demo/src/services/archived_conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_index_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_incremental_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/session/auth_repository.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/src/platform/web_im_realtime_watchdog.dart';
import 'package:tencent_cloud_chat_demo/src/services/home_post_im_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/home_realtime_connection_state_machine.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_warm_scheduler.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/push_identity_cache.dart';
import 'package:tencent_cloud_chat_demo/utils/init_step.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:flutter/foundation.dart';

/// 首页之后的业务预热。任何单项失败都不能改变 Session 状态。
class HomeBootstrap {
  HomeBootstrap._();
  static final instance = HomeBootstrap._();
  String? _startedUserId;
  int? _startedSessionGeneration;
  Future<void>? _running;
  Future<void>? _realtimePostHomeRunning;
  Future<void>? _idleSideEffectsRunning;
  Future<void>? _lowPriorityNetworkRunning;
  int _generation = 0;
  bool _homeFrameReady = false;
  Completer<void>? _homeFrameGate;
  Future<void>? _groupIdleSyncRunning;

  Future<void> start({
    LocalSetting? settings,
    String reason = 'login',
    int visibleConvType = 1,
  }) {
    final userId = SessionManager.instance.state.userId ?? '';
    if (userId.isEmpty) return Future<void>.value();
    final sessionGeneration = SessionManager.instance.sessionGeneration;
    final running = _running;
    if (_startedUserId == userId &&
        _startedSessionGeneration == sessionGeneration) {
      StartupPerfLog.markTagged(
        'home_bootstrap_join',
        category: 'cold_start',
        details: <String, Object>{
          'reason': reason,
          'sessionGeneration': sessionGeneration,
        },
      );
      return running ?? Future<void>.value();
    }
    _startedUserId = userId;
    _startedSessionGeneration = sessionGeneration;
    final generation = ++_generation;
    StartupPerfLog.markTagged(
      'home_bootstrap_start',
      category: 'cold_start',
      details: <String, Object>{
        'reason': reason,
        'bootstrapGeneration': generation,
        'sessionGeneration': sessionGeneration,
        'visibleConvType': visibleConvType,
      },
    );
    final identity = SessionIdentityService.instance.capture(
      ownerUserId: userId,
    );
    // Warm only the small conversation index while the home route crosses its
    // frame gate. The first-screen query joins this single-flight open.
    unawaited(ConversationLocalStore.instance.warmFirstScreenIndex());
    final run = _run(
      generation: generation,
      identity: identity,
      settings: settings,
      reason: reason,
      visibleConvType: visibleConvType,
    );
    _running = run;
    return run.whenComplete(() {
      if (identical(_running, run)) _running = null;
    });
  }

  /// Whether first-screen/realtime readiness is still in flight. Background
  /// restoration can remain paused across lifecycle changes; it must not
  /// suppress App's foreground IM reconnection while waiting to continue.
  bool get isRunningForCurrentSession {
    final userId = SessionManager.instance.state.userId ?? '';
    return userId.isNotEmpty &&
        (_running != null || _realtimePostHomeRunning != null) &&
        _startedUserId == userId &&
        _startedSessionGeneration == SessionManager.instance.sessionGeneration;
  }

  Future<void> _run({
    required int generation,
    required SessionIdentity identity,
    required LocalSetting? settings,
    required String reason,
    required int visibleConvType,
  }) async {
    await _waitForHomeFrame(identity, generation);
    if (!_isCurrent(identity, generation)) return;
    // 手机先灌本地归档 ID，避免已归档行先闪后消失。
    // 桌面不走 SP：首屏直接拉云端快照。
    await _runWithRetry(
      _BootstrapTask(
        archivedConversationPersistToDisk
            ? 'archive_local_ids'
            : 'archive_cloud_ids',
        () => archivedConversationPersistToDisk
            ? ensureArchivedConversationIDsLoaded()
            : ArchivedConversationSyncService.instance.syncOnLogin(
                force: true,
                expectedIdentity: identity,
              ),
      ),
      identity,
      generation,
    );
    if (!_isCurrent(identity, generation)) return;
    // Establish the first-screen projection before joining the heavier SDK
    // realtime path. The page may already have requested the same restore;
    // ChatSessionController coalesces that work into one local read.
    await _runWithRetry(
      _BootstrapTask(
        'conversation_local_projection',
        () => ChatSessionController.instance.restoreProjection(
          reason: ConversationStoreProjectionReason.coldStart,
          visibleConvType: visibleConvType,
        ),
      ),
      identity,
      generation,
    );
    if (!_isCurrent(identity, generation)) return;
    ConversationHistoryWarmScheduler.instance.markFirstScreenReady();
    _scheduleOtherTabPrime(visibleConvType);
    await _runWithRetry(
      _BootstrapTask(
        'notification_listeners',
        () => NotificationSettingsService.instance.ensureListenersAttached(),
      ),
      identity,
      generation,
    );
    if (!_isCurrent(identity, generation)) return;

    // Listeners may already be attached at IM login. This joins the socket
    // handshake for IM catch-up only; business idle work does not wait.
    HomeRealtimeConnectionStateMachine.instance.start(
      identity: identity,
      onReady: (readyIdentity) => _onRealtimeReady(
        identity: readyIdentity,
        generation: generation,
        reason: reason,
      ),
    );
    unawaited(ContactsProtocolSyncService.instance.attach());

    // Warm only the visible C2C names; reading the whole address book must
    // neither delay realtime activation nor compete with the first paint.
    unawaited(_runWithRetry(
      _BootstrapTask(
        'c2c_display_name_warmup',
        () => FriendSyncService.instance.warmupC2cDisplayNamesFromLocalStore(
          friendUserIds: ChatSessionController.instance.conversations
              .where((row) => row.type == 1)
              .map((row) => row.userID ?? '')
              .where((id) => id.isNotEmpty)
              .take(100)
              .toList(growable: false),
        ),
      ),
      identity,
      generation,
    ));

    // Archive/folder/sticker and group inbox do not wait for IM socket ready.
    _startNativeIdleSideEffects(identity: identity, generation: generation);
    _startGroupIdleSync(
      identity: identity,
      generation: generation,
      reason: reason,
    );
    unawaited(_startIdentityBindings(
      identity: identity,
      generation: generation,
      settings: settings,
    ));
    unawaited(_startLowPriorityNetworkIdle(
      identity: identity,
      generation: generation,
    ));
  }

  Future<void> _startLowPriorityNetworkIdle({
    required SessionIdentity identity,
    required int generation,
  }) async {
    final existing = _lowPriorityNetworkRunning;
    if (existing != null) {
      await existing;
      return;
    }
    late final Future<void> run;
    run = () async {
      // Give native IM reconciliation and the first interaction a quiet
      // window. This is intentionally longer than a frame-delay: a large
      // account can keep the SDK database busy for several seconds after the
      // connection becomes ready.
      await Future<void>.delayed(const Duration(seconds: 30));
      if (!_isCurrent(identity, generation)) return;

      final tasks = <_BootstrapTask>[
        _BootstrapTask(
          'device_sync',
          () => DeviceSyncService.instance.scheduleSyncAfterLogin(),
        ),
      ];
      for (final task in tasks) {
        if (!_isCurrent(identity, generation)) return;
        await _runWithRetry(task, identity, generation);
      }
    }();
    _lowPriorityNetworkRunning = run;
    try {
      await run;
    } finally {
      if (identical(_lowPriorityNetworkRunning, run)) {
        _lowPriorityNetworkRunning = null;
      }
    }
  }

  Future<void> _onRealtimeReady({
    required SessionIdentity identity,
    required int generation,
    required String reason,
  }) async {
    if (!_isCurrent(identity, generation)) return;
    if (kIsWeb) {
      WebImRealtimeWatchdog.start();
      await _runWithRetry(
        _BootstrapTask(
          'web_realtime_catch_up',
          () => WebImRealtimeWatchdog.catchUpNow(reason: 'home_bootstrap'),
        ),
        identity,
        generation,
      );
      return;
    }
    if (_realtimePostHomeRunning != null) return;
    final run = _runPostHomeAfterRealtime(
      identity: identity,
      generation: generation,
      reason: reason,
    );
    _realtimePostHomeRunning = run;
    unawaited(run.whenComplete(() {
      if (identical(_realtimePostHomeRunning, run)) {
        _realtimePostHomeRunning = null;
      }
    }));
  }

  Future<void> _runPostHomeAfterRealtime({
    required SessionIdentity identity,
    required int generation,
    required String reason,
  }) async {
    await _runWithRetry(
      _BootstrapTask(
        'native_post_home',
        () => HomePostImSyncService.instance.run(
          reason: reason,
          identity: identity,
          isCurrent: () => _isCurrent(identity, generation),
        ),
      ),
      identity,
      generation,
    );
  }

  void _scheduleOtherTabPrime(int visibleConvType) {
    final other = visibleConvType == 1 ? 2 : 1;
    unawaited(
      ConversationTabStore.instance.ensurePrimed(
        convType: other,
        coldStart: true,
        caller: 'otherTabPrime',
      ),
    );
  }

  Future<void> _startIdentityBindings({
    required SessionIdentity identity,
    required int generation,
    required LocalSetting? settings,
  }) async {
    if (!_isCurrent(identity, generation)) return;
    if (!await _waitForUiIdle(identity: identity, generation: generation)) {
      return;
    }
    await _runWithRetry(
      _BootstrapTask(
        'push_registration',
        () => PushRegistrationService.instance.syncAfterLogin(
          settings: settings,
        ),
      ),
      identity,
      generation,
    );
    if (!_isCurrent(identity, generation)) return;
    await _runWithRetry(
      _BootstrapTask(
        'friend_request_notice_idle',
        () => FriendRequestNoticeService.instance.ensureRunning(),
      ),
      identity,
      generation,
    );
  }

  void _startNativeIdleSideEffects({
    required SessionIdentity identity,
    required int generation,
  }) {
    if (kIsWeb || !_isCurrent(identity, generation)) return;
    if (_idleSideEffectsRunning != null) return;
    final run = _runNativeIdleSideEffects(
      identity: identity,
      generation: generation,
    );
    _idleSideEffectsRunning = run;
    unawaited(run.whenComplete(() {
      if (identical(_idleSideEffectsRunning, run)) {
        _idleSideEffectsRunning = null;
      }
    }));
  }

  Future<void> _runNativeIdleSideEffects({
    required SessionIdentity identity,
    required int generation,
  }) async {
    // Give the first usable frame a short quiet window before opening the
    // friend/profile and pin stores. This is an idle lane, not a readiness
    // gate, and is fenced by the same session generation as the main queue.
    await Future<void>.delayed(const Duration(seconds: 2));
    for (final task in _nativeSideEffectTasks(identity)) {
      if (!_isCurrent(identity, generation)) return;
      if (!await _waitForUiIdle(identity: identity, generation: generation)) {
        return;
      }
      await _runWithRetry(task, identity, generation);
    }
  }

  /// A timer delay is not the same as user-idle: users often start scrolling
  /// or open a chat a few seconds after the first frame. Do not spend the
  /// SQLite/SDK budget while either interaction is active. If the user keeps
  /// interacting, dropping this pass is intentional; the next foreground or
  /// session start will schedule it again.
  Future<bool> _waitForUiIdle({
    required SessionIdentity identity,
    required int generation,
  }) async {
    final startedAt = DateTime.now();
    const maxWait = Duration(seconds: 15);
    while (_isCurrent(identity, generation)) {
      if (!ActiveChatRegistry.instance.hasOpenChat &&
          !ChatSessionController.instance.isFeedScrollingNow) {
        return true;
      }
      if (DateTime.now().difference(startedAt) >= maxWait) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// 群直播/通知仍是 freshness 工作，不是首页 ready 条件。
  /// 已加入群、好友关系改由 IM SDK 会话/关系链回调提供，首页 idle 不再全量对账
  /// 或翻自建 change-event / friends Difference。contacts v2 catch-up 由
  /// ContactsProtocolSyncService 在 home_bind / tcp_auth_ok 路径执行。
  void _startGroupIdleSync({
    required SessionIdentity identity,
    required int generation,
    required String reason,
  }) {
    if (kIsWeb || !_isCurrent(identity, generation)) return;
    if (_groupIdleSyncRunning != null) return;
    late final Future<void> run;
    run = _runGroupIdleSync(
      identity: identity,
      generation: generation,
      reason: reason,
    ).whenComplete(() {
      if (identical(_groupIdleSyncRunning, run)) {
        _groupIdleSyncRunning = null;
      }
    });
    _groupIdleSyncRunning = run;
    unawaited(run);
  }

  Future<void> _runGroupIdleSync({
    required SessionIdentity identity,
    required int generation,
    required String reason,
  }) async {
    // 首屏和第一次用户交互保留安静窗口。若用户立即进入聊天，直接让出
    // 本轮；下一次 auth-ok / foreground 会重新安排。
    await Future<void>.delayed(const Duration(seconds: 8));
    if (!_isCurrent(identity, generation) ||
        ActiveChatRegistry.instance.hasOpenChat) {
      return;
    }
    final tasks = <_BootstrapTask>[
      _BootstrapTask(
        'idle_group_live_index',
        () => GroupLiveIndexSyncService.instance.fetchIndex(
          reason: '${reason}_idle',
        ),
      ),
      _BootstrapTask(
        'idle_group_notice_incremental',
        () => GroupNoticeIncrementalSyncService.instance.sync(
          reason: '${reason}_idle',
        ),
      ),
    ];
    for (final task in tasks) {
      if (!_isCurrent(identity, generation) ||
          ActiveChatRegistry.instance.hasOpenChat) {
        return;
      }
      if (!await _waitForUiIdle(identity: identity, generation: generation)) {
        return;
      }
      await _runWithRetry(task, identity, generation);
    }
  }

  List<_BootstrapTask> _nativeSideEffectTasks(SessionIdentity identity) {
    return <_BootstrapTask>[
      _BootstrapTask(
        'archived_sync',
        () => ArchivedConversationSyncService.instance.syncOnLogin(
          expectedIdentity: identity,
        ),
      ),
      _BootstrapTask(
        'folder_sync',
        () => ConversationFolderSyncService.instance.syncOnLogin(),
      ),
      _BootstrapTask(
        'pin_sync',
        () => ConversationPinSyncService.instance.syncOnLogin(),
      ),
      _BootstrapTask('avatar_push', () async {
        final me = await AuthApi.instance.fetchMe();
        await UserAvatarHelper.syncSelfAvatarFromBackend(me.avatarUrl);
        await PushIdentityCache.instance.refreshSelf();
      }),
      _BootstrapTask('stickers', () async {
        await UserStickerProvider.shared.refresh(force: true);
        final navContext = AppNavigator.context;
        if (navContext != null && navContext.mounted) {
          await InitStep.publishStickerPackages(navContext);
        }
      }),
      _BootstrapTask(
        'group_notice',
        () => GroupNoticeBootstrap.install(
          refreshApplications: false,
          startFallbackPolling: false,
        ),
      ),
      _BootstrapTask(
        'moments_cover_cache',
        () => MomentsSettingsService.instance.hydrateFromLocal(),
      ),
    ];
  }

  Future<void> _waitForHomeFrame(
    SessionIdentity identity,
    int generation,
  ) async {
    if (_homeFrameReady) return;
    final gate = _homeFrameGate ??= Completer<void>();
    await gate.future;
  }

  /// Called by HomePage's post-frame callback. It is deliberately separate
  /// from route navigation so a login path can schedule work before the route
  /// exists without guessing with a timer.
  void markHomeFirstFrameReady({String? ownerUserId}) {
    final currentUser = SessionManager.instance.state.userId ?? '';
    if (ownerUserId != null && ownerUserId != currentUser) return;
    if (!_homeFrameReady) {
      StartupPerfLog.markTagged(
        'home_first_frame_ready',
        category: 'cold_start',
        details: <String, Object>{'ownerUserId': currentUser},
      );
      StartupPerfLog.markTagged(
        'auth_route_wait_end',
        category: 'cold_start',
        details: <String, Object>{'target': 'home'},
      );
    }
    _homeFrameReady = true;
    final gate = _homeFrameGate;
    _homeFrameGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _runWithRetry(
    _BootstrapTask task,
    SessionIdentity identity,
    int generation,
  ) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!_isCurrent(identity, generation)) return;
      final startedAt = DateTime.now();
      StartupPerfLog.markTagged(
        'home_task_start',
        category: 'post_home',
        details: <String, Object>{
          'task': task.name,
          'attempt': attempt,
          'generation': generation,
          'owner': identity.ownerUserId,
        },
      );
      try {
        await task.run();
        StartupPerfLog.markTagged(
          'home_task_finish',
          category: 'post_home',
          details: <String, Object>{
            'task': task.name,
            'attempt': attempt,
            'generation': generation,
            'owner': identity.ownerUserId,
            'result': 'ok',
            'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
          },
        );
        return;
      } catch (error) {
        if (_isTerminalAuthError(error)) {
          if (StartupPerfLog.consoleLoggingEnabled) {
            debugPrint(
              'HomeBootstrap task stopped by auth state: ${task.name}',
            );
          }
          StartupPerfLog.markTagged(
            'home_task_finish',
            category: 'post_home',
            details: <String, Object>{
              'task': task.name,
              'attempt': attempt,
              'generation': generation,
              'owner': identity.ownerUserId,
              'result': 'auth_terminal',
              'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
            },
          );
          return;
        }
        if (attempt == maxAttempts) {
          if (StartupPerfLog.consoleLoggingEnabled) {
            debugPrint('HomeBootstrap task failed: ${task.name}: $error');
          }
          StartupPerfLog.markTagged(
            'home_task_finish',
            category: 'post_home',
            details: <String, Object>{
              'task': task.name,
              'attempt': attempt,
              'generation': generation,
              'owner': identity.ownerUserId,
              'result': 'failed',
              'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
            },
          );
          return;
        }
        StartupPerfLog.markTagged(
          'home_task_retry',
          category: 'post_home',
          details: <String, Object>{
            'task': task.name,
            'attempt': attempt,
            'generation': generation,
            'owner': identity.ownerUserId,
          },
        );
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  bool _isTerminalAuthError(Object error) {
    if (error is SessionAuthExpiredException) return true;
    if (error is DioError) {
      return error.response?.statusCode == 401;
    }
    return false;
  }

  bool _isCurrent(SessionIdentity identity, int generation) {
    return generation == _generation &&
        SessionManager.instance.sessionGeneration ==
            _startedSessionGeneration &&
        SessionManager.instance.state.userId == identity.ownerUserId &&
        SessionIdentityService.instance.isCurrent(identity);
  }

  void reset({String reason = 'reset'}) {
    _generation++;
    _groupIdleSyncRunning = null;
    _realtimePostHomeRunning = null;
    _idleSideEffectsRunning = null;
    _lowPriorityNetworkRunning = null;
    HomeRealtimeConnectionStateMachine.instance.reset(reason: reason);
    ContactsProtocolSyncService.instance.detach();
    _startedUserId = null;
    _startedSessionGeneration = null;
    _homeFrameReady = false;
    final gate = _homeFrameGate;
    _homeFrameGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}

class _BootstrapTask {
  const _BootstrapTask(this.name, this.run);

  final String name;
  final FutureOr<void> Function() run;
}
