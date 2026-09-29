import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reason.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_list_sync_notifier.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/native_bootstrap_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

/// Owns the post-home IM data plan for native platforms.
///
/// [HomeBootstrap] owns scheduling, retries, and session generations. This
/// service owns the single ordered native post-home IM data plan.
class HomePostImSyncService {
  HomePostImSyncService._();

  static final instance = HomePostImSyncService._();

  Future<void> run({
    required String reason,
    required SessionIdentity identity,
    required bool Function() isCurrent,
  }) async {
    final overallT0 = DateTime.now();
    final safeReason = _truncateReason(reason);
    var conversationUsable = false;
    // Friend data is not required for the conversation first paint. It is
    // hydrated from local storage and reconciled when the contacts surface is
    // opened, so it must not hold the post-home queue here.
    var friendReady = true;
    // Group membership is not part of the conversation first paint. The
    // group surface owns its local-first load and bounded reconciliation.
    // Cursor expiry may still request a full repair from the group domain.
    const groupReady = true;
    var stage1StateApplied = false;
    StartupPerfLog.markTagged(
      'post_home_im_sync_start',
      category: 'post_home',
      details: <String, Object>{'reason': safeReason},
    );

    try {
      DeviceSyncService.instance.suspendPhotoSync(
        reason: 'home_post_im_sync',
        duration: const Duration(seconds: 25),
      );
      final listenersReady = ImConnectStatusService.isSocketReady &&
          ConversationSyncService.instance.isRealtimeActiveFor(identity);
      _log(
        'realtime_readiness_observed generation=${identity.generation} '
        'socket=${ImConnectStatusService.isSocketReady} '
        'bindings=${ConversationSyncService.instance.isRealtimeActiveFor(identity)} '
        'ready=$listenersReady',
      );
      if (!isCurrent()) return;
      await Future<void>.delayed(NativeBootstrapPerfFlags.postHomeStartDelay);
      if (!isCurrent()) return;
      await _waitWhileFeedScrollingIfNeeded(isCurrent: isCurrent);
      if (!isCurrent()) return;

      final conversationT0 = DateTime.now();
      final conversationResult = listenersReady
          ? await _stage1ConversationFirstPage(
              reason: reason,
              isCurrent: isCurrent,
            )
          : ConversationBootstrapResult.failed;
      _logStageTiming('conversation_s1', conversationT0);
      conversationUsable = conversationResult.isUsable;
      if (!listenersReady) {
        ConversationListSyncNotifier.instance.setRetryableFailure(true);
      }
      if (!isCurrent()) return;

      // A locally synchronized projection is already the first-screen source.
      // Do not immediately reopen SQLite and rebuild the same window after a
      // redundant SDK first-page attempt. Realtime deltas still flow through
      // ConversationSyncService, and user-driven pagination remains intact.
      if (conversationResult != ConversationBootstrapResult.localReady) {
        await _waitWhileFeedScrollingIfNeeded(isCurrent: isCurrent);
        if (!isCurrent()) return;
        await _runCatching(
          'conversation_hot_window_reload',
          () => ChatSessionController.instance.restoreProjection(
            reason: ConversationStoreProjectionReason.authBootstrap,
          ),
        );
      } else {
        _log('conversation_hot_window_reload skipped local_projection_ready');
      }
      if (!isCurrent()) return;

      AuthBootstrapService.instance.applyNativePostHomeStage1Finished(
        conversationReady: conversationResult.isSuccess,
      );
      stage1StateApplied = true;
      await _yieldIfCurrent(isCurrent);
      if (!isCurrent()) return;
      await _waitWhileFeedScrollingIfNeeded(isCurrent: isCurrent);
      if (!isCurrent()) return;
      if (!conversationUsable || !friendReady || !groupReady) {
        throw StateError(
          'post-home IM sync incomplete: '
          'conversation=$conversationUsable friend=$friendReady group=$groupReady',
        );
      }
      _log('done reason=$safeReason');
      _logStageTiming('all', overallT0);
      StartupPerfLog.markTagged(
        'post_home_im_sync_done',
        category: 'post_home',
        details: <String, Object>{
          'conversationUsable': conversationUsable,
          'friendReady': friendReady,
          'groupReady': groupReady,
        },
      );
    } catch (error, stackTrace) {
      _log('failed reason=$safeReason error=$error\n$stackTrace');
      _logStageTiming('all', overallT0);
      StartupPerfLog.markTagged(
        'post_home_im_sync_failed',
        category: 'post_home',
        details: <String, Object>{'reason': safeReason},
      );
      if (isCurrent() && !stage1StateApplied) {
        AuthBootstrapService.instance.applyNativePostHomeStage1Finished(
          conversationReady: false,
        );
      }
      rethrow;
    } finally {
      // A stale account must not flush the current account's cold-start tab
      // batches after a logout or fast account switch.
      if (isCurrent()) {
        ConversationTabStore.instance.notifyColdStartEnded();
      }
    }
  }

  Future<ConversationBootstrapResult> _stage1ConversationFirstPage({
    required String reason,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return ConversationBootstrapResult.stale;
    try {
      // Login, page entry and S1 reuse the SDK tab's first-page task. The
      // backend archive index is not a readiness signal for the main list.
      return await _bootstrapTypedFirstScreen(
          reason: '${reason}_s1', reset: false, isCurrent: isCurrent);
    } catch (error) {
      if (isCurrent())
        ConversationListSyncNotifier.instance.setRetryableFailure(true);
      _log('conversation_s1 failed: $error');
      return ConversationBootstrapResult.failed;
    }
  }

  Future<ConversationBootstrapResult> _bootstrapTypedFirstScreen({
    required String reason,
    required bool reset,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return ConversationBootstrapResult.failed;
    StartupPerfLog.markTagged(
      's1_bootstrap_start',
      category: 'post_home',
      details: <String, Object>{'reason': reason},
    );
    final result = await ConversationSyncService.instance
        .bootstrapTypedFirstScreen(reason: reason, reset: reset);
    StartupPerfLog.markTagged(
      's1_bootstrap_done',
      category: 'post_home',
      details: <String, Object>{'result': result.name},
    );
    StartupPerfLog.emitColdStartTraceSummary(phase: 's1');
    return result;
  }

  Future<void> _waitWhileFeedScrollingIfNeeded({
    required bool Function() isCurrent,
  }) async {
    if (!ConversationPerfFlags.postHomePauseWhileFeedScrolling) return;
    final scrolling = ChatSessionController.instance.isFeedScrolling;
    if (scrolling == null || !scrolling()) return;
    final startedAt = DateTime.now();
    final maxWait = ConversationPerfFlags.postHomeScrollPauseMaxWait;
    while (true) {
      if (!isCurrent()) return;
      if (DateTime.now().difference(startedAt) >= maxWait) return;
      final fn = ChatSessionController.instance.isFeedScrolling;
      if (fn == null || !fn()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _yieldIfCurrent(bool Function() isCurrent) async {
    if (!isCurrent()) return;
    await Future<void>.delayed(NativeBootstrapPerfFlags.stageYield);
  }

  Future<void> _runCatching(
      String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _log('stage $label failed: $error');
    }
  }

  void _log(String message) {
    if (StartupPerfLog.consoleLoggingEnabled) {
      debugPrint('HomePostImSync: $message');
    }
  }

  void _logStageTiming(String stage, DateTime startedAt) {
    if (!StartupPerfLog.consoleLoggingEnabled) return;
    debugPrint(
      'HomePostImSync: stage=$stage '
      'elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds}',
    );
  }

  String _truncateReason(String reason) {
    const maxLen = 64;
    const headLen = 32;
    const tailLen = 16;
    if (reason.length <= maxLen) return reason;
    return '${reason.substring(0, headLen)}…${reason.substring(reason.length - tailLen)}';
  }
}
