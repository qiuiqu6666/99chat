import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/presence_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/app_badge_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_chat_notification_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/ios_apns_push_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_system_notification_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/push_msgkey_dedup.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

/// P0：清除聊天离线 Push 残留（仅 `type=im_chat`，不误删其他通知）。
class ImChatNotificationClearService {
  ImChatNotificationClearService._();

  static final ImChatNotificationClearService instance =
      ImChatNotificationClearService._();

  Future<void>? _clearAllInFlight;
  int? _clearAllInFlightGeneration;
  Future<void>? _foregroundInFlight;
  int? _foregroundInFlightGeneration;

  Future<void> clearAllImChatNotifications({String reason = 'manual'}) {
    final generation = SessionIdentityService.instance.generation;
    final existing = _clearAllInFlight;
    if (existing != null && _clearAllInFlightGeneration == generation) {
      return existing;
    }
    late final Future<void> task;
    task = _clearAllImChatNotifications(reason: reason).whenComplete(() {
      if (identical(_clearAllInFlight, task)) {
        _clearAllInFlight = null;
        _clearAllInFlightGeneration = null;
      }
    });
    _clearAllInFlight = task;
    _clearAllInFlightGeneration = generation;
    return task;
  }

  Future<void> _clearAllImChatNotifications({required String reason}) async {
    if (kIsWeb) {
      return;
    }

    final generation = SessionIdentityService.instance.generation;
    bool isCurrent() =>
        SessionIdentityService.instance.isGenerationCurrent(generation);

    final registry = ImChatNotificationRegistry.instance;
    final localIds = registry.allImChatIds().toList();
    for (final id in localIds) {
      await LocalSystemNotificationService.instance.cancelNotification(id);
      if (!isCurrent()) return;
    }

    await LocalSystemNotificationService.instance
        .clearDeliveredImChatNotifications();
    await IosApnsPushService.instance.clearAllImChatNotifications();
    if (!isCurrent()) return;

    registry.clearAll();

    if (kDebugMode) {
      debugPrint(
        'ImChatNotificationClear: clearAll reason=$reason localIds=${localIds.length}',
      );
    }
  }

  Future<void> clearChatNotificationsForConversation(
    String conversationID, {
    String reason = 'conversation',
  }) async {
    if (kIsWeb) {
      return;
    }
    final threadId =
        ImChatNotificationRegistry.threadIdFromConversationId(conversationID);
    if (threadId == null || threadId.isEmpty) {
      return;
    }
    await clearChatNotificationsForThread(threadId, reason: reason);
  }

  Future<void> clearChatNotificationsForThread(
    String threadId, {
    String reason = 'thread',
  }) async {
    if (kIsWeb) {
      return;
    }
    final registry = ImChatNotificationRegistry.instance;
    final ids = registry.idsForThread(threadId).toList();
    for (final id in ids) {
      await LocalSystemNotificationService.instance.cancelNotification(id);
    }
    await LocalSystemNotificationService.instance
        .clearDeliveredImChatNotifications(threadId: threadId);
    await IosApnsPushService.instance
        .clearDeliveredImChatNotifications(threadId: threadId);
    registry.clearThread(threadId);

    if (kDebugMode) {
      debugPrint(
        'ImChatNotificationClear: clearThread reason=$reason '
        'threadId=$threadId ids=${ids.length}',
      );
    }
  }

  Future<void> cancelByMsgKey(String? msgKey) async {
    final key = PushMsgKeyDedup.instance.normalizeKey(msgKey);
    if (kIsWeb || key == null) {
      return;
    }
    final id = ImChatNotificationRegistry.notificationIdFor(key);
    await LocalSystemNotificationService.instance.cancelNotification(id);
    await IosApnsPushService.instance.cancelNotificationForMsgKey(key);
    ImChatNotificationRegistry.instance.remove(id);
  }

  /// App 进入前台：清全部 im_chat + 心跳 + 清零桌面角标。
  Future<void> onAppEnteredForeground({String reason = 'resumed'}) {
    final generation = SessionIdentityService.instance.generation;
    final existing = _foregroundInFlight;
    if (existing != null && _foregroundInFlightGeneration == generation) {
      return existing;
    }
    late final Future<void> task;
    task = _onAppEnteredForeground(reason: reason).whenComplete(() {
      if (identical(_foregroundInFlight, task)) {
        _foregroundInFlight = null;
        _foregroundInFlightGeneration = null;
      }
    });
    _foregroundInFlight = task;
    _foregroundInFlightGeneration = generation;
    return task;
  }

  Future<void> _onAppEnteredForeground({required String reason}) async {
    final generation = SessionIdentityService.instance.generation;
    await clearAllImChatNotifications(reason: reason);
    if (!SessionIdentityService.instance.isGenerationCurrent(generation)) {
      return;
    }
    unawaited(PresenceApi.instance.heartbeat().catchError((_) {}));
    unawaited(AppBadgeSyncService.instance.syncForForeground(reason: reason));
  }
}
