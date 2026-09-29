// ignore_for_file: avoid_print

import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/conversation_notify_sync_service.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/platform/listener_store.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/starred_friend_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/user_sticker_provider.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_identity_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_background_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/privileged_game_user_service.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_join_application_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_incremental_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_entry_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_incremental_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_unread_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_system_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_conversation_unread_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_preview_text_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/archived_conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_sync_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/desktop_login_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_session_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_receipt_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_account_data_purge.dart';
import 'package:tencent_cloud_chat_demo/src/services/owner_disk_state_snapshot.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_system_notification_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/push_registration_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_dispatch_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_diagnostics.dart';
import 'package:tencent_cloud_chat_demo/src/bootstrap/home_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_message_send_queue.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/services/biometric_pay_service.dart';
import 'package:tencent_cloud_chat_demo/utils/constant.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_lifecycle_service.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_demo/src/services/call_lifecycle_service_web.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_peek_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class AccountSessionService {
  AccountSessionService._();

  void _sessionLog(String message) {
    SessionDiagnostics.log(message);
  }

  /// F 块（P2 F2）：账户切换结束埋点。文档 §9 P2 F2 要求
  /// reason/owner/durationMs/purgeOwnerDisk 完整字段。
  /// 与 [StartupPerfLog.markTagged] 不同——这里同时打两条：
  ///   1. `account_switch_finish` 通用埋点（含所有字段）。
  ///   2. `conv_owner_purge_finish` 单独埋点（强化 SDKAppID 切换场景观测）。
  void _recordAccountSwitchFinish({
    required String reason,
    required bool logoutIm,
    required bool purgeOwnerDisk,
    required String logoutOwner,
    DateTime? startedAt,
  }) {
    final durationMs = startedAt == null
        ? -1
        : DateTime.now().difference(startedAt).inMilliseconds;
    StartupPerfLog.markTagged(
      'account_switch_finish',
      category: 'account_lifecycle',
      details: <String, Object>{
        'phase': 'finish',
        'reason': reason,
        'logoutIm': logoutIm,
        'purgeOwnerDisk': purgeOwnerDisk,
        'logoutOwner': logoutOwner,
        'durationMs': durationMs,
      },
    );
    if (purgeOwnerDisk) {
      StartupPerfLog.markTagged(
        'conv_owner_purge_finish',
        category: 'account_lifecycle',
        details: <String, Object>{
          'reason': reason,
          'logoutOwner': logoutOwner,
          'durationMs': durationMs,
        },
      );
    }
  }

  static final AccountSessionService instance = AccountSessionService._();

  Future<void>? _clearTask;

  /// Login transitions wait here so an already-running logout cannot overlap
  /// the new account's credential and IM installation.
  Future<void> waitForPendingClear() async {
    final running = _clearTask;
    if (running != null) {
      await running;
    }
  }

  Future<void> clearForLogout({
    String reason = 'logout',
    bool logoutIm = true,
    // Keep owner-scoped disk data across ordinary logout so the next login
    // can hydrate conversations, contacts and other cached state immediately.
    // Destructive flows (for example account cancellation) must opt in with
    // `purgeOwnerDisk: true` explicitly.
    bool purgeOwnerDisk = false,
    SessionIdentity? expectedIdentity,
  }) {
    final running = _clearTask;
    if (running != null) {
      _sessionLog(
        'SESSION_LOG clearForLogout reuse '
        'reason=$reason logoutIm=$logoutIm purgeOwnerDisk=$purgeOwnerDisk',
      );
      return running;
    }

    _sessionLog(
      'SESSION_LOG clearForLogout schedule '
      'reason=$reason logoutIm=$logoutIm purgeOwnerDisk=$purgeOwnerDisk',
    );

    // F 块（v15/v16）：账户切换/登出事件的可观测性打点。
    // 区分：
    //   - reason == 'account_switch' → 用户主动换号（高频路径）
    //   - reason == 'logout' → 主动登出
    //   - reason == 'session_expired' / 'kicked_offline' → 被踢
    StartupPerfLog.markTagged(
      'account_switch',
      category: 'account_lifecycle',
      details: <String, Object>{
        'phase': 'schedule',
        'reason': reason,
        'logoutIm': logoutIm,
        'purgeOwnerDisk': purgeOwnerDisk,
      },
    );

    return _startClearTask(
      () => _clear(
        reason: reason,
        logoutIm: logoutIm,
        purgeOwnerDisk: purgeOwnerDisk,
        expectedIdentity: expectedIdentity,
      ),
    );
  }

  Future<void> _startClearTask(Future<void> Function() action) {
    final running = _clearTask;
    if (running != null) {
      return running;
    }
    late final Future<void> trackedTask;
    trackedTask = action().whenComplete(() {
      if (identical(_clearTask, trackedTask)) {
        _clearTask = null;
      }
    });
    _clearTask = trackedTask;
    return trackedTask;
  }

  @visibleForTesting
  Future<void> runClearTaskForTest(Future<void> Function() action) =>
      _startClearTask(action);

  /// F 块（P2 F2）：账户切换开始时间戳，用于最终埋点 [account_switch_finish] 计算
  /// 总耗时。
  DateTime? _clearStartedAt;

  Future<void> _clear({
    required String reason,
    required bool logoutIm,
    required bool purgeOwnerDisk,
    SessionIdentity? expectedIdentity,
  }) async {
    if (expectedIdentity != null &&
        !SessionIdentityService.instance.isCurrent(expectedIdentity)) {
      return;
    }
    _clearStartedAt = DateTime.now();
    final token = ApiClient.instance.token;
    final clearGeneration =
        SessionIdentityService.instance.invalidate(reason: reason);
    ApiClient.instance.setLogoutInProgress(true);
    AgentIdentityService.instance.clearSession();
    SangongMyConfigService.instance.clearSession();
    SangongGameHttp.clearTenant();
    ConversationHistorySyncCoordinator.instance.invalidate();
    HomeBootstrap.instance.reset();
    // The new SessionManager is the owner of the active IM lifecycle. Keep
    // this cleanup at the account boundary so old and new login paths cannot
    // leave two independent session states alive during a switch.
    // This service already invalidates SessionIdentityService above so that it
    // can retain the clear generation while purging owner-scoped data. Do not
    // invalidate it a second time from SessionManager.
    await _safe(
      () => SessionManager.instance.signOut(
        invalidateIdentity: false,
        reason: reason,
      ),
    );
    ConversationUnreadClearService.clearSession();
    ConversationNotifySyncService.instance.clearSession();
    GroupConversationUnreadHelper.clearSession();
    OutgoingMessageSendQueue.instance.clearSession();
    WalletCardDispatchService.instance.clearSession();
    LocalMessageOverlayStore.instance.invalidateScope();
    bool isCurrentClear() =>
        SessionIdentityService.instance.isGenerationCurrent(clearGeneration);
    final tokenValid = ApiClient.isValidJwt(token);
    // IM logout / clearToken 前固定 owner：注销清盘 + push 本地按号隔离共用。
    final logoutOwner =
        await SessionIdentityService.instance.resolveCurrentOwnerUserId();
    if (!isCurrentClear()) {
      _sessionLog(
        'SESSION_LOG clear abort stale generation reason=$reason '
        'generation=$clearGeneration',
      );
      return;
    }
    final ownerForPurge = purgeOwnerDisk ? logoutOwner : '';
    if (purgeOwnerDisk && logoutOwner.isNotEmpty) {
      await _safe(
        () => ConversationReadOutboxStore.instance.clearOwner(logoutOwner),
      );
      await _safe(
        () => ReadReceiptOutboxStore.instance.clearOwner(logoutOwner),
      );
    }
    PushRegistrationService.instance.rememberLogoutOwner(logoutOwner);
    _sessionLog(
      'SESSION_LOG clear begin '
      'reason=$reason logoutIm=$logoutIm purgeOwnerDisk=$purgeOwnerDisk '
      'logoutOwner=$logoutOwner tokenValid=$tokenValid '
      'hasToken=${token != null && token.trim().isNotEmpty}',
    );
    ApiClient.instance.setLogoutInProgress(true);
    try {
      AuthSessionService.instance.resetAuthFlow();
      // SessionManager is the only IM lifecycle owner. AuthBootstrapService
      // only clears compatibility flags so it cannot race a second SDK
      // logout/unInit during account switching.
      AuthBootstrapService.instance
          .resetCompatibilityStateForAccountBoundary(reason: reason);
      PlatformOfficialAccountService.resetSessionState();

      // 11.3：先 DELETE /me/push-token，再退出 IM，最后停前台服务。
      await _safe(ConversationSyncService.instance.detachRealtimeListeners);
      await _safe(
        PushRegistrationService.instance.deletePushTokenBeforeImLogout,
      );
      if (purgeOwnerDisk) {
        if (ownerForPurge.isEmpty) {
          _sessionLog(
            'SESSION_LOG purgeOwnerDisk skipped: empty owner '
            'reason=$reason',
          );
        } else {
          await _safe(
            () => LocalAccountDataPurge.instance.purgeOwnerDisk(ownerForPurge),
          );
          // F5（v15/v16 P3）：清盘后立刻拍 owner disk 状态快照，给「登出后
          // 立即冷启动」提供审计点；若任一会话行残留则触发
          // `owner_disk_state_residual_rows` 红线埋点。
          await _safe(
            () => OwnerDiskStateSnapshot.snapshotNow(
              phase: 'after_purge',
              hintOwner: ownerForPurge,
            ),
          );
        }
      }

      if (!isCurrentClear()) {
        _sessionLog('SESSION_LOG clear abort before IM logout reason=$reason');
        return;
      }

      if (logoutIm) {
        await _safe(() async {
          await CallLifecycleService.instance.teardown().timeout(
                const Duration(seconds: 6),
              );
        });
      }

      await _safe(
        PushRegistrationService.instance.stopForegroundServiceOnLogout,
      );

      if (!isCurrentClear()) {
        _sessionLog(
          'SESSION_LOG clear abort before credential delete reason=$reason',
        );
        return;
      }

      await _safe(
        () => ListenerStore.beforeLogout().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        ),
      );

      if (!isCurrentClear()) {
        return;
      }
      var tokenCleared = false;
      await _safe(() async {
        tokenCleared = await ApiClient.instance.clearTokenIfCurrent(token);
      });
      if (!isCurrentClear()) {
        return;
      }
      if (tokenCleared) {
        if (logoutOwner.isNotEmpty) {
          await _safe(
            () => ImSessionCache.instance.clearForUser(logoutOwner),
          );
        } else {
          await _safe(ImSessionCache.instance.clear);
        }
      }
      if (!isCurrentClear()) {
        return;
      }
      await _safe(() => BiometricPayService.instance.disableAndClear());
      await _safe(_clearLegacyLoginPrefs);
      await _safe(LocalSystemNotificationService.instance.cancelAll);

      try {
        await FriendSyncService.instance.clearSession(
          ownerUserId: logoutOwner,
        );
      } catch (_) {}
      try {
        await ContactsProtocolSyncService.instance.clearSession(
          ownerUserId: logoutOwner,
        );
      } catch (_) {}
      try {
        await GroupMembershipSyncService.instance.clearSession();
      } catch (_) {}
      try {
        GroupNoticeBootstrap.stopFallbackPolling();
      } catch (_) {}
      try {
        await GroupNoticeIncrementalSyncService.instance.clearSession();
      } catch (_) {}
      try {
        await GroupMemberIncrementalSyncService.instance.clearSession();
      } catch (_) {}
      try {
        GroupJoinApplicationService.instance.clearSession();
      } catch (_) {}
      try {
        GroupSystemNoticeService.instance.clearSession();
      } catch (_) {}
      try {
        GroupNoticeUnreadService.instance.clearSession();
      } catch (_) {}
      try {
        GroupNoticeEntrySettingsService.instance.clearSession();
      } catch (_) {}
      try {
        await ConversationSyncService.instance.clearSession(
          ownerUserId: logoutOwner,
        );
      } catch (_) {}
      try {
        DesktopLoginSessionService.instance.clear();
      } catch (_) {}
      try {
        StarredFriendProvider.shared.clear();
      } catch (_) {}
      try {
        await ArchivedConversationSyncService.instance.clearSession();
      } catch (_) {}
      try {
        await ConversationFolderSyncService.instance.clearSession();
      } catch (_) {}
      try {
        await ConversationPinSyncService.instance.clearSession();
      } catch (_) {}
      try {
        PresenceProvider.clearActiveSessionState();
      } catch (_) {}
      try {
        UserStickerProvider.shared.clear();
      } catch (_) {}
      try {
        ChatBackgroundService.instance.clearSessionState();
      } catch (_) {}
      try {
        PrivilegedGameUserService.instance.clearSession();
      } catch (_) {}
      try {
        SangongMyConfigService.instance.clearSession();
      } catch (_) {}
      try {
        SangongGameHttp.clearTenant();
      } catch (_) {}
      try {
        AgentIdentityService.instance.clearSession();
      } catch (_) {}

      try {
        DisplayNameStore.instance.clear(notify: false);
        GroupMemberStore.instance.clear(notify: false);
        ConversationPreviewTextCache.instance.clear();
        LoginUserInfo.clearAllSessions();
      } catch (_) {}

      try {
        C2cFriendMessageGuard.clearSession();
      } catch (_) {}
      try {
        ChatHistoryPeekBootstrap.clearSession();
      } catch (_) {}
      try {
        MomentsSettingsService.instance.clearMemoryCache();
      } catch (_) {}

      try {
        serviceLocator<TUISearchViewModel>().clearSession(notify: false);
      } catch (_) {}
      try {
        serviceLocator<TUIConversationViewModel>().clearData();
      } catch (_) {}
      try {
        serviceLocator<TUIFriendShipViewModel>().clearData();
      } catch (_) {}
      try {
        serviceLocator<TUIChatGlobalModel>().clearData();
      } catch (_) {}

      ConversationRefreshBus.instance.requestRefresh(reason: reason);
      // F 块 P2 强化：账户切换结束埋点，包含完整审计字段（doc §9 P2 F2）。
      _recordAccountSwitchFinish(
        reason: reason,
        logoutIm: logoutIm,
        purgeOwnerDisk: purgeOwnerDisk,
        logoutOwner: logoutOwner,
        startedAt: _clearStartedAt,
      );
      _sessionLog('SESSION_LOG clear finish reason=$reason');
    } finally {
      ApiClient.instance.setLogoutInProgress(false);
    }
  }

  Future<void> _clearLegacyLoginPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Const.DEV_LOGIN_USER_ID);
    await prefs.remove(Const.DEV_LOGIN_USER_SIG);
    await prefs.remove(Const.SMS_LOGIN_TOKEN);
    await prefs.remove(Const.SMS_LOGIN_PHONE);
  }

  Future<void> _safe(FutureOr<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (kDebugMode) {
        _sessionLog('AccountSessionService cleanup skipped: $e');
      }
    }
  }
}
