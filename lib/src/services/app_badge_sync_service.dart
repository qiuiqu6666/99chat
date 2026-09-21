import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_entry_settings_service.dart';
import "package:tencent_cloud_chat_demo/src/services/group_notice_unread_service.dart";
import "package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart";
import "package:tencent_cloud_chat_demo/src/services/local_system_notification_service.dart";
import 'package:tencent_cloud_chat_demo/src/utils/app_badge_unread_utils.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

/// 将桌面图标角标同步为与 App 内 Tab 角标一致的总未读数。
class AppBadgeSyncService {
  AppBadgeSyncService._();

  static final AppBadgeSyncService instance = AppBadgeSyncService._();

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _listenersAttached = false;
  int? _lastSyncedCount;
  Future<void>? _foregroundInFlight;
  int? _foregroundInFlightGeneration;
  DateTime? _lastForegroundAt;

  void setLifecycle(AppLifecycleState state) {
    _lifecycle = state;
  }

  bool get _isBackground =>
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.hidden ||
      _lifecycle == AppLifecycleState.detached;

  void ensureListenersAttached() {
    if (_listenersAttached) {
      return;
    }
    _listenersAttached = true;
    void onUnreadSourcesChanged() {
      unawaited(syncBadgeIfNeeded(reason: "unread_source_changed"));
    }

    ConversationUnreadAggregate.instance.addListener(onUnreadSourcesChanged);
    ChatSessionController.instance.addListener(onUnreadSourcesChanged);
    archivedConversationC2cIDsNotifier.addListener(onUnreadSourcesChanged);
    archivedConversationGroupIDsNotifier.addListener(onUnreadSourcesChanged);
    GroupNoticeUnreadService.instance.addListener(onUnreadSourcesChanged);
    GroupNoticeEntrySettingsService.instance
        .addListener(onUnreadSourcesChanged);
    FriendRequestNoticeService.instance.pendingApplicationCount
        .addListener(onUnreadSourcesChanged);
  }

  Future<void> syncForForeground({String reason = 'foreground'}) {
    final generation = SessionIdentityService.instance.generation;
    final existing = _foregroundInFlight;
    if (existing != null && _foregroundInFlightGeneration == generation) {
      return existing;
    }
    final now = DateTime.now();
    final last = _lastForegroundAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return Future<void>.value();
    }
    _lastForegroundAt = now;
    late final Future<void> task;
    task = _syncForForeground(reason: reason).whenComplete(() {
      if (identical(_foregroundInFlight, task)) {
        _foregroundInFlight = null;
        _foregroundInFlightGeneration = null;
      }
    });
    _foregroundInFlight = task;
    _foregroundInFlightGeneration = generation;
    return task;
  }

  Future<void> _syncForForeground({required String reason}) async {
    if (kIsWeb || !PlatformUtils().isMobile) {
      return;
    }
    final count = AppBadgeUnreadUtils.totalAppBadgeUnreadCount();
    _lastSyncedCount = count;
    try {
      await TIMUIKitCore.getInstance().setOfflinePushStatus(
        status: AppStatus.foreground,
      );
      await LocalSystemNotificationService.instance.setAppBadge(count);
      if (kDebugMode) {
        debugPrint('AppBadgeSync: foreground reason=$reason');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppBadgeSync: foreground failed reason=$reason error=$e');
      }
    }
  }

  Future<void> syncForBackground({String reason = 'background'}) async {
    if (kIsWeb || !PlatformUtils().isMobile) {
      return;
    }
    await syncBadgeIfNeeded(reason: reason, force: true);
  }

  Future<void> syncBadgeIfNeeded({
    required String reason,
    bool force = false,
  }) async {
    if (kIsWeb || !PlatformUtils().isMobile) {
      return;
    }
    final count = AppBadgeUnreadUtils.totalAppBadgeUnreadCount();
    if (!force && count == _lastSyncedCount) {
      return;
    }
    _lastSyncedCount = count;
    await LocalSystemNotificationService.instance.setAppBadge(count);
    if (!_isBackground) {
      return;
    }
    try {
      await TIMUIKitCore.getInstance().setOfflinePushStatus(
        status: AppStatus.background,
        totalCount: count,
      );
      if (kDebugMode) {
        debugPrint('AppBadgeSync: background reason=$reason count=$count');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppBadgeSync: background failed reason=$reason error=$e');
      }
    }
  }
}
