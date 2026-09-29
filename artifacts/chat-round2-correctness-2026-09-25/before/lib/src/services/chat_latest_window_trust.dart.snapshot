import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_sync_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

/// Result of comparing a raw SDK latest window against the conversation
/// preview. `previewUnverifiable` means the preview itself cannot serve as a
/// cloud target (synthetic/local-only or an unconfirmed self send); the window
/// is accepted for display but freshness must be proven separately.
@immutable
class LatestEdgeMatch {
  const LatestEdgeMatch({
    required this.matched,
    this.previewUnverifiable = false,
  });

  final bool matched;
  final bool previewUnverifiable;

  static const LatestEdgeMatch mismatch = LatestEdgeMatch(matched: false);
}

/// Newest message in [newestFirst] that the server can be expected to have
/// returned: a real msgID, not a synthetic local row, not a local group tip,
/// and either inbound or a confirmed self send.
V2TimMessage? rawConfirmedLatest(List<V2TimMessage> newestFirst) {
  for (final message in newestFirst) {
    if (isConfirmedServerRow(message)) return message;
  }
  return null;
}

/// A row the server can be expected to have returned: real msgID, not a
/// synthetic local row or local group tip, and not an unconfirmed self send.
bool isConfirmedServerRow(V2TimMessage message) {
  if ((message.msgID?.trim() ?? '').isEmpty) return false;
  if (ConversationPreviewHistorySync.isSyntheticLocalMessage(message)) {
    return false;
  }
  if ((message.localCustomData ?? '').contains('"localGroupTips"')) return false;
  if (message.isSelf == true &&
      message.status != MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
    return false;
  }
  return true;
}

bool _isUnconfirmedSelfPreview(V2TimMessage preview) {
  if (preview.isSelf != true) return false;
  final msgID = preview.msgID?.trim() ?? '';
  return msgID.isEmpty ||
      preview.status != MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
}

/// Validates the **raw** SDK window (before any splice) against the preview.
/// The preview is the validation target and must never be part of the data
/// being validated.
LatestEdgeMatch latestEdgeMatchesPreview({
  required V2TimMessage? preview,
  required List<V2TimMessage> rawWindow,
}) {
  final confirmed = rawConfirmedLatest(rawWindow);
  if (confirmed == null) return LatestEdgeMatch.mismatch;
  if (preview == null) return LatestEdgeMatch.mismatch;
  if (ConversationPreviewHistorySync.isSyntheticLocalMessage(preview) ||
      _isUnconfirmedSelfPreview(preview)) {
    return const LatestEdgeMatch(matched: true, previewUnverifiable: true);
  }
  // Only confirmed rows may satisfy the preview; a SENDING / synthetic row
  // that happens to share the preview's msgID is not server proof.
  final previewId = preview.msgID?.trim() ?? '';
  if (previewId.isNotEmpty) {
    for (final message in rawWindow) {
      if ((message.msgID?.trim() ?? '') == previewId &&
          isConfirmedServerRow(message)) {
        return const LatestEdgeMatch(matched: true);
      }
    }
  }
  if (TUIChatGlobalModel.compareMessagesChronological(confirmed, preview) > 0) {
    return const LatestEdgeMatch(matched: true);
  }
  return LatestEdgeMatch.mismatch;
}

/// Whether one raw SDK page can stand alone as a continuous visible window.
/// Groups use seq contiguity; a single C2C page is continuous by construction.
bool windowIsSelfContiguous({
  required List<V2TimMessage> rawWindow,
  required bool isGroup,
}) {
  if (rawWindow.isEmpty) return false;
  if (!isGroup) return true;
  final sorted = TUIChatGlobalModel.sortMessagesNewestFirst(
    List<V2TimMessage>.from(rawWindow),
  );
  final spine = ChatViewportReadiness.takeNewestContiguous(
    newestFirst: sorted,
    useSeqContiguity: true,
  );
  return spine.length == sorted.length;
}

/// Whether this specific request can prove the server's latest state.
bool freshnessProven({
  required bool cloudTransportConfirmed,
  required bool networkOnline,
  required bool transportReady,
  required bool serverSyncPendingBefore,
  required bool serverSyncPendingAfter,
}) {
  return cloudTransportConfirmed &&
      networkOnline &&
      transportReady &&
      !serverSyncPendingBefore &&
      !serverSyncPendingAfter;
}

/// Per-conversation record of the recovery epoch in which a continuous latest
/// window was installed and proven fresh.
class ChatLatestWindowTrust {
  ChatLatestWindowTrust._();

  static final ChatLatestWindowTrust instance = ChatLatestWindowTrust._();

  final Map<String, int> _trustedEpochByKey = <String, int>{};

  void markTrusted(String conversationKey, int epoch) {
    final key = conversationKey.trim();
    if (key.isEmpty) return;
    _trustedEpochByKey[key] = epoch;
  }

  int? trustedEpochFor(String conversationKey) =>
      _trustedEpochByKey[conversationKey.trim()];

  void clear() => _trustedEpochByKey.clear();

  void onRecoveryEpochChanged(int epoch) {
    if (kDebugMode) {
      debugPrint(
        'ChatLatestWindowTrust recovery epoch changed epoch=$epoch '
        'trusted=${_trustedEpochByKey.length}',
      );
    }
  }

  /// Trust is epoch-bound: a real reconnect invalidates every earlier proof.
  bool needsLatestWindowReset({
    required String conversationKey,
    required int currentEpoch,
    bool provisionalRegistered = false,
  }) {
    if (provisionalRegistered) return true;
    if (currentEpoch <= 0) return false;
    return trustedEpochFor(conversationKey) != currentEpoch;
  }
}

/// Gate for writing the chat page's 20s cloud-verify TTL. Only answers "is the
/// environment able to certify a cloud result right now"; the request's own
/// provenance must be checked by the caller.
class ChatHistoryVerificationGate {
  const ChatHistoryVerificationGate._();

  static bool canMarkCloudVerifiedNow() {
    return NetworkStatusService.instance.status.value ==
            NetworkReachability.online &&
        ImConnectStatusService.isTransportReady &&
        !ImSdkRelationshipSyncAnchor.serverSyncPending;
  }
}
