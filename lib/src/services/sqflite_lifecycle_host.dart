import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/privileged_game_user_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_media_metadata_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/push_token_local/push_token_upload_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/red_packet_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';

import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_rebate_local/agent_rebate_entry_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_history_coverage_store.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_snapshot_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/photo_backup_progress_store.dart';

enum SqfliteWriteGateResult { ready, deferred, cancelled }

enum SqfliteLifecycleStatus { ready, paused, closing, degraded }

/// UI deadlines never release the real native close fence. Lifecycle events
/// overwrite one desired state instead of queueing behind an unbounded close.
class SqfliteLifecycleHost {
  SqfliteLifecycleHost._();
  static Completer<void>? _closeInFlight;
  static Completer<void>? _openAllowed;
  static int _epoch = 0;
  static bool _closeFailed = false;
  static AppLifecycleState _desired = AppLifecycleState.resumed;
  static final ValueNotifier<SqfliteLifecycleStatus> status =
      ValueNotifier(SqfliteLifecycleStatus.ready);
  static final Set<String> _pendingStores = {};
  static Set<String> get pendingStores => Set.unmodifiable(_pendingStores);
  static bool get _closeDatabasesOnPause =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _writesReady =>
      !_closeFailed &&
      _closeInFlight == null &&
      SqfliteLifecycleGuard.instance.writesAllowed &&
      SqfliteLifecycleGuard.instance.canOpenDatabase;

  static Future<bool> waitUntilOpenAllowed({
    Duration timeout = const Duration(seconds: 2),
  }) async =>
      await waitForWrites(timeout: timeout) == SqfliteWriteGateResult.ready;

  static Future<SqfliteWriteGateResult> waitForWrites({
    Duration timeout = const Duration(seconds: 2),
    bool Function()? isCurrent,
  }) async {
    final watch = Stopwatch()..start();
    while (true) {
      if (!(isCurrent?.call() ?? true)) return SqfliteWriteGateResult.cancelled;
      if (_writesReady) return SqfliteWriteGateResult.ready;
      final remaining = timeout - watch.elapsed;
      if (_closeFailed || remaining <= Duration.zero)
        return SqfliteWriteGateResult.deferred;
      final waiting =
          _closeInFlight?.future ?? (_openAllowed ??= Completer<void>()).future;
      try {
        await waiting.timeout(remaining);
      } on TimeoutException {
        if (!(isCurrent?.call() ?? true))
          return SqfliteWriteGateResult.cancelled;
        return _writesReady
            ? SqfliteWriteGateResult.ready
            : SqfliteWriteGateResult.deferred;
      }
    }
  }

  /// Compatibility for durable command workers that retain their exact token.
  /// UI paths use waitForWrites and must consume its deferred result.
  static Future<void> waitUntilWritesAllowed() async {
    while (!_writesReady) {
      await (_openAllowed ??= Completer<void>()).future;
    }
  }

  static Future<void> handle(
    AppLifecycleState state, {
    Duration waitBudget = const Duration(seconds: 2),
  }) async {
    _desired = state;
    await _handleImpl(state, waitBudget: waitBudget);
  }

  static Future<void> _handleImpl(
    AppLifecycleState state, {
    Duration waitBudget = const Duration(seconds: 2),
  }) async {
    switch (state) {
      case AppLifecycleState.inactive:
        _pauseWrites();
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _pauseWrites();
        if (!_closeDatabasesOnPause || _closeFailed) return;
        await _waitForClose(_closeDatabases(), waitBudget);
        return;
      case AppLifecycleState.resumed:
        if (_closeFailed) {
          status.value = SqfliteLifecycleStatus.degraded;
          return;
        }
        final pending = _closeInFlight;
        if (pending != null) {
          await _waitForClose(pending.future, waitBudget);
        } else {
          _resumeIfCurrent();
        }
        return;
    }
  }

  static Future<void> _waitForClose(Future<void> close, Duration budget) async {
    final epoch = _epoch;
    try {
      await close.timeout(budget);
    } on TimeoutException {
      if (epoch == _epoch && _closeInFlight != null) {
        status.value = SqfliteLifecycleStatus.degraded;
        StartupPerfLog.markTagged('database_close_deferred',
            category: 'database',
            details: {'epoch': epoch, 'pendingStores': _pendingStores.length});
      }
    }
  }

  static void _pauseWrites() {
    SqfliteLifecycleGuard.instance.pauseWrites();
    ConversationLocalStore.instance.pauseCoalesceForBackground();
    if (_closeInFlight == null && !_closeFailed)
      status.value = SqfliteLifecycleStatus.paused;
  }

  static void _resumeIfCurrent() {
    if (_desired != AppLifecycleState.resumed ||
        _closeInFlight != null ||
        _closeFailed) return;
    SqfliteLifecycleGuard.instance.resume();
    ConversationLocalStore.instance.resumeCoalesceAfterForeground();
    status.value = SqfliteLifecycleStatus.ready;
    _signalOpenAllowed();
  }

  static Future<void> _closeDatabases() {
    final existing = _closeInFlight;
    if (existing != null) return existing.future;
    final myEpoch = ++_epoch;
    final gate = Completer<void>();
    _closeInFlight = gate;
    SqfliteLifecycleGuard.instance.forbidOpen();
    _resetOpenAllowedWaiters();
    status.value = SqfliteLifecycleStatus.closing;
    unawaited(() async {
      var safelyClosed = false;
      try {
        await ConversationLocalStore.instance.waitUntilUpsertWriteIdle(
            maxWait: const Duration(milliseconds: 250));
        final stores = <String, Future<void> Function()>{
          'conversation': ConversationLocalStore.instance.closeIfOpen,
          'message_core': MessageCoreStore.instance.closeIfOpen,
          'history_window': HistoryWindowStore.instance.closeIfOpen,
          'history_coverage': MessageHistoryCoverageStore.instance.closeIfOpen,
          'friend': FriendLocalStore.instance.closeIfOpen,
          'group': GroupLocalStore.instance.closeIfOpen,
          'group_member': GroupMemberLocalStore.instance.closeIfOpen,
          'media': MessageMediaMetadataStore.instance.closeIfOpen,
          'moments': MomentsLocalStore.instance.closeIfOpen,
          'red_packet': RedPacketLocalStore.instance.closeIfOpen,
          'push': PushTokenUploadLocalStore.instance.closeIfOpen,
          'profile': UserProfileLocalStore.instance.closeIfOpen,
          'game': SangongMyConfigStore.instance.closeIfOpen,
          'privilege': PrivilegedGameUserStore.instance.closeIfOpen,
          'agent_entry': AgentRebateEntryLocalStore.instance.closeIfOpen,
          'wallet_snapshot': WalletSnapshotLocalStore.instance.close,
          'photo_backup_progress':
              PhotoBackupProgressStore.instance.closeIfOpen,
        };
        await Future.wait(stores.entries.map((entry) async {
          if (myEpoch != _epoch) return;
          _pendingStores.add(entry.key);
          final watch = Stopwatch()..start();
          StartupPerfLog.markTagged('database_close_start',
              category: 'database',
              details: {'epoch': myEpoch, 'store': entry.key});
          try {
            await entry.value();
            if (myEpoch == _epoch) _pendingStores.remove(entry.key);
            StartupPerfLog.markTagged('database_close_done',
                category: 'database',
                details: {
                  'epoch': myEpoch,
                  'store': entry.key,
                  'elapsedMs': watch.elapsedMilliseconds
                });
          } catch (_) {
            // The handle's state is unknown. Keep its fence and report degraded.
            rethrow;
          }
        }));
        safelyClosed = true;
      } catch (_) {
        if (myEpoch == _epoch) {
          _closeFailed = true;
          status.value = SqfliteLifecycleStatus.degraded;
        }
      } finally {
        if (myEpoch == _epoch) {
          _closeInFlight = null;
          if (safelyClosed) {
            status.value = SqfliteLifecycleStatus.paused;
            _resumeIfCurrent();
          }
        }
        if (!gate.isCompleted) gate.complete();
      }
    }());
    return gate.future;
  }

  static void _signalOpenAllowed() {
    final waiter = _openAllowed;
    _openAllowed = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  static void _resetOpenAllowedWaiters() => _signalOpenAllowed();

  @visibleForTesting
  static void debugReset() {
    _epoch++;
    _closeInFlight = null;
    _closeFailed = false;
    _desired = AppLifecycleState.resumed;
    _pendingStores.clear();
    status.value = SqfliteLifecycleStatus.ready;
    _signalOpenAllowed();
  }
}

void scheduleSqfliteLifecycle(AppLifecycleState state) {
  unawaited(SqfliteLifecycleHost.handle(state));
}
