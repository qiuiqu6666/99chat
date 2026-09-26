import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

/// 群系统提示触发 SDK 未读校准；本地隐藏提示不改变云端计数。
class GroupConversationUnreadHelper {
  GroupConversationUnreadHelper._();

  static const int _effectLedgerCap = 512;
  static final LinkedHashSet<String> _absorbedEffectIds =
      LinkedHashSet<String>();
  static final Set<String> _absorbingEffectIds = <String>{};

  /// Silent-tip delivery may race an SDK count callback. Reconcile with the
  /// provider; subtracting locally would disagree with other logged-in devices.
  static Future<void> absorbOneUnreadBump(
    String conversationID, {
    String? effectId,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    final rawEffect = effectId?.trim() ?? '';
    final effectKey = rawEffect.isEmpty ? '' : '$id|$rawEffect';
    if (effectKey.isNotEmpty &&
        (_absorbedEffectIds.contains(effectKey) ||
            !_absorbingEffectIds.add(effectKey))) {
      return;
    }
    try {
      ConversationUnreadAggregate.instance.scheduleRefresh(
        reason: 'absorb_tip_unread',
      );
      if (effectKey.isNotEmpty) {
        _absorbedEffectIds.add(effectKey);
        while (_absorbedEffectIds.length > _effectLedgerCap) {
          _absorbedEffectIds.remove(_absorbedEffectIds.first);
        }
      }
    } catch (e) {
      debugPrint('absorb group tip unread bump failed: $e');
    } finally {
      if (effectKey.isNotEmpty) {
        _absorbingEffectIds.remove(effectKey);
      }
    }
  }

  static void clearSession() {
    _absorbedEffectIds.clear();
    _absorbingEffectIds.clear();
  }

  static Future<void> clearConversationUnread(
    String conversationID, {
    V2TimConversation? conversation,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    final canonicalId = id.startsWith('group_') ? id : 'group_$id';
    final snapshot = conversation ??
        ConversationUnreadAggregate.instance.sdkSnapshotFor(canonicalId);
    if (snapshot == null) return;
    try {
      await ConversationUnreadClearService.clearLocalForOpen(
          conversation: snapshot);
      await ConversationUnreadClearService.scheduleSdkUnreadClean(
        conversationID: canonicalId,
        trigger: SdkUnreadCleanTrigger.open,
        hadUnread: true,
      );
    } catch (e) {
      debugPrint('clear group conversation unread failed: $e');
    }
  }

  /// 系统群提示可能晚于首屏到达，延迟校准 SDK 未读。
  static void scheduleClearAfterGroupCreate(
    String conversationID, {
    V2TimConversation? conversation,
    String? effectId,
  }) {
    scheduleAbsorbOnce(conversationID, effectId: effectId);
  }

  /// 本人操作的群系统提示（邀请/踢人等）到达后，延迟校准。
  static void scheduleClearForSelfOperatedGroupTips(
    String conversationID, {
    V2TimConversation? conversation,
    String? effectId,
  }) {
    scheduleAbsorbOnce(conversationID, effectId: effectId);
  }

  /// Wait once for the SDK unread snapshot and deduplicate the refresh effect.
  static void scheduleAbsorbOnce(
    String conversationID, {
    String? effectId,
    Duration delay = const Duration(milliseconds: 600),
  }) {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    Future<void>.delayed(delay, () {
      unawaited(absorbOneUnreadBump(id, effectId: effectId));
    });
  }
}
