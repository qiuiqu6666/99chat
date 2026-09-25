import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';
// ignore_for_file: avoid_print, unnecessary_getters_setters, unused_element
import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/history_search_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_conversation_read_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/c2c_peer_rejected_tip_message.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/gap_detector.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/inbound_reorder_buffer.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_application.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_application.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_download_progress.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_download_progress.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_class.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_model_tools.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/indexed_message_windows.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_commit_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_cloud_catch_up.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_writer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/open_hydrate_result.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_batch.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/conversation_peer_read_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/data_services/profile/user_profile_local_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/error_message_converter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_send_status.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_visible_probe.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_jitter_diag.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/regexp_probe.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_expand.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_height_cache.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_inbound_batch_coalescer.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_inbound_chunk_reveal.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_send_fly_overlay.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/logger.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_window_trim_transaction.dart';

part 'tui_chat_bounded_history.dart';

enum ConvType { none, c2c, group }

enum HistoryMessagePosition {
  bottom,
  inTwoScreen,
  awayTwoScreen,
  notShowLatest,
}

/// 搜索跳转进会话时的加载/定位状态（供消息列表 UI 与 _loadData 共用）。
enum SearchJumpStatus { idle, loading, positioning, success, failed }

enum GroupSystemNoticeType {
  grantAdministrator,
  revokeAdministrator,
  transferOwner,
  memberAdded,
  memberRemoved,
  memberLeft,
}

class GroupSystemNoticeItem {
  final String id;
  final String groupID;
  final String groupName;
  final String groupFaceUrl;
  final GroupSystemNoticeType type;
  final String operatorUserID;
  final String operatorName;
  final String targetUserID;
  final String targetName;
  final int timestamp;

  GroupSystemNoticeItem({
    required this.id,
    required this.groupID,
    required this.groupName,
    required this.groupFaceUrl,
    required this.type,
    required this.operatorUserID,
    required this.operatorName,
    required this.targetUserID,
    required this.targetName,
    required this.timestamp,
  });
}

class CurrentConversation {
  final String conversationID;
  final ConvType conversationType;

  CurrentConversation(this.conversationID, this.conversationType);
}

class AppContactPresenceBridge {
  final Listenable? presenceListenable;
  final MemberPresenceLabelBuilder? presenceLabelBuilder;
  final MemberPresenceLoadingChecker? presenceLoadingChecker;
  final MemberPresenceOnlineResolver? presenceOnlineResolver;
  final void Function(List<String> userIds)? onContactListLoaded;

  const AppContactPresenceBridge({
    this.presenceListenable,
    this.presenceLabelBuilder,
    this.presenceLoadingChecker,
    this.presenceOnlineResolver,
    this.onContactListLoaded,
  });
}

class _InboundUnreadState {
  int unreadCount = 0;
  int receivedCount = 0;
  int lockedEntryUnreadCount = 0;
  int entryReminderVersion = 0;

  // Exact durable counters outlive the four-session cache and its 120 hot rows.
  bool durableDeferred = false;
  int durableUnreadCount = 0;
  int unreadVisitGeneration = 0;
  bool unreadVisitBaselinePending = false;
  int unreadVisitBaselineReceived = 0;
  int unreadVisitBaselineUnread = 0;
  int unreadVisitBaselineSequence = -1;
  final Set<String> unreadVisitLegacyKeys = {};
  int durableOperationCount = 0;
  int pendingDurableAdmissions = 0;
  int? returnDeferredWatermark;
  String? returnDeferredMessageKey;
  int returnDeferredSeq = 0;
  int returnDeferredTimestamp = 0;
  Future<void> deferredOperationTail = Future<void>.value();

  /// Frozen at open: first unread group seq for tip jump (survives mark-read).
  int lockedFirstUnreadSeq = 0;
  // A coalesced batch may become deferred after its original bottom admission.
  // Keep it distinct until it joins the durable bucket, so SQL counts cannot
  // overwrite these not-yet-persisted rows.
  final Map<String, V2TimMessage> pendingLegacyMessages = {};
  final List<V2TimMessage> bufferedMessages = <V2TimMessage>[];
  final Set<String> bufferedMessageKeys = <String>{};
  // Local-buffer identities survive attachment until the reading edge crosses
  // them. SQL-backed deliveries have their own exact identity ledger.
  final Set<String> revealedUnreadMessageIDs = {};
  // True latest end has been observed; later SQL publishes must not revive N.
  bool trueLatestEndAbsorbed = false;
  /// 进会话后离底期间的 live 新消息，尚未被认定看见。不等于未接入。
  final LinkedHashSet<String> remainingLiveIncomingIds = LinkedHashSet<String>();
  /// 本次 visit 内已认定看见或整体 COMMIT 清账的 id。日常回底不清。
  final Set<String> seenLiveIncomingIds = <String>{};
  /// live 进入 buffer 即递增，供整体确认快照失效。
  int liveReceiveGeneration = 0;
  int restoreOpId = 0;

  int get visibleLegacyCount => revealedUnreadMessageIDs.length +
      (unreadVisitBaselinePending
          ? pendingLegacyMessages.keys
              .where((key) => !unreadVisitLegacyKeys.contains(key))
              .length
          : pendingLegacyMessages.length);

  bool get isEmpty =>
      !durableDeferred &&
      !unreadVisitBaselinePending &&
      durableOperationCount == 0 &&
      unreadCount == 0 &&
      receivedCount == 0 &&
      lockedEntryUnreadCount == 0 &&
      lockedFirstUnreadSeq == 0 &&
      bufferedMessages.isEmpty &&
      bufferedMessageKeys.isEmpty &&
      revealedUnreadMessageIDs.isEmpty;

  void clear() {
    unreadCount = 0;
    receivedCount = 0;
    lockedEntryUnreadCount = 0;
    entryReminderVersion++;
    durableDeferred = false;
    durableUnreadCount = 0;
    unreadVisitGeneration++;
    unreadVisitBaselinePending = false;
    unreadVisitBaselineReceived = 0;
    unreadVisitBaselineUnread = 0;
    unreadVisitBaselineSequence = -1;
    unreadVisitLegacyKeys.clear();
    returnDeferredWatermark = null;
    returnDeferredMessageKey = null;
    returnDeferredSeq = 0;
    returnDeferredTimestamp = 0;
    pendingLegacyMessages.clear();
    lockedFirstUnreadSeq = 0;
    bufferedMessages.clear();
    bufferedMessageKeys.clear();
    revealedUnreadMessageIDs.clear();
    trueLatestEndAbsorbed = false;
    remainingLiveIncomingIds.clear();
    seenLiveIncomingIds.clear();
    liveReceiveGeneration = 0;
    restoreOpId = 0;
  }
}

enum _HistoryConversationKind { c2c, group }

/// Viewport coordinates captured when a message context menu opens.
///
/// The scroll extent is not a sufficient anchor for a reverse chat list: the
/// unread center, time dividers, spacers, or a later row measurement can all
/// change the extent without preserving the selected row's screen position.
class MessageContextMenuViewportAnchor {
  const MessageContextMenuViewportAnchor({
    required this.identity,
    required this.seq,
    required this.viewportTop,
  });

  /// Message `msgID`, or the local id while an optimistic row has no server id.
  final String? identity;

  /// Sequence is a fallback for SDK rows whose identity changes during sync.
  final String? seq;

  /// Top edge of the selected row relative to the chat scroll viewport.
  final double viewportTop;
}

enum RowLocalMessageReplacementResult {
  replaced,
  stale,
  notFound,
  ambiguous,
  reordered,
  semanticChange,
}

/// Immutable synchronous snapshot produced by [TUIChatGlobalModel.setMessageList].
///
/// Callers that need post-commit state must consume this value instead of
/// sampling the mutable global maps again.
class MessageCommitResult {
  const MessageCommitResult({
    required this.conversationID,
    required this.token,
    required this.generation,
    required this.listRevision,
    required this.projectionRevision,
    required this.rawCount,
    required this.firstIdentity,
    required this.lastIdentity,
    required this.memoryWindowMissingNewer,
    required this.memoryWindowMissingOlder,
    required this.memoryWindowSuppressed,
    required this.unreadBufferedCount,
    required this.unreadProjectionHeld,
    required this.structureChanged,
    required this.contentChanged,
    this.writerRevision,
    this.writerGeneration,
    this.writerClearEpoch,
    this.writerOwnerUserID,
    this.writerAccountGeneration,
    this.writerDomainGeneration,
  });

  final String conversationID;
  final int token;
  final int generation;
  final int listRevision;
  final int projectionRevision;
  final int rawCount;
  final String? firstIdentity;
  final String? lastIdentity;
  final bool memoryWindowMissingNewer;
  final bool memoryWindowMissingOlder;
  final bool memoryWindowSuppressed;
  final int unreadBufferedCount;
  final bool unreadProjectionHeld;
  final bool structureChanged;
  final bool contentChanged;

  /// Revision and scope of the authoritative Message Writer commit that
  /// produced this UI snapshot. Null means this was a legacy direct snapshot.
  final int? writerRevision;
  final int? writerGeneration;
  final int? writerClearEpoch;
  final String? writerOwnerUserID;
  final int? writerAccountGeneration;
  final int? writerDomainGeneration;

  int? get commitRevision => writerRevision;

  /// Unified revision view for Writer-backed and legacy UI commits.
  int get revision => writerRevision ?? listRevision;
}

/// Diagnostic metadata for the last authoritative history commit.
///
/// This deliberately contains no message payload, credentials, or media URL.
class MessageHistoryCommitMetadata {
  const MessageHistoryCommitMetadata({
    required this.conversationKey,
    required this.source,
    required this.batchKind,
    required this.generation,
    required this.revision,
    required this.resultCount,
    required this.proofKind,
    required this.clearEpoch,
  });

  final String conversationKey;
  final MessageReconciliationSource source;
  final MessageHistoryBatchKind batchKind;
  final int generation;
  final int revision;
  final int resultCount;
  final MessageHistoryProofKind proofKind;
  bool get cloudProof => proofKind != MessageHistoryProofKind.none;
  bool get cloudTransportConfirmed => cloudProof;
  bool get serverContinuityProven =>
      proofKind == MessageHistoryProofKind.serverContinuity;
  final int clearEpoch;

  Map<String, Object?> toMetadataJson() => <String, Object?>{
        'conversationKey': conversationKey,
        'source': source.name,
        'batchKind': batchKind.name,
        'generation': generation,
        'revision': revision,
        'resultCount': resultCount,
        'proofKind': proofKind.name,
        'cloudProof': cloudProof,
        'cloudTransportConfirmed': cloudTransportConfirmed,
        'serverContinuityProven': serverContinuityProven,
        'clearEpoch': clearEpoch,
      };
}

class _MessageDedupMeta {
  const _MessageDedupMeta(this.groupId, this.seq);
  final String groupId;
  final int seq;
}

/// Published structure is immutable. The ordinary path reads the Writer's
/// record-backed value view; exceptional compatibility projections freeze once.
class _TrackedMessageList extends ListBase<V2TimMessage> {
  _TrackedMessageList(List<V2TimMessage> values)
      : _values = values is MessageReconciliationValues<V2TimMessage>
            ? values
            : List<V2TimMessage>.unmodifiable(values);
  final List<V2TimMessage> _values;
  @override
  int get length => _values.length;
  @override
  V2TimMessage operator [](int index) => _values[index];
  @override
  set length(int value) => throw UnsupportedError('Use the message Writer');
  @override
  void operator []=(int index, V2TimMessage value) =>
      throw UnsupportedError('Use the message Writer');
}

/// Newest-first display view over the one freshly built chronological layout.
class _ReversedMessageList extends ListBase<V2TimMessage> {
  _ReversedMessageList(this._chronological);
  final List<V2TimMessage> _chronological;
  @override
  int get length => _chronological.length;
  @override
  V2TimMessage operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _chronological[length - index - 1];
  }

  @override
  set length(int value) => throw UnsupportedError('Display is read-only');
  @override
  void operator []=(int index, V2TimMessage value) =>
      throw UnsupportedError('Display is read-only');
}

class _MessageIdentityLookup {
  _MessageIdentityLookup(List<V2TimMessage> list)
      : mutationEpoch = V2TimMessage.identityMutationEpoch {
    for (var index = 0; index < list.length; index++) {
      final row = list[index];
      final msgID = row.msgID;
      final id = row.id;
      final seq = row.seq?.trim();
      if (msgID != null && msgID.isNotEmpty) {
        serverIDs[msgID] ??= index;
        rowKeys[msgID] ??= index;
      }
      if (id != null && id.isNotEmpty) {
        clientIDs[id] ??= index;
        rowKeys[id] ??= index;
      }
      if (seq != null && seq.isNotEmpty) rowKeys['seq_$seq'] ??= index;
      if ((msgID?.trim().isNotEmpty ?? false) ||
          (id?.trim().isNotEmpty ?? false) ||
          (seq?.isNotEmpty ?? false)) {
        rowKeys[ChatUiStateStore.messageKeyOf(row)] ??= index;
      } else {
        anonymousIndices.add(index);
      }
    }
  }
  final int mutationEpoch;
  final Map<String, int> serverIDs = {};
  final Map<String, int> clientIDs = {};
  final Map<String, int> rowKeys = {};
  final List<int> anonymousIndices = [];
}

class TUIChatGlobalModel extends ChangeNotifier implements TIMUIKitClass {
  // A message object is reused across inbound merge, commit, and UI reads.
  // Cache the expensive group-id/sequence normalization on that object so
  // dedupe comparisons do not repeatedly trim, uppercase, parse, and slice.
  static final Expando<_MessageDedupMeta> _dedupMeta =
      Expando<_MessageDedupMeta>();
  static void Function(TUIChatGlobalModel model)? registerAppExtensions;

  static void ensureAppExtensionsRegistered() {
    setupServiceLocator();
    registerAppExtensions?.call(serviceLocator<TUIChatGlobalModel>());
  }

  final MessageService _messageService = serviceLocator<MessageService>();
  final GroupServices _groupServices = serviceLocator<GroupServices>();
  final ChatUiStateStore _chatUiStateStore = serviceLocator<ChatUiStateStore>();
  late final IndexedMessageWindows _messageListMap = IndexedMessageWindows(
    onRetained: (keys) => _messageReadReceiptMap.retain(keys),
    onReleased: (keys) => _messageReadReceiptMap.release(keys),
    onWindowRemoved: (conversation) {
      _messageReadReceiptMap.removeWhere((id, receipt) =>
          !_messageListMap.containsMessage(id) &&
          _isSameConversationID(
              receipt.groupID?.isNotEmpty == true
                  ? receipt.groupID
                  : receipt.userID,
              conversation));
    },
    onWindowChanged: (conversation) {
      _chatUiStateStore.retainMessageRows(conversation,
          _messageListMap.entries
              .where((entry) => _isSameConversationID(entry.key, conversation))
              .expand((entry) => entry.value ?? const <V2TimMessage>[]));
    },
    onCleared: () {
      _messageReadReceiptMap.clear();
      _chatUiStateStore.clearAllStates();
    },
  );
  final Expando<_MessageIdentityLookup> _messageIdentityLookups =
      Expando<_MessageIdentityLookup>();

  _MessageIdentityLookup? _identityLookupFor(List<V2TimMessage> list) {
    if (list is! _TrackedMessageList &&
        list is! MessageReconciliationValues<V2TimMessage>) return null;
    var index = _messageIdentityLookups[list];
    if (index == null ||
        index.mutationEpoch != V2TimMessage.identityMutationEpoch) {
      index = _MessageIdentityLookup(list);
      _messageIdentityLookups[list] = index;
      ChatMainThreadPerf.increment('message_identity_index_built');
    }
    return index;
  }

  final Map<String, MessageHistoryCommitMetadata>
      _lastHistoryCommitMetadataByConv =
      <String, MessageHistoryCommitMetadata>{};
  final MessageCommitCoordinator _messageCommitCoordinator =
      MessageCommitCoordinator();
  late final MessageReconciliationWriter<V2TimMessage>
      _messageReconciliationWriter = MessageReconciliationWriter<V2TimMessage>(
    comparator: (left, right) =>
        compareMessagesChronological(right.value, left.value),
  );
  int _nextRealtimeReconciliationEvent = 0;
  final Map<String, Object> _writerProjectionAuthorities = {};

  /// App-owned connectivity bridge. UIKit does not import the host app's
  /// network services; when no provider is installed, reconciliation stays in
  /// the conservative `unknown` state and never claims cloud completeness.
  MessageReconciliationNetworkState Function()?
      appMessageReconciliationNetworkStateProvider;

  /// Host-app persistence for coverage metadata. UIKit owns the state shape,
  /// while the app owns the SQLite lifecycle and account scoping.
  MessageHistoryCoverageRepository? appMessageHistoryCoverageRepository;
  Im06HistoryCoverageStore? appIm06HistoryCoverageStore;
  Im06HistorySearchCoordinator? _im06HistorySearchCoordinator;
  int _im06HistoryRequestSequence = 0;
  final Map<String, Map<String, Object?>> _lastHistoryErrorByConversation =
      <String, Map<String, Object?>>{};

  Map<String, Object?>? lastHistoryErrorMetadata(String conversationID) {
    final key = conversationID.trim();
    final metadata = _lastHistoryErrorByConversation[key];
    return metadata == null
        ? null
        : Map<String, Object?>.unmodifiable(metadata);
  }

  /// Last IM06 history failure type for [conversationID], e.g.
  /// `scope_not_configured`, `scope_changed`, or a coordinator error name.
  String? lastHistoryErrorType(String conversationID) {
    final type = lastHistoryErrorMetadata(conversationID)?['errorType'];
    return type is String && type.isNotEmpty ? type : null;
  }

  Future<MessageHistoryCoverage?> loadMessageHistoryCoverage(
    String conversationID,
  ) {
    final repository = appMessageHistoryCoverageRepository;
    return repository?.load(conversationID) ??
        Future<MessageHistoryCoverage?>.value();
  }

  Future<void> persistMessageHistoryCoverage(
    MessageHistoryCoverage coverage,
  ) async {
    await appMessageHistoryCoverageRepository?.save(coverage);
  }

  Future<void> clearMessageHistoryCoverage(
    String conversationID, {
    required bool isGroup,
    required int clearEpoch,
  }) async {
    await appMessageHistoryCoverageRepository?.clearConversation(
      conversationID,
      isGroup: isGroup,
      clearEpoch: clearEpoch,
    );
  }

  Future<V2TimMessageListResult?> getHistoryMessageListThroughIm06({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    final writerScope = _messageReconciliationWriter.configuredScope;
    final peer = userID?.trim() ?? '';
    final group = groupID?.trim() ?? '';
    final conversationID = group.isNotEmpty ? group : peer;
    // DIAG: IM06 scope 读取点。判断进页/翻页时 scope 是否就绪。
    ChatHistoryTrace.log(
      'diag_im06_scope_read',
      conversationID: conversationID,
      extras: <String, Object?>{
        'scopeNull': writerScope == null,
        'currentOwnerUserID': writerScope?.ownerUserID ?? '',
        'currentAccountGen': writerScope?.accountGeneration ?? -1,
        'currentDomainGen': writerScope?.domainGeneration ?? -1,
        'requestedSource': getType.name,
        'peer': peer,
        'group': group,
        'lastMsgID': lastMsgID ?? '',
        'lastMsgSeq': lastMsgSeq,
        'count': count,
      },
    );
    if (writerScope == null || peer.isNotEmpty == group.isNotEmpty) {
      _lastHistoryErrorByConversation[conversationID] = <String, Object?>{
        'errorType':
            writerScope == null ? 'scope_not_configured' : 'invalid_address',
        'errorCode': null,
        'description': 'IM history scope is unavailable or address is invalid',
      };
      ChatHistoryTrace.log(
        'history_im06_unavailable',
        conversationID: conversationID,
        extras: <String, Object?>{
          'reason':
              writerScope == null ? 'scope_not_configured' : 'invalid_address',
          'requestedSource': getType.name,
        },
      );
      return null;
    }
    final conversationType =
        group.isNotEmpty ? ImConversationType.group : ImConversationType.c2c;
    final scope = AccountScopedConversationKey.tryParse(
      ownerUserId: writerScope.normalizedOwnerUserID,
      conversationType: conversationType,
      conversationId: group.isNotEmpty ? group : peer,
    );
    if (scope == null) {
      _lastHistoryErrorByConversation[conversationID] = <String, Object?>{
        'errorType': 'invalid_scope',
        'errorCode': null,
        'description': 'IM history scope cannot be created',
      };
      ChatHistoryTrace.log(
        'history_im06_unavailable',
        conversationID: conversationID,
        extras: <String, Object?>{
          'reason': 'invalid_scope',
          'requestedSource': getType.name,
        },
      );
      return null;
    }

    final requestedSource = switch (getType) {
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG ||
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG =>
        ImHistorySource.local,
      _ => ImHistorySource.cloud,
    };
    final cursorId = (lastMsgID ?? lastMsg?.msgID)?.trim() ?? '';
    final cursorSeq =
        conversationType == ImConversationType.group && lastMsgSeq > 0
            ? lastMsgSeq
            : null;
    final hasPinnedGroupSeqs = conversationType == ImConversationType.group &&
        messageSeqList?.isNotEmpty == true;
    final hasPaginationCursor = cursorId.isNotEmpty || cursorSeq != null;
    // An exact group-Seq lookup is still a directional history request even
    // though it deliberately has no pagination cursor. Treating it as the
    // latest window rewrites CLOUD_NEWER to CLOUD_OLDER in the typed adapter.
    final hasDirectionalAnchor = hasPaginationCursor || hasPinnedGroupSeqs;
    final direction = !hasDirectionalAnchor
        ? ImHistoryDirection.latest
        : switch (getType) {
            HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG ||
            HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG =>
              ImHistoryDirection.newer,
            _ => ImHistoryDirection.older,
          };
    final requestGeneration = ++_im06HistoryRequestSequence;
    final coordinator = _im06HistorySearchCoordinator ??=
        Im06HistorySearchCoordinator.production(
      messageService: _messageService,
      platform: _im06Platform,
      ownerUserId: writerScope.normalizedOwnerUserID,
      accountGeneration: writerScope.accountGeneration,
      domainGeneration: writerScope.domainGeneration,
      coverageStore: appIm06HistoryCoverageStore,
    );
    final result = await coordinator.readHistory(
      Im06HistoryRequest(
        scope: scope,
        platform: _im06Platform,
        requestedSource: requestedSource,
        direction: direction,
        requestId: 'uikit-history-$requestGeneration',
        requestGeneration: requestGeneration,
        accountGeneration: writerScope.accountGeneration,
        domainGeneration: writerScope.domainGeneration,
        clearEpoch: messageDeltaClearEpochFor(scope.conversationId),
        count: count,
        lastMessage: lastMsg,
        cursor: hasPaginationCursor
            ? Im06HistoryCursor(
                messageId: cursorId.isEmpty ? null : cursorId,
                sequence: cursorSeq,
              )
            : const Im06HistoryCursor.latest(),
        messageTypeList: messageTypeList,
        messageSeqList: messageSeqList,
        timeBegin: timeBegin,
        timePeriod: timePeriod,
      ),
    );
    if (_messageReconciliationWriter.configuredScope != writerScope ||
        !result.isSuccess ||
        result.page == null) {
      _lastHistoryErrorByConversation[conversationID] = <String, Object?>{
        'errorType': _messageReconciliationWriter.configuredScope != writerScope
            ? 'scope_changed'
            : result.error?.name ?? 'unknown',
        'errorCode': result.errorCode,
        'description': result.errorDescription ?? 'history request failed',
      };
      ChatHistoryTrace.log(
        'history_im06_failure',
        conversationID: conversationID,
        extras: <String, Object?>{
          'reason': _messageReconciliationWriter.configuredScope != writerScope
              ? 'scope_changed'
              : result.error?.name ?? 'unknown',
          'error': result.error?.name,
          'errorCode': result.errorCode,
          'description': result.errorDescription,
          'route': result.route.name,
          'requestedSource': requestedSource.name,
        },
      );
      return null;
    }
    _lastHistoryErrorByConversation.remove(conversationID);
    return V2TimMessageListResult(
      isFinished: result.page!.isCompleted,
      messageList: result.page!.messages.whereType<V2TimMessage>().toList(),
    );
  }

  ImPlatform get _im06Platform {
    if (kIsWeb) return ImPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => ImPlatform.android,
      TargetPlatform.iOS => ImPlatform.ios,
      TargetPlatform.macOS => ImPlatform.macos,
      TargetPlatform.windows => ImPlatform.windows,
      TargetPlatform.linux => ImPlatform.linux,
      TargetPlatform.fuchsia => ImPlatform.unknown,
    };
  }

  MessageReconciliationNetworkState get messageReconciliationNetworkState {
    try {
      return appMessageReconciliationNetworkStateProvider?.call() ??
          MessageReconciliationNetworkState.unknown;
    } catch (_) {
      return MessageReconciliationNetworkState.unknown;
    }
  }

  MessageReconciliationRecord<V2TimMessage> _reconciliationRecord(
    V2TimMessage message,
  ) {
    return MessageReconciliationRecord<V2TimMessage>(
      value: message,
      msgID: message.msgID,
      localID: message.id,
      outgoingStableID: readOutgoingStableId(message) ??
          (message.isSelf == true &&
                  ((message.msgID?.trim() ?? '').isEmpty ||
                      message.msgID?.trim() == message.id?.trim())
              ? message.id
              : null),
      seq: message.seq,
    );
  }

  MessageReconciliationRecord<V2TimMessage> messageDeltaRecord(
    V2TimMessage message,
  ) =>
      _reconciliationRecord(message);

  Iterable<MessageReconciliationRecord<V2TimMessage>> _reconciliationRecords(
    Iterable<V2TimMessage> messages,
  ) {
    return messages.map(_reconciliationRecord);
  }

  String? _outgoingRecordStableIdentity(V2TimMessage message) =>
      readOutgoingStableId(message) ??
      (message.isSelf == true &&
              ((message.msgID?.trim() ?? '').isEmpty ||
                  message.msgID?.trim() == message.id?.trim())
          ? message.id
          : null);

  void _seedMessageWriterFromProjection(
    String key,
    List<V2TimMessage> current, {
    required int clearEpoch,
  }) {
    final trackSeqGaps = _isGroupConversation(key, messages: current);
    if (_messageReconciliationWriter.ownsAuthoritativeWindow(
      conversationID: key,
      expectedAuthority: _writerProjectionAuthorities[key],
      values: current,
      matchesRecord: (record, value) =>
          record.msgID == value.msgID &&
          record.localID == value.id &&
          record.seq == value.seq &&
          record.outgoingStableID == _outgoingRecordStableIdentity(value),
      trackSeqGaps: trackSeqGaps,
      clearEpoch: clearEpoch,
    )) {
      ChatMainThreadPerf.increment('message_writer_seed_reused');
      return;
    }
    ChatMainThreadPerf.increment('message_writer_seed_performed');
    _messageReconciliationWriter.seedAuthoritative(
      conversationID: key,
      records: _reconciliationRecords(current),
      trackSeqGaps: trackSeqGaps,
      clearEpoch: clearEpoch,
    );
    _writerProjectionAuthorities[key] =
        _messageReconciliationWriter.authorityFor(key);
  }

  int messageDeltaGenerationFor(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    if (key.isEmpty) return 0;
    return _messageReconciliationWriter.coordinator
        .stateFor(key)
        .requestGeneration;
  }

  int messageDeltaClearEpochFor(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    return _messageHistoryCoverageByConv[key]?.clearEpoch ?? 0;
  }

  /// 窗口库中已记录的最高清空 epoch；null 表示本次未能读取，而非版本 0。
  Future<int?> _persistedHistoryWindowClearEpoch(String canonicalKey) async {
    final repository = HistoryWindowRepositoryProvider.repository;
    final owner =
        _messageReconciliationWriter.configuredScope?.normalizedOwnerUserID ??
            '';
    if (repository == null || owner.isEmpty || canonicalKey.isEmpty) {
      return null;
    }
    try {
      return await repository.persistedClearEpoch(
        ownerUserID: owner,
        conversationID: canonicalKey,
      );
    } catch (_) {
      return null;
    }
  }

  /// 内存 clearEpoch 落后于窗口库时采纳窗口库的值。
  /// 否则 `_checkScope` 会把每次分页读都判成 stale，上拉永远静默失败。
  Future<void> syncHistoryClearEpochFromWindowStore(
    String conversationID,
  ) async {
    final key = canonicalHistoryStorageKey(conversationID);
    if (key.isEmpty) return;
    if (_historyWindowClearEpochSyncedKeys.contains(key)) return;
    final sessionGeneration = _messageHistoryCoverageSessionGeneration;
    final persisted = await _persistedHistoryWindowClearEpoch(key);
    if (persisted == null ||
        sessionGeneration != _messageHistoryCoverageSessionGeneration) return;
    final current = messageDeltaClearEpochFor(key);
    if (persisted <= current) {
      _historyWindowClearEpochSyncedKeys.add(key);
      return;
    }
    await ensureMessageHistoryCoverageLoaded(key, clearEpoch: persisted);
    if (sessionGeneration != _messageHistoryCoverageSessionGeneration) return;
    final coverage = messageHistoryCoverageFor(key);
    // A failed/obsolete read, or a concurrent coverage load that did not adopt
    // the floor yet, must leave the next foreground pagination free to retry.
    if (coverage == null || coverage.clearEpoch < persisted) return;
    _historyWindowClearEpochSyncedKeys.add(key);
    unawaited(persistMessageHistoryCoverage(coverage));
    ChatHistoryTrace.log(
      'history_clear_epoch_synced_from_window_store',
      conversationID: key,
      extras: <String, Object?>{
        'memoryEpoch': current,
        'persistedEpoch': persisted,
      },
    );
  }

  @visibleForTesting
  int messageWriterRetainedCountForTesting(String conversationID) =>
      _messageReconciliationWriter
          .recordsFor(
            canonicalHistoryStorageKey(conversationID),
          )
          .length;

  /// DIAG: 当前 IM06 scope 状态读取接口（仅用于 trace，不参与业务逻辑）。
  String? get im06WriterOwnerUserID =>
      _messageReconciliationWriter.configuredScope?.ownerUserID;
  int? get im06WriterAccountGeneration =>
      _messageReconciliationWriter.configuredScope?.accountGeneration;
  int? get im06WriterDomainGeneration =>
      _messageReconciliationWriter.configuredScope?.domainGeneration;
  bool get im06WriterScopeConfigured =>
      _messageReconciliationWriter.configuredScope != null;

  /// Supplies the account and SDK-session scope captured by app ingress.
  ///
  /// The UIKit model does not infer the logged-in account. The host app must
  /// call this at login/session ownership time so late events can be rejected
  /// by the single Writer.
  void configureMessageWriterScope({
    required String ownerUserID,
    required int accountGeneration,
    required int domainGeneration,
  }) {
    final previousScope = _messageReconciliationWriter.configuredScope;
    ChatHistoryTrace.log(
      'diag_im06_scope_configured',
      conversationID: '',
      extras: <String, Object?>{
        'ownerUserID': ownerUserID,
        'accountGeneration': accountGeneration,
        'domainGeneration': domainGeneration,
        'previousScopeNull': previousScope == null,
        'previousOwnerUserID': previousScope?.ownerUserID ?? '',
      },
    );
    _messageReconciliationWriter.configureScope(
      MessageReconciliationWriterScope(
        ownerUserID: ownerUserID,
        accountGeneration: accountGeneration,
        domainGeneration: domainGeneration,
      ),
    );
    final afterScope = _messageReconciliationWriter.configuredScope;
    if (previousScope != _messageReconciliationWriter.configuredScope) {
      invalidateBoundedHistorySessions();
      if (previousScope != null &&
          previousScope.normalizedOwnerUserID !=
              afterScope?.normalizedOwnerUserID) {
        _inboundUnreadStateByConversation.clear();
        _deferredUntilUserBottomConversations.clear();
        _dismissedEntryUnreadTongueCountByConversation.clear();
        _unreadTongueRemainingByConversation.clear();
        _unreadTongueBelowByConversation.clear();
        _followingLatestByConversation.clear();
        _historyReadingWindowByConversation.clear();
        _freezeHistoryReadingWindowByConversation.clear();
        _attachingBufferedTowardLatest = false;
        _attachingBufferedTowardLatestUntilMs = 0;
      }
      _writerProjectionAuthorities.clear();
      _im06HistorySearchCoordinator = null;
      _im06HistoryRequestSequence = 0;
    }
  }

  void releaseMessageDeltaTombstones(
    String conversationID,
    Iterable<String> msgIDs,
  ) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    if (key.isEmpty) return;
    _messageReconciliationWriter.releaseTombstones(key, msgIDs);
  }

  void restoreMessageDeltaAfterDeleteFailure(
    String conversationID,
    Iterable<V2TimMessage> messages,
  ) {
    final restored = messages.toList(growable: false);
    if (restored.isEmpty) return;
    final ids = restored
        .map((message) => message.msgID?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    releaseMessageDeltaTombstones(conversationID, ids);
    commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: conversationID,
        eventID:
            'delete_rollback:${ids.join(',')}:${DateTime.now().microsecondsSinceEpoch}',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.userAction,
        generation: messageDeltaGenerationFor(conversationID),
        clearEpoch: messageDeltaClearEpochFor(conversationID),
        upserts: _reconciliationRecords(restored),
      ),
    );
  }

  /// Authoritative boundary for realtime, optimistic, edit, revoke and delete.
  /// `setMessageList` remains the final UI projection writer, but no caller in
  /// these mutation paths decides merge/removal semantics independently.
  ///
  /// [forcePublishForRevoke] bypasses the active history request barrier for
  /// revoke deltas only; this lets the user-visible revoke UX refresh
  /// immediately instead of waiting for the in-flight history transaction.
  /// Other kinds, scope mismatches, generation mismatches and eventID dupes
  /// are still rejected.
  MessageCommitResult? commitMessageDelta(
    MessageDelta<V2TimMessage> delta, {
    bool applyMemoryWindow = true,
    bool memoryWindowPreferLatest = false,
    bool forcePublishForRevoke = false,
  }) {
    final storageKey = _resolveMessageListStorageKey(delta.conversationKey);
    final key = storageKey.isEmpty ? delta.conversationKey.trim() : storageKey;
    if (key.isEmpty || delta.isSynthetic) return null;
    if (!_messageReconciliationWriter.hasActiveRequest(key)) {
      final current = _mergedAliasMessageList(key);
      _seedMessageWriterFromProjection(
        key,
        current,
        clearEpoch: delta.clearEpoch,
      );
    }
    final normalized = MessageDelta<V2TimMessage>(
      conversationKey: key,
      eventID: delta.eventID,
      kind: delta.kind,
      source: delta.source,
      generation: delta.generation,
      clearEpoch: delta.clearEpoch,
      ownerUserID: delta.ownerUserID,
      accountGeneration: delta.accountGeneration,
      domainGeneration: delta.domainGeneration,
      replace: delta.replace,
      upserts: delta.upserts,
      localDeletes: delta.localDeletes,
      explicitDeletes: delta.explicitDeletes,
      tombstones: delta.tombstones,
    );
    // A history request is a read-side transaction. It must never hold back
    // realtime rows (including group rows) or the send/ack projection for the
    // same conversation. The Writer still retains each delta for the final
    // history merge, so publishing here cannot lose ordering or dedupe.
    final publishDuringHistory =
        normalized.kind == MessageDeltaKind.realtimeUpsert ||
            normalized.kind == MessageDeltaKind.delete ||
            normalized.source == MessageDeltaSource.sendPipeline;
    final writerCommit =
        forcePublishForRevoke && delta.kind == MessageDeltaKind.revoke
            ? _messageReconciliationWriter.applyRevokeDelta(normalized)
            : _messageReconciliationWriter.applyDelta(
                normalized,
                publishDuringHistory: publishDuringHistory,
              );
    if (writerCommit == null) return null;
    if (normalized.kind == MessageDeltaKind.realtimeUpsert &&
        normalized.source == MessageDeltaSource.sdkRealtime) {
      final appended = _commitRealtimeWriterAppend(key, writerCommit);
      if (appended != null) return appended;
    }
    if (normalized.source == MessageDeltaSource.sendPipeline &&
        (normalized.kind == MessageDeltaKind.edit ||
            normalized.kind == MessageDeltaKind.optimisticAdoption)) {
      final rowCommit = _commitOutgoingMediaRows(key, writerCommit);
      if (rowCommit != null) return rowCommit;
    }
    return setMessageList(
      key,
      _messageReconciliationWriter.valuesFor(key),
      needResetNewMessageCount: false,
      replace: true,
      isDeleteMsg: delta.kind == MessageDeltaKind.delete,
      applyMemoryWindow: applyMemoryWindow,
      memoryWindowPreferLatest: memoryWindowPreferLatest,
      writerCommit: writerCommit,
      historyCommitSource:
          'message_delta:${delta.kind.name}:r${writerCommit.revision}',
    );
  }

  /// Publishes a Writer-approved newest-prefix append without running the
  /// full history reconciliation, sort and gap scan again. The surrounding
  /// inbound pipeline owns the one list-revision bump and presentation
  /// pacing for this batch.
  MessageCommitResult? _commitRealtimeWriterAppend(
    String storageKey,
    MessageReconciliationWriterCommit<V2TimMessage> writerCommit,
  ) {
    if (writerCommit.missingSeqRanges.isNotEmpty ||
        writerCommit.seqIdentityConflicts.isNotEmpty) {
      return null;
    }
    final previous = _mergedAliasMessageList(storageKey);
    final authoritative = _messageReconciliationWriter.valuesFor(storageKey);
    if (authoritative.isEmpty ||
        authoritative.length > ChatMessageWindowPolicy.softMax) {
      return null;
    }
    final appendedCount = previous.isEmpty
        ? authoritative.length
        : _canonicalRealtimeAppendCount(previous, authoritative);
    if (appendedCount <= 0) return null;

    final next = _messageReconciliationWriter.valuesFor(storageKey);
    _messageListMap[storageKey] = next;
    _collapseHistoryAliasesToCanonical(storageKey, canonical: storageKey);
    _invalidateMessageListDisplayCache(storageKey);
    _messageListContentSignatureByConv[storageKey] =
        _messageListContentSignature(next);
    ChatMessageHeightCache.instance.seedEstimatesForMessages(
      next.take(appendedCount).toList(growable: false),
    );
    ChatMainThreadPerf.increment('message_realtime_writer_append');
    ChatMainThreadPerf.increment('message_realtime_canonical_reused');
    return _messageCommitSnapshot(
      conversationID: storageKey,
      storageKey: storageKey,
      list: next,
      structureChanged: true,
      contentChanged: true,
      recordCommit: true,
      writerCommit: writerCommit,
    );
  }

  /// Same-position media adoption must not reset the history viewport.
  /// Publish the accepted Writer snapshot, then notify only changed rows.
  MessageCommitResult? _commitOutgoingMediaRows(
    String storageKey,
    MessageReconciliationWriterCommit<V2TimMessage> writerCommit,
  ) {
    final previous = _mergedAliasMessageList(storageKey);
    final next = _messageReconciliationWriter.valuesFor(storageKey);
    if (previous.isEmpty ||
        previous.length != next.length ||
        !isNewestFirstStorageOrderValid(next)) {
      return null;
    }
    final changed = <MapEntry<V2TimMessage, V2TimMessage>>[];
    for (var index = 0; index < previous.length; index++) {
      final before = previous[index];
      final after = next[index];
      if (identical(before, after)) continue;
      if (_commitSnapshotIdentity(before) == _commitSnapshotIdentity(after) &&
          _messageListContentSignature([before]) ==
              _messageListContentSignature([after])) {
        continue;
      }
      final stableId = readOutgoingStableId(before)?.trim() ?? '';
      if (stableId.isEmpty ||
          stableId != readOutgoingStableId(after) ||
          !_isRowLocalOutgoingMediaReceipt(before, after)) {
        return null;
      }
      changed.add(MapEntry(before, after));
    }
    _messageListMap[storageKey] = next;
    _collapseHistoryAliasesToCanonical(storageKey, canonical: storageKey);
    _invalidateMessageListDisplayCache(storageKey);
    _messageListContentSignatureByConv[storageKey] =
        _messageListContentSignature(next);
    for (final change in changed) {
      ChatMessageHeightCache.instance.rememberAliasesBetween(
        change.key,
        change.value,
      );
      _markMessageRowChanged(storageKey, change.value, extraKey: change.key.id);
    }
    return _messageCommitSnapshot(
      conversationID: storageKey,
      storageKey: storageKey,
      list: next,
      structureChanged: false,
      contentChanged: changed.isNotEmpty,
      recordCommit: true,
      writerCommit: writerCommit,
    );
  }

  /// Starts one history transaction against the current authoritative window.
  /// Realtime callbacks are queued by the same writer until this generation
  /// either commits or fails, so an old history response cannot overwrite them.
  MessageReconciliationRequest beginHistoryReconciliation({
    required String conversationID,
    required MessageReconciliationSource requestedSource,
    required MessageReconciliationNetworkState networkState,
  }) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final authoritative = _mergedAliasMessageList(storageKey);
    _seedMessageWriterFromProjection(
      storageKey,
      authoritative,
      clearEpoch: messageDeltaClearEpochFor(storageKey),
    );
    return _messageReconciliationWriter.beginInitialHistory(
      conversationID: storageKey,
      requestedSource: requestedSource,
      networkState: networkState,
      clearEpoch: messageDeltaClearEpochFor(storageKey),
    );
  }

  bool hasActiveHistoryReconciliation(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    return key.isNotEmpty && _messageReconciliationWriter.hasActiveRequest(key);
  }

  /// Releases a history writer owned by a chat page that has been disposed.
  ///
  /// Native SDK history reads cannot be cancelled. Dropping the writer state
  /// here prevents a late completion from retaining the conversation's shared
  /// mutation lane and lets incoming/send deltas publish normally after the
  /// route has changed. The runner's generation/clear guards still reject the
  /// late response when its Future eventually completes.
  void cancelHistoryReconciliation(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    if (key.isEmpty) {
      return;
    }
    _messageReconciliationWriter.reset(key);
  }

  MessageReconciliationState messageReconciliationStateFor(
    String conversationID,
  ) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    return _messageReconciliationWriter.coordinator.stateFor(
      storageKey.isEmpty ? conversationID : storageKey,
    );
  }

  MessageHistoryCommitMetadata? messageHistoryCommitMetadataFor(
    String conversationID,
  ) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    return _lastHistoryCommitMetadataByConv[
        storageKey.isEmpty ? conversationID.trim() : storageKey];
  }

  MessageCommitResult? completeHistoryReconciliation({
    required MessageReconciliationRequest request,
    required Iterable<V2TimMessage> history,
    required MessageReconciliationSource actualSource,
    required MessageReconciliationNetworkState networkState,
    bool applyMemoryWindow = true,
    bool memoryWindowPreferLatest = false,
    String historyCommitSource = 'reconciliation',
    bool cloudHasMoreNewer = false,
    MessageHistoryBatchKind batchKind = MessageHistoryBatchKind.olderPage,
    bool? historyIsFinished,
    int? clearEpoch,
    MessageHistoryCursor? requestedCursor,
    MessageHistoryBounds? returnedBounds,
    MessageHistoryProofKind? proofKind,
    bool? cloudResponseProven,
    Iterable<String> explicitDeletes = const <String>[],
    Iterable<String> tombstones = const <String>[],
    bool skipEquivalentHistoryWindow = false,

    /// Already canonical window captured by the pagination caller. Reusing it
    /// avoids a second alias merge/dedupe while committing an older page.
    List<V2TimMessage>? currentWindowOverride,
  }) {
    // Include direct row-local/self-send commits made while the request was in
    // flight. Inbound callbacks are already held in pendingRealtime.
    final historyList = history.toList(growable: false);
    final effectiveClearEpoch =
        clearEpoch ?? messageDeltaClearEpochFor(request.conversationKey);
    final current = currentWindowOverride ??
        _mergedAliasMessageList(request.conversationKey);
    final authoritativeBase =
        batchKind == MessageHistoryBatchKind.latestWindow &&
                actualSource == MessageReconciliationSource.cloud
            ? _authoritativeBaseForCloudLatestWindow(
                conversationID: request.conversationKey,
                current: current,
                cloudWindow: historyList,
              )
            : current;
    final resolvedProofKind = proofKind ??
        (cloudResponseProven != null
            ? (cloudResponseProven
                ? MessageHistoryProofKind.transportObserved
                : MessageHistoryProofKind.none)
            : actualSource == MessageReconciliationSource.cloud &&
                    networkState == MessageReconciliationNetworkState.online
                ? MessageHistoryProofKind.transportObserved
                : MessageHistoryProofKind.none);
    final commit = _messageReconciliationWriter.completeHistory(
      request: request,
      history: _reconciliationRecords(historyList),
      authoritativeBase: _reconciliationRecords(authoritativeBase),
      actualSource: actualSource,
      networkState: networkState,
      clearEpoch: effectiveClearEpoch,
      cloudHasMoreNewer: cloudHasMoreNewer,
      batchKind: batchKind,
      proofKind: resolvedProofKind,
      historyIsFinished: historyIsFinished,
      explicitDeletes: explicitDeletes,
      tombstones: tombstones,
    );
    if (commit == null) {
      return null;
    }
    final result = setMessageList(
      commit.conversationKey,
      _messageReconciliationWriter.valuesFor(commit.conversationKey),
      needResetNewMessageCount: false,
      replace: true,
      applyMemoryWindow: applyMemoryWindow,
      memoryWindowPreferLatest: memoryWindowPreferLatest,
      skipEquivalentHistoryWindow: true,
      writerCommit: commit,
      historyCommitSource: skipEquivalentHistoryWindow
          ? historyCommitSource
          : '$historyCommitSource:r${commit.revision}',
    );
    final resolvedMetadataKey = _resolveMessageListStorageKey(
      commit.conversationKey,
    );
    final metadataKey = resolvedMetadataKey.isEmpty
        ? commit.conversationKey.trim()
        : resolvedMetadataKey;
    _lastHistoryCommitMetadataByConv[metadataKey] =
        MessageHistoryCommitMetadata(
      conversationKey: metadataKey,
      source: actualSource,
      batchKind: batchKind,
      generation: request.generation,
      revision: commit.revision,
      resultCount: result.rawCount,
      proofKind: resolvedProofKind,
      clearEpoch: effectiveClearEpoch,
    );
    _recordMessageHistoryCoverageAfterCommit(
      request: request,
      batchKind: batchKind,
      actualSource: actualSource,
      networkState: networkState,
      history: historyList,
      historyIsFinished: historyIsFinished,
      cloudHasMoreNewer: cloudHasMoreNewer,
      clearEpoch: effectiveClearEpoch,
      requestedCursor: requestedCursor,
      returnedBounds: returnedBounds,
      proofKind: resolvedProofKind,
    );
    unawaited(
      ImOutgoingSendCoordinator.instance
          .adoptProviderHistory(historyList, source: ImProviderEvidenceSource.sdkHistory)
          .catchError((Object error) {
        debugPrint(
          'OUTBOX_HISTORY_ADOPTION_FAILURE '
          'errorType=${error.runtimeType}',
        );
        return 0;
      }),
    );
    return result;
  }

  /// Commits a typed history envelope after validating its request generation
  /// and clear epoch. Transport provenance and continuity proof remain
  /// separate; an online response is not promoted to complete history.
  MessageCommitResult? completeHistoryBatch({
    required MessageReconciliationRequest request,
    required MessageHistoryBatch<V2TimMessage> batch,
    required MessageReconciliationNetworkState networkState,
    required int clearEpoch,
    bool applyMemoryWindow = true,
    bool memoryWindowPreferLatest = false,
    String historyCommitSource = 'reconciliation_batch',
    bool skipEquivalentHistoryWindow = false,
  }) {
    final batchKey = batch.conversationKey.trim();
    final requestKey = request.conversationKey.trim();
    final sameConversation = isSameConversationIdForHistory(
      batchKey,
      requestKey,
    );
    final stale = batch.isStale(
      generation: request.generation,
      clearEpoch: clearEpoch,
    );
    if (!sameConversation || stale) {
      ChatHistoryTrace.log(
        'history_batch_rejected',
        conversationID: requestKey,
        extras: <String, Object?>{
          'reason': !sameConversation ? 'conversation_mismatch' : 'stale',
          'batchKind': batch.batchKind.name,
          'requestGeneration': request.generation,
          'batchGeneration': batch.generation,
          'clearEpoch': clearEpoch,
          'batchClearEpoch': batch.clearEpoch,
        },
      );
      return null;
    }
    if (batchKey != requestKey) {
      ChatHistoryTrace.log(
        'history_batch_alias_accepted',
        conversationID: requestKey,
        extras: <String, Object?>{
          'batchKind': batch.batchKind.name,
          'requestGeneration': request.generation,
        },
      );
    }
    return completeHistoryReconciliation(
      request: request,
      history: batch.messages,
      actualSource: batch.actualSource,
      networkState: networkState,
      applyMemoryWindow: applyMemoryWindow,
      memoryWindowPreferLatest: memoryWindowPreferLatest,
      historyCommitSource: historyCommitSource,
      skipEquivalentHistoryWindow: skipEquivalentHistoryWindow,
      cloudHasMoreNewer: batch.cloudHasMoreNewer,
      batchKind: batch.batchKind,
      historyIsFinished: batch.isFinished,
      clearEpoch: clearEpoch,
      requestedCursor: batch.requestedCursor,
      returnedBounds: batch.returnedBounds,
      proofKind: batch.proofKind,
      explicitDeletes: batch.explicitDeletes,
      tombstones: batch.tombstones,
    );
  }

  List<V2TimMessage> _authoritativeBaseForCloudLatestWindow({
    required String conversationID,
    required List<V2TimMessage> current,
    required List<V2TimMessage> cloudWindow,
  }) {
    // A latest-window response proves only the bounded window it returned.
    // Absence from that page is not a delete/revoke proof, especially when the
    // SDK cloud request can fall back to local data. Keep every existing row;
    // explicit tombstones/revoke callbacks are the only removal authority.
    return current;
  }

  bool _groupWindowsOverlapOrTouch(
    List<V2TimMessage> first,
    List<V2TimMessage> second,
  ) {
    int? firstMin;
    int? firstMax;
    int? secondMin;
    int? secondMax;
    for (final message in first) {
      final seq = int.tryParse(message.seq?.trim() ?? '');
      if (seq == null || seq <= 0) continue;
      firstMin = firstMin == null || seq < firstMin ? seq : firstMin;
      firstMax = firstMax == null || seq > firstMax ? seq : firstMax;
    }
    for (final message in second) {
      final seq = int.tryParse(message.seq?.trim() ?? '');
      if (seq == null || seq <= 0) continue;
      secondMin = secondMin == null || seq < secondMin ? seq : secondMin;
      secondMax = secondMax == null || seq > secondMax ? seq : secondMax;
    }
    if (firstMin == null ||
        firstMax == null ||
        secondMin == null ||
        secondMax == null) {
      return false;
    }
    return firstMin <= secondMax + 1 && secondMin <= firstMax + 1;
  }

  void _recordMessageHistoryCoverageAfterCommit({
    required MessageReconciliationRequest request,
    required MessageHistoryBatchKind batchKind,
    required MessageReconciliationSource actualSource,
    required MessageReconciliationNetworkState networkState,
    required List<V2TimMessage> history,
    required bool? historyIsFinished,
    required bool cloudHasMoreNewer,
    required int clearEpoch,
    MessageHistoryCursor? requestedCursor,
    MessageHistoryBounds? returnedBounds,
    required MessageHistoryProofKind proofKind,
  }) {
    final storageKey = _resolveMessageListStorageKey(request.conversationKey);
    final key = storageKey.isEmpty ? request.conversationKey : storageKey;
    final coverageSessionGeneration = _messageHistoryCoverageSessionGeneration;
    final reconciliationState =
        _messageReconciliationWriter.coordinator.stateFor(key);
    final missingSeqRanges = List<MessageSeqRange>.unmodifiable(
      reconciliationState.missingSeqRanges,
    );
    final historySnapshot = List<V2TimMessage>.unmodifiable(history);

    void applyLoadedCoverage() {
      if (coverageSessionGeneration !=
          _messageHistoryCoverageSessionGeneration) {
        return;
      }
      final current = _messageHistoryCoverageByConv[key];
      if (current == null || current.clearEpoch != clearEpoch) return;
      final previousGeneration =
          _messageHistoryCoverageRequestGenerationByConv[key] ?? 0;
      if (request.generation <= previousGeneration) return;
      _messageHistoryCoverageRequestGenerationByConv[key] = request.generation;
      _applyMessageHistoryCoverageCommit(
        current: current,
        request: request,
        batchKind: batchKind,
        actualSource: actualSource,
        networkState: networkState,
        history: historySnapshot,
        historyIsFinished: historyIsFinished,
        cloudHasMoreNewer: cloudHasMoreNewer,
        missingSeqRanges: missingSeqRanges,
        requestedCursor: requestedCursor,
        returnedBounds: returnedBounds,
        proofKind: proofKind,
      );
    }

    if (_messageHistoryCoverageLoadedConvs.contains(key) &&
        !_messageHistoryCoverageUpdateTailByConv.containsKey(key)) {
      applyLoadedCoverage();
      return;
    }

    unawaited(
      _enqueueMessageHistoryCoverageUpdate(key, () async {
        await ensureMessageHistoryCoverageLoaded(key, clearEpoch: clearEpoch);
        applyLoadedCoverage();
      }),
    );
  }

  Future<void> _enqueueMessageHistoryCoverageUpdate(
    String conversationID,
    Future<void> Function() update,
  ) {
    final previous = _messageHistoryCoverageUpdateTailByConv[conversationID];
    late final Future<void> task;
    task = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      await update();
    }()
        .whenComplete(() {
      if (identical(
        _messageHistoryCoverageUpdateTailByConv[conversationID],
        task,
      )) {
        _messageHistoryCoverageUpdateTailByConv.remove(conversationID);
      }
    });
    _messageHistoryCoverageUpdateTailByConv[conversationID] = task;
    return task;
  }

  void _applyMessageHistoryCoverageCommit({
    required MessageHistoryCoverage current,
    required MessageReconciliationRequest request,
    required MessageHistoryBatchKind batchKind,
    required MessageReconciliationSource actualSource,
    required MessageReconciliationNetworkState networkState,
    required List<V2TimMessage> history,
    required bool? historyIsFinished,
    required bool cloudHasMoreNewer,
    required List<MessageSeqRange> missingSeqRanges,
    MessageHistoryCursor? requestedCursor,
    MessageHistoryBounds? returnedBounds,
    required MessageHistoryProofKind proofKind,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isGroup = current.isGroup ||
        _isGroupConversation(request.conversationKey, messages: history);
    final oldest = _oldestServerHistoryMessage(history);
    final newest = _newestServerHistoryMessage(history);
    final cloudTransportConfirmed =
        actualSource == MessageReconciliationSource.cloud &&
            proofKind != MessageHistoryProofKind.none;
    final serverContinuityProven =
        proofKind == MessageHistoryProofKind.serverContinuity;
    final holes = _coverageHolesForCommit(
      current: current,
      isGroup: isGroup,
      batchKind: batchKind,
      generation: request.generation,
      history: history,
      missingSeqRanges: missingSeqRanges,
      cloudProven: cloudTransportConfirmed,
      nowMs: now,
    );
    final nextNewerHasMore =
        batchKind == MessageHistoryBatchKind.latestWindow ||
                batchKind == MessageHistoryBatchKind.newerCatchUp
            ? cloudHasMoreNewer
            : current.newerHasMore;
    // An online transport response only proves that this bounded request
    // reached the server. It does not prove the conversation is continuous;
    // only an explicit server-continuity token may produce `verified`.
    final status = batchKind == MessageHistoryBatchKind.localSnapshot
        ? MessageHistoryCoverageStatus.provisional
        : !cloudTransportConfirmed
            ? MessageHistoryCoverageStatus.offlineLocalOnly
            : holes.isNotEmpty ||
                    nextNewerHasMore ||
                    historyIsFinished != true ||
                    !serverContinuityProven
                ? MessageHistoryCoverageStatus.partial
                : MessageHistoryCoverageStatus.verified;
    var next = current.copyWith(
      isGroup: isGroup,
      coverageRevision: current.coverageRevision + 1,
      status: status,
      holes: holes,
      newerHasMore: nextNewerHasMore,
      updatedAtMs: now,
      lastRequestGeneration: request.generation,
      lastRequestedSource: request.requestedSource.name,
      lastActualSource: actualSource.name,
      lastBatchKind: batchKind.name,
      lastCursorDirection: requestedCursor?.direction.name,
      lastCursorMsgID: requestedCursor?.lastMsgID,
      lastCursorSeq: requestedCursor?.lastMsgSeq,
      clearLastCursor: requestedCursor == null,
      lastReturnedOldestMsgID: returnedBounds?.oldestMsgID,
      lastReturnedNewestMsgID: returnedBounds?.newestMsgID,
      lastReturnedOldestSeq: returnedBounds?.oldestSeq,
      lastReturnedNewestSeq: returnedBounds?.newestSeq,
      clearLastReturnedBounds: returnedBounds == null,
      lastProofKind: proofKind,
      lastCloudResponseProven: cloudTransportConfirmed,
    );
    final direction = _coverageDirectionForBatch(batchKind);
    final boundedRange = _coverageRangeForCommit(
      direction: direction,
      isGroup: isGroup,
      returnedBounds: returnedBounds,
      history: history,
      proofKind: proofKind,
      closed: serverContinuityProven &&
          historyIsFinished == true &&
          !cloudHasMoreNewer &&
          holes.isEmpty,
      generation: request.generation,
      nowMs: now,
    );
    final page = MessageHistoryPageRecord(
      key:
          'p:${request.generation}:${direction.name}:${requestedCursor?.lastMsgID ?? ''}:${requestedCursor?.lastMsgSeq ?? ''}',
      direction: direction,
      cursorMsgID: requestedCursor?.lastMsgID,
      cursorSeq: requestedCursor?.lastMsgSeq,
      returnedOldestMsgID: returnedBounds?.oldestMsgID,
      returnedNewestMsgID: returnedBounds?.newestMsgID,
      returnedOldestSeq: returnedBounds?.oldestSeq,
      returnedNewestSeq: returnedBounds?.newestSeq,
      isFinished: historyIsFinished == true,
      hasMore: cloudHasMoreNewer || historyIsFinished != true,
      proofKind: proofKind,
      generation: request.generation,
      updatedAtMs: now,
    );
    final continuationPending = !serverContinuityProven ||
        cloudHasMoreNewer ||
        historyIsFinished != true ||
        holes.isNotEmpty;
    // Persist the cursor that can actually continue this page chain. A
    // requested cursor is the previous anchor; resuming must use the returned
    // boundary (oldest for older pages, newest for newer/latest windows).
    final continuationDirection = continuationPending
        ? cloudHasMoreNewer
            ? MessageHistoryCoverageDirection.newer
            : historyIsFinished == false
                ? MessageHistoryCoverageDirection.older
                : direction
        : null;
    final continuationCursorMsgID =
        continuationDirection == MessageHistoryCoverageDirection.older
            ? (returnedBounds?.oldestMsgID ?? oldest?.msgID)
            : (returnedBounds?.newestMsgID ?? newest?.msgID);
    final continuationCursorSeq =
        continuationDirection == MessageHistoryCoverageDirection.older
            ? (returnedBounds?.oldestSeq ?? _messageNumericSeq(oldest))
            : (returnedBounds?.newestSeq ?? _messageNumericSeq(newest));
    next = next.copyWith(
      ranges: _appendCoverageRange(current.ranges, boundedRange),
      pages: _appendCoveragePage(current.pages, page),
      continuationPending: continuationPending,
      continuationDirection: continuationDirection,
      clearContinuationDirection: !continuationPending,
      continuationCursorMsgID:
          continuationPending ? continuationCursorMsgID : null,
      continuationCursorSeq: continuationPending ? continuationCursorSeq : null,
      clearContinuationCursor: !continuationPending,
    );
    if (batchKind == MessageHistoryBatchKind.localSnapshot) {
      next = next.copyWith(
        localOldestMsgID: oldest?.msgID,
        localNewestMsgID: newest?.msgID,
      );
    } else if (cloudTransportConfirmed) {
      final updatesOldest = batchKind == MessageHistoryBatchKind.latestWindow ||
          batchKind == MessageHistoryBatchKind.olderPage;
      final updatesNewest = batchKind == MessageHistoryBatchKind.latestWindow ||
          batchKind == MessageHistoryBatchKind.newerCatchUp;
      next = next.copyWith(
        verifiedOldestMsgID:
            updatesOldest ? oldest?.msgID : current.verifiedOldestMsgID,
        verifiedNewestMsgID:
            updatesNewest ? newest?.msgID : current.verifiedNewestMsgID,
        verifiedOldestSeq: updatesOldest
            ? _messageNumericSeq(oldest)
            : current.verifiedOldestSeq,
        verifiedNewestSeq: updatesNewest
            ? _messageNumericSeq(newest)
            : current.verifiedNewestSeq,
        olderExhausted: batchKind == MessageHistoryBatchKind.olderPage ||
                batchKind == MessageHistoryBatchKind.latestWindow
            ? historyIsFinished == true
            : current.olderExhausted,
        cloudVerifiedAtMs: now,
      );
    }
    _storeMessageHistoryCoverage(next);
  }

  MessageHistoryCoverageDirection _coverageDirectionForBatch(
    MessageHistoryBatchKind batchKind,
  ) {
    switch (batchKind) {
      case MessageHistoryBatchKind.olderPage:
      case MessageHistoryBatchKind.gapFill:
        return MessageHistoryCoverageDirection.older;
      case MessageHistoryBatchKind.newerCatchUp:
        return MessageHistoryCoverageDirection.newer;
      case MessageHistoryBatchKind.localSnapshot:
      case MessageHistoryBatchKind.latestWindow:
        return MessageHistoryCoverageDirection.latest;
    }
  }

  MessageHistoryCoverageRange? _coverageRangeForCommit({
    required MessageHistoryCoverageDirection direction,
    required bool isGroup,
    required MessageHistoryBounds? returnedBounds,
    required List<V2TimMessage> history,
    required MessageHistoryProofKind proofKind,
    required bool closed,
    required int generation,
    required int nowMs,
  }) {
    final oldest = returnedBounds?.oldestMsgID ??
        _oldestServerHistoryMessage(history)?.msgID;
    final newest = returnedBounds?.newestMsgID ??
        _newestServerHistoryMessage(history)?.msgID;
    final oldestSeq = returnedBounds?.oldestSeq ??
        _messageNumericSeq(_oldestServerHistoryMessage(history));
    final newestSeq = returnedBounds?.newestSeq ??
        _messageNumericSeq(_newestServerHistoryMessage(history));
    if (isGroup && oldestSeq != null && newestSeq != null) {
      return MessageHistoryCoverageRange(
        key: 'seq:${direction.name}:$oldestSeq-$newestSeq',
        direction: direction,
        oldestMsgID: oldest,
        newestMsgID: newest,
        startSeq: oldestSeq,
        endSeq: newestSeq,
        proofKind: proofKind,
        closed: closed,
        generation: generation,
        updatedAtMs: nowMs,
      );
    }
    if (oldest == null && newest == null) return null;
    return MessageHistoryCoverageRange(
      key: 'page:${direction.name}:${oldest ?? ''}:$newest',
      direction: direction,
      oldestMsgID: oldest,
      newestMsgID: newest,
      proofKind: proofKind,
      closed: closed,
      generation: generation,
      updatedAtMs: nowMs,
    );
  }

  List<MessageHistoryCoverageRange> _appendCoverageRange(
    List<MessageHistoryCoverageRange> existing,
    MessageHistoryCoverageRange? incoming,
  ) {
    if (incoming == null) return existing;
    final next = <MessageHistoryCoverageRange>[
      ...existing.where((range) => range.key != incoming.key),
      incoming,
    ];
    next.sort((a, b) => a.updatedAtMs.compareTo(b.updatedAtMs));
    return List<MessageHistoryCoverageRange>.unmodifiable(
      next.length <= 64 ? next : next.sublist(next.length - 64),
    );
  }

  List<MessageHistoryPageRecord> _appendCoveragePage(
    List<MessageHistoryPageRecord> existing,
    MessageHistoryPageRecord incoming,
  ) {
    final next = <MessageHistoryPageRecord>[
      ...existing.where((page) => page.key != incoming.key),
      incoming,
    ];
    next.sort((a, b) => a.updatedAtMs.compareTo(b.updatedAtMs));
    return List<MessageHistoryPageRecord>.unmodifiable(
      next.length <= 64 ? next : next.sublist(next.length - 64),
    );
  }

  List<MessageHistoryHole> _coverageHolesForCommit({
    required MessageHistoryCoverage current,
    required bool isGroup,
    required MessageHistoryBatchKind batchKind,
    required int generation,
    required List<V2TimMessage> history,
    required List<MessageSeqRange> missingSeqRanges,
    required bool cloudProven,
    required int nowMs,
  }) {
    if (isGroup) {
      if (batchKind == MessageHistoryBatchKind.gapFill &&
          missingSeqRanges.isEmpty) {
        // The merged authoritative window is now Seq-contiguous. Retain
        // unrelated hole kinds, but retire the group Seq holes that this
        // gap-fill request was responsible for repairing.
        return current.holes
            .where((hole) => hole.kind != MessageHistoryHoleKind.groupSeq)
            .toList(growable: false);
      }
      if (missingSeqRanges.isEmpty &&
          batchKind != MessageHistoryBatchKind.gapFill) {
        // A bounded newer/older page can be disjoint from a previously
        // recorded hole. Do not erase that durable gap merely because this
        // writer generation did not carry both Seq anchors.
        return current.holes
            .where((hole) => hole.kind == MessageHistoryHoleKind.groupSeq)
            .toList(growable: false);
      }
      final status = batchKind == MessageHistoryBatchKind.gapFill
          ? cloudProven
              ? MessageHistoryHoleStatus.retryable
              : MessageHistoryHoleStatus.cloudUnavailable
          : MessageHistoryHoleStatus.open;
      return missingSeqRanges
          .map(
            (range) => MessageHistoryHole(
              key: 'seq:${range.start}-${range.end}',
              kind: MessageHistoryHoleKind.groupSeq,
              status: status,
              startSeq: range.start,
              endSeq: range.end,
              generation: generation,
              updatedAtMs: nowMs,
            ),
          )
          .toList(growable: false);
    }
    final nonBoundaryHoles = current.holes
        .where((hole) => hole.kind != MessageHistoryHoleKind.c2cBoundary)
        .toList(growable: true);
    if (batchKind == MessageHistoryBatchKind.localSnapshot) {
      return nonBoundaryHoles;
    }
    final historyIDs = <String>{
      for (final message in history)
        if ((message.msgID?.trim() ?? '').isNotEmpty) message.msgID!.trim(),
    };
    final overlaps = historyIDs.contains(current.localOldestMsgID) ||
        historyIDs.contains(current.localNewestMsgID);
    if (overlaps) {
      return nonBoundaryHoles;
    }
    final existingBoundaryStatus = !cloudProven
        ? MessageHistoryHoleStatus.cloudUnavailable
        : batchKind == MessageHistoryBatchKind.latestWindow
            ? MessageHistoryHoleStatus.open
            : MessageHistoryHoleStatus.retryable;
    final existingBoundaryHoles = current.holes
        .where((hole) => hole.kind == MessageHistoryHoleKind.c2cBoundary)
        .where((hole) => !historyIDs.contains(hole.olderMsgID))
        .map(
          (hole) => MessageHistoryHole(
            key: hole.key,
            kind: hole.kind,
            status: existingBoundaryStatus,
            startSeq: hole.startSeq,
            endSeq: hole.endSeq,
            olderMsgID: hole.olderMsgID,
            newerMsgID: hole.newerMsgID,
            generation: generation,
            updatedAtMs: nowMs,
          ),
        )
        .toList(growable: false);
    if (batchKind != MessageHistoryBatchKind.latestWindow ||
        current.status != MessageHistoryCoverageStatus.provisional ||
        history.isEmpty ||
        current.localNewestMsgID == null) {
      return <MessageHistoryHole>[
        ...nonBoundaryHoles,
        ...existingBoundaryHoles,
      ];
    }
    final oldest = _oldestServerHistoryMessage(history);
    return <MessageHistoryHole>[
      ...nonBoundaryHoles,
      MessageHistoryHole(
        key: 'c2c:${current.localNewestMsgID}:${oldest?.msgID ?? ''}',
        kind: MessageHistoryHoleKind.c2cBoundary,
        status: cloudProven
            ? MessageHistoryHoleStatus.open
            : MessageHistoryHoleStatus.cloudUnavailable,
        olderMsgID: current.localNewestMsgID,
        newerMsgID: oldest?.msgID,
        generation: generation,
        updatedAtMs: nowMs,
      ),
    ];
  }

  V2TimMessage? _oldestServerHistoryMessage(List<V2TimMessage> messages) {
    V2TimMessage? result;
    for (final message in messages) {
      if ((message.msgID?.trim() ?? '').isEmpty) continue;
      if (result == null || compareMessagesChronological(message, result) < 0) {
        result = message;
      }
    }
    return result;
  }

  V2TimMessage? _newestServerHistoryMessage(List<V2TimMessage> messages) {
    V2TimMessage? result;
    for (final message in messages) {
      if ((message.msgID?.trim() ?? '').isEmpty) continue;
      if (result == null || compareMessagesChronological(message, result) > 0) {
        result = message;
      }
    }
    return result;
  }

  int? _messageNumericSeq(V2TimMessage? message) {
    final seq = int.tryParse(message?.seq?.trim() ?? '');
    return seq == null || seq <= 0 ? null : seq;
  }

  MessageCommitResult? failHistoryReconciliation({
    required MessageReconciliationRequest request,
    required String reason,
  }) {
    final commit = _messageReconciliationWriter.failHistory(
      request: request,
      reason: reason,
      networkState: messageReconciliationNetworkState,
    );
    if (commit == null) {
      return null;
    }
    return setMessageList(
      commit.conversationKey,
      _messageReconciliationWriter.valuesFor(commit.conversationKey),
      needResetNewMessageCount: false,
      replace: true,
      applyMemoryWindow: false,
      writerCommit: commit,
      historyCommitSource: 'reconciliation_fail:r${commit.revision}',
    );
  }

  final Map<String, int> _messageCommitGenerationByConv = {};
  final Map<String, int> _messageCommitTokenByConv = {};
  int _nextMessageCommitToken = 0;

  /// 内存窗口裁掉了较新端：下翻/回底需能再 loadLatest。
  final Map<String, bool> _memoryWindowMissingNewerByConv = {};
  final Map<String, Map<String, String>> _rowLocalAliasByConversation = {};
  final Map<String, bool> _memoryWindowMissingOlderByConv = {};
  final Map<String, int> _memoryWindowBoundaryTimestampByConv = {};
  final Map<String, String> _memoryWindowBoundarySeqByConv = {};

  /// 搜索/引用定位拉历史期间抑制窗口，避免目标被 trim 掉。
  final Set<String> _memoryWindowSuppressedConvs = {};
  String? _memoryWindowAnchorMsgID;
  String? _memoryWindowAnchorSeq;
  String? _memoryWindowAnchorConvID;
  final Map<String, SearchJumpStatus> _searchJumpStatusMap = {};
  final Object _searchJumpWorkOwner = Object();

  void _updateSearchJumpWorkGate() {
    final active = _openPageConvId;
    BackgroundMediaGate.instance.setBusy(
      _searchJumpWorkOwner,
      active != null &&
          _searchJumpStatusMap.entries.any((entry) =>
              (entry.value == SearchJumpStatus.loading ||
                  entry.value == SearchJumpStatus.positioning) &&
              _isSameConversationID(entry.key, active)),
    );
  }

  final Map<String, List<V2TimMessage>> _localMergerMessageCache = {};
  final Set<String> _initialHistoryLoadedConvs = {};
  final Map<String, bool> _mayHaveOlderHistoryByConv = {};
  final Map<String, MessageHistoryCoverage> _messageHistoryCoverageByConv =
      <String, MessageHistoryCoverage>{};
  final Set<String> _messageHistoryCoverageLoadedConvs = <String>{};
  /// 每会话每 canonical key 只向窗口库对一次 clearEpoch。
  final Set<String> _historyWindowClearEpochSyncedKeys = <String>{};
  final Map<String, Future<MessageHistoryCoverage?>>
      _messageHistoryCoverageLoadInFlight =
      <String, Future<MessageHistoryCoverage?>>{};
  final Map<String, Future<void>> _messageHistoryCoverageUpdateTailByConv =
      <String, Future<void>>{};
  final Map<String, int> _messageHistoryCoverageRequestGenerationByConv =
      <String, int>{};
  int _messageHistoryCoverageSessionGeneration = 0;

  bool _isMessageLifecycleCurrent(int generation) {
    return generation == _messageHistoryCoverageSessionGeneration;
  }

  final Map<String, Future<OpenHydrateResult>> _openHydrateInFlightByConv = {};
  // Weak keys avoid retaining abandoned page guards once a flight is evicted.
  final Expando<bool Function()> _openHydrateCanPublish =
      Expando<bool Function()>('openHydrateCanPublish');
  final Map<String, OpenHydrateResult> _openHydrateResultByConv =
      <String, OpenHydrateResult>{};
  late final WindowMessageReceiptCache _messageReadReceiptMap =
      WindowMessageReceiptCache(isLoaded: _messageListMap.containsMessage);
  final Map<String, int> _c2cPeerReadTimestampMap = {};
  final Map<String, int> _messageListProgressMap = {};
  final Map<String, String> _fileListLocationMap = {};
  final Map<String, Size> _fileMessageSizeMap = {};
  final Set<String> _cancelledOutgoingMediaIds = <String>{};
  final Map<String, dynamic> _preloadImageMap = {};
  final Map<String, HistoryMessagePosition> _historyMessagePositionMap = {};
  final List<CurrentConversation> _currentConversationList = [];
  final List<VoidCallback> _roamingSyncListeners = <VoidCallback>[];

  Map<String, dynamic> get preloadImageMap => _preloadImageMap;

  ChatLifeCycle? _lifeCycle;
  bool _isDownloading = false;
  final List<Map<String, String>> _waitingDownloadList = List.empty(
    growable: true,
  ); // example {"savePath":"","url":"",msgId:""}
  int _totalUnreadCount = 0;
  String localKeyPrefix = "TUIKit_conversation_stored_";
  String localMsgIDListKey = "TUIKit_conversation_list";

  late V2TimAdvancedMsgListener advancedMsgListener;
  final Map<String, _InboundUnreadState> _inboundUnreadStateByConversation =
      <String, _InboundUnreadState>{};
  final Map<String, int> _unreadTongueRemainingByConversation = {};
  final Map<String, bool> _unreadTongueBelowByConversation = {};
  final Map<String, int> _dismissedEntryUnreadTongueCountByConversation = {};
  int _unreadTongueMetricsVersion = 0;
  final Map<String, bool> _followingLatestByConversation = <String, bool>{};
  final Set<String> _historyReadingWindowByConversation = <String>{};
  final Map<String, ({
    void Function() freeze,
    bool Function()? canAppend,
    void Function(List<V2TimMessage>)? didAppend,
  })> _freezeHistoryReadingWindowByConversation = {};
  bool _attachingBufferedTowardLatest = false;
  int _attachingBufferedTowardLatestUntilMs = 0;
  static const int _attachBufferedTowardLatestHoldMs = 300;
  /// 超过这个距离就不再跟最新端上推。不能用 80px：靠近底部一点点也会被 pin。
  static const double _stickToLatestEpsilonPx = 24.0;
  static const double _desktopStickToLatestSlopPx = 80.0;

  // use for generate a new sliver list to show received message list
  final Set<String> _deferredUntilUserBottomConversations = <String>{};

  TIMUIKitChatConfig chatConfig = const TIMUIKitChatConfig();
  List<V2TimGroupApplication>? _groupApplicationList;
  DateTime? _lastGroupApplicationRefreshAt;
  Future<void>? _groupApplicationRefreshTask;
  Timer? _pendingGroupApplicationRefreshTimer;
  static const Duration _groupApplicationRefreshInterval = Duration(
    seconds: 20,
  );
  List<GroupSystemNoticeItem> _groupSystemNoticeList = [];
  String Function(V2TimMessage message)? _abstractMessageBuilder;
  Widget Function(
    BuildContext context,
    TextEditingController controller,
    ValueChanged<String> onChanged,
  )? _appSearchBarBuilder;
  Widget Function(BuildContext context)? _appForwardSelectFriendPage;
  Widget Function(BuildContext context)? _appForwardSelectGroupPage;
  List<V2TimConversation> Function()? _appForwardRecentConversations;
  Listenable? _appForwardRecentConversationsListenable;
  String Function(String userId, String fallbackFaceUrl)?
      _appSearchFaceUrlResolver;
  String Function(String groupId, String fallbackFaceUrl)?
      _appSearchGroupFaceUrlResolver;
  String? Function(String groupId)? _appSearchGroupNameResolver;
  SearchConversationDisplay Function({
    required String conversationId,
    V2TimFriendInfo? friendHint,
    V2TimGroupInfo? groupHint,
  })? _appSearchConversationDisplayResolver;
  Widget Function(BuildContext context, String userId, String name)?
      _appSearchNameBuilder;
  NavigatorState? Function()? _appRootNavigator;
  AppContactPresenceBridge Function(BuildContext context)?
      _appContactPresenceBridgeBuilder;
  final Map<String, int> _c2cMessageEditStatusMap = Map.from(
    {},
  ); // 0 normal 1 sending
  final Map<String, bool> _c2cMessageFromUserActiveMap = Map.from({});
  final Map<String, Timer> _c2cMessageActiveTimer = Map.from({});
  bool _showC2cMessageEditStatus = true;
  final Map<String, Timer> _c2cMessageStatusShowTimer = Map.from({});
  Map<String, List> loadingMessage = {};
  final Set<String> _messageEnterAnimationKeys = <String>{};
  final Map<String, int> _enterAnimationThrottleMarkMsByConv = <String, int>{};
  final Map<String, String> _enterAnimationThrottlePendingKeyByConv =
      <String, String>{};
  ChatSendFlyOverlayRequest? _sendFlyOverlayRequest;
  final Map<String, ScrollController> _activeChatScrollControllerMap = {};
  final Map<String, double> _mediaPreviewScrollOffsetMap = {};
  final Map<String, String> _mediaPreviewAnchorMsgIDMap = {};
  static const int _mediaPreviewRestoreLockMilliseconds = 300;
  static const int _mediaPreviewRestoreTailLockMilliseconds = 80;
  bool _isMediaPreviewOverlayOpen = false;
  int _walletOverlayDepth = 0;
  bool _isRestoringScrollAfterMediaPreview = false;
  int _mediaPreviewRestoreVersion = 0;
  int _mediaPreviewRestoreLockUntil = 0;
  int _outgoingPinScrollSuppressUntilMs = 0;
  bool _isChatListUserScrolling = false;
  int _lastChatListUserScrollEndAtMs = 0;
  int _chatOpenImageDecodeDeferUntilMs = 0;
  int _previousPageImageDecodeDeferUntilMs = 0;

  /// ScrollEnd 后短窗口：跳过入场动画，避免松手瞬间与灌消息叠峰。
  static const int postScrollSkipEnterAnimationMs = 300;

  /// 进页首屏：短暂压低气泡解码上限，削多图同屏尖刺。
  static const Duration chatOpenImageDecodeDeferTtl = Duration(
    milliseconds: 700,
  );

  /// 上滑更早一页提交后：可见新图也走逐帧解码，避免一页多图同帧尖刺。
  static const Duration previousPageImageDecodeDeferTtl = Duration(
    milliseconds: 700,
  );

  /// 松手后防抖 flush 时，缓冲条数达此阈值则走分片揭示，避免一次灌爆。
  static const int postScrollFlushChunkThreshold = 8;

  /// Open chat page SSOT for scroll UI (wired from [ChatPageUiNotifiers]).
  ValueNotifier<HistoryMessagePosition>? _openPageHistoryPosition;
  ValueNotifier<bool>? _openPageUserScrolling;
  String? _openPageConvId;
  final Map<String, int> _messageListRevisionByConv = {};
  final Map<String, int> _messageProjectionRevisionByConv = {};
  final Map<String, Set<String>> _inboundHiddenKeysByConv = {};
  final Set<String> _authoritativeDeferredIncomingKeys = <String>{};
  final Set<String> _inboundFastForwardMessageKeys = <String>{};
  final Map<String, int> _outgoingLocalSeqByConv = {};
  final Map<String, List<V2TimMessage>> _messageListDisplayCache = {};
  final Map<String, Timer> _activeReadReportDebounceMap = {};
  final Map<String, int> _lastActiveReadReportAtMs = {};
  static const int _activeReadReportDebounceMs = 1200;
  static const int _activeReadReportMinIntervalMs = 3000;
  bool _notifyPending = false;
  bool _notifyScheduled = false;
  static const int _inboundBatchMaxSize = 50;
  static const Duration _inboundBatchMaxDelay = Duration(milliseconds: 50);
  static const int _bulkMessageSyncThreshold = 2;

  /// 1s 内到达条数达到该阈值 → 洪峰：关入场动画 / 关分片揭示 / 整批提交。
  static const int _inboundFloodWindowMs = 1000;
  static const int _inboundFloodCountThreshold = 8;

  /// 单次 coalesce flush 达到该条数也视为洪峰（群刷屏一批）。
  static const int _inboundFloodBatchSizeThreshold = 6;
  final List<int> _inboundFloodArrivalMs = <int>[];
  late final MessageInboundBatchCoalescer _inboundBatchCoalescer;
  late final MessageInboundChunkedReveal _inboundChunkReveal;
  final Map<String, InboundReorderBuffer> _reorderBuffersByConv =
      <String, InboundReorderBuffer>{};
  final Set<String> _gapCatchUpInFlight = <String>{};
  final Map<String, int> _groupGapAutoAttemptAtMs = <String, int>{};
  static const int _groupGapAutoCooldownMs = 5000;
  final BoundedMessageCloudCatchUp _boundedCloudCatchUp =
      BoundedMessageCloudCatchUp();
  final Map<String, int> _cloudContinuationRoundsByConv = <String, int>{};
  final Map<String, Timer> _cloudContinuationTimersByConv = <String, Timer>{};

  /// C2C has no conversation-wide seq cursor. Keep the last stalled anchor so
  /// an automatic continuation cannot replay the same CLOUD_NEWER request.
  final Map<String, String> _cloudCatchUpStalledAnchorByConv =
      <String, String>{};
  static const String _cloudCatchUpStalledBatchKind = 'cloud_catch_up_stalled';
  static const String _cloudCatchUpUnblockedBatchKind =
      'cloud_catch_up_unblocked';
  static const int _maxAutomaticCloudContinuationRounds = 2;
  static const Duration _cloudContinuationDelay = Duration(milliseconds: 600);
  final Map<String, int> _bulkMessageSyncDepthByConv = <String, int>{};
  final Map<String, bool> _pendingPinAfterBulkByConv = <String, bool>{};
  int _inboundScrollFollowSeq = 0;
  int _inboundPresentationSupersedeSeq = 0;
  bool _inboundScrollFollowSessionEnding = false;
  List<V2TimMessage> _lastInboundScrollFollowChunk = const [];
  bool _chatAppForeground = true;
  final Map<String, bool> _wasAtBottomBeforeBackgroundByConv = <String, bool>{};
  final Map<String, bool> _wasAtBottomBeforeKeyboardViewportChangeByConv =
      <String, bool>{};
  final Map<String, int> _geometryViewportTransitionDepthByConv =
      <String, int>{};
  /// 键盘占用期内用户已真实拖拽的会话：几何闸门被用户意图覆盖，
  /// depth 配对保留，下一次几何边沿重新受保护。
  final Set<String> _geometryViewportTransitionOverriddenByDragConvs =
      <String>{};
  final Map<String, double?> _keyboardAnchorOffsetByConv = <String, double?>{};
  final Map<String, String?> _keyboardAnchorMessageIdByConv =
      <String, String?>{};
  int _suppressInboundAnimationUntilMs = 0;
  final Set<String> _inactiveInboundDirtyConvs = <String>{};
  Timer? _inactiveInboundNotifyTimer;
  static const Duration _inactiveInboundNotifyDelayIdle = Duration(
    milliseconds: 80,
  );
  static const Duration _inactiveInboundNotifyDelayFlood = Duration(
    milliseconds: 250,
  );

  bool get isChatListUserScrolling =>
      _openPageUserScrolling?.value ?? _isChatListUserScrolling;

  /// 几何视口过渡（键盘 / 直播条 / SafeArea / resize）：不是用户离底。
  void beginGeometryViewportTransition(String conversationID) {
    beginKeyboardViewportTransition(conversationID);
  }

  void endGeometryViewportTransition(String conversationID) {
    endKeyboardViewportTransition(conversationID);
  }

  bool isGeometryViewportTransitionActive(String conversationID) {
    final key = _inboundStateKey(conversationID);
    if (key.isEmpty) {
      return false;
    }
    return (_geometryViewportTransitionDepthByConv[key] ?? 0) > 0 &&
        !_geometryViewportTransitionOverriddenByDragConvs.contains(key);
  }

  /// 键盘占用窗口时，viewport 变矮会被误判为"正在看历史"。
  /// 只在 occupied 边沿打快照；离开时不 jump / 不 pin。
  void beginKeyboardViewportTransition(String conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty || !_isSameConversationID(convId, currentSelectedConv)) {
      return;
    }
    final key = _inboundStateKey(convId);
    _geometryViewportTransitionDepthByConv[key] =
        (_geometryViewportTransitionDepthByConv[key] ?? 0) + 1;
    _geometryViewportTransitionOverriddenByDragConvs.remove(key);
    _wasAtBottomBeforeKeyboardViewportChangeByConv.putIfAbsent(
      key,
      () => isFollowingLatest(convId),
    );
    _keyboardAnchorOffsetByConv.putIfAbsent(
      key,
      () => _snapshotKeyboardAnchorOffset(convId),
    );
    _keyboardAnchorMessageIdByConv.putIfAbsent(
      key,
      () => _snapshotKeyboardAnchorMessageId(convId),
    );
  }

  double? _snapshotKeyboardAnchorOffset(String convId) {
    final controller = _activeChatScrollControllerMap[convId];
    final position =
        controller == null ? null : _singleScrollPositionOrNull(controller);
    if (position == null || !position.hasPixels) {
      return null;
    }
    return position.pixels;
  }

  String? _snapshotKeyboardAnchorMessageId(String convId) {
    final list = getMessageList(convId);
    if (list == null || list.isEmpty) {
      return null;
    }
    return list.first.msgID;
  }

  bool _wasAtBottomBeforeKeyboardViewportChange(String conversationID) {
    if (isSearchJumpPending(conversationID)) return false;
    return _wasAtBottomBeforeKeyboardViewportChangeByConv[_inboundStateKey(
          conversationID,
        )] ==
        true;
  }

  void endKeyboardViewportTransition(String conversationID) {
    _finishKeyboardViewportTransition(conversationID);
  }

  void _finishKeyboardViewportTransition(String conversationID) {
    final key = _inboundStateKey(conversationID);
    final remaining =
        (_geometryViewportTransitionDepthByConv[key] ?? 0) - 1;
    if (remaining > 0) {
      _geometryViewportTransitionDepthByConv[key] = remaining;
      return;
    }
    _geometryViewportTransitionDepthByConv.remove(key);
    _geometryViewportTransitionOverriddenByDragConvs.remove(key);
    final wasBottom =
        _wasAtBottomBeforeKeyboardViewportChangeByConv[key] == true;
    _wasAtBottomBeforeKeyboardViewportChangeByConv.remove(key);
    _keyboardAnchorOffsetByConv.remove(key);
    _keyboardAnchorMessageIdByConv.remove(key);
    if (wasBottom) {
      setFollowingLatest(conversationID, true, notify: false);
    }
  }

  void _clearKeyboardViewportTransition(String conversationID) {
    final key = _inboundStateKey(conversationID);
    _wasAtBottomBeforeKeyboardViewportChangeByConv.remove(key);
    _keyboardAnchorOffsetByConv.remove(key);
    _keyboardAnchorMessageIdByConv.remove(key);
  }

  /// 用户真实拖拽 = 明确离底意图；覆盖键盘占用期的几何闸门，但保留 depth
  /// 配对（键盘收起时的 end 仍能正常归零）。
  void noteUserDragOverridesGeometryViewportTransition(String conversationID) {
    final key = _inboundStateKey(conversationID);
    if (key.isEmpty ||
        (_geometryViewportTransitionDepthByConv[key] ?? 0) <= 0) {
      return;
    }
    _geometryViewportTransitionOverriddenByDragConvs.add(key);
  }

  /// 离开会话：键盘协调器 dispose / 切会话 reset 不会补发 onEnd，
  /// depth 必须在此归零，否则下次进入该会话几何闸门永久生效。
  void _resetGeometryViewportTransition(String conversationID) {
    final key = _inboundStateKey(conversationID);
    _geometryViewportTransitionDepthByConv.remove(key);
    _geometryViewportTransitionOverriddenByDragConvs.remove(key);
    _clearKeyboardViewportTransition(conversationID);
  }

  /// 进页揭开后短窗口：列表气泡走 scroll-tier 解码预算。
  void beginChatOpenImageDecodeDefer({
    Duration ttl = chatOpenImageDecodeDeferTtl,
  }) {
    final until = DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;
    if (until > _chatOpenImageDecodeDeferUntilMs) {
      _chatOpenImageDecodeDeferUntilMs = until;
    }
  }

  bool get isChatOpenImageDecodeDeferActive {
    if (_chatOpenImageDecodeDeferUntilMs <= 0) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= _chatOpenImageDecodeDeferUntilMs) {
      _chatOpenImageDecodeDeferUntilMs = 0;
      return false;
    }
    return true;
  }

  void beginPreviousPageImageDecodeDefer({
    Duration ttl = previousPageImageDecodeDeferTtl,
  }) {
    final until = DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;
    if (until > _previousPageImageDecodeDeferUntilMs) {
      _previousPageImageDecodeDeferUntilMs = until;
    }
  }

  bool get isPreviousPageImageDecodeDeferActive {
    if (_previousPageImageDecodeDeferUntilMs <= 0) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= _previousPageImageDecodeDeferUntilMs) {
      _previousPageImageDecodeDeferUntilMs = 0;
      return false;
    }
    return true;
  }

  /// 用户正在滑，或刚松手后的短窗口（用于跳过进场动画等）。
  bool get shouldSkipHeavyChatListPresentation {
    if (isPreviousPageImageDecodeDeferActive) {
      return true;
    }
    if (isChatOpenImageDecodeDeferActive) {
      return true;
    }
    if (isChatListUserScrolling) {
      return true;
    }
    if (_lastChatListUserScrollEndAtMs <= 0) {
      return _shouldDeferHeavyBubbleDecodeForAndroidHistory();
    }
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - _lastChatListUserScrollEndAtMs;
    if (elapsed >= 0 && elapsed < postScrollSkipEnterAnimationMs) {
      return true;
    }
    return _shouldDeferHeavyBubbleDecodeForAndroidHistory();
  }

  bool _shouldDeferHeavyBubbleDecodeForAndroidHistory() {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }
    final convId = currentSelectedConv.trim();
    if (convId.isEmpty) {
      return false;
    }
    if (isReadingHistory(convId)) {
      return true;
    }
    // 不在底部时推迟离屏图片解码，避免浏览历史/未读时主线程尖刺。
    return !_isActiveChatNearBottom(convId);
  }

  int deferredIncomingBufferedCount(String conversationID) {
    return _inboundUnreadStateFor(
      conversationID,
      create: false,
    ).bufferedMessages.length;
  }

  /// 后台期间缓冲、尚未合并进可见列表的新消息（含 deferred 闸门）。
  bool hasDeferredIncomingForResume(String? conversationID) {
    final convId = _safeConversationId(conversationID ?? currentSelectedConv);
    if (convId.isEmpty) {
      return false;
    }
    for (final key in _historyFlagKeys(convId)) {
      final normalized = _inboundStateKey(key);
      if (_deferredUntilUserBottomConversations.contains(normalized)) {
        return true;
      }
      if (deferredIncomingBufferedCount(key) > 0) {
        return true;
      }
    }
    return false;
  }

  /// 回前台：贴底合并并清计数；最新窗离底灌列表保留计数；缺口窗保留 buffer。
  void reconcileActiveChatAfterForegroundResume({int attempt = 0}) {
    final convId = currentSelectedConv.trim();
    if (convId.isEmpty || !_chatAppForeground) {
      return;
    }
    if (!hasDeferredIncomingForResume(convId)) {
      return;
    }
    final normalizedConvId = _inboundStateKey(convId);
    final wasAtBottomBeforeBackground =
        _wasAtBottomBeforeBackgroundByConv[normalizedConvId];
    final followingLatest = isFollowingLatest(convId);
    final controller = _activeChatScrollControllerMap[convId];
    final scrollReady = controller != null &&
        controller.hasClients &&
        controller.positions.isNotEmpty;
    if (wasAtBottomBeforeBackground == null && !scrollReady && attempt < 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        reconcileActiveChatAfterForegroundResume(attempt: attempt + 1);
      });
      return;
    }
    final isHistoryGap = hasDurableHistoryDeferred(convId) ||
        memoryWindowMissingNewer(convId) ||
        isSearchJumpPending(convId);
    final wasReadingAway = wasAtBottomBeforeBackground == false ||
        (wasAtBottomBeforeBackground == null && !followingLatest);
    if (isHistoryGap && wasReadingAway) {
      ChatJitterDiag.logInboundFlow(
        action: 'resume_reconcile_keep_buffer',
        conv: convId,
        extras: <String, Object?>{
          'buffered': deferredIncomingBufferedCount(convId),
          'attempt': attempt,
          'wasAtBottomBeforeBackground': wasAtBottomBeforeBackground,
        },
      );
      return;
    }
    if (wasAtBottomBeforeBackground == true ||
        (wasAtBottomBeforeBackground == null && followingLatest)) {
      _mergeDeferredIncomingAfterBackgroundResume(convId);
    } else {
      _mergeDeferredIncomingPreserveViewport(convId);
    }
    _wasAtBottomBeforeBackgroundByConv.remove(normalizedConvId);
  }

  void _mergeDeferredIncomingAfterBackgroundResume(String conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    if (hasDurableHistoryDeferred(convId)) {
      _storeHistoryMessagePosition(
          convId, HistoryMessagePosition.notShowLatest);
      _markNeedsNotify();
      return;
    }
    for (final key in _historyFlagKeys(convId)) {
      _deferredUntilUserBottomConversations.remove(_inboundStateKey(key));
    }
    _storeHistoryMessagePosition(convId, HistoryMessagePosition.bottom);
    flushDeferredIncomingMessages(convId, notify: false, userInitiated: true);
    unlockEntryUnreadForTongue(conversationID: convId, notify: false);
    clearReceivedUnreadState(conversationID: convId, notify: false);
    ChatJitterDiag.logInboundFlow(
      action: 'resume_reconcile_merged',
      conv: convId,
      extras: <String, Object?>{
        'listLen':
            _messageListMap[_resolveMessageListStorageKey(convId)]?.length,
      },
    );
    _markNeedsNotify();
  }

  void _mergeDeferredIncomingPreserveViewport(String conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    if (hasDurableHistoryDeferred(convId)) {
      _storeHistoryMessagePosition(
          convId, HistoryMessagePosition.notShowLatest);
      _markNeedsNotify();
      return;
    }
    for (final key in _historyFlagKeys(convId)) {
      _deferredUntilUserBottomConversations.remove(_inboundStateKey(key));
    }
    flushDeferredIncomingMessages(convId, notify: false, userInitiated: true);
    _syncHistoryPositionFromActiveScroll(convId);
    ChatJitterDiag.logInboundFlow(
      action: 'resume_reconcile_merged_preserve_viewport',
      conv: convId,
      extras: <String, Object?>{
        'listLen':
            _messageListMap[_resolveMessageListStorageKey(convId)]?.length,
        'received': receivedNewMessageCountFor(convId),
      },
    );
    _markNeedsNotify();
  }

  void _pruneInboundFloodWindow([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _inboundFloodArrivalMs.removeWhere((t) => now - t > _inboundFloodWindowMs);
  }

  void _noteInboundFloodArrivals(int count) {
    if (count <= 0) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < count; i++) {
      _inboundFloodArrivalMs.add(now);
    }
    if (_inboundFloodArrivalMs.length > 96) {
      _inboundFloodArrivalMs.removeRange(0, _inboundFloodArrivalMs.length - 96);
    }
    _pruneInboundFloodWindow(now);
  }

  /// 消息洪峰：短时高频入站，动画与分片揭示应让路给吞吐。
  bool get isInboundFloodActive {
    _pruneInboundFloodWindow();
    return _inboundFloodArrivalMs.length >= _inboundFloodCountThreshold;
  }

  /// Bind the open history list's page UI notifiers as SSOT for scroll flags.
  void attachOpenChatPageUi({
    required String conversationId,
    required ValueNotifier<HistoryMessagePosition> historyPosition,
    required ValueNotifier<bool> userScrolling,
  }) {
    final convId = _safeConversationId(conversationId);
    _openPageConvId = convId;
    _updateSearchJumpWorkGate();
    _openPageHistoryPosition = historyPosition;
    _openPageUserScrolling?.removeListener(_updateMediaScrollGate);
    _openPageUserScrolling = userScrolling;
    userScrolling.addListener(_updateMediaScrollGate);
    final seeded =
        _historyMessagePositionMap[convId] ?? HistoryMessagePosition.bottom;
    if (historyPosition.value != seeded) {
      historyPosition.value = seeded;
    }
    userScrolling.value = false;
    _isChatListUserScrolling = false;
    _updateMediaScrollGate();
    if (!isSearchJumpPending(convId)) {
      beginOpenChatBottomCapsuleLock(convId);
    }
  }

  void detachOpenChatPageUi({
    required ValueNotifier<HistoryMessagePosition> historyPosition,
    required ValueNotifier<bool> userScrolling,
  }) {
    if (!identical(_openPageHistoryPosition, historyPosition)) {
      return;
    }
    final convId = _openPageConvId;
    if (convId != null && convId.isNotEmpty) {
      _historyMessagePositionMap[convId] = historyPosition.value;
    }
    _openPageHistoryPosition = null;
    _openPageUserScrolling?.removeListener(_updateMediaScrollGate);
    _openPageUserScrolling = null;
    BackgroundMediaGate.instance.setBusy(this, false);
    _openPageConvId = null;
    _updateSearchJumpWorkGate();
    _isChatListUserScrolling = false;
    if (convId != null && convId.isNotEmpty) {
      clearOpenChatBottomCapsuleLock(convId);
    }
  }

  void _storeHistoryMessagePosition(
    String conversationID,
    HistoryMessagePosition position,
  ) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    if (position == HistoryMessagePosition.bottom &&
        (isSearchJumpPending(convId) ||
            (memoryWindowMissingNewer(convId) &&
                !isUserScrollToBottomInProgress(convId)))) {
      return;
    }
    _historyMessagePositionMap[convId] = position;
    final page = _openPageHistoryPosition;
    final pageConv = _openPageConvId;
    if (page != null &&
        pageConv != null &&
        _isSameConversationID(convId, pageConv) &&
        page.value != position) {
      page.value = position;
    }
    if (position == HistoryMessagePosition.bottom) {
      final state = _messageReconciliationWriter.coordinator.stateFor(convId);
      if (state.cloudHasMoreNewer) {
        _scheduleCloudContinuation(convId);
      }
    }
  }

  bool get shouldAnimateInboundPresentation =>
      _chatAppForeground &&
      DateTime.now().millisecondsSinceEpoch >=
          _suppressInboundAnimationUntilMs &&
      !isInboundFloodActive;

  void setChatAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _chatAppForeground;
    final foreground = state == AppLifecycleState.resumed;
    final convId = currentSelectedConv.trim();
    if (wasForeground && !foreground && convId.isNotEmpty) {
      _syncHistoryPositionFromActiveScroll(convId);
      final normalizedConvId = _inboundStateKey(convId);
      final logicalPosition = getMessageListPosition(convId);
      _wasAtBottomBeforeBackgroundByConv[normalizedConvId] =
          _isActiveChatNearBottom(convId) ||
              logicalPosition == HistoryMessagePosition.bottom;
    }
    _chatAppForeground = foreground;
    if (foreground && !wasForeground) {
      // Resume recovery may merge a large server-side backlog over several
      // asynchronous callbacks. Treat that window as synchronization, not as
      // a sequence of newly arriving foreground messages.
      _suppressInboundAnimationUntilMs =
          DateTime.now().millisecondsSinceEpoch + 5000;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        reconcileActiveChatAfterForegroundResume();
        if (convId.isNotEmpty) {
          unawaited(
            reconcileConversationCloud(convId, reason: 'app_foreground'),
          );
        }
      });
    }

    if (convId.isNotEmpty && !foreground) {
      // Rows not yet presented stay deferred. Do not reveal the queue while
      // transitioning to background, otherwise it will be replayed on resume.
      _inboundChunkReveal.cancelToBuffer(convId);
    }
    _messageEnterAnimationKeys.clear();
    // paused/hidden 阶段不重建仍在树上的长消息列表；resumed 会统一通知。
    if (foreground) {
      _markNeedsNotify();
    }
  }

  bool isBulkMessageSyncActive([String? conversationID]) {
    if (conversationID != null) {
      final convId = _safeConversationId(conversationID);
      return (_bulkMessageSyncDepthByConv[convId] ?? 0) > 0;
    }
    return _bulkMessageSyncDepthByConv.values.any((depth) => depth > 0);
  }

  void _beginBulkMessageSync(String conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    _bulkMessageSyncDepthByConv[convId] =
        (_bulkMessageSyncDepthByConv[convId] ?? 0) + 1;
    ChatJitterDiag.log(
      'bulk_message_sync_begin',
      conv: convId,
      extras: <String, Object?>{'depth': _bulkMessageSyncDepthByConv[convId]},
    );
  }

  void _endBulkMessageSync(String conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    final next = (_bulkMessageSyncDepthByConv[convId] ?? 0) - 1;
    if (next <= 0) {
      _bulkMessageSyncDepthByConv.remove(convId);
    } else {
      _bulkMessageSyncDepthByConv[convId] = next;
    }
    ChatJitterDiag.log(
      'bulk_message_sync_end',
      conv: convId,
      extras: <String, Object?>{
        'depth': _bulkMessageSyncDepthByConv[convId] ?? 0,
      },
    );
    _flushDeferredPinToBottom(convId);
  }

  void _flushDeferredPinToBottom(String conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    if (!isBulkMessageSyncActive(convId) &&
        !isChunkedRevealActive(convId) &&
        (_pendingPinAfterBulkByConv.remove(convId) ?? false)) {
      requestPinToBottom(convId, force: true);
    }
  }

  bool isChunkedRevealActive([String? conversationID]) {
    if (conversationID != null) {
      return _inboundChunkReveal.isActiveFor(conversationID);
    }
    return _inboundChunkReveal.pendingCountFor(currentSelectedConv) > 0 ||
        _inboundChunkReveal.isActiveFor(currentSelectedConv);
  }

  /// Cancels presentation-only inbound work before an authoritative history
  /// replacement reveals the complete projection.
  void cancelInboundProjectionRevealForAuthoritativeReplace(
    String conversationID,
  ) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    _inboundChunkReveal.cancelForAuthoritativeReplace(conversationID);
    if (storageKey.isNotEmpty && storageKey != conversationID.trim()) {
      _inboundChunkReveal.cancelForAuthoritativeReplace(storageKey);
    }
  }

  /// Acknowledges that the message list finished laying out and animating the
  /// currently revealed projection group. The next group is not exposed until
  /// this acknowledgement, so burst traffic can never stack row controllers.
  void completeInboundProjectionReveal(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      _inboundChunkReveal.completeCurrentReveal(conversationID);
      return;
    }
    _inboundChunkReveal.completeCurrentReveal(
      _resolveMessageListStorageKey(conversationID),
    );
  }

  bool isInboundProjectionRevealWaiting(String conversationID) =>
      _inboundChunkReveal.isWaitingForTransaction(conversationID);

  int pendingInboundProjectionCount(String conversationID) =>
      _inboundChunkReveal.pendingCountFor(conversationID);

  bool consumeInboundFastForwardFlag(V2TimMessage message) {
    return _inboundFastForwardMessageKeys.remove(messageDedupKey(message));
  }

  void cancelInboundProjectionRevealToBuffer(String conversationID) {
    _inboundChunkReveal.cancelToBuffer(conversationID);
  }

  @Deprecated('Use isChunkedRevealActive')
  bool isPacedRevealActive([String? conversationID]) =>
      isChunkedRevealActive(conversationID);

  int get inboundScrollFollowSeq => _inboundScrollFollowSeq;

  /// Bumped when paced reveal cancels an in-flight push so only the newest
  /// message keeps its animation. Message list should abort without acking.
  int get inboundPresentationSupersedeSeq => _inboundPresentationSupersedeSeq;

  bool get inboundScrollFollowSessionEnding =>
      _inboundScrollFollowSessionEnding;

  List<V2TimMessage> get lastInboundScrollFollowChunk =>
      _lastInboundScrollFollowChunk;

  int messageListRevisionFor(String conversationID) {
    final key = canonicalHistoryStorageKey(conversationID);
    return _messageListRevisionByConv[key.isNotEmpty ? key : conversationID] ??
        0;
  }

  int messageProjectionRevisionFor(String conversationID) =>
      _messageProjectionRevisionByConv[_inboundStateKey(conversationID)] ?? 0;

  /// Privacy-safe counts for diagnosing authority -> projection -> render
  /// discontinuities. Message content is intentionally excluded.
  Map<String, Object?> historyProjectionDiagnostics(String conversationID) {
    final convKey = _inboundStateKey(conversationID);
    final authoritative = _collectAuthoritativeMessages(conversationID);
    final hidden = _inboundHiddenKeysByConv[convKey] ?? const <String>{};
    final unreadState = _inboundUnreadStateFor(convKey, create: false);
    final displayKey = canonicalHistoryStorageKey(conversationID);
    final display = _messageListDisplayCache[
        displayKey.isNotEmpty ? displayKey : conversationID];
    return <String, Object?>{
      'authorityCount': authoritative.length,
      'hiddenCount': hidden.length,
      'projectedCount': authoritative
          .where((message) => !hidden.contains(messageDedupKey(message)))
          .length,
      'displayCount':
          display?.where((message) => message.elemType != 11).length,
      'displayDividerCount':
          display?.where((message) => message.elemType == 11).length,
      'displayCacheHit': display != null,
      'bufferedCount': unreadState.bufferedMessages.length,
      'tongueUnread': unreadState.unreadCount,
      'lockedEntryUnread': unreadState.lockedEntryUnreadCount,
      'pendingReveal': pendingInboundProjectionCount(convKey),
      'revealWaiting': isInboundProjectionRevealWaiting(convKey),
      'listRevision': messageListRevisionFor(conversationID),
      'projectionRevision': messageProjectionRevisionFor(convKey),
      'position': getMessageListPosition(conversationID).name,
      'deferredUntilBottom': _deferredUntilUserBottomConversations.contains(
        convKey,
      ),
    };
  }

  String _authoritativeDeferredKey(
    String conversationID,
    V2TimMessage message,
  ) {
    final normalized = _normalizeConversationID(conversationID);
    final convKey = normalized.isEmpty ? conversationID : normalized;
    return '$convKey|${messageDedupKey(message)}';
  }

  void _revealDeferredProjectionAcrossAliases(
    String conversationID,
    Iterable<V2TimMessage> messages,
  ) {
    final snapshot = List<V2TimMessage>.from(messages);
    if (snapshot.isEmpty) {
      return;
    }
    _revealInboundProjectionChunk(conversationID, snapshot);
    final pendingKeys = snapshot.map(messageDedupKey).toSet();
    for (final alias in List<String>.from(_inboundHiddenKeysByConv.keys)) {
      if (alias == conversationID) {
        continue;
      }
      final hidden = _inboundHiddenKeysByConv[alias];
      if (hidden == null || !hidden.any(pendingKeys.contains)) {
        continue;
      }
      _revealInboundProjectionChunk(alias, snapshot);
    }
  }

  void _hideInboundProjection(
    String conversationID,
    Iterable<V2TimMessage> messages,
  ) {
    final convKey = _inboundStateKey(conversationID);
    final hidden = _inboundHiddenKeysByConv.putIfAbsent(
      convKey,
      () => <String>{},
    );
    for (final message in messages) {
      hidden.add(messageDedupKey(message));
    }
  }

  bool _revealInboundProjectionChunk(
    String conversationID,
    Iterable<V2TimMessage> messages,
  ) {
    final convKey = _inboundStateKey(conversationID);
    final hidden = _inboundHiddenKeysByConv[convKey];
    if (hidden == null || hidden.isEmpty) {
      return false;
    }
    var changed = false;
    for (final message in messages) {
      final removed = hidden.remove(messageDedupKey(message));
      changed = removed || changed;
    }
    if (hidden.isEmpty) {
      _inboundHiddenKeysByConv.remove(convKey);
    }
    if (changed) {
      _bumpMessageProjectionRevisionFor(convKey);
    }
    return changed;
  }

  bool _revealAllInboundProjection(String conversationID) {
    final convKey = _inboundStateKey(conversationID);
    final hidden = _inboundHiddenKeysByConv.remove(convKey);
    _authoritativeDeferredIncomingKeys.removeWhere(
      (key) => key.startsWith('$convKey|'),
    );
    if (hidden == null || hidden.isEmpty) {
      return false;
    }
    _bumpMessageProjectionRevisionFor(convKey);
    return true;
  }

  bool _revealAllDeferredProjectionAcrossAliases(String conversationID) {
    var changed = false;
    final aliases = List<String>.from(_inboundHiddenKeysByConv.keys);
    for (final alias in aliases) {
      if (_isSameConversationID(alias, conversationID)) {
        changed = _revealAllInboundProjection(alias) || changed;
      }
    }
    // Also clears authoritative deferred keys when no projection alias remains.
    changed = _revealAllInboundProjection(conversationID) || changed;
    return changed;
  }

  void _bumpMessageProjectionRevisionFor(String conversationID) {
    final convKey = _inboundStateKey(conversationID);
    // Visibility changes independently of message IDs (hidden -> revealed).
    // Callers invoke this only after mutating projection state.
    _messageProjectionRevisionByConv[convKey] =
        (_messageProjectionRevisionByConv[convKey] ?? 0) + 1;
    _messageListDisplayCache.removeWhere(
      (key, _) => _isSameConversationID(key, convKey),
    );
  }

  void _invalidateMessageListDisplayCache(String conversationID) {
    _messageListDisplayCache.removeWhere(
      (key, _) => _isSameConversationID(key, conversationID),
    );
  }

  void _bumpMessageListRevisionFor(
    String conversationID, {
    String reason = '',
  }) {
    final canonical = canonicalHistoryStorageKey(conversationID);
    final revisionKey = canonical.isNotEmpty ? canonical : conversationID;
    final next = (_messageListRevisionByConv[revisionKey] ?? 0) + 1;
    _messageListRevisionByConv[revisionKey] = next;
    // 与投影 revision 一致：按等价会话 ID 清展示缓存，避免群 ID 别名打空洞。
    _messageListDisplayCache.removeWhere(
      (key, _) => _isSameConversationID(key, conversationID),
    );
    // 仅「绕过 setMessageList 的原地改表」清签名，迫使下次 setMessageList 再比对。
    // setMessageList 自己 bump 时绝不能清：否则刚写入的签名立刻失效，
    // 进页 hydrate / loadLatest 原样回写会每次都 signatureChanged→再 bump→整表抖。
    final fromSetMessageList = reason == 'setMessageList_signature' ||
        reason == 'setMessageList_delete';
    if (!fromSetMessageList) {
      _messageListContentSignatureByConv.remove(revisionKey);
    }
    ChatJitterDiag.log(
      'message_list_revision_bump',
      conv: conversationID,
      extras: <String, Object?>{
        'rev': next,
        'reason': reason.isEmpty ? 'unspecified' : reason,
        'stack': ChatJitterDiag.compactStack(),
      },
    );
  }

  void _scheduleNotifyListeners() {
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    // 洪峰时并到下一帧，避免同帧多次 microtask → 整表 setState 连打。
    void flush() {
      _notifyScheduled = false;
      if (!_notifyPending) {
        return;
      }
      // 相册是不透明路由。覆盖期间继续通知会让底层长消息列表在不可见时
      // 反复 rebuild，并与 PhotoKit 缩略图解码争抢 raster/主线程。
      // 保留 pending，关闭相册后由 endMediaPickerOverlay 一次性刷新。
      if (isMediaPickerOverlayOpen) {
        return;
      }
      _notifyPending = false;
      notifyListeners();
    }

    if (isInboundFloodActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => flush());
      // Buffered arrivals do not otherwise dirty the list. Schedule the frame
      // so the unread capsule still updates while the reader is stationary.
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      scheduleMicrotask(flush);
    }
  }

  void _markNeedsNotify({String? conversationID}) {
    if (conversationID != null &&
        currentSelectedConv.trim().isNotEmpty &&
        !_isSameConversationID(conversationID, currentSelectedConv)) {
      return;
    }
    _notifyPending = true;
    if (isMediaPickerOverlayOpen) {
      return;
    }
    _scheduleNotifyListeners();
  }

  void _scheduleInactiveInboundPresentationCommit(String convID) {
    final storageKey = _resolveMessageListStorageKey(convID);
    if (storageKey.isEmpty) {
      return;
    }
    _inactiveInboundDirtyConvs.add(storageKey);
    _inactiveInboundNotifyTimer?.cancel();
    final delay = isInboundFloodActive
        ? _inactiveInboundNotifyDelayFlood
        : _inactiveInboundNotifyDelayIdle;
    _inactiveInboundNotifyTimer = Timer(delay, () {
      _inactiveInboundNotifyTimer = null;
      _flushInactiveInboundPresentationCommits();
    });
  }

  void _flushInactiveInboundPresentationCommits() {
    _inactiveInboundNotifyTimer?.cancel();
    _inactiveInboundNotifyTimer = null;
    if (_inactiveInboundDirtyConvs.isEmpty) {
      return;
    }
    final convs = List<String>.from(_inactiveInboundDirtyConvs);
    _inactiveInboundDirtyConvs.clear();
    for (final convId in convs) {
      _bumpMessageListRevisionFor(
        convId,
        reason: 'inbound_batch_inactive_coalesced',
      );
    }
    final activeConvId = currentSelectedConv.trim();
    final touchesActiveConversation = activeConvId.isNotEmpty &&
        convs.any((convId) => _isSameConversationID(convId, activeConvId));
    // 当前聊天打开时，其他会话的消息只更新各自 revision；不要广播全局
    // notify 掀翻正在显示的长消息列表。切入该会话时会直接读取最新 map。
    if (activeConvId.isEmpty || touchesActiveConversation) {
      _markNeedsNotify();
    }
  }

  void flushInactiveInboundPresentationForConversation(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    if (storageKey.isEmpty) {
      return;
    }
    if (!_inactiveInboundDirtyConvs.remove(storageKey)) {
      return;
    }
    if (_inactiveInboundDirtyConvs.isEmpty) {
      _inactiveInboundNotifyTimer?.cancel();
      _inactiveInboundNotifyTimer = null;
    }
    _bumpMessageListRevisionFor(
      storageKey,
      reason: 'inbound_batch_inactive_open',
    );
    _markNeedsNotify();
  }

  /// 回前台合并缓冲后再跑 history refresh，避免与 deferred merge 抢写列表。
  Future<void> prepareForegroundChatRecovery() async {
    reconcileActiveChatAfterForegroundResume();
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  bool isOutgoingMediaCancelled(String? id) {
    if (id == null || id.isEmpty) {
      return false;
    }
    return _cancelledOutgoingMediaIds.contains(id);
  }

  void markOutgoingMediaCancelled(String? id) {
    if (id != null && id.isNotEmpty) {
      _cancelledOutgoingMediaIds.add(id);
    }
  }

  void clearOutgoingMediaCancelled(String? id) {
    if (id != null && id.isNotEmpty) {
      _cancelledOutgoingMediaIds.remove(id);
    }
  }

  int _normalizedOutgoingStatus(V2TimMessage item, int? fallback) {
    return OutgoingSendStatus.normalize(
      status: item.status,
      fallback: fallback,
      msgID: item.msgID,
    );
  }

  V2TimMessage? _messageInConversation(
    String conversationID, {
    String? clientId,
    String? msgID,
  }) {
    final list = rawMessageList(conversationID);
    if (list == null || list.isEmpty) {
      return null;
    }
    final index = _identityLookupFor(list);
    if (index != null) {
      final byClient = clientId == null ? null : index.clientIDs[clientId];
      final byServer = msgID == null ? null : index.serverIDs[msgID];
      final position = byClient == null
          ? byServer
          : byServer == null
              ? byClient
              : min(byClient, byServer);
      return position == null ? null : list[position];
    }
    for (final item in list) {
      if (clientId != null &&
          clientId.isNotEmpty &&
          item.id != null &&
          item.id == clientId) {
        return item;
      }
      if (msgID != null &&
          msgID.isNotEmpty &&
          item.msgID != null &&
          item.msgID == msgID) {
        return item;
      }
    }
    return null;
  }

  int _receiptTimestamp(int value) {
    if (value > 1000000000000) {
      return value ~/ 1000;
    }
    return value;
  }

  V2TimMessage? messageInConversationByKey(
    String conversationID,
    String messageKey,
  ) {
    final key = messageKey.trim();
    if (key.isEmpty) {
      return null;
    }
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final list = _messageListMap[storageKey];
    if (list == null || list.isEmpty) {
      return null;
    }
    final resolvedKey = _rowLocalAliasByConversation[storageKey]?[key] ?? key;
    final index = _identityLookupFor(list);
    if (index != null) {
      var position = index.rowKeys[resolvedKey];
      // Anonymous timestamp/sender keys have no SDK identity epoch. Keep
      // their small compatibility lane live rather than caching mutable data.
      for (final anonymous in index.anonymousIndices) {
        if ((position == null || anonymous < position) &&
            ChatUiStateStore.messageKeyOf(list[anonymous]) == resolvedKey) {
          position = anonymous;
          break;
        }
      }
      return position == null ? null : list[position];
    }
    for (final item in list) {
      if (item.msgID == resolvedKey || item.id == resolvedKey) {
        return item;
      }
      final seq = item.seq?.trim();
      if (seq != null && seq.isNotEmpty && 'seq_$seq' == resolvedKey) {
        return item;
      }
      if (ChatUiStateStore.messageKeyOf(item) == resolvedKey) {
        return item;
      }
    }
    return null;
  }

  bool _messageMatchesRowIdentity(
    V2TimMessage message,
    Set<String> identities,
  ) {
    if (identities.isEmpty) {
      return false;
    }
    final values = <String>{
      ChatUiStateStore.messageKeyOf(message).trim(),
      message.id?.trim() ?? '',
      message.msgID?.trim() ?? '',
      readOutgoingStableId(message)?.trim() ?? '',
      if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE)
        message.imageElem?.path?.trim() ?? '',
    }..remove('');
    return values.any(identities.contains);
  }

  void _rememberRowLocalAliases(
    String storageKey,
    Iterable<String?> aliases,
    String targetKey,
  ) {
    final target = targetKey.trim();
    if (target.isEmpty) {
      return;
    }
    final map = _rowLocalAliasByConversation.putIfAbsent(
      storageKey,
      () => <String, String>{},
    );
    final normalizedAliases = aliases
        .map((value) => value?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
    final chainedSources = map.entries
        .where((entry) => normalizedAliases.contains(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final source in chainedSources) {
      map[source] = target;
    }
    for (final value in normalizedAliases) {
      if (value.isNotEmpty && value != target) {
        map[value] = target;
      }
    }
    while (map.length > 512) {
      map.remove(map.keys.first);
    }
  }

  /// Resolves exactly one row through the outgoing stable identity chain.
  /// Missing/ambiguous identities, semantic changes and reordering are never
  /// guessed: callers must keep their full-list fallback for those results.
  RowLocalMessageReplacementResult replaceMessageRowByStableIdentity({
    required String conversationID,
    required String stableIdentity,
    required V2TimMessage replacement,
    Iterable<String?> aliases = const <String?>[],
  }) {
    final primary = stableIdentity.trim();
    if (primary.isEmpty) {
      return RowLocalMessageReplacementResult.notFound;
    }
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final current = _messageListMap[storageKey];
    if (current == null || current.isEmpty) {
      return RowLocalMessageReplacementResult.notFound;
    }
    final identities = <String>{primary};
    for (final alias in aliases) {
      final value = alias?.trim() ?? '';
      if (value.isNotEmpty) {
        identities.add(value);
      }
    }
    final matches = <int>[];
    for (var index = 0; index < current.length; index++) {
      if (_messageMatchesRowIdentity(current[index], identities)) {
        matches.add(index);
      }
    }
    if (matches.isEmpty) {
      return RowLocalMessageReplacementResult.notFound;
    }
    if (matches.length != 1) {
      return RowLocalMessageReplacementResult.ambiguous;
    }
    final index = matches.single;
    final expected = current[index];
    if (expected.elemType != replacement.elemType ||
        expected.isSelf != replacement.isSelf) {
      return RowLocalMessageReplacementResult.semanticChange;
    }
    final next = List<V2TimMessage>.from(current)..[index] = replacement;
    if (!isNewestFirstStorageOrderValid(next)) {
      return RowLocalMessageReplacementResult.reordered;
    }
    final resolvedStableIdentity = readOutgoingStableId(expected) ??
        readOutgoingStableId(replacement) ??
        expected.id ??
        expected.msgID ??
        primary;
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageKey,
        eventID:
            'row_replace:$resolvedStableIdentity:${replacement.msgID ?? ''}',
        kind: MessageDeltaKind.edit,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: messageDeltaClearEpochFor(storageKey),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: replacement,
            msgID: replacement.msgID,
            localID: replacement.id,
            outgoingStableID: resolvedStableIdentity,
            seq: replacement.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      return RowLocalMessageReplacementResult.stale;
    }
    final replacementKey = ChatUiStateStore.messageKeyOf(replacement);
    final allAliases = <String?>{
      ChatUiStateStore.messageKeyOf(expected),
      expected.id,
      expected.msgID,
      readOutgoingStableId(expected),
      replacement.id,
      replacement.msgID,
      readOutgoingStableId(replacement),
      ...aliases,
    };
    _rememberRowLocalAliases(storageKey, allAliases, replacementKey);
    for (final alias in allAliases) {
      final value = alias?.trim() ?? '';
      if (value.isNotEmpty && value != replacementKey) {
        _chatUiStateStore.bindMessageAlias(storageKey, value, replacementKey);
      }
    }
    _markMessageRowChanged(storageKey, replacement);
    return RowLocalMessageReplacementResult.replaced;
  }

  /// Replaces one authoritative row without invalidating the whole message
  /// window. The caller must already have proved that membership and ordering
  /// are unchanged; otherwise use [setMessageList].
  RowLocalMessageReplacementResult replaceMessageRowLocal({
    required String conversationID,
    required int index,
    required V2TimMessage expected,
    required V2TimMessage replacement,
    Iterable<String?> aliases = const <String?>[],
  }) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final current = _messageListMap[storageKey];
    if (current == null ||
        index < 0 ||
        index >= current.length ||
        !identical(current[index], expected)) {
      return RowLocalMessageReplacementResult.stale;
    }
    final next = List<V2TimMessage>.from(current);
    next[index] = replacement;
    if (!isNewestFirstStorageOrderValid(next)) {
      return RowLocalMessageReplacementResult.reordered;
    }
    final stableIdentity = readOutgoingStableId(expected) ??
        readOutgoingStableId(replacement) ??
        expected.id ??
        expected.msgID ??
        replacement.id ??
        replacement.msgID;
    if (stableIdentity == null || stableIdentity.trim().isEmpty) {
      return RowLocalMessageReplacementResult.notFound;
    }
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageKey,
        eventID: 'row_local_replace:$stableIdentity:${replacement.msgID ?? ''}',
        kind: MessageDeltaKind.edit,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: messageDeltaClearEpochFor(storageKey),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: replacement,
            msgID: replacement.msgID,
            localID: replacement.id,
            outgoingStableID: stableIdentity,
            seq: replacement.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      return RowLocalMessageReplacementResult.stale;
    }
    final replacementKey = ChatUiStateStore.messageKeyOf(replacement);
    final keys = <String?>{
      ChatUiStateStore.messageKeyOf(expected),
      expected.id,
      expected.msgID,
      replacement.id,
      replacement.msgID,
      ...aliases,
    };
    _rememberRowLocalAliases(storageKey, keys, replacementKey);
    for (final alias in keys) {
      final value = alias?.trim() ?? '';
      if (value.isNotEmpty && value != replacementKey) {
        _chatUiStateStore.bindMessageAlias(storageKey, value, replacementKey);
      }
    }
    _markMessageRowChanged(storageKey, replacement);
    return RowLocalMessageReplacementResult.replaced;
  }

  void _markMessageRowChanged(
    String conversationID,
    V2TimMessage message, {
    String? extraKey,
    MessageMutationType mutationType = MessageMutationType.contentOrMedia,
  }) {
    final keys = <String>{ChatUiStateStore.messageKeyOf(message)};
    final msgID = message.msgID?.trim();
    if (msgID != null && msgID.isNotEmpty) {
      keys.add(msgID);
    }
    final id = message.id?.trim();
    if (id != null && id.isNotEmpty) {
      keys.add(id);
    }
    final seq = message.seq?.trim();
    if (seq != null && seq.isNotEmpty) {
      keys.add('seq_$seq');
    }
    final key = extraKey?.trim();
    if (key != null && key.isNotEmpty) {
      keys.add(key);
    }
    _messageCommitCoordinator.stage(
      MessageMutation(
        conversationID: conversationID,
        type: mutationType,
        generation: _messageCommitGenerationByConv[conversationID] ?? 0,
        source: 'row_local',
        stableIdentity: _commitSnapshotIdentity(message),
      ),
      requiresListRevision: false,
    );
    _chatUiStateStore.markMessagesChanged(conversationID, keys);
  }

  void _markMessageRowChangedByIds(
    String conversationID, {
    String? msgID,
    String? clientId,
  }) {
    final keys = <String>{};
    final mid = msgID?.trim();
    if (mid != null && mid.isNotEmpty) {
      keys.add(mid);
    }
    final cid = clientId?.trim();
    if (cid != null && cid.isNotEmpty) {
      keys.add(cid);
    }
    final message = _messageInConversation(
      conversationID,
      clientId: cid,
      msgID: mid,
    );
    if (message != null) {
      keys.add(ChatUiStateStore.messageKeyOf(message));
      final messageId = message.id?.trim();
      if (messageId != null && messageId.isNotEmpty) {
        keys.add(messageId);
      }
      final messageMsgID = message.msgID?.trim();
      if (messageMsgID != null && messageMsgID.isNotEmpty) {
        keys.add(messageMsgID);
      }
    }
    if (keys.isNotEmpty) {
      _messageCommitCoordinator.stage(
        MessageMutation(
          conversationID: conversationID,
          type: MessageMutationType.statusOrProgress,
          generation: _messageCommitGenerationByConv[conversationID] ?? 0,
          source: 'status_progress',
          stableIdentity: mid?.isNotEmpty == true ? mid : cid,
        ),
        requiresListRevision: false,
      );
      _chatUiStateStore.markMessagesChanged(conversationID, keys);
    }
  }

  void _markMessageRowsChangedByMsgID(String msgID) {
    final key = msgID.trim();
    if (key.isEmpty) {
      return;
    }
    for (final entry in _messageListMap.find(key)) {
      _markMessageRowChanged(entry.key, entry.value, extraKey: key);
    }
  }

  void markMessageRowsChangedByMsgIDs(Iterable<String?> msgIDs) {
    final keys = msgIDs
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (keys.isEmpty) {
      return;
    }
    for (final key in keys) {
      _markMessageRowsChangedByMsgID(key);
    }
  }

  int messageStatusInConversation(
    String conversationID, {
    String? clientId,
    String? msgID,
    int? fallback,
    int? elemType,
  }) {
    final list = rawMessageList(conversationID);
    if (list == null || list.isEmpty) {
      return OutgoingSendStatus.normalize(status: fallback);
    }
    final current = _messageInConversation(conversationID,
        clientId: clientId, msgID: msgID);
    if (current != null) {
      return _normalizedOutgoingStatus(current, fallback);
    }
    return OutgoingSendStatus.normalize(status: fallback);
  }

  Future<bool> abandonOutcomeUnknownMessage({
    required String conversationID,
    required ConvType conversationType,
    required String sdkLocalId,
    String? msgID,
  }) async {
    final localId = sdkLocalId.trim();
    if (localId.isEmpty || conversationType == ConvType.none) return false;
    final abandoned =
        await ImOutgoingSendCoordinator.instance.abandonOutcomeUnknown(
      sdkLocalId: localId,
      conversationId: conversationID,
      conversationType: conversationType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
    );
    if (!abandoned) return false;
    return markOutgoingSendFailedByIdentity(
      conversationID: conversationID,
      clientId: localId,
      msgID: msgID,
      reason: 'outcome_unknown_abandoned_by_user',
    );
  }

  final Map<String, VoidCallback> _outboxResultSubscriptions = {};
  final Map<String, String> _outboxSubscriptionConversations = {};

  void _observeOutgoingResult(ImCoordinatedSendResult live, String convID,
      String clientId, ConvType convType, GroupReceiptAllowType? groupType) {
    final view = live.resultView;
    final identity = live.identity;
    if (view == null || identity == null || live.currentOutboxResult?.deliveryConfirmed == true) return;
    final key = identity.scope.ownerUserId + '|' + identity.operationId;
    if (_outboxResultSubscriptions.containsKey(key)) return;
    void remove() {
      _outboxSubscriptionConversations.remove(key);
      _outboxResultSubscriptions.remove(key)?.call();
    }
    void changed() {
      final snapshot = live.snapshot();
      if (!snapshot.isCurrentSession) { remove(); return; }
      if (snapshot.outcomeUnknown) return;
      final applied = applyOutgoingSendResult(snapshot.sdkResult, convID,
          clientId, convType, groupType, null, coordinatedResult: snapshot);
      if (snapshot.currentOutboxResult?.deliveryConfirmed == true) {
        remove();
        final message = snapshot.sdkResult.data;
        if (applied && message != null) {
          // Projection only: do not replay messageDidSend or clear input.
          final session = snapshot.accountGeneration == null ? null : SessionIdentity(
            ownerUserId: identity.scope.ownerUserId, generation: snapshot.accountGeneration!);
          unawaited(ConversationSyncService.instance.patchConversationLastMessage(
            conversationID: identity.scope.conversationId, message: message, identity: session)
              .catchError((Object error) { outputLogger.i('outbox preview repair: ' + error.runtimeType.toString()); }));
        }
      }
    }
    view.addListener(changed);
    _outboxSubscriptionConversations[key] = convID;
    _outboxResultSubscriptions[key] = () => view.removeListener(changed);
  }

  bool applyOutgoingSendResult(
    V2TimValueCallback<V2TimMessage> sendMsgRes,
    String convID,
    String clientId,
    ConvType convType,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField, {
    ImCoordinatedSendResult? coordinatedResult,
  }) {
    if (coordinatedResult != null) {
      _observeOutgoingResult(coordinatedResult, convID, clientId, convType, groupType);
      coordinatedResult = coordinatedResult.snapshot();
      final identity = coordinatedResult.identity;
      if (identity != null && coordinatedResult.accountGeneration != null &&
          !SessionIdentityService.instance.isCurrent(SessionIdentity(
              ownerUserId: identity.scope.ownerUserId,
              generation: coordinatedResult.accountGeneration!))) return false;
      if (coordinatedResult.outcomeUnknown) return false;
      sendMsgRes = coordinatedResult.sdkResult;
    }
    final dataMsgID = sendMsgRes.data?.msgID;
    if (isOutgoingMediaCancelled(clientId) ||
        isOutgoingMediaCancelled(dataMsgID)) {
      return false;
    }
    if (!_mayProjectOutgoingResult(convID, clientId, sendMsgRes)) return false;
    try {
      updateMessage(
        sendMsgRes,
        convID,
        clientId,
        convType,
        groupType,
        setInputField,
        stateVersion: coordinatedResult?.currentOutboxResult?.stateVersion,
      );
      if (sendMsgRes.code != 0) {
        markOutgoingSendFailedByIdentity(
          conversationID: convID,
          clientId: clientId,
          msgID: dataMsgID,
          sendFailCode: sendMsgRes.code,
          reason: 'sdk_send_failed',
        );
      }
      return true;
    } catch (e) {
      outputLogger.i('updateMessage error: $e');
      if (sendMsgRes.code != 0) {
        markOutgoingSendFailedByIdentity(
          conversationID: convID,
          clientId: clientId,
          msgID: dataMsgID,
          sendFailCode: sendMsgRes.code,
          reason: 'sdk_send_failed',
        );
      }
      return false;
    }
  }

  bool _mayProjectOutgoingResult(String conversationID, String clientId,
      V2TimValueCallback<V2TimMessage> result) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final tombstones = _messageReconciliationWriter.tombstonesFor(storageKey);
    final message = result.data;
    final ids = <String>{clientId, message?.id ?? '', message?.msgID ?? '',
        readOutgoingStableId(message) ?? ''}..remove('');
    if (ids.any(tombstones.contains)) return false;
    final list = _mergedAliasMessageList(storageKey);
    final index = message == null
        ? list.indexWhere((row) => row.id == clientId)
        : _findMessageIndexForUpdate(list, clientId, message);
    if (index < 0) return true;
    final previous = list[index];
    if (previous.status == MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED) return false;
    // This is an existing confirmed row, not merely a nonempty sync msgID.
    return result.code == 0 ||
        previous.status != MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
  }

  /// Recheck after awaits, before publishing previews or lifecycle effects.
  /// Delivery evidence may settle Outbox without reviving removed content.
  bool mayPublishOutgoingSendCompletion(String conversationID, String clientId,
      ImCoordinatedSendResult result) =>
      result.isCurrentSession && !result.outcomeUnknown &&
      !isOutgoingMediaCancelled(clientId) &&
      !isOutgoingMediaCancelled(result.sdkResult.data?.msgID) &&
      _mayProjectOutgoingResult(conversationID, clientId, result.sdkResult);

  void insertPeerRejectedLocalTip(
    String conversationID,
    int code, {
    String? clientId,
  }) {
    if (code != 20007) {
      return;
    }
    final convID = conversationID.trim();
    if (convID.isEmpty) {
      return;
    }
    final tip = buildC2cPeerRejectedTipMessage(clientId: clientId);
    assignOutgoingLocalSeq(convID, tip);
    commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: convID,
        eventID: 'peer_rejected_tip:$convID:${tip.id ?? ''}',
        kind: MessageDeltaKind.optimisticInsert,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(convID),
        clearEpoch: messageDeltaClearEpochFor(convID),
        upserts: [messageDeltaRecord(tip)],
      ),
    );
    requestPinToBottom(convID, force: true);
  }

  void _updateMediaScrollGate() {
    BackgroundMediaGate.instance.setBusy(this, isChatListUserScrolling);
  }

  void setChatListUserScrolling(bool scrolling) {
    BackgroundMediaGate.instance.setBusy(this, scrolling);
    final wasScrolling = isChatListUserScrolling;
    final page = _openPageUserScrolling;
    if (page != null) {
      if (page.value != scrolling) {
        page.value = scrolling;
      }
    } else {
      _isChatListUserScrolling = scrolling;
    }
    if (scrolling) {
      final convId = _safeConversationId(currentSelectedConv);
      // 用户一旦上手滑动，首屏贴底锁立刻让路，避免把真实离底的回底按钮藏掉。
      if (convId.isNotEmpty) {
        clearOpenChatBottomCapsuleLock(convId);
      }
      // A user drag supersedes the keyboard animation's earlier bottom lock.
      _clearKeyboardViewportTransition(convId);
      noteUserDragOverridesGeometryViewportTransition(convId);
      if (convId.isNotEmpty && _inboundChunkReveal.isActiveFor(convId)) {
        _inboundChunkReveal.cancelToBuffer(convId);
      }
      ChatJitterDiag.logInboundFlow(
        action: 'user_scroll_start',
        conv: convId,
        throttleKey: 'user_scroll_start',
        minIntervalMs: 200,
      );
    } else if (wasScrolling) {
      _lastChatListUserScrollEndAtMs = DateTime.now().millisecondsSinceEpoch;
      ChatJitterDiag.logInboundFlow(
        action: 'user_scroll_end',
        conv: _safeConversationId(currentSelectedConv),
        throttleKey: 'user_scroll_end',
        minIntervalMs: 200,
        extras: <String, Object?>{
          'buffered': deferredIncomingBufferedCount(currentSelectedConv),
        },
      );
    }
  }

  TUIChatGlobalModel() {
    _inboundBatchCoalescer = MessageInboundBatchCoalescer(
      maxBatchSize: _inboundBatchMaxSize,
      maxDelay: _inboundBatchMaxDelay,
      onFlush: _flushInboundMessageBatch,
    );
    _inboundChunkReveal = MessageInboundChunkedReveal(
      interval: Duration(milliseconds: chatConfig.inboundChunkRevealIntervalMs),
      maxChunkSize: chatConfig.inboundChunkRevealMaxChunk,
      alignToFrame: true,
      burstBoostChunk: 0,
      // Ordinary live bursts share one measured insertion. Reserve fast-forward
      // for genuine backlogs, instead of snapping all but the latest message.
      maxAnimatedBacklog: 24,
      coalescePendingMessages: true,
      // Paced reveal is presentation-only. Keeping it outside bulk-sync allows
      // each released row to run its extent animation while chunk-active guards
      // still suppress competing list-push and pin paths.
      onSessionBegin: (_) {},
      onSessionEnd: (convId) {
        _inboundScrollFollowSessionEnding = true;
        _lastInboundScrollFollowChunk = const [];
        _inboundScrollFollowSeq++;
        _flushDeferredPinToBottom(convId);
        _markNeedsNotify();
      },
      onRevealChunk: (convId, chunk) {
        _lastInboundScrollFollowChunk = chunk;
        _inboundScrollFollowSessionEnding = false;
        _revealInboundProjectionChunk(convId, chunk);
        if (chunk.length == 1) {
          final message = chunk.first;
          if (message.isSelf != true &&
              _inboundChunkReveal.pendingCountFor(convId) == 0) {
            _markIncomingMessageEnterAnimation(message);
          }
        }
        _inboundScrollFollowSeq++;
        _markNeedsNotify();
      },
      onDrainRemaining: _drainChunkRevealToBuffer,
      onSupersede: (convId) {
        _inboundPresentationSupersedeSeq++;
        _markNeedsNotify();
      },
      onFastForward: (convId, messages) {
        for (final message in messages) {
          _inboundFastForwardMessageKeys.add(messageDedupKey(message));
        }
        _revealInboundProjectionChunk(convId, messages);
        _markNeedsNotify();
      },
    );
    advancedMsgListener = V2TimAdvancedMsgListener(
      onRecvC2CReadReceipt: (List<V2TimMessageReceipt> receiptList) {
        _onReceiveC2CReadReceipt(receiptList);
      },
      onRecvMessageRevoked: (String msgID) {
        onMessageRevoked(msgID);
      },
      onRecvNewMessage: (V2TimMessage newMsg) {
        _onReceiveNewMsg(newMsg);
      },
      onSendMessageProgress: (V2TimMessage messagae, int progress) {
        _onSendMessageProgress(messagae, progress);
      },
      onRecvMessageReadReceipts: (List<V2TimMessageReceipt> receiptList) {
        _onReceiveMessageReadReceipts(receiptList);
      },
      onRecvMessageModified: (V2TimMessage newMsg) {
        onMessageModified(newMsg);
      },
      onMessageDownloadProgressCallback:
          (V2TimMessageDownloadProgress messageProgress) {
        onMessageDownloadProgressCallback(messageProgress);
      },
    );
  }

  bool get isDownloading => _isDownloading;

  bool get hasWaiting => _waitingDownloadList.isNotEmpty;

  Map<String, String> get currentDownLoad => _waitingDownloadList.first;

  int getWaitingListLength() {
    return _waitingDownloadList.length;
  }

  void addWaitingList(String msgID) {
    outputLogger.i("add to waiting list success");
    bool contains = false;
    for (Map<String, String> element in _waitingDownloadList) {
      String msgIDItem = element["msgID"] ?? "";
      if (msgIDItem.isNotEmpty) {
        if (msgID == msgIDItem) {
          contains = true;
          break;
        }
      }
    }
    if (!contains) {
      _waitingDownloadList.add(Map.from({"msgID": msgID}));
      // setMessageProgress(msgID, 1); // 有一点进度条，表示等待中
    }
  }

  downloadFile() async {
    if (_isDownloading || _waitingDownloadList.isEmpty) {
      return;
    }

    final nextDownload = _waitingDownloadList.first;
    final msgID = nextDownload["msgID"] ?? "";
    if (msgID.isEmpty || _messageListProgressMap[msgID] == 100) {
      return;
    }

    _isDownloading = true;
    await _messageService.downloadMessage(
      msgID: msgID,
      messageType: 6,
      imageType: 0,
      isSnapshot: false,
    );

    outputLogger.i("start another download");
  }

  int getReceived(msgID) {
    return messageListProgressMap[msgID] ?? 0;
  }

  bool isWaiting(String msgID) {
    return _waitingDownloadList.where((element) {
      String msgIDItem = element["msgID"] ?? "";
      if (msgIDItem.isNotEmpty) {
        if (msgID == msgIDItem) {
          return true;
        }
      }
      return false;
    }).isNotEmpty;
  }

  Map<String, int> get messageListProgressMap {
    return _messageListProgressMap;
  }

  late final Map<String, List<V2TimMessage>?> _readOnlyMessageListMap =
      UnmodifiableMapView(_messageListMap);

  /// Compatibility reader. All structural writes go through the Writer.
  Map<String, List<V2TimMessage>?> get messageListMap =>
      _readOnlyMessageListMap;

  String _normalizeMergerCacheKey(String? key) {
    return key?.trim() ?? '';
  }

  void cacheLocalMergerMessageList({
    required Iterable<String?> keys,
    required List<V2TimMessage> messages,
  }) {
    if (messages.isEmpty) {
      return;
    }
    final normalizedKeys = keys
        .map(_normalizeMergerCacheKey)
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalizedKeys.isEmpty) {
      return;
    }
    final cached = messages.map(_cloneMessage).toList(growable: false);
    for (final key in normalizedKeys) {
      _localMergerMessageCache[key] = cached;
    }
  }

  void bindLocalMergerMessageKeys({
    required String? sourceKey,
    required Iterable<String?> keys,
  }) {
    final source = _normalizeMergerCacheKey(sourceKey);
    if (source.isEmpty) {
      return;
    }
    final cached = _localMergerMessageCache[source];
    if (cached == null || cached.isEmpty) {
      return;
    }
    cacheLocalMergerMessageList(keys: keys, messages: cached);
  }

  List<V2TimMessage>? getLocalMergerMessageList(String? key) {
    final normalized = _normalizeMergerCacheKey(key);
    if (normalized.isEmpty) {
      return null;
    }
    final cached = _localMergerMessageCache[normalized];
    if (cached == null || cached.isEmpty) {
      return null;
    }
    return cached.map(_cloneMessage).toList(growable: false);
  }

  int get totalUnReadCount {
    return _totalUnreadCount;
  }

  set totalUnReadCount(int newValue) {
    _totalUnreadCount = newValue;
    notifyListeners();
  }

  String _inboundStateKey(String? conversationID) {
    final safe = _safeConversationId(conversationID).trim();
    final normalized = _normalizeConversationID(safe);
    return normalized.isEmpty ? safe : normalized;
  }

  _InboundUnreadState _inboundUnreadStateFor(
    String? conversationID, {
    bool create = true,
  }) {
    final key = _inboundStateKey(conversationID);
    if (!create) {
      return _inboundUnreadStateByConversation[key] ?? _InboundUnreadState();
    }
    return _inboundUnreadStateByConversation.putIfAbsent(
      key,
      _InboundUnreadState.new,
    );
  }

  int unreadCountForTongueFor(String conversationID) =>
      _inboundUnreadStateFor(conversationID, create: false).unreadCount;

  int lockedEntryUnreadCountFor(String conversationID) =>
      _inboundUnreadStateFor(
        conversationID,
        create: false,
      ).lockedEntryUnreadCount;

  int lockedFirstUnreadSeqFor(String conversationID) => _inboundUnreadStateFor(
        conversationID,
        create: false,
      ).lockedFirstUnreadSeq;

  int receivedNewMessageCountFor(String conversationID) =>
      _inboundUnreadStateFor(conversationID, create: false).receivedCount;

  int get receivedNewMessageCount =>
      receivedNewMessageCountFor(currentSelectedConv);

  int remainingLiveIncomingCountFor(String conversationID) =>
      _inboundUnreadStateFor(conversationID, create: false)
          .remainingLiveIncomingIds
          .length;

  int liveReceiveGenerationFor(String conversationID) =>
      _inboundUnreadStateFor(conversationID, create: false)
          .liveReceiveGeneration;

  int unreadVisitGenerationFor(String conversationID) =>
      _inboundUnreadStateFor(conversationID, create: false)
          .unreadVisitGeneration;

  int currentRestoreOpIdFor(String conversationID) =>
      _inboundUnreadStateFor(conversationID, create: false).restoreOpId;

  int beginLiveFollowRestoreOp(String conversationID) {
    final state = _inboundUnreadStateFor(conversationID);
    state.restoreOpId++;
    return state.restoreOpId;
  }

  Set<String> remainingLiveIncomingIdsFor(String conversationID) =>
      Set<String>.from(
        _inboundUnreadStateFor(conversationID, create: false)
            .remainingLiveIncomingIds,
      );

  static String liveIncomingIdentity(V2TimMessage message) {
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isNotEmpty) {
      return msgID;
    }
    return message.id?.trim() ?? '';
  }

  static bool isConfirmedProjectionMessage(V2TimMessage message) {
    if (message.elemType == 11) {
      return false;
    }
    if (message.isSelf == true &&
        (message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING ||
            message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL)) {
      return false;
    }
    return true;
  }

  void markLiveIncomingSeen({
    required String conversationID,
    required Iterable<String> ids,
  }) {
    final state = _inboundUnreadStateFor(conversationID, create: false);
    var changed = false;
    for (final id in ids) {
      if (id.isEmpty) {
        continue;
      }
      if (state.remainingLiveIncomingIds.remove(id)) {
        state.seenLiveIncomingIds.add(id);
        changed = true;
      }
    }
    if (changed) {
      _markNeedsNotify();
    }
  }

  void _recordBufferedLiveIncoming(_InboundUnreadState state, V2TimMessage message) {
    if (message.isSelf == true) {
      return;
    }
    final id = liveIncomingIdentity(message);
    if (id.isEmpty || state.seenLiveIncomingIds.contains(id)) {
      return;
    }
    if (state.remainingLiveIncomingIds.add(id)) {
      state.liveReceiveGeneration++;
    }
  }

  int unadmittedRemainingLiveCountFor(String conversationID) {
    final state = _inboundUnreadStateFor(conversationID, create: false);
    if (state.remainingLiveIncomingIds.isEmpty ||
        state.bufferedMessages.isEmpty) {
      return 0;
    }
    final bufferedIds = state.bufferedMessages
        .map(liveIncomingIdentity)
        .where((id) => id.isNotEmpty)
        .toSet();
    var count = 0;
    for (final id in state.remainingLiveIncomingIds) {
      if (bufferedIds.contains(id)) {
        count++;
      }
    }
    return count;
  }

  void migrateCoveredRemainingToSeen(
    String conversationID,
    Set<String> coveredIds,
  ) {
    final state = _inboundUnreadStateFor(conversationID);
    for (final id in <String>{...coveredIds, ...state.seenLiveIncomingIds}) {
      if (id.isEmpty) {
        continue;
      }
      if (state.remainingLiveIncomingIds.remove(id)) {
        state.seenLiveIncomingIds.add(id);
      }
      // Only consume the confirmed snapshot. Arrivals after it, including a
      // durable return transaction's new tail, keep their own accounting.
      if (state.revealedUnreadMessageIDs.remove(id)) {
        state.receivedCount = max(0, state.receivedCount - 1);
        state.unreadCount = max(state.lockedEntryUnreadCount, state.unreadCount - 1);
      }
    }
    // This is the synchronous commit of a proven latest window, not a
    // per-row visibility ACK. Preserve visit/dedup identities while retiring
    // the legacy counter that otherwise survives after FOLLOW is restored.
    if (state.remainingLiveIncomingIds.isEmpty &&
        state.bufferedMessages.isEmpty &&
        !state.durableDeferred &&
        state.durableOperationCount == 0 &&
        !state.unreadVisitBaselinePending) {
      state.receivedCount = 0;
      state.unreadCount = state.lockedEntryUnreadCount;
      state.revealedUnreadMessageIDs.clear();
      state.pendingLegacyMessages.clear();
      state.trueLatestEndAbsorbed = true;
    }
  }

  bool isFollowingLatest(String? conversationID) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return true;
    }
    return _followingLatestByConversation[convId] ?? true;
  }

  void setFollowingLatest(
    String conversationID,
    bool following, {
    bool notify = true,
    bool absorbUnread = true,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    if (!following && isGeometryViewportTransitionActive(convId)) {
      return;
    }
    final previous = _followingLatestByConversation[convId] ?? true;
    if (previous == following) {
      return;
    }
    _followingLatestByConversation[convId] = following;
    ChatJitterDiag.logFollowingLatest(
      action: following ? 'set_true' : 'set_false',
      conv: convId,
      extras: <String, Object?>{
        'previous': previous,
        'notify': notify,
        ...stickToLatestDiagSnapshot(convId),
      },
    );
    if (!following) {
      _inboundUnreadStateFor(convId).trueLatestEndAbsorbed = false;
      _freezeHistoryReadingWindowByConversation[convId]?.freeze();
    }
    if (following && absorbUnread) {
      clearReceivedUnreadState(conversationID: convId, notify: false);
      final previousLogical = getMessageListPosition(convId);
      setMessageListPosition(
        convId,
        HistoryMessagePosition.bottom,
        notify: false,
      );
      final nextLogical = getMessageListPosition(convId);
      ChatJitterDiag.logFollowingLatest(
        action: 'sync_logical_bottom',
        conv: convId,
        extras: <String, Object?>{
          'from': previousLogical.name,
          'to': nextLogical.name,
          'accepted': nextLogical == HistoryMessagePosition.bottom,
        },
      );
    }
    if (notify) {
      notifyListeners();
    }
  }

  bool isHistoryReadingWindowActive(String conversationID) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return false;
    }
    return _historyReadingWindowByConversation.contains(convId);
  }

  void setHistoryReadingWindowActive(String conversationID, bool active) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    if (active) {
      _historyReadingWindowByConversation.add(convId);
    } else {
      _historyReadingWindowByConversation.remove(convId);
    }
  }

  void bindHistoryLiveWindowFreeze({
    required String conversationID,
    required void Function() freezeIfNeeded,
    bool Function()? canAppendIncoming,
    void Function(List<V2TimMessage>)? didAppendIncoming,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    _freezeHistoryReadingWindowByConversation[convId] = (
      freeze: freezeIfNeeded,
      canAppend: canAppendIncoming,
      didAppend: didAppendIncoming,
    );
  }

  void clearHistoryLiveWindowFreeze({String? conversationID}) {
    if (conversationID != null && conversationID.isNotEmpty) {
      final convId = _inboundStateKey(conversationID);
      _freezeHistoryReadingWindowByConversation.remove(convId);
      _historyReadingWindowByConversation.remove(convId);
      return;
    }
    _freezeHistoryReadingWindowByConversation.clear();
    _historyReadingWindowByConversation.clear();
  }

  bool get isAttachingBufferedTowardLatest {
    if (!_attachingBufferedTowardLatest) {
      return false;
    }
    if (DateTime.now().millisecondsSinceEpoch >=
        _attachingBufferedTowardLatestUntilMs) {
      _attachingBufferedTowardLatest = false;
      _attachingBufferedTowardLatestUntilMs = 0;
      return false;
    }
    return true;
  }

  void beginAttachingBufferedTowardLatest() {
    _attachingBufferedTowardLatest = true;
    _attachingBufferedTowardLatestUntilMs =
        DateTime.now().millisecondsSinceEpoch +
            _attachBufferedTowardLatestHoldMs;
  }

  void endAttachingBufferedTowardLatest() {
    _attachingBufferedTowardLatest = false;
    _attachingBufferedTowardLatestUntilMs = 0;
  }

  List<V2TimMessage> copyBufferedIncomingPage(
    String convID, {
    required int limit,
  }) {
    if (limit <= 0 || _isHistoryGapDeferral(convID)) {
      return const <V2TimMessage>[];
    }
    final state = _inboundUnreadStateFor(convID, create: false);
    if (state.bufferedMessages.isEmpty) {
      return const <V2TimMessage>[];
    }
    return List<V2TimMessage>.from(
      state.bufferedMessages.take(limit),
      growable: false,
    );
  }

  List<V2TimMessage> commitBufferedIncomingReveal(
    String convID,
    List<V2TimMessage> page,
  ) {
    if (page.isEmpty) {
      return const <V2TimMessage>[];
    }
    final state = _inboundUnreadStateFor(convID);
    final keys = page.map(messageDedupKey).toSet();
    state.bufferedMessages
        .removeWhere((message) => keys.contains(messageDedupKey(message)));
    state.bufferedMessageKeys.removeAll(keys);
    for (final key in keys) {
      state.pendingLegacyMessages.remove(key);
    }
    // Preloading below the viewport is not a read. The local identity ledger
    // survives attachment until the measured-reading-edge consumer sees it.
    final result = _upsertIncomingMessageBatch(convID, page);
    if (result.inserted) {
      _bumpMessageListRevisionFor(
        convID,
        reason: 'reveal_buffered_toward_latest',
      );
    }
    ChatJitterDiag.logReadingHistoryIncoming(
      action: 'reveal_toward_latest',
      conv: convID,
      extras: <String, Object?>{
        'count': page.length,
        'bufferedLeft': state.bufferedMessages.length,
      },
    );
    _markNeedsNotify();
    return page;
  }

  /// Owner and clear epoch survive legitimate history-cache session changes.
  bool Function() captureMessageOwnerFence(String conversationID) {
    final writer = _messageReconciliationWriter.configuredScope;
    final clearEpoch = messageDeltaClearEpochFor(conversationID);
    return () =>
        _messageReconciliationWriter.configuredScope == writer &&
        messageDeltaClearEpochFor(conversationID) == clearEpoch;
  }

  /// A late conversation lookup may fill the frozen sequence, never re-lock
  /// an entry reminder which the reader has already dismissed or replaced.
  void Function(int) captureEntryUnreadSequenceUpdate(String conversationID) {
    final ownerCurrent = captureMessageOwnerFence(conversationID);
    final state = _inboundUnreadStateFor(conversationID, create: false);
    final version = state.entryReminderVersion;
    return (int seq) {
      if (seq <= 0 ||
          !ownerCurrent() ||
          !identical(
              _inboundUnreadStateFor(conversationID, create: false), state) ||
          state.entryReminderVersion != version ||
          state.lockedEntryUnreadCount <= 0 ||
          state.lockedFirstUnreadSeq > 0) return;
      state.lockedFirstUnreadSeq = seq;
    };
  }

  set receivedNewMessageCount(int value) {
    _inboundUnreadStateFor(currentSelectedConv).receivedCount = value;
  }

  int get unreadCountForTongue => unreadCountForTongueFor(currentSelectedConv);

  int get lockedEntryUnreadCount =>
      lockedEntryUnreadCountFor(currentSelectedConv);

  int get lockedFirstUnreadSeq => lockedFirstUnreadSeqFor(currentSelectedConv);

  bool get hasLockedEntryUnread => lockedEntryUnreadCount > 0;

  bool hasLockedEntryUnreadFor(String conversationID) {
    return lockedEntryUnreadCountFor(conversationID) > 0;
  }

  set unreadCountForTongue(int value) {
    setUnreadCountForTongue(value);
  }

  void lockEntryUnreadForTongue({
    required String conversationID,
    required int unreadCount,
    int? firstUnreadSeq,
    bool notify = true,
  }) {
    final convId = _normalizeConversationID(conversationID);
    if (convId.isEmpty || unreadCount <= 0) {
      return;
    }
    final state = _inboundUnreadStateFor(convId);
    state.entryReminderVersion++;
    state.lockedEntryUnreadCount = unreadCount;
    state.unreadCount =
        unreadCount + state.durableUnreadCount + state.visibleLegacyCount;
    state.lockedFirstUnreadSeq = 0;
    final frozenSeq = firstUnreadSeq ?? 0;
    if (frozenSeq > 0) {
      state.lockedFirstUnreadSeq = frozenSeq;
    }
    _dismissedEntryUnreadTongueCountByConversation.remove(convId);
    if (conversationID != convId) {
      _dismissedEntryUnreadTongueCountByConversation.remove(conversationID);
    }
    setUnreadTongueMetrics(
      conversationID: convId,
      remaining: unreadCount,
      below: false,
      notify: notify,
    );
  }

  /// Dismiss the entry snapshot without consuming live messages received while
  /// the first-unread window was being located.
  void releaseEntryUnreadReminder(String conversationID) {
    final state = _inboundUnreadStateFor(conversationID, create: false);
    state.entryReminderVersion++;
    state.lockedEntryUnreadCount = 0;
    state.lockedFirstUnreadSeq = 0;
    state.unreadCount = state.unreadVisitBaselinePending
        ? state.visibleLegacyCount
        : state.durableDeferred
            ? state.durableUnreadCount + state.visibleLegacyCount
            : state.bufferedMessageKeys.length +
                state.revealedUnreadMessageIDs.length;
  }

  void unlockEntryUnreadForTongue({
    String? conversationID,
    bool notify = true,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (_deferredUntilUserBottomConversations.contains(convId)) {
      return;
    }
    final state = _inboundUnreadStateFor(convId, create: false);
    // A caller may reach the bottom in the same event-loop turn that the
    // coalescer routes an inbound message to the away buffer. Never let an
    // unread cleanup operation discard a message that has not been merged.
    if (state.durableDeferred ||
        state.unreadVisitBaselinePending ||
        state.durableOperationCount > 0 ||
        (state.revealedUnreadMessageIDs.isNotEmpty &&
            !isFollowingLatest(convId)) ||
        state.bufferedMessages.isNotEmpty) {
      return;
    }
    if (state.lockedEntryUnreadCount <= 0 && state.unreadCount <= 0) {
      return;
    }
    state.clear();
    _inboundUnreadStateByConversation.remove(convId);
    if (notify) {
      notifyListeners();
    }
  }

  void setUnreadCountForTongue(
    int value, {
    String? conversationID,
    bool notify = true,
  }) {
    final state = _inboundUnreadStateFor(conversationID);
    if (value == 0 && state.lockedEntryUnreadCount > 0) {
      return;
    }
    state.unreadCount = value;
    if (notify) {
      notifyListeners();
    }
  }

  int get unreadTongueMetricsVersion => _unreadTongueMetricsVersion;

  int getUnreadTongueRemaining(String conversationID) {
    final normalized = _normalizeConversationID(conversationID);
    final direct = _unreadTongueRemainingByConversation[conversationID];
    if (direct != null) {
      return direct;
    }
    if (normalized.isNotEmpty) {
      final normalizedRemaining =
          _unreadTongueRemainingByConversation[normalized];
      if (normalizedRemaining != null) {
        return normalizedRemaining;
      }
    }
    return unreadCountForTongueFor(conversationID);
  }

  bool getUnreadTongueBelow(String conversationID) {
    final normalized = _normalizeConversationID(conversationID);
    if (_unreadTongueBelowByConversation.containsKey(conversationID)) {
      return _unreadTongueBelowByConversation[conversationID] ?? true;
    }
    if (normalized.isNotEmpty &&
        _unreadTongueBelowByConversation.containsKey(normalized)) {
      return _unreadTongueBelowByConversation[normalized] ?? true;
    }
    return true;
  }

  void setUnreadTongueMetrics({
    required String conversationID,
    required int remaining,
    required bool below,
    bool notify = true,
  }) {
    final convId = _normalizeConversationID(conversationID);
    if (convId.isEmpty) {
      return;
    }
    final safeRemaining = remaining < 0 ? 0 : remaining;
    if (_unreadTongueRemainingByConversation[convId] == safeRemaining &&
        _unreadTongueBelowByConversation[convId] == below) {
      return;
    }
    _unreadTongueRemainingByConversation[convId] = safeRemaining;
    _unreadTongueBelowByConversation[convId] = below;
    _unreadTongueMetricsVersion++;
    if (notify) {
      notifyListeners();
    }
  }

  void clearUnreadTongueMetrics(String conversationID, {bool notify = false}) {
    if (conversationID.isEmpty) {
      return;
    }
    final convId = _inboundStateKey(conversationID);
    final removedRemaining =
        _unreadTongueRemainingByConversation.remove(convId) != null;
    final removedBelow =
        _unreadTongueBelowByConversation.remove(convId) != null;
    final changed = removedRemaining || removedBelow;
    if (changed) {
      _unreadTongueMetricsVersion++;
      if (notify) {
        notifyListeners();
      }
    }
  }

  int getDismissedEntryUnreadTongueCount(String conversationID) {
    return _dismissedEntryUnreadTongueCountByConversation[_inboundStateKey(
          conversationID,
        )] ??
        0;
  }

  void markEntryUnreadTongueDismissed({
    required String conversationID,
    required int unreadCount,
    bool notify = false,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    final safeCount = unreadCount < 0 ? 0 : unreadCount;
    final previous =
        _dismissedEntryUnreadTongueCountByConversation[convId] ?? 0;
    if (safeCount <= previous) {
      return;
    }
    _dismissedEntryUnreadTongueCountByConversation[convId] = safeCount;
    if (notify) {
      notifyListeners();
    }
  }

  void clearEntryUnreadTongueDismissed(
    String conversationID, {
    bool notify = false,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    final changed =
        _dismissedEntryUnreadTongueCountByConversation.remove(convId) != null;
    if (changed && notify) {
      notifyListeners();
    }
  }

  void clearReceivedUnreadState({String? conversationID, bool notify = false}) {
    final convId = _inboundStateKey(conversationID);
    if (_deferredUntilUserBottomConversations.contains(convId)) {
      return;
    }
    final state = _inboundUnreadStateFor(convId, create: false);
    if (state.durableDeferred ||
        state.unreadVisitBaselinePending ||
        state.durableOperationCount > 0 ||
        (state.revealedUnreadMessageIDs.isNotEmpty &&
            !isFollowingLatest(convId)) ||
        state.bufferedMessages.isNotEmpty) {
      return;
    }
    if (state.lockedEntryUnreadCount > 0) {
      return;
    }
    state.clear();
    _inboundUnreadStateByConversation.remove(convId);
    _dismissedEntryUnreadTongueCountByConversation.remove(convId);
    if (notify) {
      notifyListeners();
    }
  }

  /// 真最新端强收敛：历史状态不得否定已观察到的物理尽头。
  /// 不 flush、不插行。seen 保留。remaining 按当前集合迁入 seen。
  void settleAtTrueLatestEnd(String conversationID, {bool notify = true}) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    _deferredUntilUserBottomConversations.remove(convId);
    final state = _inboundUnreadStateFor(convId);
    state.receivedCount = 0;
    state.unreadCount = state.lockedEntryUnreadCount;
    state.durableDeferred = false;
    state.durableUnreadCount = 0;
    state.revealedUnreadMessageIDs.clear();
    state.pendingLegacyMessages.clear();
    state.trueLatestEndAbsorbed = true;
    state.seenLiveIncomingIds.addAll(state.remainingLiveIncomingIds);
    state.remainingLiveIncomingIds.clear();
    setFollowingLatest(convId, true, notify: false, absorbUnread: false);
    _storeHistoryMessagePosition(convId, HistoryMessagePosition.bottom);
    endUserScrollToBottom(convId);
    ChatJitterDiag.logFollowingLatest(
      action: 'settle_at_true_latest_end',
      conv: convId,
      extras: stickToLatestDiagSnapshot(convId),
    );
    final visible = getMessageList(convId);
    if (visible != null &&
        visible.isNotEmpty &&
        historyWindowScopeFor(convId) != null &&
        HistoryWindowRepositoryProvider.repository != null) {
      final visit = state.unreadVisitGeneration;
      unawaited(acknowledgeVisibleHistoryMessages(
        convId,
        visible,
        isCurrent: () {
          final current = _inboundUnreadStateFor(convId, create: false);
          return current.trueLatestEndAbsorbed &&
              current.unreadVisitGeneration == visit &&
              isFollowingLatest(convId);
        },
      ));
    }
    if (notify) {
      notifyListeners();
    }
  }

  bool _shouldDeferIncomingToVisibleList(
    String convID, {
    required HistoryMessagePosition position,
    required bool isActuallyNearBottom,
  }) {
    if (!_isSameConversationID(convID, currentSelectedConv)) {
      return false;
    }
    if (chatConfig.desktopStickToLatestEnabled &&
        _desktopShouldRemainFollowing(convID)) {
      if (isMessageContextMenuOverlayOpen) {
        return true;
      }
      if (isSearchJumpPending(convID)) {
        return true;
      }
      return false;
    }
    if (_isHistoryGapDeferral(convID))
      return true;
    if (position == HistoryMessagePosition.notShowLatest ||
        memoryWindowMissingNewer(convID)) {
      return true;
    }
    // 长按菜单打开时：即便贴底也先缓冲，避免背景列表被新消息顶走。
    if (isMessageContextMenuOverlayOpen) {
      return true;
    }
    // 键盘几何动画中，沿用动画前的贴底状态；不能把活跃会话误路由到
    // bufferedMessages，否则仅在退出页面的 flush 中才会恢复可见。
    if (_wasAtBottomBeforeKeyboardViewportChange(convID)) {
      return false;
    }
    // Reading position controls scrolling, not admission to a connected tail.
    // A held delivery must still be filled first; appending across it would
    // silently turn this list into two disconnected history segments.
    if ((!isFollowingLatest(convID) &&
            _inboundUnreadStateFor(convID, create: false).bufferedMessages.isNotEmpty) ||
        (!isFollowingLatest(convID) &&
            _freezeHistoryReadingWindowByConversation[_inboundStateKey(convID)]
                ?.canAppend == null) ||
        _freezeHistoryReadingWindowByConversation[_inboundStateKey(convID)]
                ?.canAppend?.call() == false) {
      return true;
    }
    return false;
  }

  bool _isHistoryGapDeferral(String convID) {
    final state = _inboundUnreadStateFor(convID, create: false);
    // Loading the entry unread baseline is bookkeeping, not a missing page.
    // Keep real pending deliveries fenced, but let arrivals remain live when
    // the user entered a complete latest window and is already at its bottom.
    final hasPendingDeliveries =
        HistoryWindowRepositoryProvider.repository != null &&
            (state.durableDeferred ||
                state.pendingDurableAdmissions > 0 ||
                state.pendingLegacyMessages.isNotEmpty);
    return isSearchJumpPending(convID) ||
        hasPendingDeliveries ||
        getMessageListPosition(convID) == HistoryMessagePosition.notShowLatest ||
        memoryWindowMissingNewer(convID);
  }

  void _bufferIncomingWhileReadingAway(
    String convID,
    V2TimMessage mountedMessage, {
    required String route,
    required HistoryMessagePosition position,
    required bool isActuallyNearBottom,
  }) {
    if (!_chatAppForeground) {
      final normalizedConvId = _inboundStateKey(convID);
      _deferredUntilUserBottomConversations.add(normalizedConvId);
      _storeHistoryMessagePosition(
        normalizedConvId,
        HistoryMessagePosition.notShowLatest,
      );
    }
    final state = _inboundUnreadStateFor(convID);
    final messageKey = messageDedupKey(mountedMessage);
    final id = (mountedMessage.msgID?.trim().isNotEmpty ?? false)
        ? mountedMessage.msgID!.trim() : mountedMessage.id?.trim() ?? '';
    if (state.revealedUnreadMessageIDs.contains(id) ||
        !state.bufferedMessageKeys.add(messageKey)) {
      return;
    }
    if (_isHistoryGapDeferral(convID)) {
      state.pendingLegacyMessages[messageKey] = mountedMessage;
    } else if (id.isNotEmpty) {
      state.revealedUnreadMessageIDs.add(id);
    }
    state.unreadCount++;
    state.receivedCount++;
    state.bufferedMessages.add(mountedMessage);
    _recordBufferedLiveIncoming(state, mountedMessage);
    ChatJitterDiag.logReadingHistoryIncoming(
      action: 'route_buffer',
      conv: convID,
      extras: <String, Object?>{
        'route': route,
        'position': position.name,
        'nearBottom': isActuallyNearBottom,
        'tongueUnread': state.unreadCount,
        'bufferedLen': state.bufferedMessages.length,
        'msgId': mountedMessage.msgID,
      },
    );
    _markNeedsNotify();
  }

  /// 将看历史期间缓冲的新消息合并进可见列表（回到底部 / 点未读条时调用）。
  bool flushDeferredIncomingMessages(
    String convID, {
    bool notify = true,
    bool userInitiated = false,
  }) {
    if (hasDurableHistoryDeferred(convID)) return false;
    final normalizedConvId = _inboundStateKey(convID);
    // The viewport's bottom may only be the end of a search/history page.
    // Revealing the live tail here creates a gap and corrupts the next SDK cursor.
    if (!userInitiated &&
        (!isFollowingLatest(convID) ||
            isHistoryReadingWindowActive(convID) ||
            memoryWindowMissingNewer(convID) ||
            isSearchJumpPending(convID) ||
            getMessageListPosition(convID) ==
                HistoryMessagePosition.notShowLatest)) {
      return false;
    }
    if (_deferredUntilUserBottomConversations.contains(normalizedConvId) &&
        !userInitiated) {
      return false;
    }
    if (userInitiated) {
      if (_inboundChunkReveal.isActiveFor(convID)) {
        _inboundChunkReveal.cancelToBuffer(convID);
      } else if (_inboundChunkReveal.isActiveFor(normalizedConvId)) {
        _inboundChunkReveal.cancelToBuffer(normalizedConvId);
      }
      _deferredUntilUserBottomConversations.remove(normalizedConvId);
    }
    final projectionRevealed = userInitiated
        ? _revealAllDeferredProjectionAcrossAliases(convID)
        : false;
    final state = _inboundUnreadStateFor(normalizedConvId, create: false);
    if (state.bufferedMessages.isEmpty) {
      if (projectionRevealed && notify) {
        _markNeedsNotify();
      }
      return projectionRevealed;
    }
    final pending = List<V2TimMessage>.from(state.bufferedMessages);
    state.bufferedMessages.clear();
    state.bufferedMessageKeys.clear();
    state.pendingLegacyMessages.clear();
    final alreadyAuthoritative = <V2TimMessage>[];
    final needsUpsert = <V2TimMessage>[];
    for (final message in pending) {
      final key = _authoritativeDeferredKey(convID, message);
      if (_authoritativeDeferredIncomingKeys.remove(key)) {
        alreadyAuthoritative.add(message);
      } else {
        needsUpsert.add(message);
      }
    }
    _revealDeferredProjectionAcrossAliases(convID, alreadyAuthoritative);
    final storageKey = _resolveMessageListStorageKey(convID);

    // 松手后大缓冲：走分片揭示，避免一次 revision + 整表 layout。
    if (!userInitiated &&
        pending.length >= postScrollFlushChunkThreshold &&
        chatConfig.inboundChunkRevealEnabled &&
        !isChatListUserScrolling &&
        needsUpsert.isNotEmpty) {
      ChatJitterDiag.logInboundFlow(
        action: 'flush_deferred_paced',
        conv: storageKey,
        extras: <String, Object?>{
          'count': pending.length,
          'upsert': needsUpsert.length,
          'authoritative': alreadyAuthoritative.length,
        },
      );
      _stageInboundChunkReveal(storageKey, needsUpsert);
      if (notify) {
        _markNeedsNotify();
      }
      return true;
    }

    final result = _upsertIncomingMessageBatch(storageKey, needsUpsert);
    // Returning to the latest edge can flush rows while a history reading
    // cursor is still frozen. Admit the drained tail to that same window
    // before notifying the list; otherwise the raw rows exist but remain
    // hidden behind its old newest cursor.
    _freezeHistoryReadingWindowByConversation[_inboundStateKey(convID)]
        ?.didAppend?.call(pending);
    if (result.inserted) {
      _bumpMessageListRevisionFor(storageKey, reason: 'flush_deferred_batch');
    }
    ChatJitterDiag.logReadingHistoryIncoming(
      action: 'flush_deferred',
      conv: storageKey,
      extras: <String, Object?>{
        'count': pending.length,
        'listLen': _messageListMap[storageKey]?.length,
      },
    );
    ChatJitterDiag.logInboundFlow(
      action: 'flush_deferred',
      conv: storageKey,
      throttleKey: 'flush_deferred',
      minIntervalMs: 100,
      extras: <String, Object?>{
        'count': pending.length,
        'listLen': _messageListMap[storageKey]?.length,
      },
    );
    if (notify) {
      _markNeedsNotify();
    }
    return true;
  }

  /// Flushes messages that are either waiting in the SDK batch coalescer or
  /// buffered while the user was away from the latest message. This is the
  /// final inbound drain used by an explicit return-to-bottom transaction.
  ///
  /// The coalescer is deliberately drained first: otherwise a message already
  /// delivered by the SDK can arrive in the 50ms coalescing gap after the UI's
  /// first deferred flush and be mistaken for a post-transaction message.
  bool flushPendingIncomingMessagesForUserBottom(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final keys = <String>{
      conversationID.trim(),
      storageKey,
      _inboundStateKey(conversationID),
      _inboundStateKey(storageKey),
    }..removeWhere((key) => key.isEmpty);
    var hadCoalescedMessages = false;
    for (final key in keys) {
      hadCoalescedMessages = _inboundBatchCoalescer.pendingCountFor(key) > 0 ||
          hadCoalescedMessages;
      _inboundBatchCoalescer.flushConversation(key);
    }
    final beforeDeferred = deferredIncomingBufferedCount(conversationID);
    final flushedDeferred = flushDeferredIncomingMessages(
      storageKey.isEmpty ? conversationID : storageKey,
      notify: true,
      userInitiated: true,
    );
    return hadCoalescedMessages || beforeDeferred > 0 || flushedDeferred;
  }

  List<V2TimGroupApplication> get groupApplicationList =>
      _groupApplicationList ?? [];
  List<GroupSystemNoticeItem> get groupSystemNoticeList =>
      _groupSystemNoticeList;

  String Function(V2TimMessage message)? get abstractMessageBuilder =>
      _abstractMessageBuilder;

  Widget Function(
    BuildContext context,
    TextEditingController controller,
    ValueChanged<String> onChanged,
  )? get appSearchBarBuilder => _appSearchBarBuilder;

  Widget Function(BuildContext context)? get appForwardSelectFriendPage =>
      _appForwardSelectFriendPage;

  Widget Function(BuildContext context)? get appForwardSelectGroupPage =>
      _appForwardSelectGroupPage;

  List<V2TimConversation> Function()? get appForwardRecentConversations =>
      _appForwardRecentConversations;

  Listenable? get appForwardRecentConversationsListenable =>
      _appForwardRecentConversationsListenable;

  String Function(String userId, String fallbackFaceUrl)?
      get appSearchFaceUrlResolver => _appSearchFaceUrlResolver;

  String Function(String groupId, String fallbackFaceUrl)?
      get appSearchGroupFaceUrlResolver => _appSearchGroupFaceUrlResolver;

  String? Function(String groupId)? get appSearchGroupNameResolver =>
      _appSearchGroupNameResolver;

  SearchConversationDisplay Function({
    required String conversationId,
    V2TimFriendInfo? friendHint,
    V2TimGroupInfo? groupHint,
  })? get appSearchConversationDisplayResolver =>
      _appSearchConversationDisplayResolver;

  Widget Function(BuildContext context, String userId, String name)?
      get appSearchNameBuilder => _appSearchNameBuilder;

  NavigatorState? Function()? get appRootNavigator => _appRootNavigator;

  AppContactPresenceBridge Function(BuildContext context)?
      get appContactPresenceBridgeBuilder => _appContactPresenceBridgeBuilder;

  Map<String, V2TimMessageReceipt> get messageReadReceiptMap =>
      _messageReadReceiptMap;

  String get currentSelectedConv => _currentConversationList.isNotEmpty
      ? _currentConversationList[_currentConversationList.length - 1]
          .conversationID
      : "";

  ConvType? get currentSelectedConvType => _currentConversationList.isNotEmpty
      ? _currentConversationList[_currentConversationList.length - 1]
          .conversationType
      : null;

  String _normalizeConversationID(String? value) {
    return normalizeConversationIdForHistory(value);
  }

  /// 历史桶写入主键：C2C 固定 `c2c_<uid>`，群去掉 `group_` 前缀并保留短码大小写。
  static String canonicalHistoryStorageKey(String? conversationID) {
    final trimmed = conversationID?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    final normalized = normalizeConversationIdForHistory(trimmed);
    if (normalized.isEmpty) {
      return trimmed;
    }
    if (_historyIdKind(trimmed) == _HistoryConversationKind.group) {
      return normalized;
    }
    return 'c2c_${normalized.toLowerCase()}';
  }

  List<String> _historyAliasKeys(String conversationID) {
    final trimmed = conversationID.trim();
    final canonical = canonicalHistoryStorageKey(trimmed);
    final keys = <String>{
      if (trimmed.isNotEmpty) trimmed,
      if (canonical.isNotEmpty) canonical,
    };
    keys.addAll(
      _messageListMap.keys.where(
        (mapKey) => isSameConversationIdForHistory(mapKey, trimmed),
      ),
    );
    return keys.toList(growable: false);
  }

  List<V2TimMessage> _mergedAliasMessageList(String conversationID) {
    final windows = <List<V2TimMessage>>[];
    final seen = Set<List<V2TimMessage>>.identity();
    for (final key in _historyAliasKeys(conversationID)) {
      final list = _messageListMap[key];
      if (list != null && list.isNotEmpty && seen.add(list)) windows.add(list);
    }
    if (windows.isEmpty) return const <V2TimMessage>[];
    if (windows.length == 1) {
      ChatMainThreadPerf.increment('message_single_window_reused');
      return windows.single;
    }
    // Defensive migration for a genuinely distinct legacy alias window.
    return List<V2TimMessage>.unmodifiable(sortMessagesNewestFirst(
        dedupeMessages([for (final window in windows) ...window])));
  }

  /// 别名合并后的内存窗（`c2c_` / 裸 id 等同会话），供分页 baseline 与提交守卫使用。
  List<V2TimMessage> mergedAliasMessageList(String conversationID) {
    return _mergedAliasMessageList(conversationID);
  }

  /// Returns the canonical window already maintained by the reconciliation
  /// writer. Pending realtime deltas remain owned by the writer and are merged
  /// by completeHistory; they must not force this read back through full dedupe.
  List<V2TimMessage> canonicalMessageWindow(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    if (storageKey.isEmpty) {
      return _mergedAliasMessageList(conversationID);
    }
    final window = _messageReconciliationWriter.valuesFor(storageKey);
    return window.isEmpty ? _mergedAliasMessageList(conversationID) : window;
  }

  /// 用户正在读历史（一屏外 / 非最新），此期间禁止 latest 向 replace 抢写列表。
  bool isReadingHistory(String conversationID) {
    final position = getMessageListPosition(conversationID);
    return position == HistoryMessagePosition.awayTwoScreen ||
        position == HistoryMessagePosition.notShowLatest;
  }

  void _collapseHistoryAliasesToCanonical(
    String conversationID, {
    required String canonical,
  }) {
    if (canonical.isEmpty) {
      return;
    }
    for (final key in _historyAliasKeys(conversationID)) {
      if (key == canonical) {
        continue;
      }
      _messageListMap.remove(key);
      _messageListContentSignatureByConv.remove(key);
      final position = _historyMessagePositionMap.remove(key);
      if (position != null &&
          !_historyMessagePositionMap.containsKey(canonical)) {
        _storeHistoryMessagePosition(canonical, position);
      }
    }
  }

  /// 去掉 `c2c_` / `group_` 等前缀，供历史桶 / 进页匹配共用。
  static String normalizeConversationIdForHistory(String? value) {
    var id = value?.trim() ?? '';
    if (id.isEmpty) {
      return '';
    }
    final lower = id.toLowerCase();
    if (lower.startsWith('c2c_')) {
      id = id.substring(4);
    } else if (lower.startsWith('group_')) {
      id = id.substring(6);
    } else if (id.startsWith('C2C')) {
      id = id.substring(3);
    } else if (id.startsWith('GROUP')) {
      id = id.substring(5);
    }
    return id;
  }

  bool _isSameConversationID(String? left, String? right) {
    return isSameConversationIdForHistory(left, right);
  }

  bool _isGroupConversation(
    String conversationID, {
    Iterable<V2TimMessage> messages = const <V2TimMessage>[],
  }) {
    final selectedType = currentSelectedConvType;
    if (selectedType != null &&
        _isSameConversationID(conversationID, currentSelectedConv)) {
      return selectedType == ConvType.group;
    }
    if (messages.any(
      (message) => TencentUtils.checkString(message.groupID) != null,
    )) {
      return true;
    }
    return _historyIdKind(conversationID) == _HistoryConversationKind.group;
  }

  /// 包内外统一的会话 ID 等价判断（前缀、社群短码）。
  ///
  /// 聊天页空拉兜底、hydrate 别名探测等禁止再写字面 `==` / 手拼 `group_`。
  /// `c2c_` 与群短码即使忽略大小写相同，也不得判为同一会话。
  static bool isSameConversationIdForHistory(String? left, String? right) {
    final a = normalizeConversationIdForHistory(left);
    final b = normalizeConversationIdForHistory(right);
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    final aKind = _historyIdKind(left);
    final bKind = _historyIdKind(right);
    if (aKind != bKind) {
      final groupBody = aKind == _HistoryConversationKind.group ? a : b;
      if (groupBody.contains('TGS#') || groupBody.startsWith('@')) {
        return _communityIdsEquivalent(a, b);
      }
      return false;
    }
    if (a == b) {
      return true;
    }
    if (aKind == _HistoryConversationKind.group) {
      return _communityIdsEquivalent(a, b);
    }
    return a.toLowerCase() == b.toLowerCase();
  }

  /// 与 app [ChatIdFormat.isCommunityShortToken] 对齐：字母数字下划线且含大写。
  static final RegExp _communityShortAlnumReg = RegExp(r'^[A-Za-z0-9_]+$');
  static final RegExp _hasUpperCaseReg = RegExp(r'[A-Z]');

  static bool _looksLikeCommunityShortToken(String token) {
    final t = token.trim();
    if (t.isEmpty || t.toUpperCase().contains('TGS#')) {
      return false;
    }
    if (!_communityShortAlnumReg.hasMatch(t)) {
      return false;
    }
    return _hasUpperCaseReg.hasMatch(t);
  }

  static bool _rawHasC2cPrefix(String trimmed) {
    final lower = trimmed.toLowerCase();
    return lower.startsWith('c2c_') || trimmed.startsWith('C2C');
  }

  static bool _rawHasGroupPrefix(String trimmed) {
    final lower = trimmed.toLowerCase();
    return lower.startsWith('group_') || trimmed.startsWith('GROUP');
  }

  static _HistoryConversationKind _historyIdKind(String? conversationID) {
    final trimmed = conversationID?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _HistoryConversationKind.c2c;
    }
    if (_rawHasC2cPrefix(trimmed)) {
      return _HistoryConversationKind.c2c;
    }
    if (_rawHasGroupPrefix(trimmed)) {
      return _HistoryConversationKind.group;
    }
    final body = normalizeConversationIdForHistory(trimmed);
    if (body.contains('TGS#') ||
        body.startsWith('@') ||
        _looksLikeCommunityShortToken(body)) {
      return _HistoryConversationKind.group;
    }
    return _HistoryConversationKind.c2c;
  }

  static bool _communityIdsEquivalent(String left, String right) {
    String shortOf(String raw) {
      var id = raw.trim();
      if (id.isEmpty) {
        return '';
      }
      final upper = id.toUpperCase();
      // 默认分配社群：`@TGS#_@TGS#{short}`
      const fullPrefix = '@TGS#_@TGS#';
      if (upper.startsWith(fullPrefix)) {
        return id.substring(fullPrefix.length);
      }
      // 控制台自定义社群：`@TGS#_mc…` → `mc…`（勿把 `_mc…` 当 token）
      if (upper.startsWith('@TGS#_')) {
        return id.substring('@TGS#_'.length);
      }
      final hash = id.indexOf('#');
      if (hash >= 0 && hash + 1 < id.length && upper.contains('TGS#')) {
        var token = id.substring(hash + 1);
        if (token.startsWith('_')) {
          token = token.substring(1);
        }
        return token;
      }
      if (id.startsWith('@')) {
        return id.substring(1);
      }
      return id;
    }

    final a = shortOf(left);
    final b = shortOf(right);
    return a.isNotEmpty && b.isNotEmpty && a == b;
  }

  String? _messageConversationID(V2TimMessage message) {
    final groupID = TencentUtils.checkString(message.groupID);
    if (groupID != null) {
      final normalized = _normalizeConversationID(groupID);
      return normalized.isNotEmpty ? normalized : groupID;
    }
    final userID = TencentUtils.checkString(message.userID);
    if (userID != null) {
      final normalized = _normalizeConversationID(userID);
      return normalized.isNotEmpty ? normalized : userID;
    }
    final sender = TencentUtils.checkString(message.sender);
    if (sender == null) {
      return null;
    }
    final normalized = _normalizeConversationID(sender);
    return normalized.isNotEmpty ? normalized : sender;
  }

  setCurrentConversation(CurrentConversation value, {bool notify = true}) {
    flushInactiveInboundPresentationForConversation(value.conversationID);
    _currentConversationList.add(value);
    if (notify) {
      notifyListeners();
    }
  }

  clearCurrentConversation({bool notify = false}) {
    if (_currentConversationList.isNotEmpty) {
      final leaving = _currentConversationList.last.conversationID;
      _inboundBatchCoalescer.flushConversation(leaving);
      _inboundChunkReveal.flushConversation(leaving);
      _revealAllInboundProjection(leaving);
      // Buffered messages are not yet authoritative. Commit them before the
      // active conversation is removed so switching routes cannot lose rows.
      flushDeferredIncomingMessages(
        leaving,
        notify: false,
        userInitiated: true,
      );
      final leavingStorageKey = _resolveMessageListStorageKey(leaving);
      final reorderBuffer = _reorderBuffersByConv.remove(leavingStorageKey) ??
          _reorderBuffersByConv.remove(leaving);
      reorderBuffer?.dispose();
      _cancelCloudContinuation(leaving);
      _groupGapAutoAttemptAtMs.removeWhere(
        (key, _) => key.startsWith('$leavingStorageKey:'),
      );
      final stateKey = _inboundStateKey(leaving);
      final unreadState = _inboundUnreadStateFor(stateKey, create: false);
      if (unreadState.durableDeferred ||
          unreadState.unreadVisitBaselinePending ||
          unreadState.durableOperationCount > 0 ||
          unreadState.pendingLegacyMessages.isNotEmpty) {
        // The page can close while SQL admission is pending. Keep its scalar
        // state and queue until latest has actually consumed the durable gap.
        releaseEntryUnreadReminder(stateKey);
      } else {
        _inboundUnreadStateByConversation.remove(stateKey);
      }
      // Closing a page ends its viewport hold even when a durable ACK or SQL
      // admission must survive. The next visit owns a new reading position.
      _deferredUntilUserBottomConversations.remove(stateKey);
      _wasAtBottomBeforeBackgroundByConv.remove(stateKey);
      _followingLatestByConversation.remove(stateKey);
      _historyReadingWindowByConversation.remove(stateKey);
      _freezeHistoryReadingWindowByConversation.remove(stateKey);
      _resetGeometryViewportTransition(leaving);
    }
    if (_currentConversationList.isNotEmpty) {
      _currentConversationList.removeLast();
    }
    if (notify) {
      notifyListeners();
    }
  }

  /// History warm / open-gate keys: bare id + matching `group_` / `c2c_` shape.
  ///
  /// For group/community ids, always stamp both bare and `group_` so
  /// `@TGS#_@TGS#…` warm flags hit `group_@TGS#_@TGS#…` open reads.
  /// Do **not** invent both `group_` and `c2c_` for ambiguous bare ids.
  Set<String> _historyFlagKeys(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return const <String>{};
    }
    final normalized = _normalizeConversationID(trimmed);
    final keys = <String>{trimmed};
    if (normalized.isNotEmpty) {
      keys.add(normalized);
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('group_')) {
        keys.add('group_$normalized');
      } else if (lower.startsWith('c2c_')) {
        keys.add('c2c_$normalized');
      } else if (_looksLikeGroupHistoryId(normalized)) {
        keys.add('group_$normalized');
      }
    }
    for (final mapKey in _messageListMap.keys) {
      if (_isSameConversationID(mapKey, trimmed)) {
        keys.add(mapKey);
      }
    }
    return keys;
  }

  bool _looksLikeGroupHistoryId(String id) {
    final value = id.trim();
    if (value.isEmpty) {
      return false;
    }
    final upper = value.toUpperCase();
    if (upper.contains('TGS#')) {
      return true;
    }
    // Community short token (has uppercase); keep in sync with app ChatIdFormat.
    final token = value.startsWith('@') ? value.substring(1) : value;
    if (token.isEmpty || token.toUpperCase().contains('TGS#')) {
      return false;
    }
    if (!_communityShortAlnumReg.hasMatch(token)) {
      return false;
    }
    return _hasUpperCaseReg.hasMatch(token);
  }

  void _clearHistoryFlagsForConversation(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _initialHistoryLoadedConvs.removeWhere(
      (key) => _isSameConversationID(key, trimmed),
    );
    _mayHaveOlderHistoryByConv.removeWhere(
      (key, _) => _isSameConversationID(key, trimmed),
    );
  }

  Future<MessageHistoryCoverage> ensureMessageHistoryCoverageLoaded(
    String conversationID, {
    int clearEpoch = 0,
  }) async {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    if (key.isEmpty) {
      return MessageHistoryCoverage.empty('', isGroup: false);
    }
    final cached = _messageHistoryCoverageByConv[key];
    if (_messageHistoryCoverageLoadedConvs.contains(key) && cached != null) {
      if (clearEpoch <= cached.clearEpoch) return cached;
      final cleared = MessageHistoryCoverage.empty(
        key,
        isGroup: cached.isGroup,
        clearEpoch: clearEpoch,
      );
      _storeMessageHistoryCoverage(cleared);
      return cleared;
    }
    final existingTask = _messageHistoryCoverageLoadInFlight[key];
    if (existingTask != null) {
      final loaded = await existingTask;
      return loaded ??
          MessageHistoryCoverage.empty(
            key,
            isGroup: _looksLikeGroupConversationKey(key),
            clearEpoch: clearEpoch,
          );
    }
    late final Future<MessageHistoryCoverage?> task;
    final coverageSessionGeneration = _messageHistoryCoverageSessionGeneration;
    task = () async {
      final loaded = await loadMessageHistoryCoverage(key);
      // 窗口库的清空屏障是地板：coverage 行丢失时不能退回 0。
      final persisted = await _persistedHistoryWindowClearEpoch(
        canonicalHistoryStorageKey(key),
      );
      final floor = max(clearEpoch, persisted ?? 0);
      final isGroup = loaded?.isGroup ?? _looksLikeGroupConversationKey(key);
      final normalized = loaded == null || loaded.clearEpoch < floor
          ? MessageHistoryCoverage.empty(
              key,
              isGroup: isGroup,
              clearEpoch: floor,
            )
          : loaded.copyWith(conversationKey: key);
      if (coverageSessionGeneration !=
          _messageHistoryCoverageSessionGeneration) {
        return normalized;
      }
      _messageHistoryCoverageByConv[key] = normalized;
      _messageHistoryCoverageLoadedConvs.add(key);
      return normalized;
    }()
        .whenComplete(() {
      if (identical(_messageHistoryCoverageLoadInFlight[key], task)) {
        _messageHistoryCoverageLoadInFlight.remove(key);
      }
    });
    _messageHistoryCoverageLoadInFlight[key] = task;
    return await task ??
        MessageHistoryCoverage.empty(
          key,
          isGroup: _looksLikeGroupConversationKey(key),
          clearEpoch: clearEpoch,
        );
  }

  MessageHistoryCoverage? messageHistoryCoverageFor(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    return _messageHistoryCoverageByConv[key];
  }

  /// Records a closed missing group-seq interval produced when an older page
  /// was rejected for not abutting the contiguous spine. Does not change the
  /// message list.
  void noteRejectedOlderPageGap({
    required String conversationID,
    required int missingLowerSeq,
    required int missingUpperSeq,
    bool isGroup = true,
  }) {
    if (!isGroup ||
        missingLowerSeq <= 0 ||
        missingUpperSeq <= 0 ||
        missingLowerSeq > missingUpperSeq) {
      return;
    }
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    if (key.isEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = _messageHistoryCoverageByConv[key] ??
        MessageHistoryCoverage.empty(
          key,
          isGroup: true,
          clearEpoch: messageDeltaClearEpochFor(key),
        );
    final holeKey = 'seq:$missingLowerSeq-$missingUpperSeq';
    final nextHoles = <MessageHistoryHole>[
      for (final hole in current.holes)
        if (hole.key != holeKey) hole,
      MessageHistoryHole(
        key: holeKey,
        kind: MessageHistoryHoleKind.groupSeq,
        status: MessageHistoryHoleStatus.open,
        startSeq: missingLowerSeq,
        endSeq: missingUpperSeq,
        generation:
            _messageHistoryCoverageRequestGenerationByConv[key] ?? 0,
        updatedAtMs: now,
      ),
    ];
    _storeMessageHistoryCoverage(
      current.copyWith(
        isGroup: true,
        coverageRevision: current.coverageRevision + 1,
        status: MessageHistoryCoverageStatus.partial,
        holes: nextHoles,
        updatedAtMs: now,
      ),
    );
    _messageHistoryCoverageLoadedConvs.add(key);
  }

  @visibleForTesting
  Future<void> waitForMessageHistoryCoverageUpdates(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    return _messageHistoryCoverageUpdateTailByConv[key] ?? Future<void>.value();
  }

  Future<void> invalidateMessageHistoryCoverage(
    String conversationID, {
    required bool isGroup,
    required int clearEpoch,
  }) async {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final key = storageKey.isEmpty ? conversationID.trim() : storageKey;
    if (key.isEmpty) return;
    final coverage = MessageHistoryCoverage.empty(
      key,
      isGroup: isGroup,
      clearEpoch: clearEpoch,
    ).copyWith(updatedAtMs: DateTime.now().millisecondsSinceEpoch);
    _messageHistoryCoverageByConv[key] = coverage;
    _messageHistoryCoverageLoadedConvs.add(key);
    _messageHistoryCoverageRequestGenerationByConv.remove(key);
    _messageReconciliationWriter.reset(key);
    _boundedCloudCatchUp.invalidate(key);
    await clearMessageHistoryCoverage(
      key,
      isGroup: isGroup,
      clearEpoch: clearEpoch,
    );
  }

  void _storeMessageHistoryCoverage(MessageHistoryCoverage coverage) {
    final key = _resolveMessageListStorageKey(coverage.conversationKey);
    final storageKey = key.isEmpty ? coverage.conversationKey.trim() : key;
    if (storageKey.isEmpty) return;
    final normalized = coverage.copyWith(conversationKey: storageKey);
    _messageHistoryCoverageByConv[storageKey] = normalized;
    _messageHistoryCoverageLoadedConvs.add(storageKey);
    unawaited(persistMessageHistoryCoverage(normalized));
  }

  bool _looksLikeGroupConversationKey(String conversationID) {
    final key = conversationID.trim();
    if (key.isEmpty) return false;
    final lower = key.toLowerCase();
    return (lower.startsWith('group_') && !lower.startsWith('group_c2c_')) ||
        key.toUpperCase().contains('TGS#');
  }

  bool hasInitialHistoryLoaded(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_initialHistoryLoadedConvs.contains(trimmed)) {
      return true;
    }
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty &&
        _initialHistoryLoadedConvs.contains(normalized)) {
      return true;
    }
    for (final key in _initialHistoryLoadedConvs) {
      if (_isSameConversationID(key, trimmed)) {
        return true;
      }
    }
    return false;
  }

  void _markInitialHistoryVisible(String conversationID) {
    for (final key in _historyFlagKeys(conversationID)) {
      _initialHistoryLoadedConvs.add(key);
    }
    _activateReorderBuffer(conversationID);
  }

  /// Local SDK history is allowed to release the first-frame gate, but it is
  /// not proof that cloud history is complete and must not start a second
  /// bootstrap catch-up request.
  void markLocalInitialHistoryVisible(String conversationID) {
    _markInitialHistoryVisible(conversationID);
  }

  /// A proven initial cloud window is visible. Reconnect/foreground events own
  /// later catch-up; the bootstrap itself already performed the cloud request.
  void markCloudInitialHistoryVerified(String conversationID) {
    _markInitialHistoryVisible(conversationID);
  }

  void markInitialHistoryLoaded(String conversationID) {
    _markInitialHistoryVisible(conversationID);
    // This is a local visibility marker only. Cloud verification, roaming
    // sync, and gap repair are owned by ConversationHistorySyncCoordinator;
    // triggering catch-up here caused duplicate open requests from every
    // pagination/alias compatibility path.
    if (OutgoingVisibleProbe.matches(conversationID)) {
      OutgoingVisibleProbe.log(
        'mark_initial_history_loaded',
        conversationID: conversationID,
        extras: <String, Object?>{
          'count': rawMessageCount(conversationID),
          ...OutgoingVisibleProbe.trackedInList(rawMessageList(conversationID)),
        },
      );
    }
  }

  /// Activates the InboundReorderBuffer for group conversations after
  /// initial history is loaded. C2C seq has no global continuity, so
  /// the buffer is only used for group chats.
  void _activateReorderBuffer(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) return;
    final storageKey = _resolveMessageListStorageKey(trimmed);
    final list = _messageListMap[storageKey] ?? _messageListMap[trimmed];
    if (list == null || list.isEmpty) return;
    if (!_isGroupConversation(storageKey, messages: list)) return;
    int newestSeq = 0;
    for (final msg in list) {
      final seq = int.tryParse(msg.seq?.trim() ?? '') ?? 0;
      if (seq > newestSeq) newestSeq = seq;
    }
    if (newestSeq <= 0) return;
    final buffer = _reorderBuffersByConv.putIfAbsent(
      storageKey,
      () => InboundReorderBuffer(
        onFlush: (messages) {
          _applyInboundMessageBatch(storageKey, messages);
        },
        onGapTimeout: (anchorSeq, convID) {
          _triggerGroupGapCatchUp(convID, anchorSeq);
        },
      ),
    );
    buffer.activate(storageKey, newestSeq);
  }

  /// Triggers a CLOUD_NEWER pull when a group seq gap times out.
  Future<void> _triggerGroupGapCatchUp(
    String conversationID,
    int expectedSeq,
  ) async {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await reconcileConversationCloud(trimmed, reason: 'seq_gap_$expectedSeq');
  }

  V2TimMessage? _cloudCatchUpNewestAnchor(List<V2TimMessage> messages) {
    for (final message in messages) {
      if (HistoryPaginationAnchor.canUseForSdkPagination(message)) {
        return message;
      }
    }
    return null;
  }

  String _cloudCatchUpAnchorKey(V2TimMessage? anchor) {
    if (anchor == null) {
      return '';
    }
    final msgID = anchor.msgID?.trim() ?? '';
    if (msgID.isEmpty) {
      return '';
    }
    // Include the visible content signature in the in-memory key. A server
    // edit to the same message therefore invalidates the stalled decision.
    return '$msgID|${_messageListContentSignature(<V2TimMessage>[anchor])}';
  }

  Future<bool> _shouldHoldStalledCloudContinuation(
    String conversationID,
  ) async {
    final current = _mergedAliasMessageList(conversationID);
    final anchor = _cloudCatchUpNewestAnchor(current);
    final anchorID = anchor?.msgID?.trim() ?? '';
    if (anchorID.isEmpty) {
      return false;
    }
    final inMemory = _cloudCatchUpStalledAnchorByConv[conversationID];
    if (inMemory != null) {
      // A changed anchor or content is a fresh observation. Do not fall back
      // to the durable ID-only record, otherwise an edited tip would remain
      // blocked until another lifecycle event.
      if (inMemory == _cloudCatchUpAnchorKey(anchor)) {
        return true;
      }
      _cloudCatchUpStalledAnchorByConv.remove(conversationID);
      return false;
    }
    var coverage = messageHistoryCoverageFor(conversationID);
    coverage ??= await ensureMessageHistoryCoverageLoaded(conversationID);
    if (!coverage.cloudContinuationStalled ||
        coverage.continuationCursorMsgID != anchorID) {
      return false;
    }
    _cloudCatchUpStalledAnchorByConv[conversationID] = _cloudCatchUpAnchorKey(
      anchor,
    );
    return true;
  }

  Future<void> _markCloudCatchUpUnblocked(String conversationID) async {
    _cloudCatchUpStalledAnchorByConv.remove(conversationID);
    await _enqueueMessageHistoryCoverageUpdate(conversationID, () async {
      var coverage = messageHistoryCoverageFor(conversationID);
      coverage ??= await ensureMessageHistoryCoverageLoaded(conversationID);
      if (coverage.lastBatchKind != _cloudCatchUpStalledBatchKind) {
        return;
      }
      _storeMessageHistoryCoverage(
        coverage.copyWith(
          coverageRevision: coverage.coverageRevision + 1,
          lastBatchKind: _cloudCatchUpUnblockedBatchKind,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  Future<void> _recordCloudCatchUpStalled(
    String conversationID,
    List<V2TimMessage> current,
  ) async {
    final anchor = _cloudCatchUpNewestAnchor(current);
    final anchorID = anchor?.msgID?.trim() ?? '';
    if (anchorID.isEmpty) {
      return;
    }
    final anchorKey = _cloudCatchUpAnchorKey(anchor);
    _cloudCatchUpStalledAnchorByConv[conversationID] = anchorKey;
    await _enqueueMessageHistoryCoverageUpdate(conversationID, () async {
      var coverage = messageHistoryCoverageFor(conversationID);
      coverage ??= await ensureMessageHistoryCoverageLoaded(conversationID);
      final now = DateTime.now().millisecondsSinceEpoch;
      _storeMessageHistoryCoverage(
        coverage.copyWith(
          coverageRevision: coverage.coverageRevision + 1,
          status: MessageHistoryCoverageStatus.partial,
          newerHasMore: true,
          continuationPending: true,
          continuationDirection: MessageHistoryCoverageDirection.newer,
          continuationCursorMsgID: anchorID,
          clearContinuationCursor: false,
          lastBatchKind: _cloudCatchUpStalledBatchKind,
          lastCursorDirection: MessageHistoryCoverageDirection.newer.name,
          lastCursorMsgID: anchorID,
          clearLastCursor: false,
          updatedAtMs: now,
        ),
      );
    });
  }

  /// Runs one bounded cloud reconciliation for open/reconnect/foreground and
  /// gap-repair triggers. All fetched rows are committed through the same
  /// reconciliation writer as initial history and realtime callbacks.
  Future<MessageCloudCatchUpResult> reconcileConversationCloud(
    String conversationID, {
    required String reason,
  }) async {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    if (storageKey.isEmpty) {
      return const MessageCloudCatchUpResult(
        disposition: MessageCloudCatchUpDisposition.offline,
        attempts: 0,
        timedOut: false,
      );
    }
    if (_shouldDeferCloudCatchUpWhileReadingHistory(storageKey)) {
      ChatHistoryTrace.log(
        'cloud_catch_up_deferred_reading_history',
        conversationID: storageKey,
        extras: <String, Object?>{
          'reason': reason,
          'position': getMessageListPosition(storageKey).name,
          'memorySuppressed': isMemoryWindowSuppressed(storageKey),
          'missingNewer': memoryWindowMissingNewer(storageKey),
        },
      );
      return const MessageCloudCatchUpResult(
        disposition: MessageCloudCatchUpDisposition.settled,
        attempts: 0,
        timedOut: false,
      );
    }
    if (reason == 'cloud_continuation') {
      if (await _shouldHoldStalledCloudContinuation(storageKey)) {
        ChatHistoryTrace.log(
          'cloud_catch_up_stalled_hold',
          conversationID: storageKey,
          extras: <String, Object?>{'reason': reason},
        );
        return const MessageCloudCatchUpResult(
          disposition: MessageCloudCatchUpDisposition.stalled,
          attempts: 0,
          timedOut: false,
        );
      }
    } else {
      // A fresh lifecycle/open/bottom trigger is the explicit escape hatch
      // from a stalled same-anchor continuation.
      await _markCloudCatchUpUnblocked(storageKey);
    }
    if (reason != 'cloud_continuation') {
      _cancelCloudContinuation(storageKey, clearBudget: false);
      _cloudContinuationRoundsByConv[storageKey] = 0;
    }
    final result = await _boundedCloudCatchUp.run(
      conversationID: storageKey,
      operation: (attempt) =>
          _runCloudCatchUpAttempt(storageKey, reason: reason, attempt: attempt),
    );
    await _markUnresolvedGroupCoverageAfterCatchUp(storageKey, result);
    if (result.disposition == MessageCloudCatchUpDisposition.stalled) {
      await _recordCloudCatchUpStalled(
        storageKey,
        _mergedAliasMessageList(storageKey),
      );
    }
    if (result.settled) {
      ChatHistoryTrace.log(
        'cloud_catch_up_settled',
        conversationID: storageKey,
        extras: <String, Object?>{
          'reason': reason,
          'attempts': result.attempts,
        },
      );
    }
    if (result.completed || result.settled) {
      _cancelCloudContinuation(storageKey);
    } else if (result.needsContinuation) {
      _scheduleCloudContinuation(storageKey);
    }
    return result;
  }

  Future<void> _markUnresolvedGroupCoverageAfterCatchUp(
    String conversationID,
    MessageCloudCatchUpResult result,
  ) async {
    if (result.completed || result.settled || result.needsContinuation) return;
    final storageKey = _resolveMessageListStorageKey(conversationID);
    if (storageKey.isEmpty) return;
    await _enqueueMessageHistoryCoverageUpdate(storageKey, () async {
      final current = await ensureMessageHistoryCoverageLoaded(storageKey);
      final unresolved = current.holes
          .where(
            (hole) =>
                hole.kind == MessageHistoryHoleKind.groupSeq &&
                hole.status != MessageHistoryHoleStatus.resolved,
          )
          .toList(growable: false);
      if (!current.isGroup || unresolved.isEmpty) return;
      final nextHoleStatus =
          result.disposition == MessageCloudCatchUpDisposition.offline
              ? MessageHistoryHoleStatus.cloudUnavailable
              : MessageHistoryHoleStatus.retryable;
      if (unresolved.every((hole) => hole.status == nextHoleStatus)) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final holes = current.holes.map((hole) {
        if (hole.kind != MessageHistoryHoleKind.groupSeq ||
            hole.status == MessageHistoryHoleStatus.resolved) {
          return hole;
        }
        return MessageHistoryHole(
          key: hole.key,
          kind: hole.kind,
          status: nextHoleStatus,
          startSeq: hole.startSeq,
          endSeq: hole.endSeq,
          olderMsgID: hole.olderMsgID,
          newerMsgID: hole.newerMsgID,
          generation: hole.generation,
          updatedAtMs: now,
        );
      }).toList(growable: false);
      _storeMessageHistoryCoverage(
        current.copyWith(
          coverageRevision: current.coverageRevision + 1,
          status: result.disposition == MessageCloudCatchUpDisposition.offline
              ? MessageHistoryCoverageStatus.offlineLocalOnly
              : MessageHistoryCoverageStatus.partial,
          holes: holes,
          updatedAtMs: now,
        ),
      );
    });
  }

  void _scheduleCloudContinuation(String conversationID) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final current = storageKey.isEmpty
        ? const <V2TimMessage>[]
        : _mergedAliasMessageList(storageKey);
    if (storageKey.isEmpty ||
        _isGroupConversation(storageKey, messages: current) ||
        _cloudContinuationTimersByConv.containsKey(storageKey)) {
      return;
    }
    final rounds = _cloudContinuationRoundsByConv[storageKey] ?? 0;
    if (rounds >= _maxAutomaticCloudContinuationRounds ||
        !_chatAppForeground ||
        !_isSameConversationID(currentSelectedConv, storageKey) ||
        isChatListUserScrolling) {
      return;
    }
    final position = getMessageListPosition(storageKey);
    if (!_isActiveChatNearBottom(storageKey) &&
        position != HistoryMessagePosition.bottom) {
      return;
    }
    _cloudContinuationTimersByConv[storageKey] = Timer(
      _cloudContinuationDelay,
      () {
        _cloudContinuationTimersByConv.remove(storageKey);
        if (!_chatAppForeground ||
            !_isSameConversationID(currentSelectedConv, storageKey) ||
            isChatListUserScrolling ||
            _messageReconciliationWriter.hasActiveRequest(storageKey)) {
          return;
        }
        final currentRounds = _cloudContinuationRoundsByConv[storageKey] ?? 0;
        if (currentRounds >= _maxAutomaticCloudContinuationRounds) {
          return;
        }
        _cloudContinuationRoundsByConv[storageKey] = currentRounds + 1;
        unawaited(
          reconcileConversationCloud(storageKey, reason: 'cloud_continuation'),
        );
      },
    );
  }

  void _cancelCloudContinuation(
    String conversationID, {
    bool clearBudget = true,
  }) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    _cloudContinuationTimersByConv.remove(storageKey)?.cancel();
    if (clearBudget) {
      _cloudContinuationRoundsByConv.remove(storageKey);
    }
  }

  Future<MessageCloudCatchUpDisposition> _runCloudCatchUpAttempt(
    String storageKey, {
    required String reason,
    required MessageCloudCatchUpAttempt attempt,
  }) async {
    if (_shouldDeferCloudCatchUpWhileReadingHistory(storageKey)) {
      return MessageCloudCatchUpDisposition.settled;
    }
    final writerScope = _messageReconciliationWriter.configuredScope;
    final windowScope = historyWindowScopeFor(storageKey);
    final networkBefore = messageReconciliationNetworkState;
    if (networkBefore != MessageReconciliationNetworkState.online) {
      return MessageCloudCatchUpDisposition.offline;
    }
    if (_messageReconciliationWriter.hasActiveRequest(storageKey)) {
      return MessageCloudCatchUpDisposition.retry;
    }
    final current = _mergedAliasMessageList(storageKey);
    if (current.isEmpty) {
      return MessageCloudCatchUpDisposition.complete;
    }
    final isGroup = _isGroupConversation(storageKey, messages: current);
    final clearEpoch = messageDeltaClearEpochFor(storageKey);
    _seedMessageWriterFromProjection(
      storageKey,
      current,
      clearEpoch: clearEpoch,
    );
    final request = _messageReconciliationWriter.beginCloudCatchUp(
      conversationID: storageKey,
      networkState: networkBefore,
      clearEpoch: clearEpoch,
    );
    attempt.onInvalidated(() {
      failHistoryReconciliation(
        request: request,
        reason: 'cloud_catch_up_timeout',
      );
    });
    final sdkConversationID = normalizeConversationIdForHistory(storageKey);
    final groupID = isGroup ? sdkConversationID : null;
    final userID = isGroup ? null : sdkConversationID;
    final missingSeqs = isGroup
        ? _boundedMissingGroupSeqs(current, maxCount: 100)
        : const <int>[];
    V2TimMessage? newestAnchor;
    var newestSeq = 0;
    for (final message in current) {
      if (!HistoryPaginationAnchor.canUseForSdkPagination(message)) {
        continue;
      }
      newestAnchor ??= message;
      final seq = int.tryParse(message.seq?.trim() ?? '') ?? 0;
      if (seq > newestSeq) {
        newestSeq = seq;
      }
    }
    if ((isGroup && missingSeqs.isEmpty && newestSeq <= 0) ||
        (!isGroup && newestAnchor == null)) {
      failHistoryReconciliation(
        request: request,
        reason: 'cloud_catch_up_missing_anchor',
      );
      return MessageCloudCatchUpDisposition.complete;
    }

    try {
      if (missingSeqs.isNotEmpty) {
        ChatHistoryTrace.log(
          'cloud_gap_exact_request',
          conversationID: storageKey,
          extras: <String, Object?>{
            'reason': reason,
            'missingCount': missingSeqs.length,
            'firstMissingSeq': missingSeqs.first,
            'lastMissingSeq': missingSeqs.last,
          },
        );
      }
      var response = await getHistoryMessageListThroughIm06(
        count: missingSeqs.isNotEmpty ? missingSeqs.length : 50,
        getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
        userID: userID,
        groupID: groupID,
        // Group reconciliation uses a Seq cursor only. Passing lastMsg too
        // would make the SDK silently ignore lastMsgSeq.
        lastMsgSeq: isGroup && missingSeqs.isEmpty ? newestSeq : 0,
        lastMsg: isGroup ? null : newestAnchor,
        messageSeqList: missingSeqs.isEmpty ? null : missingSeqs,
      );
      if (isGroup && missingSeqs.isNotEmpty && response == null) {
        final exactError = lastHistoryErrorMetadata(sdkConversationID);
        if (_shouldFallbackFromExactGroupSeqRequest(exactError)) {
          final fallbackAnchorSeq = missingSeqs.first - 1;
          final fallbackCount = _groupGapRangeFallbackCount(missingSeqs);
          ChatHistoryTrace.log(
            'cloud_gap_exact_fallback',
            conversationID: storageKey,
            extras: <String, Object?>{
              'reason': reason,
              'errorCode': exactError?['errorCode'],
              'description': exactError?['description'],
              'anchorSeq': fallbackAnchorSeq,
              'count': fallbackCount,
              'missingCount': missingSeqs.length,
            },
          );
          response = await getHistoryMessageListThroughIm06(
            count: fallbackCount,
            getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
            groupID: groupID,
            lastMsgSeq: fallbackAnchorSeq,
          );
          ChatHistoryTrace.log(
            'cloud_gap_range_fallback_result',
            conversationID: storageKey,
            extras: <String, Object?>{
              'reason': reason,
              'success': response != null,
              'anchorSeq': fallbackAnchorSeq,
              'count': fallbackCount,
              'returnedCount': response?.messageList.length ?? 0,
              'isFinished': response?.isFinished,
            },
          );
        }
      }
      if (!attempt.isCurrent) {
        failHistoryReconciliation(
          request: request,
          reason: 'cloud_catch_up_stale_attempt',
        );
        return MessageCloudCatchUpDisposition.retry;
      }
      if (_shouldDeferCloudCatchUpWhileReadingHistory(storageKey)) {
        failHistoryReconciliation(
          request: request,
          reason: 'cloud_catch_up_deferred_reading_history',
        );
        return MessageCloudCatchUpDisposition.settled;
      }
      if (response == null) {
        failHistoryReconciliation(
          request: request,
          reason: 'cloud_catch_up_null_response',
        );
        return MessageCloudCatchUpDisposition.retry;
      }
      if (!isGroup &&
          !response.isFinished &&
          !_c2cCatchUpHasNewMessage(current, response.messageList)) {
        // C2C has no conversation-wide Seq. If the SDK returns the same page
        // under the same lastMsg anchor, another immediate continuation would
        // repeat the request forever. Keep reconciliation incomplete and wait
        // for a later foreground/reconnect/bottom-edge trigger.
        failHistoryReconciliation(
          request: request,
          reason: 'cloud_catch_up_no_progress',
        );
        return MessageCloudCatchUpDisposition.stalled;
      }
      if (_messageReconciliationWriter.configuredScope != writerScope ||
          messageDeltaClearEpochFor(storageKey) != clearEpoch ||
          (windowScope != null && !isHistoryWindowScopeCurrent(windowScope))) {
        failHistoryReconciliation(
            request: request, reason: 'cloud_catch_up_stale_scope');
        return MessageCloudCatchUpDisposition.retry;
      }
      final authoritativePage =
          await applyHistoryWindowMutations(storageKey, response.messageList);
      if (!attempt.isCurrent ||
          _messageReconciliationWriter.configuredScope != writerScope ||
          messageDeltaClearEpochFor(storageKey) != clearEpoch ||
          (windowScope != null && !isHistoryWindowScopeCurrent(windowScope)) ||
          _shouldDeferCloudCatchUpWhileReadingHistory(storageKey)) {
        failHistoryReconciliation(
            request: request, reason: 'cloud_catch_up_stale_after_authority');
        return MessageCloudCatchUpDisposition.retry;
      }
      final networkAfter = messageReconciliationNetworkState;
      final provenance = MessageReconciliationProvenance.resolve(
        requestedSource: MessageReconciliationSource.cloud,
        beforeRequest: networkBefore,
        afterResponse: networkAfter,
      );
      final returnedOldest = _oldestServerHistoryMessage(response.messageList);
      final returnedNewest = _newestServerHistoryMessage(response.messageList);
      final catchUpCursor = MessageHistoryCursor(
        direction: missingSeqs.isEmpty
            ? MessageHistoryCursorDirection.newer
            : MessageHistoryCursorDirection.older,
        lastMsgID: missingSeqs.isEmpty && !isGroup ? newestAnchor?.msgID : null,
        lastMsgSeq: missingSeqs.isNotEmpty
            ? missingSeqs.first
            : (isGroup && newestSeq > 0 ? newestSeq : null),
      );
      final commit = completeHistoryReconciliation(
        request: request,
        history: authoritativePage,
        actualSource: provenance.actualSource,
        networkState: provenance.networkState,
        historyCommitSource: 'cloud_catch_up:$reason:a${attempt.number}',
        cloudHasMoreNewer: missingSeqs.isEmpty && !response.isFinished,
        batchKind: missingSeqs.isEmpty
            ? MessageHistoryBatchKind.newerCatchUp
            : MessageHistoryBatchKind.gapFill,
        historyIsFinished: response.isFinished,
        clearEpoch: messageHistoryCoverageFor(storageKey)?.clearEpoch ?? 0,
        requestedCursor: catchUpCursor,
        returnedBounds: MessageHistoryBounds(
          oldestMsgID: returnedOldest?.msgID,
          newestMsgID: returnedNewest?.msgID,
          oldestSeq: _messageNumericSeq(returnedOldest),
          newestSeq: _messageNumericSeq(returnedNewest),
        ),
        cloudResponseProven: provenance.cloudResponseProven,
      );
      if (commit == null) {
        return MessageCloudCatchUpDisposition.retry;
      }
      if (!provenance.cloudResponseProven) {
        return MessageCloudCatchUpDisposition.offline;
      }
      final state = _messageReconciliationWriter.coordinator.stateFor(
        storageKey,
      );
      final needsAnotherPage = missingSeqs.isEmpty && !response.isFinished;
      if (state.missingSeqRanges.isNotEmpty || needsAnotherPage) {
        return needsAnotherPage
            ? MessageCloudCatchUpDisposition.continuation
            : MessageCloudCatchUpDisposition.retry;
      }
      // A successful finished transport response ends this bounded pass, but
      // does not upgrade durable coverage to verified. A later open/reconnect
      // can validate again without three identical immediate retries.
      if (provenance.proofKind != MessageHistoryProofKind.serverContinuity) {
        return MessageCloudCatchUpDisposition.settled;
      }
      return MessageCloudCatchUpDisposition.complete;
    } catch (_) {
      if (attempt.isCurrent) {
        failHistoryReconciliation(
          request: request,
          reason: 'cloud_catch_up_exception',
        );
      }
      return MessageCloudCatchUpDisposition.retry;
    }
  }

  bool _c2cCatchUpHasNewMessage(
    List<V2TimMessage> current,
    List<V2TimMessage> fetched,
  ) {
    final known = <String, String>{};
    for (final message in current) {
      final id = (message.msgID?.trim().isNotEmpty ?? false)
          ? message.msgID!.trim()
          : (message.id?.trim() ?? '');
      if (id.isNotEmpty) {
        known[id] = _messageListContentSignature(<V2TimMessage>[message]);
      }
    }
    for (final message in fetched) {
      final id = (message.msgID?.trim().isNotEmpty ?? false)
          ? message.msgID!.trim()
          : (message.id?.trim() ?? '');
      if (id.isEmpty || !known.containsKey(id)) return true;
      if (known[id] != _messageListContentSignature(<V2TimMessage>[message])) {
        return true;
      }
    }
    return false;
  }

  List<int> _boundedMissingGroupSeqs(
    List<V2TimMessage> newestFirst, {
    required int maxCount,
  }) {
    final gaps = GapDetector.detectGaps(
      newestFirst: newestFirst,
      isGroup: true,
      fullScan: true,
    );
    if (gaps.isEmpty) {
      return const <int>[];
    }
    final seqs = <int>[];
    for (final gap in gaps) {
      final lower = gap.lowerSeq;
      final upper = gap.upperSeq;
      if (lower == null || upper == null) {
        continue;
      }
      for (var seq = lower + 1; seq < upper && seqs.length < maxCount; seq++) {
        seqs.add(seq);
      }
      if (seqs.length >= maxCount) {
        break;
      }
    }
    return List<int>.unmodifiable(seqs);
  }

  bool _shouldFallbackFromExactGroupSeqRequest(
    Map<String, Object?>? error,
  ) {
    if (error == null) return false;
    final code = int.tryParse(error['errorCode']?.toString() ?? '');
    final description =
        error['description']?.toString().trim().toLowerCase() ?? '';
    return code == 10004 ||
        description.contains('msgseqlist') ||
        description.contains('message seq list');
  }

  int _groupGapRangeFallbackCount(List<int> missingSeqs) {
    if (missingSeqs.isEmpty) return 20;
    var contiguousCount = 1;
    for (var index = 1; index < missingSeqs.length; index++) {
      if (missingSeqs[index] != missingSeqs[index - 1] + 1) break;
      contiguousCount++;
    }
    // Include enough messages to cross the first missing range while keeping
    // the fallback bounded. A minimum page avoids another one-row edge case.
    return (contiguousCount + 2).clamp(20, 100);
  }

  void _requestDetectedGroupGapCatchUp(String conversationID, GapInfo gap) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final lower = gap.lowerSeq ?? 0;
    final upper = gap.upperSeq ?? 0;
    if (storageKey.isEmpty || lower <= 0 || upper <= lower + 1) {
      return;
    }
    if (_shouldDeferCloudCatchUpWhileReadingHistory(storageKey)) {
      ChatHistoryTrace.log(
        'seq_gap_catch_up_deferred_reading_history',
        conversationID: storageKey,
        extras: <String, Object?>{
          'lowerSeq': lower,
          'upperSeq': upper,
          'position': getMessageListPosition(storageKey).name,
          'memorySuppressed': isMemoryWindowSuppressed(storageKey),
        },
      );
      return;
    }
    final rangeKey = '$storageKey:$lower-$upper';
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = _groupGapAutoAttemptAtMs[rangeKey] ?? 0;
    if (now - previous < _groupGapAutoCooldownMs) {
      return;
    }
    _groupGapAutoAttemptAtMs[rangeKey] = now;
    unawaited(
      reconcileConversationCloud(storageKey, reason: 'seq_gap_${lower}_$upper'),
    );
  }

  bool _shouldDeferCloudCatchUpWhileReadingHistory(String conversationID) {
    return isMemoryWindowSuppressed(conversationID) ||
        isReadingHistory(conversationID);
  }

  void _clearResolvedGroupGapAttempts(
    String conversationID,
    List<GapInfo> gaps,
  ) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final active = <String>{
      for (final gap in gaps)
        '$storageKey:${gap.lowerSeq ?? 0}-${gap.upperSeq ?? 0}',
    };
    _groupGapAutoAttemptAtMs.removeWhere(
      (key, _) => key.startsWith('$storageKey:') && !active.contains(key),
    );
  }

  /// 保留当前消息窗口，只撤销“首屏已验证”资格。
  ///
  /// LOCAL-only 预热刷新了旧暖窗时使用；不清消息、分页提示、搜索或位置状态。
  void clearInitialHistoryLoaded(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _initialHistoryLoadedConvs.removeWhere(
      (key) => _isSameConversationID(key, trimmed),
    );
  }

  void markInitialHistoryMayHaveOlder(
    String conversationID, {
    required bool mayHaveOlder,
  }) {
    final keys = _historyFlagKeys(conversationID);
    if (keys.isEmpty) {
      return;
    }
    if (mayHaveOlder) {
      for (final key in keys) {
        _mayHaveOlderHistoryByConv[key] = true;
      }
    } else {
      for (final key in keys) {
        _mayHaveOlderHistoryByConv.remove(key);
      }
    }
  }

  bool mayHaveOlderHistory(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_mayHaveOlderHistoryByConv[trimmed] == true) {
      return true;
    }
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty &&
        _mayHaveOlderHistoryByConv[normalized] == true) {
      return true;
    }
    for (final entry in _mayHaveOlderHistoryByConv.entries) {
      if (entry.value && _isSameConversationID(entry.key, trimmed)) {
        return true;
      }
    }
    return false;
  }

  /// Raw in-memory window for warm/open short-circuit (alias-aware).
  ///
  /// 若本 key 上是空 list、但等价别名仍有消息，优先返回非空别名窗——
  /// 否则 tip-strip / hydrate_keep_empty 写过的空占位会永远挡住真实暖窗（灰屏）。
  List<V2TimMessage>? rawMessageList(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    List<V2TimMessage>? emptyPlaceholder;
    final direct = _messageListMap[trimmed];
    if (direct != null) {
      if (direct.isNotEmpty) {
        return direct;
      }
      emptyPlaceholder = direct;
    }
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty) {
      final byNorm = _messageListMap[normalized];
      if (byNorm != null && byNorm.isNotEmpty) {
        return byNorm;
      }
      emptyPlaceholder ??= byNorm;
    }
    for (final entry in _messageListMap.entries) {
      if (!_isSameConversationID(entry.key, trimmed)) {
        continue;
      }
      final aliasList = entry.value;
      if (aliasList == null) {
        continue;
      }
      if (aliasList.isNotEmpty) {
        return aliasList;
      }
      emptyPlaceholder ??= aliasList;
    }
    return emptyPlaceholder;
  }

  /// 是否仍有进页 hydrate / 冷开并行 peek 在飞（别名感知）。
  bool hasOpenHydrateInFlight(String conversationID) {
    return _findOpenHydrateInFlight(conversationID) != null;
  }

  /// Last terminal result for the app-owned first-window bootstrap. This is
  /// separate from the in-flight map so a caller arriving just after
  /// completion can consume the same result without issuing LOCAL/CLOUD again.
  OpenHydrateResult? openHydrateResultFor(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) return null;
    final direct = _openHydrateResultByConv[trimmed];
    if (direct != null) return direct;
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty) {
      final byNorm = _openHydrateResultByConv[normalized];
      if (byNorm != null) return byNorm;
    }
    for (final entry in _openHydrateResultByConv.entries) {
      if (_isSameConversationID(entry.key, trimmed)) return entry.value;
    }
    return null;
  }

  OpenHydrateResult? takeOpenHydrateResult(String conversationID) {
    final result = openHydrateResultFor(conversationID);
    if (result != null) {
      clearOpenHydrateResult(conversationID);
    }
    return result;
  }

  void publishOpenHydrateResult(
    String conversationID,
    OpenHydrateResult result,
  ) {
    final key = conversationID.trim();
    if (key.isEmpty) return;
    for (final alias in _historyFlagKeys(key)) {
      _openHydrateResultByConv[alias] = result;
    }
  }

  void clearOpenHydrateResult(String conversationID) {
    final key = conversationID.trim();
    if (key.isEmpty) return;
    _openHydrateResultByConv.removeWhere(
      (alias, _) => _isSameConversationID(alias, key),
    );
  }

  Future<OpenHydrateResult>? _findOpenHydrateInFlight(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final direct = _openHydrateInFlightByConv[trimmed];
    if (direct != null) {
      return direct;
    }
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty) {
      final byNorm = _openHydrateInFlightByConv[normalized];
      if (byNorm != null) {
        return byNorm;
      }
    }
    for (final entry in _openHydrateInFlightByConv.entries) {
      if (_isSameConversationID(entry.key, trimmed)) {
        return entry.value;
      }
    }
    return null;
  }

  /// The route, page and UIKit share one task and its terminal result.
  /// A caller timing out does not remove the underlying task.
  Future<OpenHydrateResult> ensureOpenHydrate(
    String conversationID, {
    required String requestSignature,
    required Future<bool> Function() load,
    required bool Function() canPublish,
  }) {
    final key = conversationID.trim();
    final existing = _findOpenHydrateInFlight(key);
    if (existing != null && (_openHydrateCanPublish[existing]?.call() ?? true)) {
      final joinTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
      ChatOpenPerfLog.markHydrateJoined(
        ChatOpenPerfLog.lastPrepareRequestId,
        trace: joinTrace,
      );
      ChatOpenPerfLog.mark(
        'app_hydrate_join',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': joinTrace.requestId,
          'prepareId': joinTrace.requestId,
        },
        trace: joinTrace,
      );
      if (_isSameConversationID(_openBottomCapsuleLockConvId, key)) {
        _openBottomCapsuleHydrateSettled = false;
      }
      return existing;
    }
    final previous = openHydrateResultFor(key);
    if (previous != null &&
        previous.requestSignature == requestSignature &&
        previous.shouldSuppressOrdinaryLoad &&
        hasInitialHistoryLoaded(key)) {
      final reuseTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
      ChatOpenPerfLog.mark(
        'app_hydrate_reuse',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': reuseTrace.requestId,
          'prepareId': reuseTrace.requestId,
          'hydrateKind': previous.kind.name,
        },
        trace: reuseTrace,
      );
      markOpenChatHydrateSettled(key);
      return Future.value(previous);
    }
    clearOpenHydrateResult(key);
    final generation = _messageHistoryCoverageSessionGeneration;
    final clearEpoch = messageDeltaClearEpochFor(key);
    final ownerTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
    final ownerRequestId = ownerTrace.requestId;
    ChatOpenPerfLog.markHydrateOwner(ownerRequestId, trace: ownerTrace);
    ChatOpenPerfLog.mark(
      'app_hydrate_registered',
      conversationID: key,
      extras: <String, Object?>{
        'requestId': ownerRequestId,
        'prepareId': ownerRequestId,
      },
      trace: ownerTrace,
    );
    late final Future<OpenHydrateResult> task;
    final ownerSpan = ChatOpenPerfLog.queueSpan('hydrate_producer',
        trace: ownerTrace, source: 'shared_local');
    task = Future<OpenHydrateResult>.microtask(() async {
      ownerSpan?.start();
      var kind = OpenHydrateResultKind.aborted;
      ChatOpenPerfLog.mark(
        'app_hydrate_started',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': ownerRequestId,
          'prepareId': ownerRequestId,
        },
        trace: ownerTrace,
      );
      try {
        if (canPublish() && await ChatOpenPerfLog.withSpan(ownerSpan, load)) {
          kind = rawMessageCount(key) > 0
              ? OpenHydrateResultKind.committedMessages
              : OpenHydrateResultKind.committedEmpty;
        }
      } catch (_) {
        kind = OpenHydrateResultKind.failed;
      }
      final current = generation == _messageHistoryCoverageSessionGeneration &&
          clearEpoch == messageDeltaClearEpochFor(key) &&
          identical(_findOpenHydrateInFlight(key), task) &&
          canPublish();
      if (!current) kind = OpenHydrateResultKind.aborted;
      final result = OpenHydrateResult(
        kind: kind,
        conversationKey: key,
        resultCount: current ? rawMessageCount(key) : 0,
        firstWindowCommitted: current &&
            (kind == OpenHydrateResultKind.committedMessages ||
                kind == OpenHydrateResultKind.committedEmpty),
        generation: generation,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
        requestSignature: requestSignature,
      );
      if (current) {
        publishOpenHydrateResult(key, result);
        ChatOpenPerfLog.mark(
          'app_hydrate_commit',
          conversationID: key,
          extras: <String, Object?>{
            'requestId': ownerRequestId,
            'prepareId': ownerRequestId,
            'hydrateKind': kind.name,
          },
          trace: ownerTrace,
        );
      } else {
        ChatOpenPerfLog.mark(
          'app_hydrate_aborted',
          conversationID: key,
          extras: <String, Object?>{
            'requestId': ownerRequestId,
            'prepareId': ownerRequestId,
            'hydrateKind': kind.name,
            'staleReason': 'hydrateAborted',
          },
          trace: ownerTrace,
        );
      }
      ownerSpan?.finish(outcome: kind.name, extras: <String, Object?>{
        'rawCount': result.resultCount,
        'committed': result.firstWindowCommitted,
      });
      return result;
    }).whenComplete(() {
      ownerSpan?.finish(outcome: 'error');
      final stillOwner = identical(_findOpenHydrateInFlight(key), task);
      _openHydrateInFlightByConv
          .removeWhere((_, value) => identical(value, task));
      if (stillOwner) markOpenChatHydrateSettled(key);
    });
    _openHydrateCanPublish[task] = canPublish;
    for (final alias in _historyFlagKeys(key)) {
      _openHydrateInFlightByConv[alias] = task;
    }
    if (_isSameConversationID(_openBottomCapsuleLockConvId, key)) {
      _openBottomCapsuleHydrateSettled = false;
    }
    return task;
  }

  Future<void> awaitOpenHydrateInFlight(
    String conversationID, {
    Duration timeout = const Duration(milliseconds: 450),
  }) async {
    final inFlight = _findOpenHydrateInFlight(conversationID);
    if (inFlight == null) {
      return;
    }
    try {
      await inFlight.timeout(timeout);
    } on TimeoutException {
      // hydrate 自行兜底。
    }
  }

  int rawMessageCount(String conversationID) {
    return rawMessageList(conversationID)?.length ?? 0;
  }

  bool memoryWindowMissingNewer(String conversationID) {
    for (final entry in _memoryWindowMissingNewerByConv.entries) {
      if (entry.value && _isSameConversationID(entry.key, conversationID)) {
        return true;
      }
    }
    return false;
  }

  /// True when the in-memory window was trimmed and must be reconciled with
  /// SDK history before it can be considered a complete open window.
  /// This is deliberately separate from the SDK's own "has more" flags.
  bool memoryWindowNeedsReconciliation(String conversationID) {
    return memoryWindowMissingNewer(conversationID) ||
        _memoryWindowMissingOlderByConv.entries.any(
          (entry) =>
              entry.value && _isSameConversationID(entry.key, conversationID),
        );
  }

  bool memoryWindowReconciliationCovered(
    String conversationID,
    List<V2TimMessage>? messages,
  ) {
    if (!memoryWindowNeedsReconciliation(conversationID) ||
        messages == null ||
        messages.isEmpty) return false;
    final boundary = _memoryWindowBoundaryTimestampByConv.entries
        .where((e) => _isSameConversationID(e.key, conversationID))
        .map((e) => e.value)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final newer = memoryWindowMissingNewer(conversationID);
    final older = _memoryWindowMissingOlderByConv.entries.any(
      (e) => e.value && _isSameConversationID(e.key, conversationID),
    );
    if (boundary <= 0) return messages.isNotEmpty;
    final timestamps =
        messages.map((m) => m.timestamp ?? 0).where((v) => v > 0);
    if (timestamps.isNotEmpty) {
      final minTs = timestamps.reduce((a, b) => a < b ? a : b);
      final maxTs = timestamps.reduce((a, b) => a > b ? a : b);
      if (newer && maxTs > boundary) return true;
      if (older && minTs < boundary) return true;
    }
    final seqs = messages
        .map((m) => int.tryParse(m.seq?.trim() ?? '') ?? 0)
        .where((v) => v > 0);
    final boundarySeq = int.tryParse(
          _memoryWindowBoundarySeqByConv.entries
              .firstWhere(
                (e) => _isSameConversationID(e.key, conversationID),
                orElse: () => const MapEntry('', ''),
              )
              .value,
        ) ??
        0;
    if (boundarySeq > 0 && seqs.isNotEmpty) {
      final minSeq = seqs.reduce((a, b) => a < b ? a : b);
      final maxSeq = seqs.reduce((a, b) => a > b ? a : b);
      return (newer && maxSeq > boundarySeq) || (older && minSeq < boundarySeq);
    }
    return false;
  }

  void markMemoryWindowMissingNewer(String conversationID) {
    final key = conversationID.trim();
    if (key.isEmpty) {
      return;
    }
    _memoryWindowMissingNewerByConv[key] = true;
  }

  void markMemoryWindowMissingOlder(String conversationID) {
    final key = conversationID.trim();
    if (key.isNotEmpty) _memoryWindowMissingOlderByConv[key] = true;
  }

  void clearMemoryWindowMissingNewer(String conversationID) {
    final keys = _memoryWindowMissingNewerByConv.keys
        .where((k) => _isSameConversationID(k, conversationID))
        .toList(growable: false);
    for (final key in keys) {
      _memoryWindowMissingNewerByConv.remove(key);
    }
  }

  void clearMemoryWindowReconciliation(String conversationID) {
    clearMemoryWindowMissingNewer(conversationID);
    final keys = _memoryWindowMissingOlderByConv.keys
        .where((k) => _isSameConversationID(k, conversationID))
        .toList(growable: false);
    for (final key in keys) {
      _memoryWindowMissingOlderByConv.remove(key);
      _memoryWindowBoundaryTimestampByConv.remove(key);
      _memoryWindowBoundarySeqByConv.remove(key);
    }
  }

  void setMemoryWindowSuppressed(String conversationID, bool suppressed) {
    final key = conversationID.trim();
    if (key.isEmpty) {
      return;
    }
    final wasSuppressed = isMemoryWindowSuppressed(conversationID);
    if (suppressed) {
      _memoryWindowSuppressedConvs.add(key);
    } else {
      _memoryWindowSuppressedConvs.removeWhere(
        (k) => _isSameConversationID(k, conversationID),
      );
    }
    if (wasSuppressed != suppressed) {
      ChatJitterDiag.log(
        'memory_window',
        conv: conversationID,
        extras: <String, Object?>{
          'action': suppressed ? 'suppress_on' : 'suppress_off',
          'rawCount': rawMessageCount(conversationID),
          'position': getMessageListPosition(conversationID).name,
        },
      );
    }
  }

  bool isMemoryWindowSuppressed(String conversationID) {
    return _memoryWindowSuppressedConvs.any(
      (k) => _isSameConversationID(k, conversationID),
    );
  }

  /// IM `onSyncServerFinish`：90 天漫游入库后通知打开中的聊天页重拉连续窗。
  void addRoamingSyncListener(VoidCallback listener) {
    if (_roamingSyncListeners.contains(listener)) {
      return;
    }
    _roamingSyncListeners.add(listener);
  }

  void removeRoamingSyncListener(VoidCallback listener) {
    _roamingSyncListeners.remove(listener);
  }

  void notifyRoamingSyncFinished() {
    final listeners = List<VoidCallback>.of(_roamingSyncListeners);
    for (final listener in listeners) {
      listener();
    }
  }

  /// 上翻分页前挂上视口锚，供 [setMessageList] 做双向窗口裁剪。
  void setMemoryWindowAnchor(
    String conversationID, {
    String? msgID,
    String? seq,
  }) {
    _memoryWindowAnchorConvID = conversationID.trim();
    _memoryWindowAnchorMsgID = msgID?.trim();
    _memoryWindowAnchorSeq = seq?.trim();
  }

  void clearMemoryWindowAnchor([String? conversationID]) {
    if (conversationID != null &&
        conversationID.trim().isNotEmpty &&
        _memoryWindowAnchorConvID != null &&
        !_isSameConversationID(_memoryWindowAnchorConvID!, conversationID)) {
      return;
    }
    _memoryWindowAnchorConvID = null;
    _memoryWindowAnchorMsgID = null;
    _memoryWindowAnchorSeq = null;
  }

  /// 对当前内存列表再跑一遍窗口闸门（搜索抑制解除后收束超长窗）。
  void applyMessageMemoryWindowNow(
    String conversationID, {
    String? memoryWindowAnchorMsgID,
    String? memoryWindowAnchorSeq,
    bool memoryWindowPreferLatest = false,
    bool forceWhileReadingHistory = false,
  }) {
    final list = rawMessageList(conversationID);
    if (list == null || list.isEmpty) {
      return;
    }
    if (list.length <= ChatMessageWindowPolicy.softMax) {
      return;
    }
    setMessageList(
      conversationID,
      List<V2TimMessage>.of(list),
      needResetNewMessageCount: false,
      replace: true,
      memoryWindowPreferLatest: memoryWindowPreferLatest,
      memoryWindowAnchorMsgID: memoryWindowAnchorMsgID,
      memoryWindowAnchorSeq: memoryWindowAnchorSeq,
      forceMemoryWindowTrimWhileReading: forceWhileReadingHistory,
    );
  }

  bool isMessageInMemoryWindow(
    String conversationID, {
    String? msgID,
    String? seq,
  }) {
    final list = rawMessageList(conversationID);
    if (list == null || list.isEmpty) {
      return false;
    }
    final id = msgID?.trim() ?? '';
    final s = seq?.trim() ?? '';
    for (final message in list) {
      if (id.isNotEmpty) {
        final mid = message.msgID?.trim() ?? '';
        final lid = message.id?.trim() ?? '';
        if (mid == id || lid == id) {
          return true;
        }
      }
      if (s.isNotEmpty && (message.seq?.trim() ?? '') == s) {
        return true;
      }
    }
    return false;
  }

  /// Leave-chat warm trim: keep newest-first [keepCount] rows (tips included).
  /// Does not delete DB/SDK storage. No-op when already within budget or empty.
  bool trimMessageListToNewestWarmWindow(
    String conversationID, {
    int keepCount = HistoryMessageDartConstant.initialOpenFetchCount,
  }) {
    final trimmedId = conversationID.trim();
    if (trimmedId.isEmpty || keepCount <= 0) {
      return false;
    }
    final list = rawMessageList(trimmedId);
    if (list == null || list.isEmpty) {
      return false;
    }
    final beforeCount = list.length;
    if (beforeCount <= keepCount) {
      return false;
    }
    final kept = List<V2TimMessage>.from(list.sublist(0, keepCount));
    clearMemoryWindowMissingNewer(trimmedId);
    clearMemoryWindowAnchor(trimmedId);
    setMemoryWindowSuppressed(trimmedId, false);
    setMessageList(
      trimmedId,
      kept,
      needResetNewMessageCount: false,
      replace: true,
      applyMemoryWindow: false,
    );
    markInitialHistoryLoaded(trimmedId);
    markInitialHistoryMayHaveOlder(trimmedId, mayHaveOlder: true);
    ChatHistoryTrace.log(
      'history_leave_trim_to_warm',
      conversationID: trimmedId,
      extras: <String, Object?>{
        'beforeCount': beforeCount,
        'afterCount': kept.length,
        'keepCount': keepCount,
      },
    );
    return true;
  }

  void removeMessageList(String conversationID) {
    final subscriptions = _outboxSubscriptionConversations.entries
        .where((entry) => _isSameConversationID(entry.value, conversationID))
        .map((entry) => entry.key).toList(growable: false);
    for (final key in subscriptions) {
      _outboxSubscriptionConversations.remove(key);
      _outboxResultSubscriptions.remove(key)?.call();
    }
    clearOpenHydrateResult(conversationID);
    _openHydrateInFlightByConv.removeWhere(
      (key, _) => _isSameConversationID(key, conversationID),
    );
    final normalized = _normalizeConversationID(conversationID);
    if (OutgoingVisibleProbe.matches(conversationID) ||
        OutgoingVisibleProbe.matches(normalized) ||
        OutgoingVisibleProbe.matches(OutgoingVisibleProbe.lastConvID)) {
      OutgoingVisibleProbe.log(
        'remove_message_list',
        conversationID: conversationID,
        extras: <String, Object?>{
          'normalized': normalized,
          ...OutgoingVisibleProbe.trackedInList(rawMessageList(conversationID)),
        },
      );
    }
    final keys = <String>{
      if (conversationID.trim().isNotEmpty) conversationID.trim(),
      if (normalized.isNotEmpty) normalized,
    };
    keys.addAll(
      _messageListMap.keys
          .where(
            (mapKey) => keys.any((key) => _isSameConversationID(mapKey, key)),
          )
          .toList(growable: false),
    );
    // Reuse the warm-cache eviction boundary for every retained authority.
    // An in-flight Writer still owns its pending deltas and request generation.
    final writerKey = canonicalHistoryStorageKey(conversationID);
    if (!_isSameConversationID(conversationID, currentSelectedConv) &&
        !_messageReconciliationWriter.hasActiveRequest(writerKey) &&
        _messageReconciliationWriter.pendingDeltaCount(writerKey) == 0) {
      _messageReconciliationWriter.reset(writerKey);
      _writerProjectionAuthorities.remove(writerKey);
      final session = _boundedHistory.sessions.remove(writerKey);
      if (session != null) _closeBoundedHistorySession(session);
    }
    // Drop every loaded/mayHaveOlder alias first — leftover flags after a wipe
    // make open path think the window is warm while map is empty (灰屏).
    _clearHistoryFlagsForConversation(conversationID);
    clearMemoryWindowMissingNewer(conversationID);
    clearMemoryWindowAnchor(conversationID);
    setMemoryWindowSuppressed(conversationID, false);
    for (final key in keys) {
      _messageListMap.remove(key);
      _rowLocalAliasByConversation.remove(key);
      _messageListContentSignatureByConv.remove(key);
      _historyMessagePositionMap.remove(key);
      _searchJumpStatusMap.remove(_searchJumpStateKey(key));
      _updateSearchJumpWorkGate();
      _messageListDisplayCache.removeWhere(
        (cacheKey, _) => _isSameConversationID(cacheKey, key),
      );
    }
    if (keys.isNotEmpty) {
      _markNeedsNotify();
    }
  }

  /// 清空聊天记录后的内存态：空列表 + 已加载完成。
  /// 必须保留 initialLoaded，否则消息列表会一直显示 bootstrapping 转圈。
  void clearLocalHistoryAsEmptyLoaded(String conversationID) {
    clearOpenHydrateResult(conversationID);
    _openHydrateInFlightByConv.removeWhere(
      (key, _) => _isSameConversationID(key, conversationID),
    );
    final normalized = _normalizeConversationID(conversationID);
    final keys = <String>{
      if (conversationID.trim().isNotEmpty) conversationID.trim(),
      if (normalized.isNotEmpty) normalized,
    };
    // hydrate / 预载会把同一份列表写在等价别名 key（如 group_ 前缀）下；
    // 只清字面 key 会留下旧窗口，再进页时被别名读回（清空后仍闪旧记录）。
    keys.addAll(
      _messageListMap.keys
          .where(
            (mapKey) => keys.any((key) => _isSameConversationID(mapKey, key)),
          )
          .toList(growable: false),
    );
    for (final key in keys) {
      // Clearing the visible window is also a formal replacement. Reset any
      // in-flight writer transaction first, then publish the empty snapshot
      // through the compatibility admission so stale history cannot restore
      // rows after the clear.
      _messageReconciliationWriter.reset(key);
      setMessageList(
        key,
        const <V2TimMessage>[],
        needResetNewMessageCount: false,
        isDeleteMsg: true,
        replace: true,
        applyMemoryWindow: false,
        historyCommitSource: 'clear_local_history',
      );
      _messageListContentSignatureByConv.remove(key);
      _initialHistoryLoadedConvs.add(key);
      _mayHaveOlderHistoryByConv.remove(key);
      _storeHistoryMessagePosition(key, HistoryMessagePosition.bottom);
      _searchJumpStatusMap.remove(_searchJumpStateKey(key));
      _updateSearchJumpWorkGate();
      // 展示层缓存必须同步失效：否则清空后再进页，getMessageList 仍会
      // 命中旧缓存，把已清空的消息整窗闪现一帧再塌掉（进页「抖两次」）。
      _messageListDisplayCache.removeWhere(
        (cacheKey, _) => _isSameConversationID(cacheKey, key),
      );
    }
    if (keys.isNotEmpty) {
      _markNeedsNotify();
    }
  }

  bool isSearchJumpPending(String conversationID) {
    final status = getSearchJumpStatus(conversationID);
    return status == SearchJumpStatus.loading ||
        status == SearchJumpStatus.positioning;
  }

  // Route IDs (c2c_peer/group_id) and SDK IDs (peer/id) address one jump.
  // Request ownership and UI status must use the same stable bucket as history.
  String _searchJumpStateKey(String conversationID) =>
      canonicalHistoryStorageKey(_safeConversationId(conversationID));

  SearchJumpStatus getSearchJumpStatus(String conversationID) {
    return _searchJumpStatusMap[_searchJumpStateKey(conversationID)] ??
        SearchJumpStatus.idle;
  }

  final Map<String, int> _searchJumpRequestMap = {};

  int searchJumpRequestFor(String conversationID) =>
      _searchJumpRequestMap[_searchJumpStateKey(conversationID)] ?? 0;

  bool isCurrentSearchJumpRequest(String conversationID, int requestID) =>
      searchJumpRequestFor(conversationID) == requestID;

  /// Reset synchronously, before a new route can inspect the previous window.
  int beginSearchJump(String conversationID) {
    final key = _searchJumpStateKey(conversationID);
    final requestID = searchJumpRequestFor(key) + 1;
    _searchJumpRequestMap[key] = requestID;
    setSearchJumpStatus(key, SearchJumpStatus.loading, notify: false);
    // Explicit navigation owns the viewport now. A menu-close restore must
    // neither block measured centering nor write its previous row afterward.
    if (isMessageContextMenuOverlayOpen ||
        _contextMenuViewportRestoreConversations
            .any((conv) => _isSameConversationID(conv, key))) {
      dismissAllContextMenuOverlays();
    }
    return requestID;
  }

  void setSearchJumpStatus(
    String conversationID,
    SearchJumpStatus status, {
    bool notify = false,
    int? requestID,
  }) {
    conversationID = _searchJumpStateKey(conversationID);
    if (requestID != null &&
        !isCurrentSearchJumpRequest(conversationID, requestID)) return;
    final previous = getSearchJumpStatus(conversationID);
    if (status == SearchJumpStatus.loading) {
      _clearKeyboardViewportTransition(conversationID);
    }
    if (previous != status) {
      ChatHistoryTrace.log('search_jump_status',
          conversationID: conversationID,
          extras: {'previous': previous.name, 'next': status.name});
    }
    if (status == SearchJumpStatus.idle) {
      _searchJumpStatusMap.remove(conversationID);
    } else {
      _searchJumpStatusMap[conversationID] = status;
    }
    _updateSearchJumpWorkGate();
    if (notify) {
      notifyListeners();
    }
  }

  void clearSearchJumpStatus(String conversationID, {bool notify = false}) {
    setSearchJumpStatus(conversationID, SearchJumpStatus.idle, notify: notify);
  }

  V2TimMessageReceipt? getMessageReadReceipt(String msgID) {
    return messageReadReceiptMap[msgID];
  }

  String _normalizeC2CKey(String value) {
    var key = value.trim();
    if (key.isEmpty) {
      return key;
    }
    if (key.toLowerCase().startsWith('c2c_')) {
      return key.substring(4);
    }
    if (key.toUpperCase().startsWith('C2C')) {
      return key.substring(3);
    }
    return key;
  }

  bool _isC2CConversationForPeer(String conversationID, String peerID) {
    final conv = _normalizeC2CKey(conversationID).toLowerCase();
    final peer = _normalizeC2CKey(peerID).toLowerCase();
    if (conv.isEmpty || peer.isEmpty) {
      return false;
    }
    return conv == peer;
  }

  int _c2cPeerReadTimestampFor(String conversationID) {
    final convKey = _normalizeC2CKey(conversationID).toLowerCase();
    if (convKey.isEmpty) {
      return 0;
    }
    var timestamp = 0;
    _c2cPeerReadTimestampMap.forEach((peerID, readAt) {
      if (_normalizeC2CKey(peerID).toLowerCase() == convKey &&
          readAt > timestamp) {
        timestamp = readAt;
      }
    });
    return timestamp;
  }

  bool isOutgoingC2CMessagePeerRead({
    required String conversationID,
    required V2TimMessage message,
  }) {
    if (message.isSelf != true) {
      return false;
    }
    final current = _messageInConversation(
      conversationID,
      clientId: message.id,
      msgID: message.msgID,
    );
    if (current?.isPeerRead == true || message.isPeerRead == true) {
      return true;
    }

    final msgID = current?.msgID ?? message.msgID;
    if (msgID != null && msgID.isNotEmpty) {
      final receipt = _messageReadReceiptMap[msgID];
      if (receipt?.isPeerRead == true) {
        return true;
      }
    }

    final readAt = _c2cPeerReadTimestampFor(conversationID);
    if (readAt <= 0) {
      return false;
    }
    final sentAt = current?.timestamp ?? message.timestamp ?? 0;
    return sentAt > 0 && sentAt <= readAt;
  }

  setShowC2cEditStatus(bool show) {
    _showC2cMessageEditStatus = show;
  }

  /// set edit status from chats
  setC2cMessageEditStatus(String userID, int status) {
    _c2cMessageEditStatusMap[userID] = status;
    if (status == 1) {
      if (_c2cMessageStatusShowTimer[userID] != null) {
        if (_c2cMessageStatusShowTimer[userID]!.isActive) {
          _c2cMessageStatusShowTimer[userID]!.cancel();
          _c2cMessageEditStatusMap[userID] = 0;
        }
      }
      _c2cMessageStatusShowTimer[userID] = Timer.periodic(
        const Duration(seconds: 5),
        (timer) {
          _c2cMessageEditStatusMap[userID] = 0;
          Timer? t = _c2cMessageStatusShowTimer[userID];
          if (t != null && t.isActive) {
            // 取消当前的定时器
            t.cancel();
          }
        },
      );
    }
    _markNeedsNotify(conversationID: userID);
  }

  int getC2cMessageEditStatus(String userID) {
    return _c2cMessageEditStatusMap[userID] ?? 0;
  }

  set abstractMessageBuilder(String Function(V2TimMessage message)? value) {
    _abstractMessageBuilder = value;
  }

  set appSearchBarBuilder(
    Widget Function(
      BuildContext context,
      TextEditingController controller,
      ValueChanged<String> onChanged,
    )? value,
  ) {
    _appSearchBarBuilder = value;
  }

  set appForwardSelectFriendPage(Widget Function(BuildContext context)? value) {
    _appForwardSelectFriendPage = value;
  }

  set appForwardSelectGroupPage(Widget Function(BuildContext context)? value) {
    _appForwardSelectGroupPage = value;
  }

  set appForwardRecentConversations(
    List<V2TimConversation> Function()? value,
  ) {
    _appForwardRecentConversations = value;
  }

  set appForwardRecentConversationsListenable(Listenable? value) {
    _appForwardRecentConversationsListenable = value;
  }

  set appSearchFaceUrlResolver(
    String Function(String userId, String fallbackFaceUrl)? value,
  ) {
    _appSearchFaceUrlResolver = value;
  }

  set appSearchGroupFaceUrlResolver(
    String Function(String groupId, String fallbackFaceUrl)? value,
  ) {
    _appSearchGroupFaceUrlResolver = value;
  }

  set appSearchGroupNameResolver(String? Function(String groupId)? value) {
    _appSearchGroupNameResolver = value;
  }

  set appSearchConversationDisplayResolver(
    SearchConversationDisplay Function({
      required String conversationId,
      V2TimFriendInfo? friendHint,
      V2TimGroupInfo? groupHint,
    })? value,
  ) {
    _appSearchConversationDisplayResolver = value;
  }

  set appSearchNameBuilder(
    Widget Function(BuildContext context, String userId, String name)? value,
  ) {
    _appSearchNameBuilder = value;
  }

  set appRootNavigator(NavigatorState? Function()? value) {
    _appRootNavigator = value;
  }

  set appContactPresenceBridgeBuilder(
    AppContactPresenceBridge Function(BuildContext context)? value,
  ) {
    _appContactPresenceBridgeBuilder = value;
  }

  set lifeCycle(ChatLifeCycle? value) {
    _lifeCycle = value;
    // messageShouldMount 变更后必须失效展示缓存，否则会继续用带「零高度行」的旧列表。
    _messageListDisplayCache.clear();
  }

  set groupApplicationList(List<V2TimGroupApplication> value) {
    _groupApplicationList = value;
  }

  void addGroupSystemNotice(GroupSystemNoticeItem notice) {
    _groupSystemNoticeList.removeWhere((item) => item.id == notice.id);
    _groupSystemNoticeList = [notice, ..._groupSystemNoticeList]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    notifyListeners();
  }

  setChatConfig(TIMUIKitChatConfig config) {
    chatConfig = config;
    _inboundChunkReveal.configure(
      interval: Duration(milliseconds: config.inboundChunkRevealIntervalMs),
      maxChunkSize: config.inboundChunkRevealMaxChunk,
      alignToFrame: true,
      burstBoostChunk: 0,
    );
  }

  initMessageMapFromLocalDatabase(
    List<V2TimConversation?> conversations,
  ) async {
    int index = 0;
    for (V2TimConversation? conversationItem in conversations) {
      if (conversationItem == null || conversationItem.type == null) {
        return;
      }
      final conversationID =
          TencentUtils.checkString(conversationItem.userID) ??
              TencentUtils.checkString(conversationItem.groupID) ??
              conversationItem.conversationID;
      if (messageListMap[conversationID] == null ||
          messageListMap[conversationID]!.isEmpty) {
        index++;
        Future.delayed(Duration(milliseconds: 500 * index), () {
          preloadMessageForConversation(
            conversationID: conversationID,
            conversationType: ConvType.values[conversationItem.type!],
          );
        });
      }
    }
  }

  preloadMessageForConversation({
    required ConvType conversationType,
    required String conversationID,
  }) async {
    final writerScope = _messageReconciliationWriter.configuredScope;
    final clearEpoch = messageDeltaClearEpochFor(conversationID);
    final windowScope = historyWindowScopeFor(conversationID);
    bool isCurrent() =>
        _messageReconciliationWriter.configuredScope == writerScope &&
        messageDeltaClearEpochFor(conversationID) == clearEpoch &&
        (windowScope == null || isHistoryWindowScopeCurrent(windowScope));
    final historyResult = await getHistoryMessageListThroughIm06(
      count: 10,
      getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
      userID: conversationType == ConvType.c2c ? conversationID : null,
      groupID: conversationType == ConvType.group ? conversationID : null,
    );
    if (!isCurrent()) return;
    final response = await applyHistoryWindowMutations(
        conversationID, historyResult?.messageList ?? const <V2TimMessage>[]);
    if (!isCurrent()) return;
    final storageKey = _resolveMessageListStorageKey(conversationID);
    if (storageKey.isEmpty || _mergedAliasMessageList(storageKey).isNotEmpty) {
      return;
    }
    final commit = setMessageList(
      storageKey,
      response,
      needResetNewMessageCount: false,
      replace: true,
      applyMemoryWindow: false,
      historyCommitSource: 'preload_local_history',
    );
    if (commit.rawCount > 0) {
      // 会话列表预载时先种行高，进聊天页不再全靠 56 估。
      ChatMessageHeightCache.instance.seedEstimatesForMessages(response);
    }
  }

  clearMessageMapFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? localMsgIDList = prefs.getStringList(localMsgIDListKey);

    if (localMsgIDList != null) {
      for (String convID in localMsgIDList) {
        prefs.remove("$localKeyPrefix$convID");
      }
    }

    prefs.remove(localMsgIDListKey);
  }

  Future<void> updateMessageFromController({
    required String msgID,
    required String conversationID,
    required ConvType conversationType,
  }) async {
    final lifecycleGeneration = _messageHistoryCoverageSessionGeneration;
    final TUIChatModelTools tools = serviceLocator<TUIChatModelTools>();
    V2TimMessage? newMessage = await tools.getExistingMessageByID(
      msgID: msgID,
      conversationID: conversationID,
      conversationType: conversationType,
    );
    if (newMessage != null && _isMessageLifecycleCurrent(lifecycleGeneration)) {
      // Keep the scope captured by the controller request. The selected
      // conversation may have changed while the SDK lookup was in flight.
      onMessageModified(newMessage, conversationID);
    }
  }

  clearData() {
    for (final cancel in _outboxResultSubscriptions.values) { cancel(); }
    _outboxResultSubscriptions.clear();
    _outboxSubscriptionConversations.clear();
    invalidateBoundedHistorySessions();
    _writerProjectionAuthorities.clear();
    // Flush all buffered inbound messages before clearing state so SDK
    // push messages that haven't been committed to messageListMap are
    // not lost. SDK internal SQLite persists them, but flushing ensures
    // consistency for any in-flight presentation.
    _inboundBatchCoalescer.flushAll();
    _inboundChunkReveal.flushAll();
    for (final buffer in _reorderBuffersByConv.values) {
      buffer.dispose();
    }
    _reorderBuffersByConv.clear();
    _gapCatchUpInFlight.clear();
    _groupGapAutoAttemptAtMs.clear();
    for (final timer in _cloudContinuationTimersByConv.values) {
      timer.cancel();
    }
    _cloudContinuationTimersByConv.clear();
    _cloudContinuationRoundsByConv.clear();
    _cloudCatchUpStalledAnchorByConv.clear();
    _messageReconciliationWriter.resetAll();
    _boundedCloudCatchUp.invalidateAll();
    _messageHistoryCoverageSessionGeneration += 1;
    _messageHistoryCoverageByConv.clear();
    _messageHistoryCoverageLoadedConvs.clear();
    _historyWindowClearEpochSyncedKeys.clear();
    _messageHistoryCoverageLoadInFlight.clear();
    _messageHistoryCoverageUpdateTailByConv.clear();
    _messageHistoryCoverageRequestGenerationByConv.clear();
    _openHydrateResultByConv.clear();
    _openHydrateInFlightByConv.clear();
    _openBottomCapsuleLockConvId = null;
    _openBottomCapsuleLockUntilMs = 0;
    _openBottomCapsuleHydrateSettled = false;
    _openBottomCapsuleFirstPinSettled = false;
    for (final timer in _activeReadReportDebounceMap.values) {
      timer.cancel();
    }
    _activeReadReportDebounceMap.clear();
    _lastActiveReadReportAtMs.clear();
    unawaited(appMessageHistoryCoverageRepository?.clearSession());
    _messageListMap.clear();
    _lastHistoryCommitMetadataByConv.clear();
    _rowLocalAliasByConversation.clear();
    _initialHistoryLoadedConvs.clear();
    _mayHaveOlderHistoryByConv.clear();
    _currentConversationList.clear();
    _totalUnreadCount = 0;
    _pendingGroupApplicationRefreshTimer?.cancel();
    _groupApplicationRefreshTask = null;
    _lastGroupApplicationRefreshAt = null;
    _groupApplicationList?.clear();
    _groupSystemNoticeList.clear();
    _totalUnreadCount = 0;
    _inboundUnreadStateByConversation.clear();
    _followingLatestByConversation.clear();
    _historyReadingWindowByConversation.clear();
    _freezeHistoryReadingWindowByConversation.clear();
    _attachingBufferedTowardLatest = false;
    _attachingBufferedTowardLatestUntilMs = 0;
    _deferredUntilUserBottomConversations.clear();
    _messageReadReceiptMap.clear();
    _messageListProgressMap.clear();
    _localMergerMessageCache.clear();
    _messageProjectionRevisionByConv.clear();
    _messageListRevisionByConv.clear();
    _inboundHiddenKeysByConv.clear();
    _authoritativeDeferredIncomingKeys.clear();
    _inboundFastForwardMessageKeys.clear();
    _messageListDisplayCache.clear();
    _bulkMessageSyncDepthByConv.clear();
    _pendingImmediatePinByConv.clear();
    _pinToBottomImmediate = false;
    _pendingPinAfterBulkByConv.clear();
    _pendingPinAfterPickerByConv.clear();
    _userScrollToBottomConvId = null;
    _userScrollToBottomTransactionActive = false;
    _userScrollToBottomUntilMs = 0;
    _lastInboundScrollFollowChunk = const <V2TimMessage>[];
    _inboundScrollFollowSessionEnding = false;
    notifyListeners();
  }

  void clearReceivedNewMessageCount({String? conversationID}) {
    final state = _inboundUnreadStateFor(conversationID);
    if (state.durableDeferred ||
        state.unreadVisitBaselinePending ||
        state.durableOperationCount > 0 ||
        state.pendingLegacyMessages.isNotEmpty ||
        state.revealedUnreadMessageIDs.isNotEmpty) return;
    state.receivedCount = 0;
  }

  _preLoadImage(List<V2TimMessage> msgList) {
    List<V2TimMessage> needPreViewList = msgList.sublist(
      0,
      max(0, min(5, msgList.length - 1)),
    );
    for (var msgItem in needPreViewList) {
      V2TimImage? getImageFromList(V2TimImageTypesEnum imgType) {
        V2TimImage? img = MessageUtils.getImageFromImgList(
          msgItem.imageElem?.imageList,
          HistoryMessageDartConstant.imgPriorMap[imgType] ??
              HistoryMessageDartConstant.oriImgPrior,
        );
        return img;
      }

      V2TimImage? originalImg = getImageFromList(V2TimImageTypesEnum.small);
      if (originalImg?.localUrl != null && originalImg!.localUrl != "") {
        try {
          ImageConfiguration configuration = const ImageConfiguration();
          final image = FileImage(File((originalImg.localUrl!)));

          image.resolve(configuration).addListener(
            ImageStreamListener((ImageInfo image, bool synchronousCall) {
              final tempImg = image.image;
              _preloadImageMap[msgItem.seq! +
                  msgItem.timestamp.toString() +
                  (msgItem.msgID ?? "")] = tempImg;
              outputLogger.i("cacheImage ${msgItem.msgID}");
            }),
          );
        } catch (e) {
          outputLogger.i("cacheImage error ${msgItem.msgID}");
        }
      }
    }
  }

  int getMessageProgress(String? msgID) {
    return _messageListProgressMap[msgID] ?? 0;
  }

  Size? getFileMessageSize(String? msgID) {
    if (msgID == null || msgID.isEmpty) {
      return null;
    }
    return _fileMessageSizeMap[msgID];
  }

  String getFileMessageLocation(String? msgID) {
    return _fileListLocationMap[msgID] ?? '';
  }

  setMessageProgress(String msgID, int progress) {
    _messageListProgressMap[msgID] = progress;
    if (progress > 0 && progress < 100) {
      _isDownloading = true;
    } else {
      _isDownloading = false;
      _waitingDownloadList.removeWhere((element) {
        String msgIDItem = element["msgID"] ?? "";
        if (msgIDItem.isNotEmpty) {
          if (msgID == msgIDItem) {
            outputLogger.i("remove download");
            return true;
          }
        }
        return false;
      });
    }
    _markNeedsNotify();
  }

  /// 上传进度高频更新只由 [ChatUiStateStore] 驱动对应气泡遮罩刷新，禁止
  /// notify 全局消息模型导致整张聊天列表参与 rebuild。
  void _setUploadProgressSilently(String msgID, int progress) {
    if (msgID.isEmpty) {
      return;
    }
    _messageListProgressMap[msgID] = progress.clamp(0, 100);
  }

  void _clearUploadProgressSilently(String? msgID) {
    final id = msgID?.trim() ?? '';
    if (id.isNotEmpty) {
      _messageListProgressMap.remove(id);
    }
  }

  void clearMessageProgress(String? msgID) {
    if (msgID == null || msgID.isEmpty) {
      return;
    }
    _messageListProgressMap.remove(msgID);
    _fileListLocationMap.remove(msgID);
    _fileMessageSizeMap.remove(msgID);
    notifyListeners();
  }

  void clearUploadProgress(String? msgID) {
    if (msgID == null || msgID.isEmpty) {
      return;
    }
    _messageListProgressMap.remove(msgID);
    _markNeedsNotify();
  }

  /// Metadata writes used while adopting an already-mounted outgoing row.
  /// The adoption publishes one row revision after all fields are coherent.
  void setUploadProgressRowLocal(String msgID, int progress) {
    _setUploadProgressSilently(msgID, progress);
  }

  void clearUploadProgressRowLocal(String? msgID) {
    _clearUploadProgressSilently(msgID);
  }

  void setFileMessageLocationRowLocal(
    String msgID,
    String location, {
    Size? imageSize,
  }) {
    _fileListLocationMap[msgID] = location;
    if (imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
      _fileMessageSizeMap[msgID] = imageSize;
    }
  }

  setFileMessageLocation(String msgID, String location, {Size? imageSize}) {
    _fileListLocationMap[msgID] = location;
    if (imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
      _fileMessageSizeMap[msgID] = imageSize;
    }
    notifyListeners();
  }

  _editStatusCheck(V2TimMessage msg) {
    bool isStatusMessage = false;
    if (msg.customElem != null &&
        TencentUtils.checkString(msg.groupID) == null) {
      V2TimCustomElem customElem = msg.customElem!;
      String sender = msg.sender ?? "";
      if (customElem.data!.isNotEmpty) {
        try {
          Map<String, dynamic>? data = json.decode(customElem.data ?? "");
          if (data != null) {
            var businessID = data["businessID"];
            int? userAction = data["userAction"];
            String? actionParam = data["actionParam"];
            if (businessID.toString() == "user_typing_status") {
              int? typingStatus = data["typingStatus"];
              if (sender != "") {
                if (typingStatus != null) {
                  setC2cMessageEditStatus(sender, typingStatus);
                } else {
                  // 兼容旧版本逻辑
                  if (userAction != null) {
                    if (userAction == 14) {
                      if (actionParam != null) {
                        setC2cMessageEditStatus(
                          sender,
                          actionParam == "EIMAMSG_InputStatus_Ing" ? 1 : 0,
                        );
                      }
                    }
                  }
                }
              }
              return true;
            }
          }
        } catch (err) {
          // err;
        }
      }
    }
    return isStatusMessage;
  }

  _checkFromUserisActive(V2TimMessage msg) async {
    // check message is c2c message and message cloudcustomdata field is not null
    if (msg.groupID == null && msg.cloudCustomData != null) {
      try {
        Map<String, dynamic> data = json.decode(msg.cloudCustomData ?? "");
        Map<String, dynamic>? messageFeature = data["messageFeature"];
        if (messageFeature != null) {
          int needTyping = messageFeature["needTyping"];
          if (needTyping == 1) {
            _c2cMessageFromUserActiveMap[msg.sender ?? ""] = true;

            if (_c2cMessageActiveTimer[msg.sender ?? ""] != null) {
              Timer? t = _c2cMessageActiveTimer[msg.sender ?? ""];
              if (t != null && t.isActive) {
                //取消原来的定时器
                t.cancel();
              }
            }
            _c2cMessageActiveTimer[msg.sender ?? ""] = Timer.periodic(
              const Duration(seconds: 30),
              (timer) {
                _c2cMessageFromUserActiveMap[msg.sender ?? ""] = false;
                Timer? t = _c2cMessageActiveTimer[msg.sender ?? ""];
                if (t != null && t.isActive) {
                  // 取消当前的定时器
                  t.cancel();
                }
              },
            );
          }
        }
      } catch (err) {
        // err
      }
    }
  }

  void sendEditStatusMessage(bool isEditing, String toUser) {
    if (!_showC2cMessageEditStatus) {
      return;
    }
    if (!(_c2cMessageFromUserActiveMap[toUser] ?? false)) {
      return;
    }
    _messageService.sendTypingStatus(
      receiver: toUser,
      isTyping: isEditing,
    );
  }

  void refreshGroupApplicationList({bool force = false}) {
    if (_groupApplicationRefreshTask != null) {
      if (force) {
        _pendingGroupApplicationRefreshTimer?.cancel();
        _pendingGroupApplicationRefreshTimer = Timer(
          const Duration(milliseconds: 300),
          () => refreshGroupApplicationList(force: true),
        );
      }
      return;
    }

    final now = DateTime.now();
    final last = _lastGroupApplicationRefreshAt;
    if (!force && last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _groupApplicationRefreshInterval) {
        _pendingGroupApplicationRefreshTimer?.cancel();
        _pendingGroupApplicationRefreshTimer = Timer(
          _groupApplicationRefreshInterval - elapsed,
          () => refreshGroupApplicationList(force: true),
        );
        return;
      }
    }

    _lastGroupApplicationRefreshAt = now;
    final task = _loadGroupApplicationList();
    _groupApplicationRefreshTask = task.whenComplete(() {
      if (identical(_groupApplicationRefreshTask, task)) {
        _groupApplicationRefreshTask = null;
      }
    });
  }

  Future<void> _loadGroupApplicationList() async {
    final res = await _groupServices.getGroupApplicationList();
    final nextList = res.data?.groupApplicationList
            ?.whereType<V2TimGroupApplication>()
            .toList() ??
        [];
    if (_isSameGroupApplicationList(
      _groupApplicationList ?? const [],
      nextList,
    )) {
      return;
    }
    _groupApplicationList = nextList;
    notifyListeners();
  }

  bool _isSameGroupApplicationList(
    List<V2TimGroupApplication> oldList,
    List<V2TimGroupApplication> nextList,
  ) {
    if (oldList.length != nextList.length) return false;
    for (var i = 0; i < oldList.length; i++) {
      final oldItem = oldList[i];
      final nextItem = nextList[i];
      if (oldItem.groupID != nextItem.groupID ||
          oldItem.fromUser != nextItem.fromUser ||
          oldItem.toUser != nextItem.toUser ||
          oldItem.addTime != nextItem.addTime ||
          oldItem.type != nextItem.type ||
          oldItem.handleStatus != nextItem.handleStatus ||
          oldItem.handleResult != nextItem.handleResult) {
        return false;
      }
    }
    return true;
  }

  cancelAllTimer() {
    _c2cMessageActiveTimer.forEach((key, value) {
      if (value.isActive) {
        value.cancel();
      }
    });
    _c2cMessageStatusShowTimer.forEach((key, value) {
      if (value.isActive) {
        value.cancel();
      }
    });
  }

  static const String _outgoingLocalSeqKey = '__outgoingLocalSeq';
  static const String _outgoingLocalSentAtKey = '__outgoingLocalSentAt';

  static int? _outgoingRandomValue(V2TimMessage message) {
    final random = message.random;
    if (random == null || random == 0) {
      return null;
    }
    return random;
  }

  static int? _readOutgoingLocalSeq(V2TimMessage message) {
    return _readOutgoingLocalInt(message, _outgoingLocalSeqKey);
  }

  static int? _readOutgoingLocalSentAt(V2TimMessage message) {
    return _readOutgoingLocalInt(message, _outgoingLocalSentAtKey);
  }

  static int? _readOutgoingLocalInt(V2TimMessage message, String key) {
    final raw = message.localCustomData?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final value = decoded[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
    } catch (_) {}
    return null;
  }

  static void _writeOutgoingLocalSeq(V2TimMessage message, int seq) {
    final data = <String, dynamic>{};
    final raw = message.localCustomData?.trim();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          data.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    data[_outgoingLocalSeqKey] = seq;
    data[_outgoingLocalSentAtKey] ??=
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    message.localCustomData = jsonEncode(data);
  }

  static void _preserveOutgoingLocalOrderData(
    V2TimMessage previous,
    V2TimMessage merged,
  ) {
    final previousRaw = previous.localCustomData?.trim();
    if (previousRaw == null || previousRaw.isEmpty) {
      return;
    }
    final data = <String, dynamic>{};
    final mergedRaw = merged.localCustomData?.trim();
    if (mergedRaw != null && mergedRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(mergedRaw);
        if (decoded is Map) {
          data.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    try {
      final previousDecoded = jsonDecode(previousRaw);
      if (previousDecoded is Map) {
        for (final key in const [
          _outgoingLocalSeqKey,
          _outgoingLocalSentAtKey,
          kChatOutgoingStableIdKey,
          kChatMediaBatchIdKey,
          kChatMediaBatchIndexKey,
        ]) {
          if (previousDecoded.containsKey(key)) {
            data[key] = previousDecoded[key];
          }
        }
      }
    } catch (_) {}
    if (data.isNotEmpty) {
      merged.localCustomData = jsonEncode(data);
    }
  }

  void assignOutgoingLocalSeq(String conversationID, V2TimMessage message) {
    final convID = _safeConversationId(conversationID);
    if (convID.isEmpty) {
      return;
    }
    final next = (_outgoingLocalSeqByConv[convID] ?? 0) + 1;
    _outgoingLocalSeqByConv[convID] = next;
    _writeOutgoingLocalSeq(message, next);
    _logOutgoingSendOrder(
      event: 'tap',
      convID: convID,
      message: message,
      clientId: message.id,
      mergePath: 'assign_local_seq',
    );
  }

  void _logOutgoingSendOrder({
    required String event,
    required String convID,
    required V2TimMessage message,
    String? clientId,
    String? mergePath,
    int? existingIndex,
    bool? reordered,
    String? warn,
  }) {
    if (!ChatJitterDiag.enabled) {
      return;
    }
    final list = _messageListMap[convID] ?? const <V2TimMessage>[];
    final msgID = message.msgID?.trim() ?? '';
    final idValue = clientId?.trim().isNotEmpty == true
        ? clientId!.trim()
        : (message.id?.trim() ?? '');
    var finalIndex = -1;
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (msgID.isNotEmpty && item.msgID == msgID) {
        finalIndex = i;
        break;
      }
      if (idValue.isNotEmpty && item.id == idValue) {
        finalIndex = i;
        break;
      }
    }
    final localSeq = _readOutgoingLocalSeq(message);
    final existing = existingIndex ?? -1;
    final reorderFlag = reordered == true;
    final warnSuffix = warn == null || warn.isEmpty ? '' : ' warn=$warn';
    debugPrint(
      '[IM_SEND_ORDER] event=$event conv=$convID clientId=$idValue msgID=$msgID '
      'tapOrder=$localSeq localSeq=$localSeq serverSeq=${message.seq ?? ''} '
      'timestamp=${message.timestamp ?? ''} finalIndex=$finalIndex listLen=${list.length} '
      'existingIndex=$existing path=${mergePath ?? ''} reordered=$reorderFlag '
      'isSelf=${message.isSelf} random=${message.random}$warnSuffix',
    );
    outputLogger.i(
      '[IM_SEND_ORDER] event=$event conv=$convID clientId=$idValue msgID=$msgID '
      'localSeq=$localSeq serverSeq=${message.seq ?? ''} ts=${message.timestamp ?? ''} '
      'path=${mergePath ?? ''} reordered=$reorderFlag warn=${warn ?? ''}',
    );
  }

  static String? _outgoingCorrelationKey(V2TimMessage message) {
    if (message.isSelf != true) {
      return null;
    }
    // Stable id bridges optimistic clientId → SDK create id across swaps.
    // Prefer it over random/id so dedupe collapses 一图两气泡 pairs.
    final stableId = readOutgoingStableId(message)?.trim();
    if (stableId != null && stableId.isNotEmpty) {
      return 'stable:$stableId:t${message.elemType}';
    }
    final random = _outgoingRandomValue(message);
    if (random != null) {
      // 带上 elemType，避免不同消息偶发同 random 时文字/图片被并成一条。
      return 'rand:$random:t${message.elemType}';
    }
    final id = message.id?.trim();
    if (id != null && id.isNotEmpty) {
      return 'id:$id:t${message.elemType}';
    }
    return null;
  }

  static bool _isClientPlaceholderMessage(V2TimMessage message) {
    if (message.isSelf != true) {
      return false;
    }
    if (message.status != MessageStatus.V2TIM_MSG_STATUS_SENDING) {
      return false;
    }
    final id = message.id;
    return id != null && id.isNotEmpty;
  }

  static bool _isResolvedOutgoingMessage(V2TimMessage message) {
    if (message.isSelf != true) {
      return false;
    }
    // C2C 镜像 dup（对方内容却标 isSelf）不是真实 outgoing ack。
    if (_isC2cConversationMessage(message) &&
        _c2cDirectionConsistencyScore(message) < 3) {
      return false;
    }
    final msgID = message.msgID?.trim();
    if (msgID == null || msgID.isEmpty) {
      return false;
    }
    final id = message.id?.trim();
    if (id != null && id.isNotEmpty && id == msgID) {
      return false;
    }
    return message.status != MessageStatus.V2TIM_MSG_STATUS_SENDING;
  }

  static bool _outgoingMessagesCorrelate(V2TimMessage a, V2TimMessage b) {
    if (a.isSelf != true || b.isSelf != true) {
      return false;
    }
    // 同 random/id 也必须同类型：否则文字占位与图片回执可能被误并。
    if (a.elemType != b.elemType) {
      return false;
    }
    final keyA = _outgoingCorrelationKey(a);
    final keyB = _outgoingCorrelationKey(b);
    if (keyA != null && keyB != null && keyA == keyB) {
      return true;
    }
    final seqA = _readOutgoingLocalSeq(a);
    final seqB = _readOutgoingLocalSeq(b);
    if (seqA != null && seqB != null && seqA == seqB) {
      return true;
    }
    // Optimistic image keeps a local path; adopt copies it onto the SDK
    // message. Path equality is a safe bridge when one side is still a
    // placeholder and random/id have not converged yet.
    if (a.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
        (_isClientPlaceholderMessage(a) || _isClientPlaceholderMessage(b))) {
      final pathA = a.imageElem?.path?.trim() ?? '';
      final pathB = b.imageElem?.path?.trim() ?? '';
      if (pathA.isNotEmpty && pathA == pathB) {
        return true;
      }
    }
    if (_outgoingRandomValue(a) != null || _outgoingRandomValue(b) != null) {
      return false;
    }
    final placeholder = _isClientPlaceholderMessage(a) ||
        _isClientPlaceholderMessage(b) ||
        _isResolvedOutgoingMessage(a) ||
        _isResolvedOutgoingMessage(b);
    if (!placeholder) {
      return false;
    }
    // Never correlate by timestamp alone: same-second sends share timestamp
    // and would merge acks into the wrong placeholder.
    return false;
  }

  /// 存储序列为 newest-first：任一相邻对 chronologically 逆序则需重排。
  @visibleForTesting
  static bool isNewestFirstStorageOrderValid(List<V2TimMessage> list) {
    if (list.length < 2) {
      return true;
    }
    for (var i = 0; i < list.length - 1; i++) {
      if (compareMessagesChronological(list[i], list[i + 1]) < 0) {
        return false;
      }
    }
    return true;
  }

  /// 秒级 epoch；字段误存毫秒时归一化（Web/归档混源常见）。
  @visibleForTesting
  static int normalizeMessageEpochSeconds(int? raw) {
    if (raw == null || raw <= 0) {
      return 0;
    }
    if (raw >= 1000000000000) {
      return raw ~/ 1000;
    }
    return raw;
  }

  static int messageEpochSecondsForDisplay(V2TimMessage message) {
    return normalizeMessageEpochSeconds(_messageSortTimestamp(message));
  }

  static int _findOutgoingPlaceholderIndex(
    List<V2TimMessage> list,
    V2TimMessage incoming,
  ) {
    final candidates = <int>[];
    for (var i = 0; i < list.length; i++) {
      final element = list[i];
      if (!_isClientPlaceholderMessage(element)) {
        continue;
      }
      if (element.elemType != incoming.elemType) {
        continue;
      }
      candidates.add(i);
    }
    if (candidates.isEmpty) {
      return -1;
    }
    final incomingStable = readOutgoingStableId(incoming)?.trim();
    if (incomingStable != null && incomingStable.isNotEmpty) {
      for (final i in candidates) {
        if (readOutgoingStableId(list[i]) == incomingStable) {
          return i;
        }
      }
    }
    if (candidates.length == 1) {
      return candidates.first;
    }
    final incomingRandom = _outgoingRandomValue(incoming);
    if (incomingRandom != null) {
      for (final i in candidates) {
        if (list[i].random == incomingRandom) {
          return i;
        }
      }
    }
    final incomingId = incoming.id?.trim();
    if (incomingId != null && incomingId.isNotEmpty) {
      for (final i in candidates) {
        if (list[i].id == incomingId) {
          return i;
        }
      }
    }
    final incomingMsgID = incoming.msgID?.trim();
    if (incomingMsgID != null && incomingMsgID.isNotEmpty) {
      for (final i in candidates) {
        if (list[i].msgID?.trim() == incomingMsgID) {
          return i;
        }
      }
    }
    final incomingLocalSeq = _readOutgoingLocalSeq(incoming);
    if (incomingLocalSeq != null) {
      for (final i in candidates) {
        if (_readOutgoingLocalSeq(list[i]) == incomingLocalSeq) {
          return i;
        }
      }
    }
    if (incoming.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
      final path = incoming.imageElem?.path?.trim() ?? '';
      if (path.isNotEmpty) {
        final pathMatches = <int>[];
        for (final i in candidates) {
          if (list[i].imageElem?.path?.trim() == path) {
            pathMatches.add(i);
          }
        }
        if (pathMatches.length == 1) {
          return pathMatches.first;
        }
      }
    }
    if (incoming.elemType == MessageElemType.V2TIM_ELEM_TYPE_SOUND) {
      final newDuration = incoming.soundElem?.duration;
      for (final i in candidates) {
        if (list[i].soundElem?.duration == newDuration) {
          return i;
        }
      }
    }
    // Ambiguous when multiple placeholders share type without random/id/msgID.
    // Orphan-insert + chronological sort is safer than guessing FIFO.
    return -1;
  }

  /// Binds SDK-assigned [msgID] to a sending placeholder before send completes.
  void bindOutgoingSyncMsgId(
    String conversationID,
    String clientId,
    String msgID,
  ) {
    final id = clientId.trim();
    final serverMsgID = msgID.trim();
    if (id.isEmpty || serverMsgID.isEmpty) {
      return;
    }
    final storageKey = _resolveMessageListStorageKey(conversationID);
    if (storageKey.isEmpty) {
      return;
    }

    final current = _mergedAliasMessageList(storageKey);
    final index = current.indexWhere(
      (item) =>
          item.isSelf == true &&
          item.id == id &&
          (item.msgID == null || item.msgID!.isEmpty || item.msgID == id),
    );
    if (index < 0) {
      return;
    }

    final previous = current[index];
    final updated = _cloneMessage(previous);
    updated.msgID = serverMsgID;
    final stableIdentity = readOutgoingStableId(previous) ?? id;
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageKey,
        eventID: 'send_bind:$id:$serverMsgID',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: messageDeltaClearEpochFor(storageKey),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: updated,
            msgID: updated.msgID,
            localID: updated.id,
            outgoingStableID: stableIdentity,
            seq: updated.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      // Rejected/stale/active-history binds must not mutate the formal list.
      return;
    }
    _chatUiStateStore.bindMessageAlias(
      storageKey,
      id,
      ChatUiStateStore.messageKeyOf(updated),
    );
    ChatMessageHeightCache.instance.rememberAlias(id, serverMsgID);
    _markMessageRowChanged(storageKey, updated, extraKey: id);
    _markNeedsNotify();
  }

  @visibleForTesting
  static int findOutgoingPlaceholderIndexForTesting(
    List<V2TimMessage> list,
    V2TimMessage incoming,
  ) {
    return _findOutgoingPlaceholderIndex(list, incoming);
  }

  @visibleForTesting
  static void preserveOutgoingLocalOrderDataForTesting(
    V2TimMessage previous,
    V2TimMessage merged,
  ) {
    _preserveOutgoingLocalOrderData(previous, merged);
  }

  @visibleForTesting
  static int? readOutgoingLocalSeqForTesting(V2TimMessage message) {
    return _readOutgoingLocalSeq(message);
  }

  int findReplaceableOutgoingIndex(
    String convID,
    V2TimMessage message, {
    String? priorTempId,
    List<V2TimMessage>? listOverride,
  }) {
    final list = listOverride ?? _messageListMap[convID] ?? [];
    if (priorTempId != null && priorTempId.isNotEmpty) {
      final byTemp = list.indexWhere(
        (item) => item.id == priorTempId || item.msgID == priorTempId,
      );
      if (byTemp != -1) {
        return byTemp;
      }
    }
    final id = message.id;
    if (id != null && id.isNotEmpty) {
      final byId = list.indexWhere((item) => item.id == id);
      if (byId != -1) {
        return byId;
      }
    }
    final msgID = message.msgID;
    if (msgID != null && msgID.isNotEmpty) {
      final byMsgID = list.indexWhere((item) => item.msgID == msgID);
      if (byMsgID != -1) {
        return byMsgID;
      }
    }
    return _findOutgoingPlaceholderIndex(list, message);
  }

  void _preserveSoundLocalPath(V2TimMessage? previous, V2TimMessage resolved) {
    if (previous == null ||
        previous.elemType != MessageElemType.V2TIM_ELEM_TYPE_SOUND ||
        resolved.elemType != MessageElemType.V2TIM_ELEM_TYPE_SOUND) {
      return;
    }
    final prevSound = previous.soundElem;
    final nextSound = resolved.soundElem;
    if (prevSound == null || nextSound == null) {
      return;
    }
    final localPath = prevSound.path ?? prevSound.localUrl;
    if (localPath == null || localPath.isEmpty) {
      return;
    }
    nextSound.path = localPath;
    nextSound.localUrl = prevSound.localUrl ?? localPath;
  }

  void _preserveImageLocalPath(V2TimMessage? previous, V2TimMessage resolved) {
    if (previous == null ||
        previous.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE ||
        resolved.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
      return;
    }
    final prevPath = previous.imageElem?.path;
    if (prevPath == null || prevPath.isEmpty) {
      return;
    }
    resolved.imageElem ??= previous.imageElem;
    resolved.imageElem!.path = prevPath;
  }

  void _preserveImageDisplaySize(V2TimMessage resolved, String clientId) {
    if (resolved.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
      return;
    }
    Size? size = _fileMessageSizeMap[clientId];
    final msgID = resolved.msgID?.trim();
    if ((size == null || size.width <= 0 || size.height <= 0) &&
        msgID != null &&
        msgID.isNotEmpty) {
      size = _fileMessageSizeMap[msgID];
    }
    if (size == null || size.width <= 0 || size.height <= 0) {
      return;
    }
    final imageList = resolved.imageElem?.imageList;
    if (imageList == null || imageList.isEmpty) {
      return;
    }
    final width = size.width.round();
    final height = size.height.round();
    for (final image in imageList) {
      if (image == null) {
        continue;
      }
      image.width = width;
      image.height = height;
    }
  }

  void _migrateFileMessageMetadata(String clientId, String? msgID) {
    if (clientId.isEmpty || msgID == null || msgID.isEmpty) {
      return;
    }
    final location = _fileListLocationMap[clientId];
    if (location != null && location.isNotEmpty) {
      _fileListLocationMap.putIfAbsent(msgID, () => location);
    }
    final size = _fileMessageSizeMap[clientId];
    if (size != null) {
      _fileMessageSizeMap.putIfAbsent(msgID, () => size);
    }
  }

  void _registerSoundLocalPath(V2TimMessage message) {
    if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_SOUND) {
      return;
    }
    final localPath = message.soundElem?.path ?? message.soundElem?.localUrl;
    if (localPath == null || localPath.isEmpty) {
      return;
    }
    final msgID = message.msgID;
    if (msgID != null && msgID.isNotEmpty) {
      setFileMessageLocation(msgID, localPath);
    }
    final clientId = message.id;
    if (clientId != null && clientId.isNotEmpty) {
      setFileMessageLocation(clientId, localPath);
    }
  }

  bool _messageCorrelatesWithStored(
    V2TimMessage stored,
    V2TimMessage incoming,
  ) {
    if (messagesCorrelateForDedup(stored, incoming)) {
      return true;
    }
    if (incoming.isSelf == true &&
        _outgoingMessagesCorrelate(stored, incoming)) {
      return true;
    }
    return false;
  }

  V2TimMessage _mergeMessageAtIndex(
    String convID,
    List<V2TimMessage> list,
    int index,
    V2TimMessage newMsg, {
    bool replacingPlaceholder = false,
    bool forceSuccess = false,
  }) {
    final previous = list[index];
    final merged = _cloneMessage(newMsg);
    final isSelf =
        _isC2cConversationMessage(previous) && _isC2cConversationMessage(newMsg)
            ? _resolveMergedIsSelf(previous, newMsg)
            : (previous.isSelf == true || newMsg.isSelf == true);
    merged.isSelf = isSelf;

    if (isSelf) {
      final clientId = previous.id;
      if (clientId != null && clientId.isNotEmpty) {
        merged.id = clientId;
      }
      _preserveOutgoingLocalOrderData(previous, merged);
      if (previous.elemType == MessageElemType.V2TIM_ELEM_TYPE_SOUND &&
          merged.elemType == MessageElemType.V2TIM_ELEM_TYPE_SOUND) {
        _preserveSoundLocalPath(previous, merged);
      }
      if (previous.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
          merged.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
        _preserveImageLocalPath(previous, merged);
        final clientId = previous.id?.trim() ?? '';
        if (clientId.isNotEmpty) {
          _preserveImageDisplaySize(merged, clientId);
          _migrateFileMessageMetadata(clientId, merged.msgID);
          final layoutSize = readPersistedImageLayoutSize(previous) ??
              _fileMessageSizeMap[clientId] ??
              ((merged.msgID?.isNotEmpty ?? false)
                  ? _fileMessageSizeMap[merged.msgID!]
                  : null);
          if (layoutSize != null) {
            applyImageLayoutToMessage(merged, layoutSize);
          }
        }
      }
      // Echo/history never pass fromFinalSendSuccess. Final send results
      // write through updateMessage / applyOutgoingSendResult instead.
      final resolvedStatus = OutgoingSendStatus.mergeSelf(
        previous: previous.status,
        incoming: merged.status,
        fromFinalSendSuccess: false,
      );
      merged.status = resolvedStatus;
      if (resolvedStatus == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
        if (ErrorMessageConverter.getSendFailCode(merged) == null) {
          final previousCode = ErrorMessageConverter.getSendFailCode(previous);
          if (previousCode != null) {
            ErrorMessageConverter.attachSendFailCode(merged, previousCode);
          } else if ((previous.localCustomData ?? '').isNotEmpty) {
            merged.localCustomData = previous.localCustomData;
          }
        }
      } else if (resolvedStatus == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
        ErrorMessageConverter.clearSendFailCode(merged);
      }
    } else if (merged.status == MessageStatus.V2TIM_MSG_STATUS_SENDING) {
      merged.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    }
    if (isSelf) {
      _logOutgoingSendOrder(
        event: 'merge_self',
        convID: convID,
        message: merged,
        clientId: merged.id,
        mergePath: replacingPlaceholder ? 'placeholder_merge' : 'inplace_merge',
        existingIndex: index,
      );
    }
    return merged;
  }

  void _applyMergedMessagePresentationSideEffects(
    String conversationID,
    V2TimMessage? previous,
    V2TimMessage message,
  ) {
    _registerSoundLocalPath(message);
    if (previous == null) {
      return;
    }
    final previousKey = ChatUiStateStore.messageKeyOf(previous);
    _chatUiStateStore.bindMessageAlias(
      conversationID,
      previousKey,
      ChatUiStateStore.messageKeyOf(message),
    );
    _markMessageRowChanged(conversationID, message, extraKey: previousKey);
  }

  bool _upsertIncomingMessage(
    String convID,
    V2TimMessage newMsg, {
    bool forceSuccess = false,
  }) {
    final storageKey = _resolveMessageListStorageKey(convID);
    if (storageKey.isEmpty) {
      return false;
    }
    final serverID = newMsg.msgID?.trim() ?? '';
    if (serverID.isNotEmpty &&
        _messageReconciliationWriter
            .tombstonesFor(storageKey)
            .contains(serverID)) {
      // A late self receipt must not reinsert a server-deleted/revoked row.
      return false;
    }
    // The writer owns the authoritative list. This local copy is only used to
    // preserve the mature outgoing merge rules before the delta is admitted.
    final list = List<V2TimMessage>.from(_mergedAliasMessageList(storageKey));
    var index = list.indexWhere(
      (element) => _messageCorrelatesWithStored(element, newMsg),
    );
    var replacingPlaceholder = false;
    if (index == -1 && newMsg.isSelf == true) {
      index = _findOutgoingPlaceholderIndex(list, newMsg);
      replacingPlaceholder = index != -1;
    }
    final previous = index == -1 ? null : list[index];
    final value = index == -1
        ? _cloneMessage(newMsg)
        : _mergeMessageAtIndex(
            storageKey,
            list,
            index,
            newMsg,
            replacingPlaceholder: replacingPlaceholder,
            forceSuccess: newMsg.isSelf != true,
          );
    final stableIdentity = readOutgoingStableId(value) ??
        readOutgoingStableId(previous) ??
        (value.isSelf == true ? value.id : null);
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageKey,
        eventID: 'realtime:${++_nextRealtimeReconciliationEvent}:'
            '${messageDedupKey(value)}',
        kind: MessageDeltaKind.realtimeUpsert,
        source: MessageDeltaSource.sdkRealtime,
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: messageDeltaClearEpochFor(storageKey),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: value,
            msgID: value.msgID,
            localID: value.id,
            outgoingStableID: stableIdentity,
            seq: value.seq,
          ),
        ],
      ),
      applyMemoryWindow: true,
    );
    if (commit == null) {
      // A history transaction, stale generation, or tombstone owns this
      // event. Never fall back to a direct list write.
      return false;
    }
    _applyMergedMessagePresentationSideEffects(storageKey, previous, value);
    _collapseHistoryAliasesToCanonical(storageKey, canonical: storageKey);
    return previous != null;
  }

  static bool _sameMessageIdentityList(
    List<V2TimMessage> a,
    List<V2TimMessage> b,
  ) {
    if (identical(a, b) || a.length != b.length) {
      return identical(a, b);
    }
    for (var i = 0; i < a.length; i++) {
      if (!messagesCorrelateForDedup(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }

  /// Applies a burst without sorting the full conversation once per message.
  ///
  /// The common path (all messages are new) performs one final sort. If a
  /// duplicate appears inside the burst, pending inserts are flushed first so
  /// the existing single-message merge semantics remain unchanged.
  ({
    bool inserted,
    V2TimMessage? lastInserted,
    List<V2TimMessage> insertedMessages,
  }) _upsertIncomingMessageBatch(String convID, List<V2TimMessage> messages) {
    if (messages.isEmpty) {
      return (
        inserted: false,
        lastInserted: null,
        insertedMessages: const <V2TimMessage>[],
      );
    }

    // Normal inbound rows use the same authoritative writer as history. Keep
    // the mature self-send correlation path below because it also migrates
    // local media metadata and placeholder status; server inbound rows have
    // no such local-only side effects.
    if (messages.every((message) => message.isSelf != true)) {
      final before = _mergedAliasMessageList(convID);
      final eventID = 'realtime:${++_nextRealtimeReconciliationEvent}:'
          '${messages.map(messageDedupKey).join(',')}';
      final commit = commitMessageDelta(
        MessageDelta<V2TimMessage>(
          conversationKey: convID,
          eventID: eventID,
          kind: MessageDeltaKind.realtimeUpsert,
          source: MessageDeltaSource.sdkRealtime,
          generation: messageDeltaGenerationFor(convID),
          clearEpoch: messageDeltaClearEpochFor(convID),
          upserts: _reconciliationRecords(messages),
        ),
      );
      if (commit == null) {
        return (
          inserted: false,
          lastInserted: null,
          insertedMessages: const <V2TimMessage>[],
        );
      }
      final after = commit.rawCount > 0
          ? (rawMessageList(convID) ?? const <V2TimMessage>[])
          : const <V2TimMessage>[];
      final insertedMessages = messages
          .where(
            (message) => !before.any(
              (existing) => _messageCorrelatesWithStored(existing, message),
            ),
          )
          .toList(growable: false);
      return (
        inserted: insertedMessages.isNotEmpty || after.length > before.length,
        lastInserted: insertedMessages.isEmpty ? null : insertedMessages.last,
        insertedMessages: insertedMessages,
      );
    }

    final storageKey = _resolveMessageListStorageKey(convID);
    if (storageKey.isEmpty) {
      return (
        inserted: false,
        lastInserted: null,
        insertedMessages: const <V2TimMessage>[],
      );
    }
    final before = _mergedAliasMessageList(storageKey);
    final known = List<V2TimMessage>.of(before);
    final records = <MessageReconciliationRecord<V2TimMessage>>[];
    final previousRecords = <V2TimMessage?>[];
    final insertedMessages = <V2TimMessage>[];

    for (final message in messages) {
      var index = known.indexWhere(
        (item) => _messageCorrelatesWithStored(item, message),
      );
      var replacingPlaceholder = false;
      if (index == -1 && message.isSelf == true) {
        index = _findOutgoingPlaceholderIndex(known, message);
        replacingPlaceholder = index != -1;
      }
      final previous = index == -1 ? null : known[index];
      final value = index == -1
          ? _cloneMessage(message)
          : _mergeMessageAtIndex(
              storageKey,
              known,
              index,
              message,
              replacingPlaceholder: replacingPlaceholder,
              forceSuccess: message.isSelf != true,
            );
      final stableIdentity = readOutgoingStableId(value) ??
          readOutgoingStableId(previous) ??
          (value.isSelf == true ? value.id : null);
      records.add(
        MessageReconciliationRecord<V2TimMessage>(
          value: value,
          msgID: value.msgID,
          localID: value.id,
          outgoingStableID: stableIdentity,
          seq: value.seq,
        ),
      );
      previousRecords.add(previous);
      if (previous == null) {
        insertedMessages.add(value);
        known.add(value);
      } else {
        known[index] = value;
      }
    }

    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageKey,
        eventID: 'realtime:batch:${++_nextRealtimeReconciliationEvent}:'
            '${messages.map(messageDedupKey).join(',')}',
        kind: MessageDeltaKind.realtimeUpsert,
        source: MessageDeltaSource.sdkRealtime,
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: messageDeltaClearEpochFor(storageKey),
        upserts: records,
      ),
    );
    if (commit != null) {
      for (var index = 0; index < records.length; index++) {
        final value = records[index].value;
        _applyMergedMessagePresentationSideEffects(
          storageKey,
          previousRecords[index],
          value,
        );
      }
    } else {
      insertedMessages.clear();
    }
    final inserted = insertedMessages.isNotEmpty;
    final lastInserted = inserted ? insertedMessages.last : null;
    if (ChatJitterDiag.enabled) {
      final groupCount =
          messages.where((message) => _isGroupLikeMessage(message)).length;
      final c2cCount = messages
          .where((message) => _isC2cConversationMessage(message))
          .length;
      ChatJitterDiag.log(
        'inbound_batch_dedup',
        conv: convID,
        extras: <String, Object?>{
          'count': messages.length,
          'upserted': insertedMessages.length,
          'duplicates': messages.length - insertedMessages.length,
          'source': groupCount > 0 && c2cCount == 0
              ? 'group'
              : c2cCount > 0 && groupCount == 0
                  ? 'c2c'
                  : 'mixed',
          'seqPresent': messages.any((message) => _messageSortSeq(message) > 0),
        },
      );
    }
    return (
      inserted: inserted,
      lastInserted: lastInserted,
      insertedMessages: insertedMessages,
    );
  }

  void _stageInboundChunkReveal(
    String conversationID,
    List<V2TimMessage> messages,
  ) {
    final result = _upsertIncomingMessageBatch(conversationID, messages);
    if (!result.inserted) {
      _markNeedsNotify();
      return;
    }

    // Install the projection barrier before invalidating the display cache.
    // The canonical list is complete immediately, but only reveal ticks may
    // make these rows visible.
    _hideInboundProjection(conversationID, result.insertedMessages);
    _bumpMessageListRevisionFor(
      conversationID,
      reason: 'inbound_authority_batch',
    );
    _storeHistoryMessagePosition(conversationID, HistoryMessagePosition.bottom);
    if (lockedEntryUnreadCountFor(conversationID) == 0) {
      flushDeferredIncomingMessages(conversationID, notify: false);
      clearReceivedUnreadState(conversationID: conversationID, notify: false);
    }
    _inboundChunkReveal.enqueueAll(conversationID, result.insertedMessages);
  }

  void _flushInboundMessageBatch(
    String conversationID,
    List<V2TimMessage> messages,
  ) {
    if (messages.isEmpty) {
      return;
    }
    final convId = _resolveMessageListStorageKey(
      _safeConversationId(conversationID),
    );
    if (convId.isEmpty) {
      return;
    }
    _noteInboundFloodArrivals(messages.length);
    final flood = isInboundFloodActive ||
        messages.length >= _inboundFloodBatchSizeThreshold;
    if (flood && _inboundChunkReveal.isActiveFor(convId)) {
      // 洪峰中取消未完成的分片揭示，改走整批插入，避免动画积压拖垮主线程。
      _inboundChunkReveal.cancelToBuffer(convId);
    }
    if (!flood && _shouldChunkRevealInbound(convId, messages)) {
      ChatJitterDiag.log(
        'inbound_chunk_reveal_enqueue',
        conv: convId,
        extras: <String, Object?>{
          'count': messages.length,
          'intervalMs': chatConfig.inboundChunkRevealIntervalMs,
          'maxChunk': chatConfig.inboundChunkRevealMaxChunk,
        },
      );
      _stageInboundChunkReveal(convId, messages);
      return;
    }
    final isBulk = flood || messages.length >= _bulkMessageSyncThreshold;
    // All fallback batches must pass through the history-reading gate below.
    // Appending small group batches here bypasses buffering/unread accounting
    // when chunk reveal was declined because the user is reading older rows.
    if (isBulk) {
      _beginBulkMessageSync(convId);
    }
    try {
      _applyInboundMessageBatch(convId, messages);
    } finally {
      if (isBulk) {
        _endBulkMessageSync(convId);
      }
    }
  }

  bool _shouldChunkRevealInbound(String convID, List<V2TimMessage> messages) {
    if (!chatConfig.inboundChunkRevealEnabled ||
        messages.isEmpty ||
        !shouldAnimateInboundPresentation ||
        isInboundFloodActive ||
        messages.length >= _inboundFloodBatchSizeThreshold) {
      return false;
    }
    if (!_isSameConversationID(convID, currentSelectedConv)) {
      return false;
    }
    // While the user explicitly returns to the bottom, incoming rows must join
    // the authoritative list immediately. Starting another reveal transaction
    // would keep moving the scroll target and can make the button never settle.
    if (isUserScrollToBottomInProgress(convID)) {
      return false;
    }
    if (isChatListUserScrolling) {
      return false;
    }
    _syncHistoryPositionFromActiveScroll(convID);
    var position = getMessageListPosition(convID);
    if (_shouldDeferIncomingToVisibleList(
      convID,
      position: position,
      isActuallyNearBottom: isFollowingLatest(convID),
    )) {
      return false;
    }
    if (!isFollowingLatest(convID)) {
      return false;
    }
    return true;
  }

  void _drainChunkRevealToBuffer(String convID, List<V2TimMessage> messages) {
    if (messages.isEmpty) {
      return;
    }
    _syncHistoryPositionFromActiveScroll(convID);
    final position = getMessageListPosition(convID);
    final isActuallyNearBottom = _isActiveChatNearBottom(convID);
    final shouldDefer = _shouldDeferIncomingToVisibleList(
      convID,
      position: position,
      isActuallyNearBottom: isActuallyNearBottom,
    );
    final following = isFollowingLatest(convID);
    if (!shouldDefer && !following) {
      // These rows already belong to the Writer; release their presentation
      // fence, then use the same admission/counting path as ordinary batches.
      _revealDeferredProjectionAcrossAliases(convID, messages);
      _freezeHistoryReadingWindowByConversation[_inboundStateKey(convID)]
          ?.didAppend?.call(messages);
      _recordVisibleLiveIncoming(convID, messages);
      _applyInboundMessageBatch(convID, messages);
      return;
    }
    for (final message in messages) {
      if (message.isSelf == true) {
        if (shouldDefer || !following) {
          continue;
        }
        _revealInboundProjectionChunk(convID, <V2TimMessage>[message]);
        continue;
      }
      if (shouldDefer || !following) {
        _authoritativeDeferredIncomingKeys.add(
          _authoritativeDeferredKey(convID, message),
        );
        _bufferIncomingWhileReadingAway(
          convID,
          message,
          route: 'chunk_reveal_cancelled',
          position: position,
          isActuallyNearBottom: isActuallyNearBottom,
        );
        continue;
      }
      _revealInboundProjectionChunk(convID, <V2TimMessage>[message]);
    }
    ChatJitterDiag.log(
      'inbound_chunk_reveal_drain_buffer',
      conv: convID,
      extras: <String, Object?>{
        'count': messages.length,
        'tongueUnread': unreadCountForTongue,
      },
    );
    _markNeedsNotify();
  }

  void _applyInboundMessageBatch(String convID, List<V2TimMessage> messages) {
    if (messages.isEmpty) {
      return;
    }
    final isActiveConversation = _isSameConversationID(
      convID,
      currentSelectedConv,
    );
    var listDirty = false;
    V2TimMessage? enterAnimationCandidate;

    if (!isActiveConversation) {
      // A callback may outlive cache eviction. Only an existing reading cache
      // receives a projection; SDK history owns unopened conversations.
      if (!_messageListMap.containsKey(_resolveMessageListStorageKey(convID))) {
        return;
      }
      final result = _upsertIncomingMessageBatch(convID, messages);
      if (result.inserted) {
        _scheduleInactiveInboundPresentationCommit(convID);
      }
      return;
    }

    _syncHistoryPositionFromActiveScroll(convID);
    var position = getMessageListPosition(convID);
    final wasAtBottomBeforeKeyboardViewportChange =
        _wasAtBottomBeforeKeyboardViewportChange(convID);
    final isActuallyNearBottom = _isActiveChatNearBottom(convID) ||
        wasAtBottomBeforeKeyboardViewportChange;
    if (wasAtBottomBeforeKeyboardViewportChange) {
      _storeHistoryMessagePosition(convID, HistoryMessagePosition.bottom);
      position = HistoryMessagePosition.bottom;
    }
    final isReturningToBottom = isUserScrollToBottomInProgress(convID);
    final isFollowing = isFollowingLatest(convID) ||
        wasAtBottomBeforeKeyboardViewportChange;
    var clearedUnreadState = false;
    final messagesToUpsert = <V2TimMessage>[];

    for (final message in messages) {
      if (message.isSelf == true) {
        if (!isFollowing) {
          final storageKey = _resolveMessageListStorageKey(convID);
          final existing = _messageListMap[storageKey];
          final key = messageDedupKey(message);
          final alreadyVisible =
              existing?.any((row) => messageDedupKey(row) == key) == true;
          if (!alreadyVisible) {
            continue;
          }
        }
        _syncSelfSentMessage(convID, message, forceSuccess: false);
        listDirty = true;
        continue;
      }

      if (!_chatAppForeground) {
        _bufferIncomingWhileReadingAway(
          convID,
          message,
          route: 'app_background',
          position: HistoryMessagePosition.notShowLatest,
          isActuallyNearBottom: false,
        );
        continue;
      }

      if (_shouldDeferIncomingToVisibleList(
            convID,
            position: position,
            isActuallyNearBottom: isActuallyNearBottom,
          )) {
        _bufferIncomingWhileReadingAway(
          convID,
          message,
          route: position == HistoryMessagePosition.notShowLatest
              ? 'notShowLatest'
              : 'awayFromBottom',
          position: position,
          isActuallyNearBottom: isActuallyNearBottom,
        );
        continue;
      }

      if (isFollowing) {
        _storeHistoryMessagePosition(convID, HistoryMessagePosition.bottom);
      }
      if (isFollowing && !clearedUnreadState && lockedEntryUnreadCountFor(convID) == 0) {
        flushDeferredIncomingMessages(convID, notify: false);
        clearReceivedUnreadState(conversationID: convID, notify: false);
        clearedUnreadState = true;
      }
      messagesToUpsert.add(message);
    }

    final upsertResult = _upsertIncomingMessageBatch(convID, messagesToUpsert);
    if (upsertResult.insertedMessages.isNotEmpty) {
      _freezeHistoryReadingWindowByConversation[_inboundStateKey(convID)]
          ?.didAppend?.call(upsertResult.insertedMessages);
    }
    if (!isFollowing) {
      _recordVisibleLiveIncoming(convID, upsertResult.insertedMessages);
    }
    if (upsertResult.inserted) {
      listDirty = true;
      enterAnimationCandidate = upsertResult.lastInserted;
    }

    if (listDirty) {
      _bumpMessageListRevisionFor(convID, reason: 'inbound_batch_active');
    }

    if (isFollowing && enterAnimationCandidate != null) {
      _markIncomingMessageEnterAnimation(enterAnimationCandidate);
    }

    final isBulk = messages.length >= _bulkMessageSyncThreshold;
    if (listDirty &&
        isFollowing &&
        !_shouldDeferIncomingToVisibleList(
          convID,
          position: position,
          isActuallyNearBottom: isActuallyNearBottom,
        )) {
      final scrollFollowActive = chatConfig.inboundScrollFollowEnabled &&
          isChunkedRevealActive(convID);
      if (isBulk ||
          isBulkMessageSyncActive(convID) ||
          isChunkedRevealActive(convID)) {
        if (!scrollFollowActive) {
          _pendingPinAfterBulkByConv[convID] = true;
        }
      } else {
        requestPinToBottom(convID);
      }
    }

    ChatJitterDiag.logInboundFlow(
      action: 'batch_applied',
      conv: convID,
      extras: <String, Object?>{
        'count': messages.length,
        'upserted': messagesToUpsert.length,
        'listDirty': listDirty,
        'bulk': isBulk,
        'nearBottom': isActuallyNearBottom,
        'bottomLocked': isInboundPresentationBottomLocked(convID),
        'returningToBottom': isReturningToBottom,
        'logicalPosition': position.name,
        'tongueUnread': unreadCountForTongue,
        'buffered': _inboundUnreadStateFor(
          convID,
          create: false,
        ).bufferedMessages.length,
        'queue': pendingInboundProjectionCount(convID),
      },
    );
    ChatJitterDiag.logFollowingLatest(
      action: 'inbound_batch',
      conv: convID,
      extras: <String, Object?>{
        'isFollowing': isFollowing,
        'keyboardBottom': wasAtBottomBeforeKeyboardViewportChange,
        'willPin': listDirty &&
            isFollowing &&
            !_shouldDeferIncomingToVisibleList(
              convID,
              position: position,
              isActuallyNearBottom: isActuallyNearBottom,
            ),
        ...stickToLatestDiagSnapshot(convID),
      },
    );
    _markNeedsNotify();
  }

  void _recordVisibleLiveIncoming(String convID, List<V2TimMessage> messages) {
    final state = _inboundUnreadStateFor(convID);
    for (final message in messages) {
      final id = liveIncomingIdentity(message);
      // Publication is not a read. Retry and history replay do not create
      // another reminder; measured visible coverage consumes this ledger.
      if (message.isSelf == true || id.isEmpty ||
          state.seenLiveIncomingIds.contains(id) ||
          !state.revealedUnreadMessageIDs.add(id)) continue;
      state.unreadCount++;
      state.receivedCount++;
      _recordBufferedLiveIncoming(state, message);
    }
  }

  bool _syncSelfSentMessage(
    String convID,
    V2TimMessage newMsg, {
    bool forceSuccess = false,
  }) {
    if (newMsg.isSelf != true) {
      return false;
    }
    if (forceSuccess &&
        (isOutgoingMediaCancelled(newMsg.id) ||
            isOutgoingMediaCancelled(newMsg.msgID))) {
      return false;
    }
    // _upsertIncomingMessage constructs and submits the authoritative delta.
    // Its null/rejected result is terminal for this callback; there is no
    // direct-list fallback after a Writer decision.
    return _upsertIncomingMessage(convID, newMsg, forceSuccess: forceSuccess);
  }

  void _syncGroupMemberFromMessage(V2TimMessage message) {
    final groupID = TencentUtils.checkString(message.groupID);
    final userID = TencentUtils.checkString(message.sender) ??
        TencentUtils.checkString(message.userID);
    if (groupID == null || userID == null) {
      return;
    }

    final nameCard = TencentUtils.checkString(message.nameCard);
    final nickName = TencentUtils.checkString(message.nickName);
    final friendRemark = TencentUtils.checkString(message.friendRemark);
    final faceUrl = TencentUtils.checkString(message.faceUrl);
    if (nameCard == null &&
        nickName == null &&
        friendRemark == null &&
        faceUrl == null) {
      return;
    }

    final current = GroupMemberStore.instance.memberOf(groupID, userID);
    if (current == null) {
      GroupMemberStore.instance.putMember(
        groupID,
        V2TimGroupMemberFullInfo(
          userID: userID,
          nameCard: nameCard,
          nickName: nickName,
          friendRemark: friendRemark,
          faceUrl: faceUrl,
        ),
      );
      return;
    }

    var changed = false;
    if (nameCard != null && current.nameCard != nameCard) {
      current.nameCard = nameCard;
      changed = true;
    }
    if (nickName != null && current.nickName != nickName) {
      current.nickName = nickName;
      changed = true;
    }
    if (friendRemark != null && current.friendRemark != friendRemark) {
      current.friendRemark = friendRemark;
      changed = true;
    }
    if (faceUrl != null && current.faceUrl != faceUrl) {
      current.faceUrl = faceUrl;
      changed = true;
    }
    if (changed) {
      GroupMemberStore.instance.putMember(groupID, current);
    }
  }

  Future<void> _onReceiveNewMsg(
    V2TimMessage msgComing, {
    String? ingressEventID,
    int? ingressSequence,
    bool projectMessageList = true,
  }) async {
    final lifecycleGeneration = _messageHistoryCoverageSessionGeneration;
    final writerScope = _messageReconciliationWriter.configuredScope;
    final initialConvID = _messageConversationID(msgComing);
    if (initialConvID == null || initialConvID.isEmpty) {
      return;
    }

    final capturedClearEpoch = messageDeltaClearEpochFor(initialConvID);
    V2TimMessage? mountedMessage = msgComing;
    if (_lifeCycle?.newMessageWillMount != null) {
      try {
        mountedMessage = await _lifeCycle!.newMessageWillMount(msgComing);
      } catch (e) {
        outputLogger.i('newMessageWillMount error: $e');
        mountedMessage = msgComing;
      }
    }
    if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
        _messageReconciliationWriter.configuredScope != writerScope ||
        messageDeltaClearEpochFor(initialConvID) != capturedClearEpoch) {
      ChatJitterDiag.log(
        'message_inbound_drop_stale_lifecycle',
        conv: initialConvID,
        extras: <String, Object?>{
          'generation': lifecycleGeneration,
          'currentGeneration': _messageHistoryCoverageSessionGeneration,
        },
      );
      return;
    }
    if (mountedMessage == null) {
      return;
    }
    mountedMessage = _normalizeInboundC2cDirection(mountedMessage);

    final rawConvID = _messageConversationID(mountedMessage) ?? initialConvID;
    final convID = _resolveMessageListStorageKey(rawConvID);
    _syncGroupMemberFromMessage(mountedMessage);
    final senderId = TencentUtils.checkString(mountedMessage.sender) ??
        TencentUtils.checkString(mountedMessage.userID);
    if (mountedMessage.isSelf != true && senderId != null) {
      unawaited(
        UserProfileLocalBridge.upsertPublicProfileFromSnapshot(
          userId: senderId,
          nickName: mountedMessage.nickName,
          faceUrl: mountedMessage.faceUrl,
        ),
      );
    }

    // Typing/status custom messages should update typing state only. They must not
    // enter the visible message list, but they also must not stop normal message
    // events in other conversations.
    final bool isEditMessage = _editStatusCheck(mountedMessage);
    if (isEditMessage) {
      return;
    }

    if (!projectMessageList) {
      if (HistoryWindowRepositoryProvider.repository != null) {
        await _admitBoundedHistoryIncoming(
          mountedMessage,
          eventID: ingressEventID,
          ingressSequence: ingressSequence,
          allowLatestReveal: false,
        );
      }
      return;
    }

    if (!_isSameConversationID(convID, currentSelectedConv) &&
        !_messageListMap.containsKey(convID)) {
      // Notifications and business signaling run outside this display model.
      // Opening this conversation will read the SDK's persisted recent page.
      return;
    }

    if (HistoryWindowRepositoryProvider.repository != null &&
        await _admitBoundedHistoryIncoming(mountedMessage,
            eventID: ingressEventID, ingressSequence: ingressSequence)) return;
    if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
        _messageReconciliationWriter.configuredScope != writerScope) return;

    _checkFromUserisActive(mountedMessage);
    final convType = TencentUtils.checkString(mountedMessage.groupID) != null
        ? ConvType.group
        : ConvType.c2c;
    final isActiveConversation = _isSameConversationID(
      convID,
      currentSelectedConv,
    );

    if (isActiveConversation &&
        chatConfig.isAutoReportRead &&
        lockedEntryUnreadCountFor(convID) == 0) {
      _scheduleActiveReadReport(convID: convID, convType: convType);
    }

    // Self-sent sync on the active chat must stay immediate for send UX.
    if (isActiveConversation && mountedMessage.isSelf == true) {
      _syncSelfSentMessage(convID, mountedMessage, forceSuccess: false);
      _markNeedsNotify();
      return;
    }

    // Group seq gap detection: if the reorder buffer is active for this
    // conversation, route through it so out-of-order messages are buffered
    // and missing messages trigger a cloud catch-up. C2C seq has no global
    // continuity so the buffer is never active for C2C.
    final buffer = _reorderBuffersByConv[convID];
    if (buffer != null && buffer.isActivated && convType == ConvType.group) {
      final result = buffer.accept(mountedMessage);
      if (result == null) {
        // Buffered: out-of-order or gap detected, will be flushed later.
        return;
      }
      if (result.isEmpty) {
        // Duplicate (seq <= expected), silently dropped.
        return;
      }
      // Contiguous: upsert immediately (may include drained buffer messages).
      for (final msg in result) {
        _inboundBatchCoalescer.enqueue(convID, msg);
      }
      return;
    }

    _inboundBatchCoalescer.enqueue(convID, mountedMessage);
  }

  String _revokedCloudCustomData(String? raw, bool isAdmin) {
    final data = <String, dynamic>{};
    final source = raw?.trim();
    if (source != null && source.isNotEmpty) {
      try {
        final decoded = jsonDecode(source);
        if (decoded is Map) {
          data.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Keep the original message render stable even when old custom data is invalid.
      }
    }
    data['isRevoke'] = true;
    data['revokeByAdmin'] = isAdmin;
    return jsonEncode(data);
  }

  void _addRevokeLookupKey(List<String> keys, String? key) {
    final value = key?.trim();
    if (value == null || value.isEmpty || keys.contains(value)) {
      return;
    }
    keys.add(value);

    if (value.startsWith('c2c_')) {
      final pure = value.substring(4);
      if (pure.isNotEmpty && !keys.contains(pure)) {
        keys.add(pure);
      }
    } else if (value.startsWith('C2C')) {
      final pure = value.substring(3);
      if (pure.isNotEmpty && !keys.contains(pure)) {
        keys.add(pure);
      }
    } else if (!value.startsWith('group_') && !value.startsWith('GROUP')) {
      final c2cKey = 'c2c_$value';
      if (!keys.contains(c2cKey)) {
        keys.add(c2cKey);
      }
    }

    if (value.startsWith('group_')) {
      final pure = value.substring(6);
      if (pure.isNotEmpty && !keys.contains(pure)) {
        keys.add(pure);
      }
    } else if (value.startsWith('GROUP')) {
      final pure = value.substring(5);
      if (pure.isNotEmpty && !keys.contains(pure)) {
        keys.add(pure);
      }
    }
  }

  void _clearRevokedInboundPresentation(
    String conversationID,
    String msgID, {
    V2TimMessage? revokedMessage,
  }) {
    final target = msgID.trim();
    if (target.isEmpty) {
      return;
    }
    final stateKey = _inboundStateKey(conversationID);
    final state = _inboundUnreadStateFor(stateKey, create: false);
    final dedupKeys = <String>{
      'msg:$target',
      if (revokedMessage != null) messageDedupKey(revokedMessage),
    };
    state.bufferedMessages.removeWhere(
      (message) =>
          message.msgID == target ||
          dedupKeys.contains(messageDedupKey(message)),
    );
    bool matchesTarget(String value) {
      return dedupKeys.contains(value) ||
          value == target ||
          value.endsWith(':$target');
    }

    state.bufferedMessageKeys.removeWhere(matchesTarget);
    _inboundFastForwardMessageKeys.removeWhere(matchesTarget);
    final deferredPrefix = '$stateKey|';
    _authoritativeDeferredIncomingKeys.removeWhere(
      (value) =>
          value.startsWith(deferredPrefix) &&
          matchesTarget(value.substring(deferredPrefix.length)),
    );
    if (revokedMessage != null) {
      _revealDeferredProjectionAcrossAliases(conversationID, <V2TimMessage>[
        revokedMessage,
      ]);
      _chatUiStateStore.markMessageChanged(
        conversationID,
        ChatUiStateStore.messageKeyOf(revokedMessage),
      );
    }
  }

  bool markMessageRevokedNow(
    String msgID, {
    String? convID,
    bool isAdmin = false,
  }) {
    final targetMsgID = msgID.trim();
    if (targetMsgID.isEmpty) {
      return false;
    }

    final keys = <String>[];
    _addRevokeLookupKey(keys, convID);
    _addRevokeLookupKey(keys, currentSelectedConv);
    for (final key in _messageListMap.keys) {
      _addRevokeLookupKey(keys, key);
    }

    var didUpdate = false;
    final visitedStorageKeys = <String>{};
    for (final key in keys) {
      final storageKey = _resolveMessageListStorageKey(key);
      if (storageKey.isEmpty || !visitedStorageKeys.add(storageKey)) {
        continue;
      }
      final activeMessageList = _messageListMap[storageKey];
      if (activeMessageList == null || activeMessageList.isEmpty) {
        // Keep the revoke authority even when the row is outside the current
        // memory window. A later older-page response must not resurrect it.
        final commit = commitMessageDelta(
          MessageDelta<V2TimMessage>(
            conversationKey: storageKey,
            eventID: 'revoke_tombstone:$targetMsgID:$storageKey',
            kind: MessageDeltaKind.revoke,
            source: MessageDeltaSource.sdkRealtime,
            generation: messageDeltaGenerationFor(storageKey),
            clearEpoch: messageDeltaClearEpochFor(storageKey),
            tombstones: <String>{targetMsgID},
          ),
          forcePublishForRevoke: true,
        );
        if (commit != null) {
          _clearRevokedInboundPresentation(storageKey, targetMsgID);
          didUpdate = true;
        }
        continue;
      }

      final target = activeMessageList.cast<V2TimMessage?>().firstWhere(
            (item) => item?.msgID == targetMsgID,
            orElse: () => null,
          );
      if (target != null) {
        final revoked = _cloneMessage(target);
        revoked.status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
        revoked.cloudCustomData = _revokedCloudCustomData(
          revoked.cloudCustomData,
          isAdmin,
        );
        revoked.id ??= revoked.msgID;
        final commit = commitMessageDelta(
          MessageDelta<V2TimMessage>(
            conversationKey: storageKey,
            eventID:
                'revoke:$targetMsgID:$storageKey:${DateTime.now().microsecondsSinceEpoch}',
            kind: MessageDeltaKind.revoke,
            source: MessageDeltaSource.sdkRealtime,
            generation: messageDeltaGenerationFor(storageKey),
            clearEpoch: messageDeltaClearEpochFor(storageKey),
            upserts: [messageDeltaRecord(revoked)],
            tombstones: <String>{targetMsgID},
          ),
          forcePublishForRevoke: true,
        );
        if (commit != null) {
          _clearRevokedInboundPresentation(
            storageKey,
            targetMsgID,
            revokedMessage: revoked,
          );
          didUpdate = true;
          continue;
        }
      }

      // A row may be outside this memory window or may already have been
      // projected away. The tombstone is still authoritative and is the only
      // accepted fallback; never mutate the formal list directly here.
      final commit = commitMessageDelta(
        MessageDelta<V2TimMessage>(
          conversationKey: storageKey,
          eventID:
              'revoke_tombstone:$targetMsgID:$storageKey:${DateTime.now().microsecondsSinceEpoch}',
          kind: MessageDeltaKind.revoke,
          source: MessageDeltaSource.sdkRealtime,
          generation: messageDeltaGenerationFor(storageKey),
          clearEpoch: messageDeltaClearEpochFor(storageKey),
          tombstones: <String>{targetMsgID},
        ),
        forcePublishForRevoke: true,
      );
      if (commit != null) {
        _clearRevokedInboundPresentation(storageKey, targetMsgID);
        didUpdate = true;
      }
    }

    // The recalled row may already be outside the in-memory chat window while
    // still present in the short gallery cache. Invalidate by server identity
    // even when no visible row was updated, and across alias conversation keys.
    ChatMediaGalleryExpandCache.removeMessage(targetMsgID);

    if (didUpdate) {
      // Revoke is a user-visible command. Refresh immediately like WeChat instead
      // of waiting for the next route switch/history reload.
      _notifyPending = false;
      notifyListeners();
    }
    return didUpdate;
  }

  Future<void> onMessageRevoked(String msgID, [String? convID]) async {
    if (HistoryWindowRepositoryProvider.repository != null) {
      await recordHistoryWindowMutation(
          conversationID: convID,
          msgID: msgID,
          kind: HistoryWindowMutationKind.revoke);
    }
    markMessageRevokedNow(msgID, convID: convID);
  }

  void markMessageChangedByMessage(
    String conversationID,
    V2TimMessage message,
  ) {
    final messageKey = ChatUiStateStore.messageKeyOf(message);
    if (messageKey.isEmpty) {
      return;
    }
    _chatUiStateStore.markMessageChanged(conversationID, messageKey);
    _markNeedsNotify(conversationID: conversationID);
  }

  /// Commits media metadata that arrived after a history row was mounted.
  ///
  /// URL resolution usually mutates the SDK message object in place. A cloud
  /// reconciliation can instead have cloned that row, so update the
  /// authoritative row when identity matches and then use the existing
  /// row-level revision channel. This keeps late media enrichment from
  /// rebuilding or resorting the whole message window.
  void mergeMessageMediaMetadata(
    V2TimMessage resolved, {
    String? conversationID,
  }) {
    final msgID = resolved.msgID?.trim() ?? '';
    final clientID = resolved.id?.trim() ?? '';
    if (msgID.isEmpty && clientID.isEmpty) {
      return;
    }

    final explicitConversation = conversationID?.trim() ?? '';
    String inferredConversation = explicitConversation;
    if (inferredConversation.isEmpty) {
      inferredConversation = resolved.userID?.trim() ?? '';
    }
    if (inferredConversation.isEmpty) {
      inferredConversation = resolved.groupID?.trim() ?? '';
    }
    if (inferredConversation.isEmpty) {
      try {
        final dynamic nativeMessage = resolved;
        inferredConversation =
            nativeMessage.messageConvID?.toString().trim() ?? '';
      } catch (_) {}
    }

    // Explicit context is authoritative. Without it, userID/groupID is only
    // a preference because self-sent C2C rows may carry the login user ID.
    final allEntries = _messageListMap.entries.toList(growable: true);
    final entries = explicitConversation.isNotEmpty
        ? allEntries
            .where(
              (entry) => _isSameConversationID(entry.key, explicitConversation),
            )
            .toList(growable: true)
        : allEntries.toList(growable: true);
    if (explicitConversation.isEmpty && inferredConversation.isNotEmpty) {
      entries.sort((left, right) {
        final leftMatches = _isSameConversationID(
          left.key,
          inferredConversation,
        );
        final rightMatches = _isSameConversationID(
          right.key,
          inferredConversation,
        );
        if (leftMatches == rightMatches) {
          return 0;
        }
        return leftMatches ? -1 : 1;
      });
    }
    final visitedStorageKeys = <String>{};
    var changed = false;
    for (final entry in entries) {
      final storageKey = _resolveMessageListStorageKey(entry.key);
      if (!visitedStorageKeys.add(storageKey)) {
        continue;
      }
      final current = _messageListMap[storageKey];
      if (current == null || current.isEmpty) {
        continue;
      }
      final index = current.indexWhere(
        (candidate) =>
            (msgID.isNotEmpty && candidate.msgID == msgID) ||
            (clientID.isNotEmpty && candidate.id == clientID),
      );
      if (index < 0) {
        continue;
      }
      final existing = current[index];
      if (identical(existing, resolved)) {
        _messageListDisplayCache.removeWhere(
          (key, _) => _isSameConversationID(key, storageKey),
        );
        _markMessageRowChanged(
          storageKey,
          existing,
          extraKey: msgID.isNotEmpty ? msgID : clientID,
        );
        changed = true;
        continue;
      }

      final replacement = _cloneMessage(existing);
      if (resolved.imageElem != null) {
        replacement.imageElem = resolved.imageElem;
      }
      if (resolved.videoElem != null) {
        replacement.videoElem = resolved.videoElem;
      }
      if (replacement.elemType == MessageElemType.V2TIM_ELEM_TYPE_NONE &&
          resolved.elemType != MessageElemType.V2TIM_ELEM_TYPE_NONE) {
        replacement.elemType = resolved.elemType;
      }
      final result = replaceMessageRowLocal(
        conversationID: storageKey,
        index: index,
        expected: existing,
        replacement: replacement,
        aliases: <String?>[msgID, clientID],
      );
      if (result == RowLocalMessageReplacementResult.replaced) {
        _messageListDisplayCache.removeWhere(
          (key, _) => _isSameConversationID(key, storageKey),
        );
        changed = true;
      }
    }

    // A metadata response may finish before the matching history window is
    // committed. The row-level invalidation is harmless and lets a later
    // alias-aware lookup rebuild the row as soon as it exists.
    if (!changed && msgID.isNotEmpty) {
      markMessageRowsChangedByMsgIDs(<String?>[msgID]);
    }
  }

  Future<void> onMessageModified(V2TimMessage modifiedMessage,
      [String? convID]) async {
    if (HistoryWindowRepositoryProvider.repository != null) {
      await recordHistoryWindowMutation(
          conversationID: convID ?? _messageConversationID(modifiedMessage),
          msgID: modifiedMessage.msgID ?? '',
          kind: HistoryWindowMutationKind.edit,
          message: modifiedMessage);
    }
    await _applyMessageModifiedNow(modifiedMessage, convID);
  }

  Future<void> _applyMessageModifiedNow(V2TimMessage modifiedMessage,
      [String? convID]) async {
    final lifecycleGeneration = _messageHistoryCoverageSessionGeneration;
    final writerScope = _messageReconciliationWriter.configuredScope;
    final String? exactId = TencentUtils.checkString(modifiedMessage.userID) ??
        TencentUtils.checkString(modifiedMessage.groupID);
    final rawConvID = convID ?? exactId;
    if (rawConvID == null || rawConvID.isEmpty) {
      return;
    }
    final resolvedConvID = _resolveMessageListStorageKey(rawConvID);
    if (resolvedConvID.isEmpty) {
      return;
    }
    final capturedClearEpoch = messageDeltaClearEpochFor(resolvedConvID);
    if (modifiedMessage.isSelf == true) {
      if (!_shouldProjectHistoryWindowEdit(resolvedConvID, modifiedMessage))
        return;
      final applied = _syncSelfSentMessage(
        resolvedConvID,
        modifiedMessage,
        forceSuccess: false,
      );
      if (applied) {
        _chatUiStateStore.markMessageChangedByMessage(
          resolvedConvID,
          modifiedMessage,
        );
        _markNeedsNotify();
      }
      return;
    }
    final V2TimMessage newMsg =
        await _lifeCycle?.modifiedMessageWillMount(modifiedMessage) ??
            modifiedMessage;
    if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
        _messageReconciliationWriter.configuredScope != writerScope ||
        messageDeltaClearEpochFor(resolvedConvID) != capturedClearEpoch) {
      ChatJitterDiag.log(
        'message_modified_drop_stale_lifecycle',
        conv: resolvedConvID,
        extras: <String, Object?>{
          'generation': lifecycleGeneration,
          'currentGeneration': _messageHistoryCoverageSessionGeneration,
        },
      );
      return;
    }
    if (!_shouldProjectHistoryWindowEdit(resolvedConvID, newMsg)) return;
    if (newMsg.isSelf != true) {
      final msgID = newMsg.msgID?.trim() ?? '';
      final clientId = newMsg.id?.trim() ?? '';
      final editCommit = commitMessageDelta(
        MessageDelta<V2TimMessage>(
          conversationKey: resolvedConvID,
          eventID: 'edit:${msgID.isNotEmpty ? msgID : clientId}:'
              '${DateTime.now().microsecondsSinceEpoch}',
          kind: MessageDeltaKind.edit,
          source: MessageDeltaSource.sdkRealtime,
          generation: messageDeltaGenerationFor(resolvedConvID),
          clearEpoch: messageDeltaClearEpochFor(resolvedConvID),
          upserts: [messageDeltaRecord(newMsg)],
        ),
      );
      // The row may be outside the current memory window. The delta still
      // needs to be remembered as an authoritative overlay so an older page
      // cannot resurrect stale content. While history is in flight the delta
      // is queued and must not be applied through the legacy direct writer.
      if (editCommit != null ||
          _messageReconciliationWriter.hasActiveRequest(resolvedConvID)) {
        return;
      }
      // A null commit means the writer rejected a stale/duplicate/tombstoned
      // edit. Never fall back to a direct list mutation in that case, or a
      // deleted row could be reintroduced outside the authoritative state.
      return;
    }
    if (newMsg.isSelf == true) {
      // A lifecycle hook may turn an inbound model into a self message. It
      // still follows the same send/adoption Writer boundary as the normal
      // self branch above.
      final applied = _syncSelfSentMessage(
        resolvedConvID,
        newMsg,
        forceSuccess: false,
      );
      if (applied) {
        _chatUiStateStore.markMessageChangedByMessage(resolvedConvID, newMsg);
        _markNeedsNotify();
      }
    }
  }

  _onReceiveC2CReadReceipt(List<V2TimMessageReceipt> receiptList) {
    var changed = false;
    final peerReadConvIds = <String, int>{};
    // Scan a peer's window once for the entire SDK watermark batch.
    final latestByPeer = <String, V2TimMessageReceipt>{};
    final wildcardPeers = <String>{};
    for (final receipt in receiptList) {
      final peerKey = _normalizeC2CKey(receipt.userID).toLowerCase();
      if (peerKey.isEmpty) continue;
      final readAt = _receiptTimestamp(receipt.timestamp);
      if (readAt <= 0) wildcardPeers.add(peerKey);
      final previous = latestByPeer[peerKey];
      if (previous == null || readAt > _receiptTimestamp(previous.timestamp)) {
        latestByPeer[peerKey] = receipt;
      }
    }
    for (final receipt in latestByPeer.values) {
      final peerID = receipt.userID.trim();
      if (peerID.isEmpty) {
        continue;
      }
      final readAt = _receiptTimestamp(receipt.timestamp);
      final peerKey = _normalizeC2CKey(peerID).toLowerCase();
      if (readAt > (_c2cPeerReadTimestampMap[peerKey] ?? 0)) {
        _c2cPeerReadTimestampMap[peerKey] = readAt;
        changed = true;
      }

      final normalizedPeer = _normalizeC2CKey(peerID);
      if (normalizedPeer.isNotEmpty) {
        peerReadConvIds['c2c_$normalizedPeer'] = readAt;
      }

      final visitedConversationKeys = <String>{};
      for (final entry in _messageListMap.entries.toList()) {
        if (!_isC2CConversationForPeer(entry.key, peerID)) {
          continue;
        }
        final storageKey = _resolveMessageListStorageKey(entry.key);
        if (storageKey.isEmpty || !visitedConversationKeys.add(storageKey)) {
          continue;
        }
        peerReadConvIds[storageKey] = readAt;
        final list = _mergedAliasMessageList(storageKey);
        if (list.isEmpty) continue;
        var convChanged = false;
        final changedKeys = <String>{};
        final updated = <V2TimMessage>[];
        for (final element in list) {
          final isSelf = element.isSelf ?? true;
          final timestamp = element.timestamp ?? 0;
          final shouldMarkRead = isSelf &&
              element.isPeerRead != true &&
              (wildcardPeers.contains(peerKey) ||
                  timestamp <= 0 ||
                  timestamp <= readAt);
          if (shouldMarkRead) {
            final msgID = element.msgID;
            if (msgID != null && msgID.isNotEmpty) {
              changedKeys.add(msgID);
            }
            changedKeys.add(ChatUiStateStore.messageKeyOf(element));
            convChanged = true;
            final next = _cloneMessage(element);
            next.isPeerRead = true;
            updated.add(next);
          }
        }
        if (convChanged) {
          final commit = commitMessageDelta(
            MessageDelta<V2TimMessage>(
              conversationKey: storageKey,
              eventID: 'read_receipt:c2c:$peerID:$readAt:'
                  '${wildcardPeers.contains(peerKey) ? 'all' : 'through'}',
              kind: MessageDeltaKind.readReceipt,
              source: MessageDeltaSource.sdkRealtime,
              generation: messageDeltaGenerationFor(storageKey),
              clearEpoch: messageDeltaClearEpochFor(storageKey),
              upserts: _reconciliationRecords(updated),
            ),
          );
          if (commit != null) {
            for (final element in updated) {
              if (element.isSelf == true && element.isPeerRead == true) {
                final msgID = element.msgID?.trim() ?? '';
                if (msgID.isNotEmpty) {
                  _messageReadReceiptMap[msgID] = V2TimMessageReceipt(
                    userID: peerID,
                    timestamp: readAt,
                    msgID: msgID,
                    isPeerRead: true,
                  );
                }
              }
            }
            _chatUiStateStore.markMessagesChanged(storageKey, changedKeys);
            changed = true;
          }
        }
      }
    }
    for (final entry in peerReadConvIds.entries) {
      ConversationPeerReadCoordinator.scheduleNotify(
        conversationID: entry.key,
        peerReadAtSec: entry.value,
      );
    }
    if (changed) {
      _markNeedsNotify();
    }
  }

  _onReceiveMessageReadReceipts(List<V2TimMessageReceipt> receiptList) {
    try {
      var changed = false;
      final latestByID = <String, V2TimMessageReceipt>{};
      for (final receipt in receiptList) {
        final id = receipt.msgID?.trim() ?? '';
        if (id.isNotEmpty) latestByID[id] = receipt;
      }
      final changedIDs = <String>{};
      for (var receipt in latestByID.values) {
        final msgID = receipt.msgID;
        if (msgID != null && msgID.isNotEmpty) {
          // Some SDK versions report a fully-read receipt as
          // unreadCount=0/readCount>0 while leaving isPeerRead=false.
          // Normalize that combination so the chat message model and the
          // conversation-list projection use the same read decision.
          final fullyRead = receipt.isPeerRead == true ||
              (receipt.unreadCount != null &&
                  receipt.unreadCount == 0 &&
                  (receipt.readCount ?? 0) > 0);
          final next = V2TimMessageReceipt(
            userID: receipt.userID,
            timestamp: _receiptTimestamp(receipt.timestamp),
            msgID: msgID,
            isPeerRead: fullyRead,
            readCount: receipt.readCount,
            unreadCount: receipt.unreadCount,
            groupID: receipt.groupID,
          );
          final previous = _messageReadReceiptMap[msgID];
          if (previous?.isPeerRead != next.isPeerRead ||
              previous?.timestamp != next.timestamp ||
              previous?.readCount != next.readCount ||
              previous?.unreadCount != next.unreadCount) {
            _messageReadReceiptMap[msgID] = next;
            changedIDs.add(msgID);
            changed = true;
          }
          if (_isReceiptFullyRead(next)) {
            final convId = _conversationIdForReadReceipt(next);
            if (convId != null && convId.isNotEmpty) {
              ConversationPeerReadCoordinator.scheduleNotify(
                conversationID: convId,
                msgID: msgID,
                peerReadAtSec: next.timestamp,
              );
            }
          }
        }
      }
      if (changed) {
        for (final msgID in changedIDs) {
          _markMessageRowsChangedByMsgID(msgID);
        }
        _markNeedsNotify();
      }
    } catch (e) {}
  }

  bool _isReceiptFullyRead(V2TimMessageReceipt receipt) {
    if (receipt.isPeerRead == true) {
      return true;
    }
    final unread = receipt.unreadCount;
    final read = receipt.readCount ?? 0;
    return unread != null && unread == 0 && read > 0;
  }

  String? _conversationIdForReadReceipt(V2TimMessageReceipt receipt) {
    final group = receipt.groupID?.trim() ?? '';
    if (group.isNotEmpty) {
      return group.startsWith('group_') ? group : 'group_$group';
    }
    final msgID = receipt.msgID?.trim() ?? '';
    if (msgID.isNotEmpty) {
      final matches = _messageListMap.find(msgID);
      if (matches.isNotEmpty) return matches.first.key;
    }
    final peer = _normalizeC2CKey(receipt.userID);
    if (peer.isNotEmpty) {
      return 'c2c_$peer';
    }
    return null;
  }

  _onSendMessageProgress(V2TimMessage message, int progress) {
    final rawConvID = _messageConversationID(message) ??
        TencentUtils.checkString(message.userID) ??
        message.groupID;
    if (rawConvID == null || rawConvID.isEmpty) {
      return;
    }
    final convID = _resolveMessageListStorageKey(rawConvID);
    if (convID.isEmpty) {
      return;
    }
    final msgID = message.msgID;
    final id = message.id;
    if (isOutgoingMediaCancelled(id) || isOutgoingMediaCancelled(msgID)) {
      return;
    }
    final progressClamped = progress.clamp(0, 100);
    if (progressClamped > 0 && progressClamped < 100) {
      // SDKs can repeat an integer percentage or deliver an older callback.
      // Keep the row stable until progress actually advances; terminal status
      // must still be reconciled even when its percentage has not changed.
      final knownProgress = max(
        getMessageProgress(msgID ?? ''),
        getMessageProgress(id ?? ''),
      );
      if (progressClamped <= knownProgress &&
          message.status != MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
        return;
      }

      if (msgID != null && msgID.isNotEmpty) {
        _setUploadProgressSilently(msgID, progressClamped);
      }
      if (id != null && id.isNotEmpty) {
        _setUploadProgressSilently(id, progressClamped);
      }
      _markMessageRowChangedByIds(convID, msgID: msgID, clientId: id);
    } else if (progressClamped >= 100) {
      if (msgID != null && msgID.isNotEmpty) {
        _clearUploadProgressSilently(msgID);
      }
      if (id != null && id.isNotEmpty) {
        _clearUploadProgressSilently(id);
      }
      _markMessageRowChangedByIds(convID, msgID: msgID, clientId: id);
    }
  }

  Future<void> onMessageDownloadProgressCallback(
    V2TimMessageDownloadProgress messageProgress, {
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) return;
    final currentProgress = getMessageProgress(messageProgress.msgID);

    if (messageProgress.isError || messageProgress.errorCode != 0) {
      V2TimMessage? message = await _findAndRetrieveMessage(
        messageProgress.msgID,
      );
      if (isCurrent?.call() == false) return;
      _handleDownloadError(messageProgress, message);
      return;
    }

    if (messageProgress.isFinish && currentProgress < 100) {
      V2TimMessage? message = await _findAndRetrieveMessage(
        messageProgress.msgID,
      );
      if (isCurrent?.call() == false) return;
      _handleFinishedDownload(messageProgress, message, isCurrent: isCurrent);
      return;
    }

    _updateProgressIfNeeded(messageProgress, currentProgress);
  }

  Future<V2TimMessage?> _findAndRetrieveMessage(String messageId) async {
    final messages = await _messageService.findMessages(
      messageIDList: [messageId],
    );
    return messages == null || messages.isEmpty ? null : messages.first;
  }

  void _handleFinishedDownload(
    V2TimMessageDownloadProgress messageProgress,
    V2TimMessage? message, {
    bool Function()? isCurrent,
  }) {
    if (message != null) {
      bool isImageType =
          message.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
      bool isVideoType =
          message.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
      const originalImageType = 0;
      if (!isImageType && !isVideoType) {
        _updateMessageLocationAndDownloadFile(messageProgress);
      } else if ((isImageType && messageProgress.type == originalImageType) ||
          (isVideoType && !messageProgress.isSnapshot)) {
        Future.delayed(
          const Duration(seconds: 1),
          () {
            if (isCurrent?.call() == false) return;
            _updateMessageAndDownloadFile(message, messageProgress);
          },
        );
      } else {
        return;
      }
    } else {
      _updateMessageLocationAndDownloadFile(messageProgress);
    }
  }

  void _handleDownloadError(
    V2TimMessageDownloadProgress messageProgress,
    V2TimMessage? message,
  ) {
    setMessageProgress(messageProgress.msgID, 0);
    _markMessageRowsChangedByMsgID(messageProgress.msgID);
    _markNeedsNotify();
    downloadFile();
  }

  void _updateMessageAndDownloadFile(
    V2TimMessage message,
    V2TimMessageDownloadProgress messageProgress,
  ) {
    updateAsyncMessage(
      message,
      TencentUtils.checkString(message.userID) ??
          TencentUtils.checkString(message.groupID) ??
          "",
    );

    _updateMessageLocationAndDownloadFile(messageProgress);
  }

  void _updateMessageLocationAndDownloadFile(
    V2TimMessageDownloadProgress messageProgress,
  ) {
    setFileMessageLocation(messageProgress.msgID, messageProgress.path);
    setMessageProgress(messageProgress.msgID, 100);
    _markMessageRowsChangedByMsgID(messageProgress.msgID);
    _markNeedsNotify();
    downloadFile();
  }

  void _updateProgressIfNeeded(
    V2TimMessageDownloadProgress messageProgress,
    int currentProgress,
  ) {
    try {
      if (messageProgress.totalSize != -1 && !messageProgress.isFinish) {
        int progress = min(
          99,
          (messageProgress.currentSize / messageProgress.totalSize * 100)
              .floor(),
        );
        if (progress > 1 && progress > currentProgress) {
          setMessageProgress(messageProgress.msgID, progress);
          _markMessageRowsChangedByMsgID(messageProgress.msgID);
          _markNeedsNotify();
        }
      }
    } catch (e) {
      outputLogger.i("calculate error: ${messageProgress.toJson()}");
    }
  }

  /// Ordinary chat callbacks are owned by the app-level
  /// [TencentAdvancedMessageAdapter]. Keep the old API source-compatible but
  /// prevent a view model from registering a second SDK listener.
  @Deprecated('The app MessageCore owns the only ordinary chat listener.')
  void addAdvancedMsgListener() {}

  @Deprecated('The app MessageCore owns the only ordinary chat listener.')
  void removeAdvanceMsgListener() {}

  /// Application-layer compatibility bridge for the single IM ingress.
  ///
  /// The SDK listener is owned by the app MessageCore. These methods preserve
  /// the existing UIKit projection behavior without registering another SDK
  /// listener inside the view model.
  Future<void> applyAppRealtimeMessage(
    V2TimMessage message, {
    String? ingressEventID,
    int? ingressSequence,
    bool projectMessageList = true,
  }) async {
    await _onReceiveNewMsg(
      message,
      ingressEventID: ingressEventID,
      ingressSequence: ingressSequence,
      projectMessageList: projectMessageList,
    );
    if (message.isSelf == true) {
      unawaited(ImOutgoingSendCoordinator.instance
          .adoptProviderHistory(<V2TimMessage>[message], source: ImProviderEvidenceSource.sdkRealtime)
          .catchError((Object error) {
        debugPrint('[IM_SEND_COORDINATOR] realtime result repair pending: ${error.runtimeType}');
        return 0;
      }));
    }
  }

  Future<void> applyAppMessageModified(
    V2TimMessage message, {
    String? conversationID,
    String? ingressEventID,
    int ingressSequence = 0,
  }) async {
    if (HistoryWindowRepositoryProvider.repository != null) {
      await recordHistoryWindowMutation(
          conversationID: conversationID ?? _messageConversationID(message),
          msgID: message.msgID ?? '',
          kind: HistoryWindowMutationKind.edit,
          message: message,
          eventID: ingressEventID,
          revision: ingressSequence);
    }
    await _applyMessageModifiedNow(message, conversationID);
  }

  Future<void> applyAppMessageRevoked(String msgID,
      [String? conversationID]) async {
    await onMessageRevoked(msgID, conversationID);
  }

  void applyAppC2CReadReceipts(List<V2TimMessageReceipt> receipts) {
    _onReceiveC2CReadReceipt(receipts);
  }

  void applyAppMessageReadReceipts(List<V2TimMessageReceipt> receipts) {
    _onReceiveMessageReadReceipts(receipts);
  }

  void applyAppSendMessageProgress(V2TimMessage message, int progress) {
    _onSendMessageProgress(message, progress);
  }

  Future<void> applyAppMessageDownloadProgress(
    V2TimMessageDownloadProgress progress, {
    bool Function()? isCurrent,
  }) {
    return onMessageDownloadProgressCallback(progress, isCurrent: isCurrent);
  }

  markMessageAsRead({
    required String convID,
    required ConvType convType,
  }) async {
    ChatJitterDiag.log(
      'active_read_report_start',
      conv: convID,
      extras: <String, Object?>{'convType': convType.name},
    );
    dynamic result;
    final identity = SessionIdentityService.instance.capture();
    if (convType == ConvType.c2c) {
      result = await TencentConversationReadService.markRead(
        messageService: _messageService,
        conversationID: convID,
        isGroup: false,
        capturedIdentity: identity,
      );
    } else if (kIsWeb) {
      ChatJitterDiag.log(
        'active_read_report_skip',
        conv: convID,
        extras: const <String, Object?>{'reason': 'web_group'},
      );
      return null;
    } else {
      result = await TencentConversationReadService.markRead(
        messageService: _messageService,
        conversationID: convID,
        isGroup: true,
        capturedIdentity: identity,
      );
    }
    ChatJitterDiag.log(
      'active_read_report_done',
      conv: convID,
      extras: <String, Object?>{
        'convType': convType.name,
        'sdkCode': result?.code,
        'sdkDesc': result?.desc,
      },
    );
    return result;
  }

  void _scheduleActiveReadReport({
    required String convID,
    required ConvType convType,
  }) {
    final lifecycleGeneration = _messageHistoryCoverageSessionGeneration;
    final normalizedConvID = _normalizeConversationID(convID);
    if (normalizedConvID.isEmpty) {
      return;
    }

    if (convType == ConvType.c2c) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastActiveReadReportAtMs[normalizedConvID] ?? 0;
      final elapsed = now - last;
      final delayMs = elapsed >= _activeReadReportMinIntervalMs
          ? _activeReadReportDebounceMs
          : _activeReadReportMinIntervalMs - elapsed;
      _activeReadReportDebounceMap[normalizedConvID]?.cancel();
      _activeReadReportDebounceMap[normalizedConvID] = Timer(
        Duration(milliseconds: delayMs),
        () async {
          _activeReadReportDebounceMap.remove(normalizedConvID);
          if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
              !_isSameConversationID(normalizedConvID, currentSelectedConv)) {
            ChatJitterDiag.log(
              'active_read_report_skip',
              conv: normalizedConvID,
              extras: const <String, Object?>{
                'reason': 'lifecycle_or_conversation_changed',
              },
            );
            return;
          }
          if (_isSameConversationID(normalizedConvID, currentSelectedConv)) {
            await markMessageAsRead(
              convID: normalizedConvID,
              convType: convType,
            );
            if (_isMessageLifecycleCurrent(lifecycleGeneration) &&
                _isSameConversationID(normalizedConvID, currentSelectedConv)) {
              _lastActiveReadReportAtMs[normalizedConvID] =
                  DateTime.now().millisecondsSinceEpoch;
            }
          }
        },
      );
      ChatJitterDiag.log(
        'active_read_report_scheduled',
        conv: normalizedConvID,
        extras: <String, Object?>{
          'convType': 'c2c',
          'delayMs': delayMs,
          'elapsedMs': elapsed,
        },
      );
      return;
    }

    if (kIsWeb) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastActiveReadReportAtMs[normalizedConvID] ?? 0;
    final elapsed = now - last;
    final delayMs = elapsed >= _activeReadReportMinIntervalMs
        ? _activeReadReportDebounceMs
        : _activeReadReportMinIntervalMs - elapsed;

    _activeReadReportDebounceMap[normalizedConvID]?.cancel();
    _activeReadReportDebounceMap[normalizedConvID] = Timer(
      Duration(milliseconds: delayMs),
      () async {
        _activeReadReportDebounceMap.remove(normalizedConvID);
        if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
            !_isSameConversationID(normalizedConvID, currentSelectedConv)) {
          ChatJitterDiag.log(
            'active_read_report_skip',
            conv: normalizedConvID,
            extras: const <String, Object?>{
              'reason': 'lifecycle_or_conversation_changed',
            },
          );
          return;
        }
        await markMessageAsRead(convID: normalizedConvID, convType: convType);
        if (_isMessageLifecycleCurrent(lifecycleGeneration) &&
            _isSameConversationID(normalizedConvID, currentSelectedConv)) {
          _lastActiveReadReportAtMs[normalizedConvID] =
              DateTime.now().millisecondsSinceEpoch;
        }
      },
    );
    ChatJitterDiag.log(
      'active_read_report_scheduled',
      conv: normalizedConvID,
      extras: <String, Object?>{
        'convType': 'group',
        'delayMs': delayMs,
        'elapsedMs': elapsed,
      },
    );
  }

  Future<GroupReceiptAllowType?> _loadGroupReceiptType(String groupID) async {
    final groupInfoList = await _groupServices.getGroupsInfo(
      groupIDList: [groupID],
    );
    if (groupInfoList == null || groupInfoList.isEmpty) {
      return null;
    }
    final groupInfo = groupInfoList.first.groupInfo;
    const groupTypeMap = {
      "Meeting": GroupReceiptAllowType.meeting,
      "Public": GroupReceiptAllowType.public,
      "Work": GroupReceiptAllowType.work,
      "Community": GroupReceiptAllowType.community,
    };
    return groupTypeMap[groupInfo?.groupType];
  }

  bool _isReadReceiptAllowedGroup(GroupReceiptAllowType? groupType) {
    return groupType == GroupReceiptAllowType.work ||
        groupType == GroupReceiptAllowType.public ||
        groupType == GroupReceiptAllowType.meeting;
  }

  static bool _looksLikeCommunityGroupId(String? input) {
    var id = input?.trim() ?? '';
    if (id.isEmpty) {
      return false;
    }
    if (id.length > 6 && id.toLowerCase().startsWith('group_')) {
      id = id.substring(6);
    }
    final upper = id.toUpperCase();
    return upper.startsWith('@TGS#_') || upper.startsWith('TGS#_');
  }

  Future<V2TimValueCallback<V2TimMessage>?>? sendMessageFromController({
    required V2TimMessage? messageInfo,
    required ConvType convType,
    required String convID,
    ValueChanged<String>? setInputField,
    OfflinePushInfo? offlinePushInfo,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? onlineUserOnly,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? cloudCustomData,
    String? localCustomData,
    bool recoverPreparedOutbox = false,
    String? operationIdOverride,
    String? clientCorrelationIdOverride,
    ValueChanged<ImCoordinatedSendResult>? onCoordinatedResult,
  }) {
    final TUIChatModelTools tools = serviceLocator<TUIChatModelTools>();
    if (messageInfo != null) {
      final messageInfoWithSender = messageInfo.sender == null
          ? tools.setUserInfoForMessage(messageInfo, messageInfo.id!)
          : messageInfo;
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      markMessageEnterAnimation(messageInfoWithSender);
      prepareForOutgoingMessage(convID);
      assignOutgoingLocalSeq(convID, messageInfoWithSender);
      commitMessageDelta(
        MessageDelta<V2TimMessage>(
          conversationKey: convID,
          eventID: 'optimistic:controller:${messageInfoWithSender.id ?? ''}',
          kind: MessageDeltaKind.optimisticInsert,
          source: MessageDeltaSource.sendPipeline,
          generation: messageDeltaGenerationFor(convID),
          clearEpoch: messageDeltaClearEpochFor(convID),
          upserts: [messageDeltaRecord(messageInfoWithSender)],
        ),
      );
      requestPinToBottom(convID, force: true);
      if (loadingMessage[convID] != null &&
          loadingMessage[convID]!.isNotEmpty) {
        loadingMessage[convID]!.add(messageInfoWithSender);
      } else {
        loadingMessage[convID] = <V2TimMessage>[messageInfoWithSender];
      }
      return _sendMessage(
        priority: priority,
        onlineUserOnly: onlineUserOnly,
        isExcludedFromUnreadCount: isExcludedFromUnreadCount,
        needReadReceipt: needReadReceipt,
        cloudCustomData: cloudCustomData,
        localCustomData: localCustomData,
        isExcludedFromContentModeration:
            messageInfo.isExcludedFromContentModeration ?? false,
        recoverPreparedOutbox: recoverPreparedOutbox,
        operationIdOverride: operationIdOverride,
        clientCorrelationIdOverride: clientCorrelationIdOverride,
        messageInfo: messageInfoWithSender,
        convID: convID,
        setInputField: setInputField,
        id: messageInfo.id as String,
        convType: ConvType.values[convType.index],
        offlinePushInfo: offlinePushInfo ??
            tools.buildMessagePushInfo(
              messageInfo,
              convID,
              ConvType.values[convType.index],
            ),
        onCoordinatedResult: onCoordinatedResult,
      );
    }
    return null;
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendReplyMessageFromController({
    required String text,
    required V2TimMessage messageBeenReplied,
    required String convID,
    required ConvType convType,
    ValueChanged<String>? setInputField,
    OfflinePushInfo? offlinePushInfo,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? onlineUserOnly,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? localCustomData,
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final TUIChatModelTools tools = serviceLocator<TUIChatModelTools>();
    V2TimMsgCreateInfoResult? textMessageInfo =
        await _messageService.createTextMessage(text: text);

    textMessageInfo = await _messageService.createTextAtMessage(
      text: text +
          "\n@${TencentUtils.checkString(messageBeenReplied.nickName) ?? TencentUtils.checkString(messageBeenReplied.sender) ?? TencentUtils.checkString(messageBeenReplied.userID)}",
      atUserList: [
        TencentUtils.checkString(messageBeenReplied.sender) ??
            TencentUtils.checkString(messageBeenReplied.userID) ??
            "",
      ],
    );

    final V2TimMessage? messageInfo = textMessageInfo!.messageInfo;

    if (messageInfo != null) {
      final messageInfoWithSender = messageInfo.sender == null
          ? tools.setUserInfoForMessage(
              messageInfo,
              messageInfo.id ?? textMessageInfo.id ?? "",
            )
          : messageInfo;
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      final hasNickName = messageBeenReplied.nickName != null &&
          messageBeenReplied.nickName != "";
      final cloudCustomData = {
        "messageReply": {
          "messageID": messageBeenReplied.msgID,
          "messageAbstract": tools.getMessageAbstract(
            messageBeenReplied,
            abstractMessageBuilder,
          ),
          "messageSender": hasNickName
              ? messageBeenReplied.nickName
              : messageBeenReplied.sender,
          "messageType": messageBeenReplied.elemType,
          "version": 1,
        },
      };
      messageInfoWithSender.cloudCustomData = json.encode(cloudCustomData);

      markMessageEnterAnimation(messageInfoWithSender);
      prepareForOutgoingMessage(convID);
      assignOutgoingLocalSeq(convID, messageInfoWithSender);
      commitMessageDelta(
        MessageDelta<V2TimMessage>(
          conversationKey: convID,
          eventID: 'optimistic:reply:${messageInfoWithSender.id ?? ''}',
          kind: MessageDeltaKind.optimisticInsert,
          source: MessageDeltaSource.sendPipeline,
          generation: messageDeltaGenerationFor(convID),
          clearEpoch: messageDeltaClearEpochFor(convID),
          upserts: [messageDeltaRecord(messageInfoWithSender)],
        ),
      );
      requestPinToBottom(convID, force: true);
      if (loadingMessage[convID] != null &&
          loadingMessage[convID]!.isNotEmpty) {
        loadingMessage[convID]!.add(messageInfoWithSender);
      } else {
        loadingMessage[convID] = <V2TimMessage>[messageInfoWithSender];
      }

      return _sendMessage(
        cloudCustomData: json.encode(cloudCustomData),
        id: textMessageInfo.id as String,
        offlinePushInfo: offlinePushInfo ??
            tools.buildMessagePushInfo(
              messageInfo,
              convID,
              ConvType.values[convType.index],
            ),
        priority: priority,
        onlineUserOnly: onlineUserOnly,
        isExcludedFromUnreadCount: isExcludedFromUnreadCount,
        needReadReceipt: needReadReceipt,
        localCustomData: localCustomData,
        messageInfo: messageInfoWithSender,
        convID: convID,
        setInputField: setInputField,
        convType: ConvType.values[convType.index],
      );
    }
    return null;
  }

  Future<bool> setLocalCustomData(
    String msgID,
    String localCustomData,
    String conversationID,
  ) async {
    final res = await _messageService.setLocalCustomData(
      msgID: msgID,
      localCustomData: localCustomData,
    );
    if (res.code != 0) return false;
    _commitLocalMessageMetadata(
      conversationID: conversationID,
      messageID: msgID,
      localCustomData: localCustomData,
      eventID: 'local_custom_data:$conversationID:$msgID',
    );
    return true;
  }

  Future<bool> setLocalCustomInt(
    String msgID,
    int localCustomInt,
    String conversationID,
  ) async {
    final targetId = msgID.trim();
    if (targetId.isEmpty || conversationID.trim().isEmpty) {
      return false;
    }

    final storageKey = _resolveMessageListStorageKey(conversationID);
    final current = storageKey.isEmpty
        ? const <V2TimMessage>[]
        : _mergedAliasMessageList(storageKey);
    final touched = current.any(
      (item) => item.msgID?.trim() == targetId || item.id?.trim() == targetId,
    );
    if (touched) {
      _commitLocalMessageMetadata(
        conversationID: storageKey,
        messageID: targetId,
        localCustomInt: localCustomInt,
        eventID: 'local_custom_int:$storageKey:$targetId',
      );
    }

    final res = await _messageService.setLocalCustomInt(
      msgID: targetId,
      localCustomInt: localCustomInt,
    );
    if (res.code != 0) return touched;

    if (!touched && storageKey.isNotEmpty) {
      _commitLocalMessageMetadata(
        conversationID: storageKey,
        messageID: targetId,
        localCustomInt: localCustomInt,
        eventID: 'local_custom_int_sdk:$storageKey:$targetId',
      );
    }
    return true;
  }

  bool _commitLocalMessageMetadata({
    required String conversationID,
    required String messageID,
    String? localCustomData,
    int? localCustomInt,
    required String eventID,
  }) {
    final storageKey = _resolveMessageListStorageKey(conversationID);
    final targetID = messageID.trim();
    if (storageKey.isEmpty || targetID.isEmpty) return false;
    final current = _mergedAliasMessageList(storageKey);
    for (final item in current) {
      if (item.msgID?.trim() != targetID && item.id?.trim() != targetID) {
        continue;
      }
      final next = _cloneMessage(item);
      if (localCustomData != null) next.localCustomData = localCustomData;
      if (localCustomInt != null) next.localCustomInt = localCustomInt;
      if (next.localCustomData == item.localCustomData &&
          next.localCustomInt == item.localCustomInt) {
        return true;
      }
      final commit = commitMessageDelta(
        MessageDelta<V2TimMessage>(
          conversationKey: storageKey,
          eventID: eventID,
          kind: MessageDeltaKind.localMetadata,
          source: MessageDeltaSource.userAction,
          generation: messageDeltaGenerationFor(storageKey),
          clearEpoch: messageDeltaClearEpochFor(storageKey),
          upserts: <MessageReconciliationRecord<V2TimMessage>>[
            _reconciliationRecord(next),
          ],
        ),
      );
      if (commit == null) return false;
      _chatUiStateStore.markMessagesChanged(storageKey, <String>{
        ChatUiStateStore.messageKeyOf(item),
        ChatUiStateStore.messageKeyOf(next),
        targetID,
      });
      _markMessageRowChanged(storageKey, next, extraKey: targetID);
      if (_isSameConversationID(storageKey, currentSelectedConv)) {
        _markNeedsNotify();
      }
      return true;
    }
    return false;
  }

  Future<V2TimValueCallback<V2TimMessage>> _sendMessage({
    required String id,
    required String convID,
    required ConvType convType,
    OfflinePushInfo? offlinePushInfo,
    bool? onlineUserOnly = false,
    bool? isEditStatusMessage = false,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? cloudCustomData,
    String? localCustomData,
    V2TimMessage? messageInfo,
    bool isExcludedFromContentModeration = false,
    bool recoverPreparedOutbox = false,
    String? operationIdOverride,
    String? clientCorrelationIdOverride,
    ValueChanged<ImCoordinatedSendResult>? onCoordinatedResult,
  }) async {
    String receiver = convType == ConvType.c2c ? convID : '';
    String groupID = convType == ConvType.group ? convID : '';
    // 历史桶 key 常带 `c2c_` / `group_` 前缀；IM sendMessage 必须用裸 userID / groupID。
    if (receiver.toLowerCase().startsWith('c2c_') && receiver.length > 4) {
      receiver = receiver.substring(4);
    }
    if (groupID.toLowerCase().startsWith('group_') && groupID.length > 6) {
      groupID = groupID.substring(6);
    }
    final receiptGroupType = groupType ??
        (convType == ConvType.group
            ? await _loadGroupReceiptType(groupID)
            : null);
    final useReadReceipt =
        (needReadReceipt ?? chatConfig.isShowReadingStatus) &&
            (convType != ConvType.group ||
                _isReadReceiptAllowedGroup(receiptGroupType)) &&
            !_looksLikeCommunityGroupId(groupID);
    final coordinatedSend = await ImOutgoingSendCoordinator.instance.send(
      messageService: _messageService,
      sdkLocalId: id,
      conversationId: convID,
      conversationType: convType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
      receiver: receiver,
      groupID: groupID,
      fallbackMessage: messageInfo,
      needReadReceipt: useReadReceipt,
      priority: priority,
      localCustomData: localCustomData,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount ?? false,
      offlinePushInfo: offlinePushInfo,
      isExcludedFromContentModeration: isExcludedFromContentModeration,
      onlineUserOnly: onlineUserOnly ?? false,
      businessCloudCustomData: cloudCustomData ??
          json.encode({
            "messageFeature": {"needTyping": 1, "version": 1},
          }),
      persistOutbox: isEditStatusMessage != true,
      recoverPreparedOutbox: recoverPreparedOutbox,
      operationIdOverride: operationIdOverride,
      clientCorrelationIdOverride: clientCorrelationIdOverride,
      onSyncMsgID: (syncMsgID) {
        bindOutgoingSyncMsgId(convID, id, syncMsgID);
      },
    );
    onCoordinatedResult?.call(coordinatedSend);
    var sendMsgRes = coordinatedSend.sdkResult;
    // IM-08: when the SDK Future resolves OutcomeUnknown, the dispatch path
    // cannot prove the provider accepted or rejected the operation. The
    // Outbox main + recovery copy already record OutcomeUnknown; the
    // single Writer must keep the optimistic bubble in SENDING and wait
    // for history/realtime to claim it. Auto-committing a success/failed
    // projection here would resurrect an in-flight message or flash a
    // red retry icon on a still-pending send.
    var projectionCommitted = true;
    if (isEditStatusMessage == false) {
      projectionCommitted = applyOutgoingSendResult(
        sendMsgRes,
        convID,
        id,
        convType,
        receiptGroupType,
        setInputField,
        coordinatedResult: coordinatedSend,
      );
    } else if (coordinatedSend.outcomeUnknown) {
      projectionCommitted = false;
    }
    if (mayPublishOutgoingSendCompletion(convID, id, coordinatedSend)) {
      insertPeerRejectedLocalTip(
        convID,
        sendMsgRes.code,
        clientId: id,
      );
    }
    if (projectionCommitted && coordinatedSend.canCompleteProjection) {
      await ImOutgoingSendCoordinator.instance.completeSuccessfulProjection(
        coordinatedSend,
      );
    }
    sendMsgRes = coordinatedSend.sdkResult;
    if (_lifeCycle?.messageDidSend != null &&
        mayPublishOutgoingSendCompletion(convID, id, coordinatedSend)) {
      _lifeCycle!.messageDidSend(sendMsgRes);
    }

    return sendMsgRes;
  }

  String? _messageEnterAnimationKey(V2TimMessage message) {
    final id = message.id;
    if (id != null && id.toString().isNotEmpty) {
      return id.toString();
    }
    final msgID = message.msgID;
    if (msgID != null && msgID.isNotEmpty) {
      return msgID;
    }
    return null;
  }

  void markMessageEnterAnimation(V2TimMessage message) {
    final skip = chatConfig.skipMessageEnterAnimationForMessage;
    if (skip != null && skip(message)) {
      return;
    }
    final convId = _messageConversationID(message);
    if (convId != null && isBulkMessageSyncActive(convId)) {
      return;
    }
    final key = _messageEnterAnimationKey(message);
    if (key == null) {
      return;
    }
    final throttleMs = chatConfig.messageEnterAnimationThrottleMs;
    if (convId != null && throttleMs > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastMark = _enterAnimationThrottleMarkMsByConv[convId] ?? 0;
      if (now - lastMark < throttleMs) {
        final superseded = _enterAnimationThrottlePendingKeyByConv[convId];
        if (superseded != null) {
          _messageEnterAnimationKeys.remove(superseded);
        }
      }
      _enterAnimationThrottleMarkMsByConv[convId] = now;
      _enterAnimationThrottlePendingKeyByConv[convId] = key;
    }
    _messageEnterAnimationKeys.add(key);
    _maybeScheduleSendFlyOverlay(message, key);
  }

  ChatSendFlyOverlayRequest? get sendFlyOverlayRequest =>
      _sendFlyOverlayRequest;

  bool isSendFlyOverlayPendingForMessage(V2TimMessage message) {
    final req = _sendFlyOverlayRequest;
    if (req == null) {
      return false;
    }
    final key = _messageEnterAnimationKey(message);
    return key != null && key == req.messageKey;
  }

  bool shouldHideBubbleForSendFly(V2TimMessage message) {
    if (!chatConfig.sendFlyOverlayEnabled) {
      return false;
    }
    return isSendFlyOverlayPendingForMessage(message);
  }

  void reportSendFlyTargetRect(V2TimMessage message, Rect rect) {
    final req = _sendFlyOverlayRequest;
    if (req == null) {
      return;
    }
    final key = _messageEnterAnimationKey(message);
    if (key == null || key != req.messageKey) {
      return;
    }
    final existing = req.targetRect;
    if (existing != null &&
        (existing.top - rect.top).abs() < 0.5 &&
        (existing.height - rect.height).abs() < 0.5) {
      return;
    }
    _sendFlyOverlayRequest = req.copyWith(targetRect: rect);
    notifyListeners();
  }

  void completeSendFlyOverlay() {
    if (_sendFlyOverlayRequest == null) {
      return;
    }
    _sendFlyOverlayRequest = null;
    notifyListeners();
  }

  void _maybeScheduleSendFlyOverlay(V2TimMessage message, String key) {
    if (!chatConfig.sendFlyOverlayEnabled) {
      return;
    }
    if (message.isSelf != true) {
      return;
    }
    if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_TEXT) {
      return;
    }
    final text = message.textElem?.text?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    final convId = _messageConversationID(message);
    if (convId == null || convId.isEmpty) {
      return;
    }
    _sendFlyOverlayRequest = ChatSendFlyOverlayRequest(
      messageKey: key,
      text: text,
      conversationId: convId,
    );
    notifyListeners();
  }

  void _markIncomingMessageEnterAnimation(V2TimMessage message) {
    if (message.isSelf == true) {
      return;
    }
    if (!shouldAnimateInboundPresentation) {
      return;
    }
    // WeChat list-push mode animates the viewport itself: a complete row starts
    // below the list's clipping edge and the scroll offset moves back to the
    // bottom. A per-bubble translate would double the movement and make the
    // row appear to expand or rebound.
    if (chatConfig.messageEnterAnimationStyle ==
            MessageEnterAnimationStyle.wechat &&
        chatConfig.messageEnterAnimationListPushEnabled) {
      return;
    }
    final convId = _messageConversationID(message);
    if (convId != null && isBulkMessageSyncActive(convId)) {
      return;
    }
    if (convId != null && !_isActiveChatNearBottom(convId)) {
      return;
    }
    markMessageEnterAnimation(message);
  }

  /// 消息是否仍在播放入场动画（仿微信 notifyItemInserted 后 ItemAnimator 未结束）。
  bool isMessageEnterAnimationPending(V2TimMessage message) {
    final key = _messageEnterAnimationKey(message);
    if (key == null) {
      return false;
    }
    return _messageEnterAnimationKeys.contains(key);
  }

  void finishMessageEnterAnimation(V2TimMessage message) {
    final key = _messageEnterAnimationKey(message);
    if (key != null) {
      _messageEnterAnimationKeys.remove(key);
    }
  }

  @Deprecated('Use isMessageEnterAnimationPending')
  bool shouldPlayMessageEnterAnimation(V2TimMessage message) {
    return isMessageEnterAnimationPending(message);
  }

  @Deprecated('Use markMessageEnterAnimation')
  void markOutgoingMessageEnterAnimation(V2TimMessage message) {
    markMessageEnterAnimation(message);
  }

  @Deprecated('Use isMessageEnterAnimationPending')
  bool shouldPlayOutgoingEnterAnimation(V2TimMessage message) {
    return isMessageEnterAnimationPending(message);
  }

  /// 覆盖 msgID/seq/状态的内容签名。打开会话后本地校验、头像回填等
  /// 路径会把同样的列表原样写回；签名一致时跳过 revision bump，
  /// 避免 Selector 因 revision 变化整表重建（进入页面时头像/列表抖动）。
  ///
  /// 故意不含 faceUrl：头像回填只改展示字段，不应触发消息列表 revision。
  static bool _listHasCorrelatingDup(List<V2TimMessage> messages) {
    if (messages.length < 2) {
      return false;
    }
    final scanCount = messages.length < 32 ? messages.length : 32;
    for (var i = 0; i < scanCount; i++) {
      for (var j = i + 1; j < scanCount; j++) {
        if (messagesCorrelateForDedup(messages[i], messages[j])) {
          return true;
        }
      }
    }
    return false;
  }

  static int _canonicalRealtimeAppendCount(
    List<V2TimMessage> previous,
    List<V2TimMessage> incoming,
  ) {
    final added = incoming.length - previous.length;
    if (previous.isEmpty || added <= 0) return 0;
    for (var i = 0; i < previous.length; i++) {
      if (!identical(previous[i], incoming[added + i])) return 0;
    }
    final identities = previous.map(messageDedupKey).toSet();
    for (var i = 0; i < added; i++) {
      final message = incoming[i];
      if (message.isSelf == true ||
          (message.msgID?.trim().isEmpty ?? true) ||
          !identities.add(messageDedupKey(message)) ||
          compareMessagesChronological(message, previous.first) <= 0) {
        return 0;
      }
    }
    return added;
  }

  static bool isCanonicalPlainTextProjection(List<V2TimMessage> messages) =>
      _isCanonicalMessageProjection(messages, plainTextOnly: true);

  /// Content type does not change the protocol's distinct-SDK-ID / distinct
  /// group-Seq guards. Apply this after app-owned call/tip normalization.
  static bool _isCanonicalMessageProjection(
    List<V2TimMessage> messages, {
    bool plainTextOnly = false,
  }) {
    final ids = <String>{};
    final groupSequences = <int>{};
    final groupID =
        messages.isEmpty ? '' : _normalizedGroupIdForMessage(messages.first);
    V2TimMessage? previous;
    for (final message in messages) {
      final id = message.msgID?.trim() ?? '';
      if ((plainTextOnly &&
              (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_TEXT ||
                  message.customElem != null ||
                  (message.localCustomData?.isNotEmpty ?? false))) ||
          id.isEmpty ||
          !ids.add(id) ||
          (previous != null &&
              compareMessagesChronological(previous, message) > 0)) {
        return false;
      }
      if (groupID.isNotEmpty) {
        final seq = int.tryParse(message.seq?.trim() ?? '') ?? 0;
        if (_normalizedGroupIdForMessage(message) != groupID ||
            seq <= 0 ||
            !groupSequences.add(seq)) {
          return false;
        }
      } else if (!_isC2cLikeMessage(message) || !_isLikelyTencentSdkMsgId(id)) {
        return false;
      }
      previous = message;
    }
    return messages.isNotEmpty;
  }

  static List<V2TimMessage> canonicalizeMessageProjection(
    List<V2TimMessage> messages,
  ) {
    if (_isCanonicalMessageProjection(messages)) {
      ChatMainThreadPerf.increment('message_mixed_projection_reused');
      return messages;
    }
    ChatMainThreadPerf.increment('message_projection_canonicalized');
    return sortMessagesChronologicallyAsc(dedupeMessages(messages));
  }

  static void _writeSignatureField(StringBuffer buffer, Object? value) {
    if (value == null) {
      buffer.write('-;');
      return;
    }
    final text = value.toString();
    buffer
      ..write(text.length)
      ..write(':')
      ..write(text)
      ..write(';');
  }

  static String _messageListContentSignature(List<V2TimMessage> messageList) {
    final buffer = StringBuffer()
      ..write(messageList.length)
      ..write(';');
    for (final message in messageList) {
      // Read mutable SDK fields afresh without allocating serialization Maps
      // or the former per-message JSON/media arrays. Length framing prevents
      // delimiter and null/string collisions, including custom-card payloads.
      _writeSignatureField(buffer, message.msgID ?? message.id ?? '');
      _writeSignatureField(buffer, message.seq);
      _writeSignatureField(buffer, message.status);
      _writeSignatureField(buffer, message.progress);
      _writeSignatureField(buffer, message.localCustomInt);
      _writeSignatureField(buffer, message.elemType);
      _writeSignatureField(buffer, message.id);
      _writeSignatureField(buffer, message.timestamp);
      _writeSignatureField(buffer, message.sender);
      _writeSignatureField(buffer, message.userID);
      _writeSignatureField(buffer, message.groupID);
      _writeSignatureField(buffer, message.isSelf);
      _writeSignatureField(buffer, message.random);
      _writeSignatureField(buffer, message.isRead);
      _writeSignatureField(buffer, message.isPeerRead);
      _writeSignatureField(buffer, message.revokeReason);
      _writeSignatureField(buffer, message.localCustomData);
      _writeSignatureField(buffer, message.cloudCustomData);
      _writeSignatureField(buffer, message.textElem != null);
      _writeSignatureField(buffer, message.textElem?.text);
      final image = message.imageElem;
      _writeSignatureField(buffer, image != null);
      if (image != null) {
        _writeSignatureField(buffer, image.path);
        _writeSignatureField(buffer, image.imageList?.length);
        for (final item in image.imageList ?? const <V2TimImage?>[]) {
          _writeSignatureField(buffer, item != null);
          _writeSignatureField(buffer, item?.type);
          _writeSignatureField(buffer, item?.uuid);
          _writeSignatureField(buffer, item?.size);
          _writeSignatureField(buffer, item?.width);
          _writeSignatureField(buffer, item?.height);
          _writeSignatureField(buffer, item?.url);
          _writeSignatureField(buffer, item?.localUrl);
        }
      }
      final custom = message.customElem;
      _writeSignatureField(buffer, custom != null);
      if (custom != null) {
        _writeSignatureField(buffer, custom.data);
        _writeSignatureField(buffer, custom.desc);
        _writeSignatureField(buffer, custom.extension);
      }
      final video = message.videoElem;
      _writeSignatureField(buffer, video != null);
      if (video != null) {
        _writeSignatureField(buffer, video.videoPath);
        _writeSignatureField(buffer, video.UUID);
        _writeSignatureField(buffer, video.videoSize);
        _writeSignatureField(buffer, video.duration);
        if (!kIsWeb) _writeSignatureField(buffer, video.videoType);
        _writeSignatureField(buffer, video.snapshotPath);
        _writeSignatureField(buffer, video.snapshotUUID);
        _writeSignatureField(buffer, video.snapshotSize);
        _writeSignatureField(buffer, video.snapshotWidth);
        _writeSignatureField(buffer, video.snapshotHeight);
        _writeSignatureField(buffer, video.videoUrl);
        _writeSignatureField(buffer, video.snapshotUrl);
        _writeSignatureField(buffer, video.localVideoUrl);
        _writeSignatureField(buffer, video.localSnapshotUrl);
      }
      final sound = message.soundElem;
      _writeSignatureField(buffer, sound != null);
      if (sound != null) {
        _writeSignatureField(buffer, sound.path);
        _writeSignatureField(buffer, sound.UUID);
        _writeSignatureField(buffer, sound.dataSize);
        _writeSignatureField(buffer, sound.duration);
        _writeSignatureField(buffer, sound.url);
        _writeSignatureField(buffer, sound.localUrl);
      }
      final file = message.fileElem;
      _writeSignatureField(buffer, file != null);
      if (file != null) {
        _writeSignatureField(buffer, file.path);
        _writeSignatureField(buffer, file.UUID);
        _writeSignatureField(buffer, file.fileName);
        _writeSignatureField(buffer, file.fileSize);
        _writeSignatureField(buffer, file.url);
        _writeSignatureField(buffer, file.localUrl);
      }
      final face = message.faceElem;
      _writeSignatureField(buffer, face != null);
      if (face != null) {
        _writeSignatureField(buffer, face.index);
        _writeSignatureField(buffer, face.data);
      }
      final location = message.locationElem;
      _writeSignatureField(buffer, location != null);
      if (location != null) {
        _writeSignatureField(buffer, location.desc);
        _writeSignatureField(buffer, location.longitude);
        _writeSignatureField(buffer, location.latitude);
      }
      // These SDK elements contain private wire fields/nested messages.
      // Preserve their full compatibility signature until the SDK exposes a
      // mutation-aware representation; common media never enters this path.
      final groupTips = message.groupTipsElem;
      _writeSignatureField(buffer, groupTips != null);
      if (groupTips != null) {
        _writeSignatureField(buffer, groupTips.type);
        ChatMainThreadPerf.increment('message_signature_nested_json');
        _writeSignatureField(buffer, jsonEncode(groupTips.toJson()));
      }
      final merger = message.mergerElem;
      _writeSignatureField(buffer, merger != null);
      if (merger != null) {
        ChatMainThreadPerf.increment('message_signature_nested_json');
        _writeSignatureField(buffer, jsonEncode(merger.toJson()));
      }
      if (kIsWeb) {
        // The web adapter exposes additional chained element Maps. Do not
        // drop them while replacing each element's toJson with direct reads.
        for (final element in <dynamic>[
          message.textElem,
          image,
          custom,
          video,
          sound,
          file,
          face,
          location,
        ]) {
          final next = element?.nextElem;
          _writeSignatureField(buffer, next == null ? null : jsonEncode(next));
        }
      }
    }
    return buffer.toString();
  }

  @visibleForTesting
  static String messageListCommitSignatureForTesting(
    List<V2TimMessage> messages,
  ) =>
      _messageListContentSignature(messages);

  /// A fresh content snapshot, also used by the mounted projection cache.
  /// SDK message and nested element objects may change without replacement.
  static String messageListProjectionSignature(List<V2TimMessage> messages) =>
      _messageListContentSignature(messages);

  final Map<String, String> _messageListContentSignatureByConv = {};
  final Map<String, String> _historyWindowCommitSignatureByConv = {};

  /// 读历史（一屏外 / 非最新）期间冻结内存窗口裁剪，避免 prepend 后列表长度震荡。
  bool _shouldFreezeMemoryWindowTrimWhileReadingHistory(String conversationID) {
    final isActive = currentSelectedConv.trim().isNotEmpty &&
        _isSameConversationID(conversationID, currentSelectedConv);
    if (!isActive) {
      return false;
    }
    final position = getMessageListPosition(conversationID);
    return position == HistoryMessagePosition.awayTwoScreen ||
        position == HistoryMessagePosition.notShowLatest;
  }

  bool _hasConnectedHistoryReadingTail(String conversationID) {
    if (isFollowingLatest(conversationID) ||
        _isHistoryGapDeferral(conversationID)) {
      return false;
    }
    return _freezeHistoryReadingWindowByConversation[
                _inboundStateKey(conversationID)]
            ?.canAppend
            ?.call() ==
        true;
  }

  /// 内存窗口闸门：只裁 `_messageListMap`，绝不删 DB/SDK 存储。
  List<V2TimMessage> _applyMessageMemoryWindow(
    String conversationID,
    List<V2TimMessage> sorted, {
    String? anchorMsgID,
    String? anchorSeq,
    bool forcePreferLatest = false,
    bool forceWhileReadingHistory = false,
  }) {
    if (!ChatMessageWindowPolicy.enabled) {
      return sorted;
    }
    final overHistoryBudget =
        sorted.length > ChatMessageWindowPolicy.historyReadSoftMax;
    if (isMemoryWindowSuppressed(conversationID) &&
        !forceWhileReadingHistory &&
        !overHistoryBudget) {
      ChatJitterDiag.log(
        'memory_window',
        conv: conversationID,
        extras: <String, Object?>{
          'action': 'skip_suppressed',
          'len': sorted.length,
          'position': getMessageListPosition(conversationID).name,
        },
      );
      return sorted;
    }
    if (!forceWhileReadingHistory &&
        !overHistoryBudget &&
        (_shouldFreezeMemoryWindowTrimWhileReadingHistory(conversationID) ||
            _hasConnectedHistoryReadingTail(conversationID))) {
      ChatJitterDiag.log(
        'memory_window',
        conv: conversationID,
        extras: <String, Object?>{
          'action': 'skip_frozen_reading_history',
          'len': sorted.length,
          'position': getMessageListPosition(conversationID).name,
        },
      );
      return sorted;
    }
    if (sorted.length <= ChatMessageWindowPolicy.softMax) {
      return sorted;
    }

    final isActive = currentSelectedConv.trim().isNotEmpty &&
        _isSameConversationID(conversationID, currentSelectedConv);
    final position = getMessageListPosition(conversationID);
    final preferLatest = forcePreferLatest ||
        !isActive ||
        position == HistoryMessagePosition.bottom ||
        position == HistoryMessagePosition.inTwoScreen;

    String? resolvedMsgID = anchorMsgID?.trim();
    String? resolvedSeq = anchorSeq?.trim();
    if ((resolvedMsgID == null || resolvedMsgID.isEmpty) &&
        (resolvedSeq == null || resolvedSeq.isEmpty) &&
        _memoryWindowAnchorConvID != null &&
        _isSameConversationID(_memoryWindowAnchorConvID!, conversationID)) {
      resolvedMsgID = _memoryWindowAnchorMsgID;
      resolvedSeq = _memoryWindowAnchorSeq;
    }

    final result = ChatMessageWindow.trimToWindow(
      list: sorted,
      preferLatest: preferLatest,
      anchorMsgID: resolvedMsgID,
      anchorSeq: resolvedSeq,
    );
    if (!result.didTrim) {
      return sorted;
    }
    if (result.trimmedAwayLatest) {
      markMemoryWindowMissingNewer(conversationID);
    }
    if (result.trimmedAwayOldestInMemory) {
      markMemoryWindowMissingOlder(conversationID);
    }
    final retainedBoundary = result.list.isEmpty
        ? 0
        : (preferLatest
            ? (result.list.last.timestamp ?? 0)
            : (result.list.first.timestamp ?? 0));
    if (retainedBoundary > 0) {
      _memoryWindowBoundaryTimestampByConv[conversationID.trim()] =
          retainedBoundary;
    }
    final retainedSeq = result.list.isEmpty
        ? ''
        : (preferLatest
            ? (result.list.last.seq ?? '')
            : (result.list.first.seq ?? ''));
    if (retainedSeq.trim().isNotEmpty) {
      _memoryWindowBoundarySeqByConv[conversationID.trim()] =
          retainedSeq.trim();
    }
    // 注意：preferLatest 只表示「保留当前内存里的最新端」，不等于全局最新。
    // missingNewer 只能在真正 loadLatest 到底 / reloadNewest 成功后清除。
    ChatHistoryTrace.log(
      'memory_window_trim',
      conversationID: conversationID,
      extras: <String, Object?>{
        'before': sorted.length,
        'after': result.list.length,
        'removedNewer': result.removedNewerCount,
        'removedOlder': result.removedOlderCount,
        'trimmedAwayLatest': result.trimmedAwayLatest,
        'trimmedAwayOldest': result.trimmedAwayOldestInMemory,
        'preferLatest': preferLatest,
        'forcePreferLatest': forcePreferLatest,
        'position': position.name,
        'isActive': isActive,
        'anchorMsgID': resolvedMsgID,
        'anchorSeq': resolvedSeq,
      },
    );
    ChatJitterDiag.log(
      'memory_window',
      conv: conversationID,
      extras: <String, Object?>{
        'action': 'trim',
        'before': sorted.length,
        'after': result.list.length,
        'removedNewer': result.removedNewerCount,
        'removedOlder': result.removedOlderCount,
        'preferLatest': preferLatest,
        'position': position.name,
        'anchorMsgID': resolvedMsgID,
      },
    );
    return result.list;
  }

  String _commitSnapshotIdentity(V2TimMessage message) {
    final key = messageDedupKey(message).trim();
    if (key.isNotEmpty) return key;
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isNotEmpty) return 'msg:$msgID';
    final id = message.id?.trim() ?? '';
    if (id.isNotEmpty) return 'id:$id';
    return 'wire:${message.timestamp ?? 0}:${message.random ?? 0}';
  }

  bool _messageCommitStructureChanged(
    List<V2TimMessage> previous,
    List<V2TimMessage> next,
  ) {
    if (previous.length != next.length) return true;
    for (var index = 0; index < previous.length; index++) {
      if (_commitSnapshotIdentity(previous[index]) !=
          _commitSnapshotIdentity(next[index])) {
        return true;
      }
    }
    return false;
  }

  bool _memoryWindowMissingOlder(String conversationID) =>
      _memoryWindowMissingOlderByConv.entries.any(
        (entry) =>
            entry.value && _isSameConversationID(entry.key, conversationID),
      );

  /// Public accessor: true when the memory window was trimmed on the older
  /// side and the user can scroll up to load more (haveMoreData must be true).
  bool memoryWindowMissingOlder(String conversationID) =>
      _memoryWindowMissingOlder(conversationID);

  /// C2C lastMessage verification: when onConversationChanged arrives with
  /// a lastMessage that is not in the active C2C chat's visible list,
  /// the onRecvNewMessage push was lost. Trigger a CLOUD_NEWER catch-up.
  void verifyC2CLastMessage(List<V2TimConversation> conversations) {
    final activeConv = currentSelectedConv;
    if (activeConv.isEmpty) return;
    for (final conv in conversations) {
      final convIdRaw = (conv.conversationID ?? '').trim();
      if (!convIdRaw.toLowerCase().startsWith('c2c')) continue;
      final convID = _resolveMessageListStorageKey(conv.conversationID ?? '');
      if (!_isSameConversationID(convID, activeConv)) continue;
      final lastMsg = conv.lastMessage;
      if (lastMsg == null) continue;
      final lastMsgID = (lastMsg.msgID ?? lastMsg.id ?? '').trim();
      if (lastMsgID.isEmpty) continue;
      final list = _messageListMap[convID] ??
          _messageListMap[_resolveMessageListStorageKey(convID)];
      if (list == null || list.isEmpty) continue;
      bool found = false;
      for (final msg in list) {
        final msgID = (msg.msgID ?? msg.id ?? '').trim();
        if (msgID.isNotEmpty && msgID == lastMsgID) {
          found = true;
          break;
        }
      }
      if (!found && !_gapCatchUpInFlight.contains(convID)) {
        _gapCatchUpInFlight.add(convID);
        unawaited(_c2cLastMessageCatchUp(convID, activeConv));
      }
    }
  }

  Future<void> _c2cLastMessageCatchUp(String convID, String rawConvID) async {
    await reconcileConversationCloud(
      rawConvID.isEmpty ? convID : rawConvID,
      reason: 'c2c_preview_ahead',
    );
    _gapCatchUpInFlight.remove(convID);
  }

  /// Clears the missing-older flag so haveMoreData reflects only the SDK
  /// pagination state.
  void clearMemoryWindowMissingOlder(String conversationID) {
    final keys = _memoryWindowMissingOlderByConv.keys
        .where((k) => _isSameConversationID(k, conversationID))
        .toList(growable: false);
    for (final key in keys) {
      _memoryWindowMissingOlderByConv.remove(key);
    }
  }

  MessageCommitResult _messageCommitSnapshot({
    required String conversationID,
    required String storageKey,
    required List<V2TimMessage> list,
    required bool structureChanged,
    required bool contentChanged,
    required bool recordCommit,
    MessageReconciliationWriterCommit<V2TimMessage>? writerCommit,
  }) {
    if (recordCommit) {
      if (identical(_messageListMap[storageKey], list) &&
          list is! _TrackedMessageList) {
        final writerValues = _messageReconciliationWriter.valuesFor(storageKey);
        final sharesWriterWindow = identical(writerValues, list) ||
            (writerValues.length == list.length &&
                Iterable<int>.generate(list.length)
                    .every((index) => identical(writerValues[index], list[index])));
        _messageListMap[storageKey] =
            sharesWriterWindow ? writerValues : _TrackedMessageList(list);
      }
      if (writerCommit != null &&
          writerCommit.revision ==
              _messageReconciliationWriter.revisionFor(storageKey)) {
        _writerProjectionAuthorities[storageKey] =
            _messageReconciliationWriter.authorityFor(storageKey);
      } else {
        _writerProjectionAuthorities.remove(storageKey);
      }
      _messageCommitGenerationByConv[storageKey] =
          (_messageCommitGenerationByConv[storageKey] ?? 0) + 1;
      _messageCommitTokenByConv[storageKey] = ++_nextMessageCommitToken;
    }
    final projectionKey = _inboundStateKey(conversationID);
    final unreadState = _inboundUnreadStateFor(projectionKey, create: false);
    return MessageCommitResult(
      conversationID: storageKey,
      token: _messageCommitTokenByConv[storageKey] ?? 0,
      generation: _messageCommitGenerationByConv[storageKey] ?? 0,
      listRevision: messageListRevisionFor(storageKey),
      projectionRevision: messageProjectionRevisionFor(conversationID),
      rawCount: list.length,
      firstIdentity: list.isEmpty ? null : _commitSnapshotIdentity(list.first),
      lastIdentity: list.isEmpty ? null : _commitSnapshotIdentity(list.last),
      memoryWindowMissingNewer: memoryWindowMissingNewer(conversationID),
      memoryWindowMissingOlder: _memoryWindowMissingOlder(conversationID),
      memoryWindowSuppressed: isMemoryWindowSuppressed(conversationID),
      unreadBufferedCount: unreadState.bufferedMessageKeys.length,
      unreadProjectionHeld: _deferredUntilUserBottomConversations.contains(
        projectionKey,
      ),
      structureChanged: structureChanged,
      contentChanged: contentChanged,
      writerRevision: writerCommit?.revision,
      writerGeneration: writerCommit?.generation,
      writerClearEpoch: writerCommit?.clearEpoch,
      writerOwnerUserID: writerCommit?.ownerUserID,
      writerAccountGeneration: writerCommit?.accountGeneration,
      writerDomainGeneration: writerCommit?.domainGeneration,
    );
  }

  bool isMessageCommitCurrent(MessageCommitResult result) {
    final key = canonicalHistoryStorageKey(result.conversationID);
    final storageKey = key.isNotEmpty ? key : result.conversationID.trim();
    return (_messageCommitTokenByConv[storageKey] ?? 0) == result.token &&
        (_messageCommitGenerationByConv[storageKey] ?? 0) == result.generation;
  }

  MessageMutationType _messageMutationTypeForCommit({
    required bool replace,
    required bool isDeleteMsg,
    required bool structureChanged,
  }) {
    if (replace) return MessageMutationType.historyWindow;
    if (isDeleteMsg) return MessageMutationType.removeOrRevoke;
    if (structureChanged) return MessageMutationType.reorder;
    return MessageMutationType.contentOrMedia;
  }

  MessageCommitResult setMessageList(
    String conversationID,
    List<V2TimMessage> messageList, {
    bool needResetNewMessageCount = true,
    bool isDeleteMsg = false,

    /// true：整表替换，不与旧内存拼接（会话预览首屏 / 已合并全量列表写入用）。
    bool replace = false,

    /// false：跳过内存窗口裁剪（搜索定位拉史等）。
    bool applyMemoryWindow = true,

    /// False for an explicitly retained, durably recoverable working window.
    bool preserveInFlightOutgoing = true,

    /// true：强制保留最新端窗口（loadLatest / 回底补窗）。
    bool memoryWindowPreferLatest = false,

    /// true：显式分页收尾时允许按锚点收束读历史窗口。
    bool forceMemoryWindowTrimWhileReading = false,

    /// 覆盖全局挂起的窗口锚点。
    String? memoryWindowAnchorMsgID,
    String? memoryWindowAnchorSeq,
    bool skipEquivalentHistoryWindow = false,
    String historyCommitSource = 'unspecified',
    MessageReconciliationWriterCommit<V2TimMessage>? writerCommit,
  }) {
    final canonical = canonicalHistoryStorageKey(conversationID);
    final storageKey = canonical.isNotEmpty ? canonical : conversationID.trim();
    final previous = _mergedAliasMessageList(conversationID);
    if (writerCommit == null &&
        _messageReconciliationWriter.hasActiveRequest(storageKey)) {
      // A history transaction owns the next formal publication. Legacy
      // callers may still invoke setMessageList, but they cannot publish a
      // competing snapshot while that transaction is active.
      return _messageCommitSnapshot(
        conversationID: conversationID,
        storageKey: storageKey,
        list: previous,
        structureChanged: false,
        contentChanged: false,
        recordCommit: false,
      );
    }
    if (writerCommit == null) {
      // Legacy callers remain source-compatible, but their snapshot must be
      // admitted by the same identity/revision boundary as every other
      // formal mutation. Seed from the current projection first because the
      // Writer may be seeing this conversation for the first time.
      final clearEpoch = messageDeltaClearEpochFor(storageKey);
      _seedMessageWriterFromProjection(
        storageKey,
        previous,
        clearEpoch: clearEpoch,
      );
      final compatibilityCommit =
          _messageReconciliationWriter.applyCompatibilitySnapshot(
        conversationID: storageKey,
        eventID:
            'compatibility:set_message_list:$storageKey:${++_nextRealtimeReconciliationEvent}',
        records: _reconciliationRecords(messageList),
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: clearEpoch,
        replace: replace || isDeleteMsg,
        // 删除操作已经通过 MessageDelta.explicitDeletes 提供了精确
        // 的消息 ID。当前列表通常只是可视窗口，不能因为窗口外的
        // 历史消息暂时不在 messageList 中，就把它们误判为已删除。
        tombstoneMissing: false,
      );
      if (compatibilityCommit == null) {
        return _messageCommitSnapshot(
          conversationID: conversationID,
          storageKey: storageKey,
          list: previous,
          structureChanged: false,
          contentChanged: false,
          recordCommit: false,
        );
      }
      writerCommit = compatibilityCommit;
      messageList = _messageReconciliationWriter.valuesFor(storageKey);
      // The Writer has already produced a complete authoritative snapshot;
      // this method now only applies the existing memory-window/UI projection.
      replace = true;
    }
    if (replace) {
      // Do this before the equivalent-window fast path as well. A replace can
      // carry no content delta while still superseding a pending presentation
      // transaction that has hidden rows in the projection.
      cancelInboundProjectionRevealForAuthoritativeReplace(conversationID);
    }
    if (skipEquivalentHistoryWindow &&
        writerCommit != null &&
        replace &&
        !isDeleteMsg &&
        previous.length == messageList.length) {
      final previousSignature = _messageListContentSignature(previous);
      final incomingSignature = _messageListContentSignature(messageList);
      final commitSignature = '$historyCommitSource|$incomingSignature';
      if (previousSignature == incomingSignature &&
          _historyWindowCommitSignatureByConv[storageKey] == commitSignature) {
        if (replace &&
            _revealAllDeferredProjectionAcrossAliases(conversationID)) {
          _markNeedsNotify(conversationID: conversationID);
        }
        return _messageCommitSnapshot(
          conversationID: conversationID,
          storageKey: storageKey,
          list: previous,
          structureChanged: false,
          contentChanged: false,
          recordCommit: false,
          writerCommit: writerCommit,
        );
      }
      _historyWindowCommitSignatureByConv[storageKey] = commitSignature;
    }
    // The writer already sorts and reconciles identities. Reuse that work
    // only for a proven new prefix with the entire previous suffix retained.
    final realtimeAppendCount =
        historyCommitSource.startsWith('message_delta:realtimeUpsert:') &&
                writerCommit.missingSeqRanges.isEmpty &&
                writerCommit.seqIdentityConflicts.isEmpty &&
                !isDeleteMsg
            ? _canonicalRealtimeAppendCount(previous, messageList)
            : 0;
    String? canonicalSignature;
    final equivalentCanonical = replace &&
        !isDeleteMsg &&
        previous.isNotEmpty &&
        previous.length == messageList.length &&
        messageList.length <= ChatMessageWindowPolicy.softMax &&
        !_messageCommitStructureChanged(previous, messageList) &&
        _messageListContentSignatureByConv[storageKey] ==
            (canonicalSignature = _messageListContentSignature(messageList)) &&
        !_listHasCorrelatingDup(messageList);
    final reuseCanonical = realtimeAppendCount > 0 || equivalentCanonical;
    if (reuseCanonical) {
      ChatMainThreadPerf.increment(realtimeAppendCount > 0
          ? 'message_realtime_canonical_reused'
          : 'message_noop_canonical_reused');
    }
    var incomingForMerge = messageList;
    if (!reuseCanonical &&
        !isDeleteMsg &&
        previous.isNotEmpty &&
        preserveInFlightOutgoing) {
      final extras = collectUncorrelatedInFlightOutgoing(
        previous: previous,
        incoming: messageList,
      );
      if (OutgoingVisibleProbe.matches(conversationID) ||
          OutgoingVisibleProbe.matches(storageKey)) {
        OutgoingVisibleProbe.log(
          replace ? 'set_list_replace_retain' : 'set_list_merge_retain',
          conversationID: storageKey,
          extras: <String, Object?>{
            'prevCount': previous.length,
            'incomingCount': messageList.length,
            'retainCount': extras.length,
            'retainIds':
                extras.map((m) => '${m.id ?? ''}/${m.msgID ?? ''}').join(','),
            'prevHasTracked': OutgoingVisibleProbe.trackedInList(
              previous,
            ).toString(),
            'incomingHasTracked': OutgoingVisibleProbe.trackedInList(
              messageList,
            ).toString(),
          },
        );
      }
      if (extras.isNotEmpty) {
        incomingForMerge = <V2TimMessage>[...messageList, ...extras];
      }
    }
    if (!reuseCanonical &&
        replace &&
        !isDeleteMsg &&
        applyMemoryWindow &&
        HistoryPaginationAnchor.shouldRejectC2cPeekRestamp(
          existingCount: previous.length,
          incomingCount: incomingForMerge.length,
        )) {
      if (OutgoingVisibleProbe.matches(conversationID) ||
          OutgoingVisibleProbe.matches(storageKey)) {
        OutgoingVisibleProbe.log(
          'c2c_reject_peek_restamp',
          conversationID: storageKey,
          extras: <String, Object?>{
            'prevCount': previous.length,
            'incomingCount': incomingForMerge.length,
          },
        );
      }
      incomingForMerge = mergeC2cOfficialOlderPage(
        existing: previous,
        fetched: incomingForMerge,
      );
    } else if (replace &&
        previous.isEmpty &&
        (OutgoingVisibleProbe.matches(conversationID) ||
            OutgoingVisibleProbe.matches(storageKey))) {
      OutgoingVisibleProbe.log(
        'set_list_replace_empty_prev',
        conversationID: storageKey,
        extras: <String, Object?>{
          'incomingCount': messageList.length,
          'incomingHasTracked': OutgoingVisibleProbe.trackedInList(
            messageList,
          ).toString(),
        },
      );
    }
    // 始终 dedupe：分页写入常已含 previous，再拼接会产生重复 key，表现为顶部无法加载。
    final mergedInput = replace || isDeleteMsg || previous.isEmpty
        ? incomingForMerge
        : <V2TimMessage>[...incomingForMerge, ...previous];
    final writerCanonicalInput = identical(mergedInput, messageList);
    final sorted = ChatMainThreadPerf.measure(
      ChatMainThreadPerf.setMessageListMs,
      () {
        // dedupeMessages is the single canonicalization boundary for this
        // merged batch. A second full-list correlation scan here used to
        // repeat the O(n²) group-id normalization work during every commit.
        var result = reuseCanonical || writerCanonicalInput
            ? mergedInput
            : sortMessagesNewestFirst(dedupeMessages(mergedInput));
        if (applyMemoryWindow && !isDeleteMsg) {
          // Only group Seq provides protocol-level continuity. A detected
          // range is repaired through the bounded reconciliation writer;
          // synchronization state never enters the message list as a marker.
          final isGroup = _isGroupConversation(storageKey, messages: result);
          final gaps = isGroup && !reuseCanonical
              ? GapDetector.detectGaps(
                  newestFirst: result,
                  isGroup: true,
                  fullScan: true,
                )
              : const <GapInfo>[];
          if (isGroup && !equivalentCanonical) {
            _clearResolvedGroupGapAttempts(storageKey, gaps);
          }
          if (gaps.isNotEmpty) {
            _requestDetectedGroupGapCatchUp(storageKey, gaps.first);
          }
          result = _applyMessageMemoryWindow(
            conversationID,
            result,
            anchorMsgID: memoryWindowAnchorMsgID,
            anchorSeq: memoryWindowAnchorSeq,
            forcePreferLatest: memoryWindowPreferLatest,
            forceWhileReadingHistory: forceMemoryWindowTrimWhileReading,
          );
        }
        if ((!reuseCanonical || result.length != mergedInput.length) &&
            !isDeleteMsg &&
            previous.isNotEmpty &&
            preserveInFlightOutgoing) {
          result = restoreUncorrelatedInFlightOutgoing(
            previous: previous,
            incoming: result,
          );
        }
        return result;
      },
      count: mergedInput.length,
      source: replace ? 'replace' : 'merge',
      conversationType: ChatMainThreadPerf.conversationTypeForId(
        conversationID,
      ),
    );
    // The Writer must retain the same working set as the raw/UI projection.
    // Waiting for the next seedAuthoritative call keeps the evicted objects
    // alive after the raw window and its display cache have released them.
    if (sorted.length < writerCommit.records.length) {
      _messageReconciliationWriter.retainCommittedWindow(
        conversationID: storageKey,
        expectedRevision: writerCommit.revision,
        expectedClearEpoch: writerCommit.clearEpoch,
        expectedScope: _messageReconciliationWriter.configuredScope,
        retainedValues: sorted,
      );
    }
    if (skipEquivalentHistoryWindow) {
      _historyWindowCommitSignatureByConv[storageKey] =
          '$historyCommitSource|${_messageListContentSignature(sorted)}';
    }

    if (replace ||
        isDeleteMsg ||
        previous.isEmpty ||
        sorted.length != previous.length) {
      if (OutgoingVisibleProbe.matches(conversationID) ||
          OutgoingVisibleProbe.matches(storageKey)) {
        OutgoingVisibleProbe.log(
          'set_list_committed',
          conversationID: storageKey,
          extras: <String, Object?>{
            'replace': replace,
            'isDeleteMsg': isDeleteMsg,
            'prevCount': previous.length,
            'nextCount': sorted.length,
            'inputCount': messageList.length,
            'prevTracked': OutgoingVisibleProbe.trackedInList(
              previous,
            ).toString(),
            'nextTracked': OutgoingVisibleProbe.trackedInList(
              sorted,
            ).toString(),
          },
        );
      }
      if (replace && sorted.length < previous.length) {
        ChatJitterDiag.log(
          'history_list_shrink',
          conv: conversationID,
          extras: <String, Object?>{
            'prevCount': previous.length,
            'nextCount': sorted.length,
            'inputCount': messageList.length,
            'lost': previous.length - sorted.length,
            'applyMemoryWindow': applyMemoryWindow,
            'memorySuppressed': isMemoryWindowSuppressed(conversationID),
            'position': getMessageListPosition(conversationID).name,
          },
        );
      }
    }
    final normalizedConvId = _inboundStateKey(conversationID);
    final unreadState = _inboundUnreadStateFor(normalizedConvId, create: false);
    final holdUntilUserBottom = _deferredUntilUserBottomConversations.contains(
      normalizedConvId,
    );
    var projectionChanged = false;
    if (replace) {
      // 会话预览同源首屏 / 分页全量写回：必须露出完整窗口。
      // 否则上一轮 inbound hide（群聊未读缓充）会把窗口内消息滤掉，出现空洞。
      projectionChanged = _revealAllDeferredProjectionAcrossAliases(
        conversationID,
      );
      final authoritativePrefix = '$normalizedConvId|';
      _authoritativeDeferredIncomingKeys.removeWhere(
        (key) => key.startsWith(authoritativePrefix),
      );
    } else if (holdUntilUserBottom &&
        unreadState.bufferedMessageKeys.isNotEmpty) {
      final authoritativeDeferred = sorted
          .where(
            (message) => unreadState.bufferedMessageKeys.contains(
              messageDedupKey(message),
            ),
          )
          .toList(growable: false);
      if (authoritativeDeferred.isNotEmpty) {
        projectionChanged = true;
        _hideInboundProjection(conversationID, authoritativeDeferred);
        for (final message in authoritativeDeferred) {
          _authoritativeDeferredIncomingKeys.add(
            _authoritativeDeferredKey(conversationID, message),
          );
        }
      }
    }
    // 先算内容签名：进页 hydrate / peek 原样回写时必须跳过 bump+notify，
    // 否则短会话一次打开会固定多轮 list_rebuild（日志里 spacer 晚到也叠在这上面）。
    var signature = equivalentCanonical
        ? canonicalSignature!
        : _messageListContentSignature(sorted);
    var signatureChanged =
        _messageListContentSignatureByConv[storageKey] != signature;
    final structureChanged = _messageCommitStructureChanged(previous, sorted);
    if (!signatureChanged && !isDeleteMsg) {
      if (_listHasCorrelatingDup(sorted)) {
        signatureChanged = true;
      } else {
        ChatMainThreadPerf.increment('message_list_noop_commit');
        // 列表语义未变：仍补种行高供短历史估 spacer，但不掀翻 UI。
        if (OutgoingVisibleProbe.matches(conversationID) ||
            OutgoingVisibleProbe.matches(storageKey)) {
          OutgoingVisibleProbe.log(
            'set_list_signature_unchanged',
            conversationID: storageKey,
            extras: <String, Object?>{
              'replace': replace,
              'count': sorted.length,
              ...OutgoingVisibleProbe.trackedInList(sorted),
            },
          );
        }
        if (!equivalentCanonical) {
          ChatMessageHeightCache.instance.seedEstimatesForMessages(sorted);
        }
        _messageListContentSignatureByConv[storageKey] = signature;
        _messageListMap[storageKey] = sorted;
        _collapseHistoryAliasesToCanonical(
          conversationID,
          canonical: storageKey,
        );
        if (needResetNewMessageCount &&
            !holdUntilUserBottom &&
            !unreadState.durableDeferred &&
            !unreadState.unreadVisitBaselinePending &&
            unreadState.durableOperationCount == 0 &&
            unreadState.pendingLegacyMessages.isEmpty &&
            unreadState.revealedUnreadMessageIDs.isEmpty) {
          unreadState.receivedCount = 0;
        }
        // 签名未变但投影显隐变了：仍需通知，否则缓充消息会一直藏着。
        if (projectionChanged) {
          _markNeedsNotify(conversationID: conversationID);
        }
        return _messageCommitSnapshot(
          conversationID: conversationID,
          storageKey: storageKey,
          list: sorted,
          structureChanged: structureChanged,
          contentChanged: false,
          recordCommit: true,
          writerCommit: writerCommit,
        );
      }
    }

    _messageListMap[storageKey] = sorted;
    _collapseHistoryAliasesToCanonical(conversationID, canonical: storageKey);
    // stage() coalesces list revisions within a microtask, but a consumer
    // may read the display cache between two inserts. Invalidate on every
    // accepted content change, even when this batch already reserved a bump.
    _invalidateMessageListDisplayCache(storageKey);
    // 首屏 / 增量写入时补种缺省行高，避免冷进页 short-history 全靠常量估算。
    ChatMessageHeightCache.instance.seedEstimatesForMessages(
      realtimeAppendCount > 0
          ? sorted.take(realtimeAppendCount).toList()
          : sorted,
    );
    _messageListContentSignatureByConv[storageKey] = signature;
    final commitStage = _messageCommitCoordinator.stage(
      MessageMutation(
        conversationID: storageKey,
        type: _messageMutationTypeForCommit(
          replace: replace,
          isDeleteMsg: isDeleteMsg,
          structureChanged: structureChanged,
        ),
        generation: (_messageCommitGenerationByConv[storageKey] ?? 0) + 1,
        source: historyCommitSource,
        expectedFirstIdentity:
            sorted.isEmpty ? null : _commitSnapshotIdentity(sorted.first),
        expectedLastIdentity:
            sorted.isEmpty ? null : _commitSnapshotIdentity(sorted.last),
      ),
    );
    ChatMainThreadPerf.increment('message_list_structural_commit');
    if (commitStage.shouldAdvanceListRevision) {
      _bumpMessageListRevisionFor(
        storageKey,
        reason:
            isDeleteMsg ? 'setMessageList_delete' : 'setMessageList_signature',
      );
    }
    // bump 对 setMessageList_* 不再清签名；此处再写一次以防旧调用路径。
    _messageListContentSignatureByConv[storageKey] = signature;
    if (needResetNewMessageCount &&
        !holdUntilUserBottom &&
        !unreadState.durableDeferred &&
        !unreadState.unreadVisitBaselinePending &&
        unreadState.durableOperationCount == 0 &&
        unreadState.pendingLegacyMessages.isEmpty &&
        unreadState.revealedUnreadMessageIDs.isEmpty) {
      unreadState.receivedCount = 0;
    }

    if (isDeleteMsg) {
      final retainedKeys = sorted.map(messageDedupKey).toSet();
      final removedKeys = previous
          .map(messageDedupKey)
          .where((key) => !retainedKeys.contains(key))
          .toSet();
      if (removedKeys.isNotEmpty) {
        final projectionKey = _inboundStateKey(conversationID);
        final hidden = _inboundHiddenKeysByConv[projectionKey];
        hidden?.removeWhere(removedKeys.contains);
        if (hidden != null && hidden.isEmpty) {
          _inboundHiddenKeysByConv.remove(projectionKey);
        }
        final authoritativePrefix = '$projectionKey|';
        _authoritativeDeferredIncomingKeys.removeWhere(
          (key) =>
              key.startsWith(authoritativePrefix) &&
              removedKeys.contains(key.substring(authoritativePrefix.length)),
        );
        final state = _inboundUnreadStateFor(conversationID, create: false);
        state.bufferedMessages.removeWhere(
          (message) => removedKeys.contains(messageDedupKey(message)),
        );
        state.bufferedMessageKeys.removeWhere(removedKeys.contains);
        _inboundFastForwardMessageKeys.removeWhere(removedKeys.contains);
        _bumpMessageProjectionRevisionFor(projectionKey);
      }
      HistoryMessagePosition position = getMessageListPosition(conversationID);
      if (position == HistoryMessagePosition.awayTwoScreen) {
        _storeHistoryMessagePosition(
          conversationID,
          HistoryMessagePosition.notShowLatest,
        );
      }
    }

    _markNeedsNotify(conversationID: conversationID);
    return _messageCommitSnapshot(
      conversationID: conversationID,
      storageKey: storageKey,
      list: sorted,
      structureChanged: structureChanged,
      contentChanged: true,
      recordCommit: true,
      writerCommit: writerCommit,
    );
  }

  V2TimMessage _cloneMessage(V2TimMessage message) {
    try {
      return V2TimMessage.fromJson(Map<String, dynamic>.from(message.toJson()));
    } catch (_) {
      return message;
    }
  }

  int _findMessageIndexForUpdate(
    List<V2TimMessage> messageList,
    String id,
    V2TimMessage sentMessage,
  ) {
    return findReplaceableOutgoingIndex(
      '',
      sentMessage,
      priorTempId: id,
      listOverride: messageList,
    );
  }

  bool _isRowLocalOutgoingMediaReceipt(
    V2TimMessage? previous,
    V2TimMessage replacement,
  ) {
    if (previous == null ||
        previous.isSelf != true ||
        replacement.isSelf != true ||
        previous.elemType != replacement.elemType) {
      return false;
    }
    return const <int>{
      MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
      MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
      MessageElemType.V2TIM_ELEM_TYPE_FILE,
      MessageElemType.V2TIM_ELEM_TYPE_SOUND,
    }.contains(replacement.elemType);
  }

  updateMessage(
    V2TimValueCallback<V2TimMessage> sendMsgRes,
    String convID,
    String id,
    ConvType convType,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField, {
    int? stateVersion,
  }) {
    if (!_mayProjectOutgoingResult(convID, id, sendMsgRes)) return;
    final storageConvID = _resolveMessageListStorageKey(convID);
    List<V2TimMessage> currentHistoryMsgList =
        _messageListMap[storageConvID] ?? _collectAuthoritativeMessages(convID);
    final V2TimMessage sendMsgResData = sendMsgRes.data as V2TimMessage;
    final resolvedMessage = _cloneMessage(sendMsgResData);

    // Always set the correct status based on send result
    if (sendMsgRes.code == 0) {
      resolvedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
      _setUploadProgressSilently(id, 100);
      final resolvedMsgID = resolvedMessage.msgID?.trim();
      if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _setUploadProgressSilently(resolvedMsgID, 100);
      }
    } else {
      resolvedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    if (resolvedMessage.id == null || resolvedMessage.id!.isEmpty) {
      resolvedMessage.id = id;
    }
    final targetIndex = _findMessageIndexForUpdate(
      currentHistoryMsgList,
      id,
      resolvedMessage,
    );
    final originalRowCount = currentHistoryMsgList.length;
    if (sendMsgRes.code != 0 &&
        resolvedMessage.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      ErrorMessageConverter.attachSendFailCode(
        resolvedMessage,
        sendMsgRes.code,
      );
      final msgID = resolvedMessage.msgID;
      if (msgID != null &&
          msgID.isNotEmpty &&
          resolvedMessage.localCustomData != null) {
        _messageService.setLocalCustomData(
          msgID: msgID,
          localCustomData: resolvedMessage.localCustomData!,
        );
      }
    }
    V2TimMessage? previousForMerge;
    if (targetIndex != -1) {
      currentHistoryMsgList = [...currentHistoryMsgList];
      previousForMerge = currentHistoryMsgList[targetIndex];
      if (sendMsgRes.code != 0) {
        final boundMsgID = previousForMerge.msgID?.trim();
        if (boundMsgID != null && boundMsgID.isNotEmpty) {
          resolvedMessage.msgID = boundMsgID;
        }
      }
      _preserveSoundLocalPath(previousForMerge, resolvedMessage);
      _preserveImageLocalPath(previousForMerge, resolvedMessage);
      _preserveImageDisplaySize(resolvedMessage, id);
      _preserveOutgoingLocalOrderData(previousForMerge, resolvedMessage);
      currentHistoryMsgList[targetIndex] = resolvedMessage;
    } else {
      currentHistoryMsgList = [resolvedMessage, ...currentHistoryMsgList];
    }
    final resolvedId = resolvedMessage.id ?? id;
    final resolvedMsgID = resolvedMessage.msgID;
    if (sendMsgRes.code == 0) {
      final hadFailCode =
          ErrorMessageConverter.getSendFailCode(resolvedMessage) != null;
      ErrorMessageConverter.clearSendFailCode(resolvedMessage);
      if (hadFailCode && resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _messageService.setLocalCustomData(
          msgID: resolvedMsgID,
          localCustomData: resolvedMessage.localCustomData ?? '',
        );
      }
      _clearUploadProgressSilently(resolvedId);
      if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _clearUploadProgressSilently(resolvedMsgID);
      }
      _migrateFileMessageMetadata(id, resolvedMsgID);
      if (resolvedMessage.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
        final layoutSize = _fileMessageSizeMap[id] ??
            ((resolvedMsgID?.isNotEmpty ?? false)
                ? _fileMessageSizeMap[resolvedMsgID!]
                : null);
        if (layoutSize != null &&
            layoutSize.width > 0 &&
            layoutSize.height > 0) {
          applyImageLayoutToMessage(resolvedMessage, layoutSize);
          if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
            _messageService.setLocalCustomData(
              msgID: resolvedMsgID,
              localCustomData: resolvedMessage.localCustomData ?? '',
            );
          }
        }
      }
    }
    if (resolvedId.isNotEmpty || (resolvedMsgID?.isNotEmpty ?? false)) {
      currentHistoryMsgList = currentHistoryMsgList.where((element) {
        if (identical(element, resolvedMessage)) {
          return true;
        }
        final sameId = resolvedId.isNotEmpty && element.id == resolvedId;
        final sameMsgID = resolvedMsgID != null &&
            resolvedMsgID.isNotEmpty &&
            element.msgID == resolvedMsgID;
        if (!sameId && !sameMsgID) {
          return true;
        }
        return false;
      }).toList();
    }
    final collapsedDuplicate = currentHistoryMsgList.length < originalRowCount;
    if (loadingMessage[storageConvID] != null &&
        loadingMessage[storageConvID]!.isNotEmpty) {
      loadingMessage[storageConvID]!.removeWhere((element) => element.id == id);
    }
    if (chatConfig.isShowReadingStatus &&
        groupType != GroupReceiptAllowType.community &&
        sendMsgRes.data?.msgID != null) {
      _messageReadReceiptMap[sendMsgRes.data!.msgID!] = V2TimMessageReceipt(
        timestamp: 0,
        userID: "",
        readCount: 0,
      );
    }
    _registerSoundLocalPath(resolvedMessage);
    final stableIdentity =
        readOutgoingStableId(previousForMerge)?.trim().isNotEmpty == true
            ? readOutgoingStableId(previousForMerge)!.trim()
            : readOutgoingStableId(resolvedMessage)?.trim().isNotEmpty == true
                ? readOutgoingStableId(resolvedMessage)!.trim()
                : id.trim();
    final adoptionRecord = MessageReconciliationRecord<V2TimMessage>(
      value: resolvedMessage,
      msgID: resolvedMessage.msgID,
      localID: resolvedMessage.id,
      outgoingStableID: stableIdentity,
      seq: resolvedMessage.seq,
    );
    final authoritativeSendCommit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageConvID,
        // A later committed result is a new event for the same message.
        // Legacy callbacks still distinguish failure from confirmed success.
        eventID: 'send_adoption:$stableIdentity:${resolvedMessage.msgID ?? ''}:'
            '${stateVersion ?? resolvedMessage.status}',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageConvID),
        clearEpoch: messageDeltaClearEpochFor(storageConvID),
        upserts: [adoptionRecord],
      ),
    );
    if (authoritativeSendCommit == null) {
      // A queued, stale, or rejected receipt cannot use the old row-local or
      // full-list fallback. History completion or a later valid receipt owns
      // the next formal publication.
      // `send_done_row_local_fallback` is intentionally retired as a formal
      // list path; keep the diagnostic term for compatibility with probes.
      return;
    }
    _chatUiStateStore.bindMessageAlias(
      storageConvID,
      id,
      ChatUiStateStore.messageKeyOf(resolvedMessage),
    );
    // temp id 上已测到的行高迁到正式 msgID，避免 send_done 后失缓存再估高抖动。
    ChatMessageHeightCache.instance.rememberAlias(id, resolvedMessage.msgID);
    final knownHeight = ChatMessageHeightCache.instance.heightFor(
      resolvedMessage,
    );
    if (knownHeight != null && knownHeight > 0) {
      ChatMessageHeightCache.instance.remember(resolvedMessage, knownHeight);
    }
    _markMessageRowChanged(storageConvID, resolvedMessage, extraKey: id);
    final insertedRow = targetIndex == -1;
    final reordered = !isNewestFirstStorageOrderValid(currentHistoryMsgList);
    final isRowLocalMediaReceipt = targetIndex != -1 &&
        !collapsedDuplicate &&
        stableIdentity.isNotEmpty &&
        _isRowLocalOutgoingMediaReceipt(previousForMerge, resolvedMessage);
    final structuralChange = insertedRow || collapsedDuplicate || reordered;
    if (structuralChange) {
      _bumpMessageListRevisionFor(
        storageConvID,
        reason: insertedRow
            ? 'send_done_insert_sort'
            : collapsedDuplicate
                ? 'send_done_duplicate_collapse'
                : 'send_done_reorder',
      );
    }
    _logOutgoingSendOrder(
      event: 'send_done',
      convID: storageConvID,
      message: resolvedMessage,
      clientId: id,
      mergePath: isRowLocalMediaReceipt
          ? 'row_local_stable_identity'
          : targetIndex != -1
              ? 'update_replace'
              : 'update_insert',
      existingIndex: targetIndex,
      reordered: reordered,
    );
    // 同位回执只由 ChatUiStateStore 通知该行；不发全局 notify，
    // 也不请求贴底，避免用户正在上滑时被拉回底部。
    if (!structuralChange) {
      return;
    }
    // 发送后 350ms suppress 窗口内推迟整表 notify，让 list-push 先播完。
    if (targetIndex != -1 && shouldSuppressOutgoingPinScroll()) {
      Future<void>.delayed(const Duration(milliseconds: 380), () {
        _markNeedsNotify();
      });
    } else {
      _markNeedsNotify();
    }
  }

  bool markOutgoingSendFailedByIdentity({
    required String conversationID,
    String? clientId,
    String? msgID,
    String? localCustomData,
    int? sendFailCode,
    String reason = 'send_failed',
  }) {
    final storageConvID = _resolveMessageListStorageKey(conversationID);
    final cid = clientId?.trim() ?? '';
    final mid = msgID?.trim() ?? '';
    if (storageConvID.isEmpty || (cid.isEmpty && mid.isEmpty)) {
      return false;
    }
    final list = _mergedAliasMessageList(storageConvID);
    if (list.isEmpty) {
      return false;
    }
    final index = list.indexWhere((item) {
      final stable = readOutgoingStableId(item)?.trim() ?? '';
      if (cid.isNotEmpty && (item.id == cid || stable == cid)) {
        return true;
      }
      if (mid.isNotEmpty && (item.msgID == mid || stable == mid)) {
        return true;
      }
      return false;
    });
    if (index < 0) {
      return false;
    }
    final previous = list[index];
    if (previous.status == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC ||
        previous.status == MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED) return false;
    final failed = _cloneMessage(previous);
    failed.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    if (localCustomData != null) {
      failed.localCustomData = localCustomData;
    }
    if (sendFailCode != null) {
      ErrorMessageConverter.attachSendFailCode(failed, sendFailCode);
    }
    final stableIdentity = readOutgoingStableId(previous) ??
        readOutgoingStableId(failed) ??
        (cid.isNotEmpty ? cid : mid);
    final safeReason = reason.trim().isEmpty
        ? 'send_failed'
        : reason.trim().replaceAll(':', '_');
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageConvID,
        eventID: 'send_fail:$storageConvID:$safeReason:$stableIdentity:$mid',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageConvID),
        clearEpoch: messageDeltaClearEpochFor(storageConvID),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: failed,
            msgID: failed.msgID,
            localID: failed.id,
            outgoingStableID: stableIdentity,
            seq: failed.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      return false;
    }
    final failedKey = ChatUiStateStore.messageKeyOf(failed);
    for (final alias in <String>{cid, mid, stableIdentity}..remove('')) {
      if (alias != failedKey) {
        _chatUiStateStore.bindMessageAlias(storageConvID, alias, failedKey);
      }
    }
    _markMessageRowChanged(
      storageConvID,
      failed,
      extraKey: cid.isNotEmpty ? cid : mid,
      mutationType: MessageMutationType.statusOrProgress,
    );
    if (_isSameConversationID(storageConvID, currentSelectedConv)) {
      _markNeedsNotify();
    }
    return true;
  }

  /// Marks an optimistic outgoing message as SEND_FAIL when the commit guard
  /// rejected the send (e.g. conversation switched during async media prep).
  /// Finds the message by temporary client [id], updates its status, and
  /// stamps [localCustomData] with guard_dropped so the UI can show a retry.
  void markOutgoingGuardDropped({
    required String conversationID,
    required String clientId,
    String? localCustomData,
  }) {
    markOutgoingSendFailedByIdentity(
      conversationID: conversationID,
      clientId: clientId,
      localCustomData: localCustomData,
      reason: 'guard_dropped',
    );
  }

  void updateAsyncMessage(V2TimMessage message, String convID) {
    if (message.id == null || message.id!.isEmpty) {
      message.id =
          message.msgID ?? DateTime.now().millisecondsSinceEpoch.toString();
    }

    final storageKey = _resolveMessageListStorageKey(convID);
    if (storageKey.isEmpty) {
      return;
    }
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isEmpty) {
      return;
    }
    final current = _mergedAliasMessageList(storageKey);
    final index = current.indexWhere((item) => item.msgID == msgID);
    if (index < 0) {
      return;
    }
    final previous = current[index];
    final resolved = _cloneMessage(message);
    final stableIdentity = readOutgoingStableId(previous) ??
        readOutgoingStableId(resolved) ??
        previous.id ??
        resolved.id ??
        msgID;
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageKey,
        eventID: 'async_message_edit:$storageKey:$msgID',
        kind: MessageDeltaKind.edit,
        source: MessageDeltaSource.sdkRealtime,
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: messageDeltaClearEpochFor(storageKey),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: resolved,
            msgID: resolved.msgID,
            localID: resolved.id,
            outgoingStableID: stableIdentity,
            seq: resolved.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      return;
    }
    _chatUiStateStore.markMessagesChanged(storageKey, <String>{
      ChatUiStateStore.messageKeyOf(previous),
      ChatUiStateStore.messageKeyOf(resolved),
      msgID,
    });
    _markMessageRowChanged(storageKey, resolved, extraKey: msgID);
    if (_isSameConversationID(storageKey, currentSelectedConv)) {
      _markNeedsNotify();
    }
  }

  /// 群 dedup 用：与 [_normalizeConversationID] 同规则，但不依赖实例。
  static String _normalizeGroupIdForDedup(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return '';
    }
    var normalized = raw;
    if (normalized.startsWith('GROUP')) {
      normalized = normalized.substring(5);
    }
    if (normalized.startsWith('group_')) {
      normalized = normalized.substring(6);
    }
    return normalized.trim();
  }

  static String _groupShortTokenForDedup(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final upper = trimmed.toUpperCase();
    // 默认分配：`@TGS#_@TGS#short` → 取内层；自定义：`@TGS#_mc…` → 原样
    if (upper.startsWith('@TGS#_@TGS#')) {
      return trimmed.substring('@TGS#_'.length); // `@TGS#short`
    }
    if (upper.startsWith('@TGS#_')) {
      return trimmed;
    }
    return trimmed;
  }

  static bool _groupIdsEquivalentForDedup(String? left, String? right) {
    final a = _normalizeGroupIdForDedup(left);
    final b = _normalizeGroupIdForDedup(right);
    if (a.isEmpty && b.isEmpty) {
      return true;
    }
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    if (a == b) {
      return true;
    }
    final shortA = _groupShortTokenForDedup(a);
    final shortB = _groupShortTokenForDedup(b);
    if (shortA.isNotEmpty && shortA == shortB) {
      return true;
    }
    return false;
  }

  /// 群消息：含 groupID、归档 msgKey，或带 archiveHistory 的群归档行（C2C 归档不算）。
  static bool _isGroupLikeMessage(V2TimMessage message) {
    final userID = message.userID?.trim() ?? '';
    if (userID.isNotEmpty) {
      return false;
    }
    final groupID = message.groupID?.trim() ?? '';
    if (groupID.isNotEmpty) {
      return true;
    }
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.contains('@TGS#') && msgID.contains(':')) {
      return true;
    }
    if (HistoryPaginationAnchor.isArchiveHistoryMessage(message)) {
      return true;
    }
    return false;
  }

  /// 从 groupID 或归档 msgKey（@TGS#xxx:seq）解析 canonical 群 token。
  static String _normalizedGroupIdForMessage(V2TimMessage message) {
    final cached = _dedupMeta[message];
    if (cached != null) return cached.groupId;
    final fromGroup = _normalizeGroupIdForDedup(message.groupID);
    String result;
    if (fromGroup.isNotEmpty) {
      result = _groupShortTokenForDedup(fromGroup);
      _dedupMeta[message] =
          _MessageDedupMeta(result, _messageSortSeqUncached(message));
      return result;
    }
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isEmpty) {
      result = '';
      _dedupMeta[message] =
          _MessageDedupMeta(result, _messageSortSeqUncached(message));
      return result;
    }
    if (_isLikelyTencentSdkMsgId(msgID)) {
      return '';
    }
    final colon = msgID.lastIndexOf(':');
    if (colon > 0) {
      final prefix = msgID.substring(0, colon);
      final normalized = _normalizeGroupIdForDedup(prefix);
      if (normalized.isNotEmpty) {
        result = _groupShortTokenForDedup(normalized);
        _dedupMeta[message] =
            _MessageDedupMeta(result, _messageSortSeqUncached(message));
        return result;
      }
    }
    result = _groupShortTokenForDedup(_normalizeGroupIdForDedup(msgID));
    _dedupMeta[message] =
        _MessageDedupMeta(result, _messageSortSeqUncached(message));
    return result;
  }

  static int _messageSortSeq(V2TimMessage message) {
    final cached = _dedupMeta[message];
    if (cached != null) return cached.seq;
    return _messageSortSeqUncached(message);
  }

  static int _messageSortSeqUncached(V2TimMessage message) {
    final fromField = int.tryParse(message.seq?.toString() ?? '') ?? 0;
    if (fromField > 0) {
      return fromField;
    }
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isEmpty) {
      return 0;
    }
    final colon = msgID.lastIndexOf(':');
    if (colon <= 0 || colon + 1 >= msgID.length) {
      return 0;
    }
    final suffix = msgID.substring(colon + 1);
    if (!_isAllAsciiDigits(suffix)) {
      return 0;
    }
    return int.tryParse(suffix) ?? 0;
  }

  /// Whether [message] carries a group-global monotonic [seq] that can be
  /// trusted for chronological ordering.
  ///
  /// Only GROUP messages have a conversation-wide monotonic seq. In C2C (1-to-1)
  /// chats each side numbers its own messages independently, so seq is NOT
  /// comparable across senders and must never drive ordering — timestamps are
  /// the source of truth there.
  static bool _hasGroupSeqOrdering(V2TimMessage message) {
    if (_messageSortSeq(message) <= 0) {
      return false;
    }
    return _isGroupLikeMessage(message);
  }

  /// A self message that is still being sent (no server [seq] yet) and carries
  /// a local outgoing sequence. Such a row is the most recently tapped message
  /// and must sort as the newest on a timestamp tie.
  static bool _isLiveOutgoingPlaceholder(V2TimMessage message) {
    return _messageSortSeq(message) <= 0 &&
        message.isSelf == true &&
        _readOutgoingLocalSeq(message) != null &&
        message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING;
  }

  /// Messages without a server [seq] (local group tips, sending placeholders).
  static bool _usesTimelineLocalOrdering(V2TimMessage message) {
    if (_messageSortSeq(message) > 0) {
      return false;
    }
    final raw = message.localCustomData?.trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          if (decoded['localGroupTips'] == true) {
            return true;
          }
          if (decoded.containsKey('timelineRank')) {
            return true;
          }
        }
      } catch (_) {}
    }
    return message.isSelf == true &&
        _readOutgoingLocalSeq(message) != null &&
        message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING;
  }

  static int _messageTimelineSortRank(V2TimMessage message) {
    final raw = message.localCustomData?.trim() ?? '';
    if (raw.isEmpty) {
      return 50;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final rank = decoded['timelineRank'];
        if (rank is num) {
          return rank.toInt();
        }
      }
    } catch (_) {}
    return 50;
  }

  static int _messageSortTimestamp(V2TimMessage message) {
    final timestamp = normalizeMessageEpochSeconds(message.timestamp);
    if (timestamp > 0) {
      return timestamp;
    }
    final localSentAt = normalizeMessageEpochSeconds(
      _readOutgoingLocalSentAt(message),
    );
    if (localSentAt > 0) {
      return localSentAt;
    }
    return 0;
  }

  static int compareMessagesChronological(V2TimMessage a, V2TimMessage b) {
    final sa = _messageSortSeq(a);
    final sb = _messageSortSeq(b);
    final aLocalTimeline = _usesTimelineLocalOrdering(a);
    final bLocalTimeline = _usesTimelineLocalOrdering(b);

    // In GROUP chats the server seq is the source of truth: msgID/server
    // timestamps can be non-monotonic while seq stays ordered (see logs). In
    // C2C chats seq is per-sender and NOT chronological, so it must not be used
    // here — fall through to timestamp ordering instead.
    final batchA = readChatMediaBatchId(a);
    final batchB = readChatMediaBatchId(b);
    final batchIndexA = readChatMediaBatchIndex(a);
    final batchIndexB = readChatMediaBatchIndex(b);
    if (batchA != null &&
        batchA == batchB &&
        batchIndexA != null &&
        batchIndexB != null &&
        batchIndexA != batchIndexB) {
      return batchIndexA.compareTo(batchIndexB);
    }

    final aGroupSeq = !aLocalTimeline && _hasGroupSeqOrdering(a);
    final bGroupSeq = !bLocalTimeline && _hasGroupSeqOrdering(b);
    if (aGroupSeq && bGroupSeq) {
      if (sa != sb) {
        return sa.compareTo(sb);
      }
    }

    final ta = _messageSortTimestamp(a);
    final tb = _messageSortTimestamp(b);
    if (ta != tb) {
      return ta.compareTo(tb);
    }
    // Equal timestamps (same-second send): a live SENDING placeholder was just
    // created locally and is therefore newer than any already-resolved message
    // it ties with. Sends are serialized, so any resolved row in the list was
    // dispatched before this placeholder was tapped. Without this, the
    // placeholder (seq=0) loses the seq tie-break below and briefly renders
    // *above* (older than) the previous message, then snaps back once its own
    // server seq arrives — the visible "reorder then recover" flicker.
    final aSendingPlaceholder = _isLiveOutgoingPlaceholder(a);
    final bSendingPlaceholder = _isLiveOutgoingPlaceholder(b);
    if (aSendingPlaceholder != bSendingPlaceholder) {
      return aSendingPlaceholder ? 1 : -1;
    }
    // 同一秒内本地发送与入站消息的兜底顺序：我方先发、对方后回，
    // 升序里 self 在前。群聊某些本地发送/回执阶段可能暂时没有 server
    // seq，此时不能让 msgID/hash 决定顺序，否则回复会短暂显示在自己消息上方。
    if (ta == tb &&
        ta > 0 &&
        (_isC2cLikeMessage(a) || _isGroupLikeMessage(a)) &&
        (_isC2cLikeMessage(b) || _isGroupLikeMessage(b)) &&
        a.isSelf != b.isSelf) {
      if (a.isSelf == true) {
        return -1;
      }
      if (b.isSelf == true) {
        return 1;
      }
    }
    final rankA = _messageTimelineSortRank(a);
    final rankB = _messageTimelineSortRank(b);
    if (rankA != rankB) {
      return rankA.compareTo(rankB);
    }
    if (aGroupSeq && bGroupSeq && sa != sb) {
      return sa.compareTo(sb);
    }
    final la = _readOutgoingLocalSeq(a);
    final lb = _readOutgoingLocalSeq(b);
    if (la != null && lb != null && la != lb) {
      return la.compareTo(lb);
    }
    if (la != null && lb == null) {
      return 1;
    }
    if (la == null && lb != null) {
      return -1;
    }
    final ma = a.msgID ?? a.id ?? '';
    final mb = b.msgID ?? b.id ?? '';
    return ma.compareTo(mb);
  }

  static List<V2TimMessage> sortMessagesChronologicallyAsc(
    List<V2TimMessage> messages,
  ) {
    return List<V2TimMessage>.from(messages)
      ..sort(compareMessagesChronological);
  }

  /// 缓存 _isLikelyTencentSdkMsgId 结果——控制台日志显示历史拉取后
  /// 该函数被调用 160 万次。纯函数 + msgID 不变，适合 LRU 缓存。
  static final LinkedHashMap<String, bool> _likelySdkMsgIdCache =
      LinkedHashMap<String, bool>();
  static const int _likelySdkMsgIdCacheCap = 8192;

  /// 腾讯 SDK / 端上自消息 msgID（数字 TIM id 或 `userId-ts-random`；非归档 `@TGS#:seq`）。
  static bool _isLikelyTencentSdkMsgId(String? msgID) {
    final id = msgID?.trim() ?? '';
    if (id.isEmpty) {
      return false;
    }
    final cached = _likelySdkMsgIdCache[id];
    if (cached != null) {
      RegExpProbe.recordCacheHit('msgId.isLikelySdk');
      _likelySdkMsgIdCache.remove(id);
      _likelySdkMsgIdCache[id] = cached;
      return cached;
    }
    RegExpProbe.recordCacheMiss('msgId.isLikelySdk');
    final result = RegExpProbe.measure('msgId.isLikelySdk', () {
      // These two checks intentionally mirror the old anchored regexes, but
      // avoid invoking the RegExp interpreter for the high-volume identity
      // comparator. The prefix check accepts malformed-but-prefixed SDK IDs
      // exactly as `^\d{6,}-` did.
      if (_hasDigitDashPrefix(id)) {
        return true;
      }
      // 自消息常见：`q14gkm5swv-1785731054-174908238`
      return _matchesUserIdDashShape(id) && !_isArchiveUnderscoreMsgId(id);
    });
    _likelySdkMsgIdCache[id] = result;
    while (_likelySdkMsgIdCache.length > _likelySdkMsgIdCacheCap) {
      _likelySdkMsgIdCache.remove(_likelySdkMsgIdCache.keys.first);
    }
    return result;
  }

  static bool _hasDigitDashPrefix(String id) {
    var index = 0;
    while (index < id.length) {
      final code = id.codeUnitAt(index);
      if (code < 0x30 || code > 0x39) {
        break;
      }
      index++;
    }
    return index >= 6 && index < id.length && id.codeUnitAt(index) == 0x2d;
  }

  /// Fast structural equivalent of `^[A-Za-z0-9_-]+-\d+-\d+$`.
  static bool _matchesUserIdDashShape(String id) {
    final last = id.lastIndexOf('-');
    if (last <= 0 || last == id.length - 1) {
      return false;
    }
    final middle = id.lastIndexOf('-', last - 1);
    if (middle <= 0 || middle == last - 1) {
      return false;
    }
    return _isUserIdWireHead(id.substring(0, middle)) &&
        _isAllAsciiDigits(id.substring(middle + 1, last)) &&
        _isAllAsciiDigits(id.substring(last + 1));
  }

  /// `seq_random_ts` 归档 msgID：`^(\d+)_(\d+)_(\d+)$`（结构匹配，对齐旧 hasMatch）。
  static bool _isArchiveUnderscoreMsgId(String msgID) {
    final last = msgID.lastIndexOf('_');
    if (last <= 0) {
      return false;
    }
    final mid = msgID.lastIndexOf('_', last - 1);
    if (mid <= 0) {
      return false;
    }
    // 恰好两段 `_`，三段均非空数字（含 0），与 RegExp hasMatch 一致。
    if (msgID.indexOf('_') != mid) {
      return false;
    }
    final head = msgID.substring(0, mid);
    final midPart = msgID.substring(mid + 1, last);
    final tail = msgID.substring(last + 1);
    return _isAllAsciiDigits(head) &&
        _isAllAsciiDigits(midPart) &&
        _isAllAsciiDigits(tail);
  }

  static bool _isAllAsciiDigits(String s) {
    if (s.isEmpty) {
      return false;
    }
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) {
        return false;
      }
    }
    return true;
  }

  static bool _isUserIdWireHead(String s) {
    if (s.isEmpty) {
      return false;
    }
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39;
      final isUpper = c >= 0x41 && c <= 0x5a;
      final isLower = c >= 0x61 && c <= 0x7a;
      final isSep = c == 0x5f /* _ */ || c == 0x2d /* - */;
      if (!isDigit && !isUpper && !isLower && !isSep) {
        return false;
      }
    }
    return true;
  }

  /// `^(\d{6,})-(\d+)-(\d+)$` → (ts, random)
  static ({int ts, int random})? _tryParseTimDigitDashWire(String msgID) {
    final last = msgID.lastIndexOf('-');
    if (last <= 0) {
      return null;
    }
    final mid = msgID.lastIndexOf('-', last - 1);
    if (mid <= 0) {
      return null;
    }
    final head = msgID.substring(0, mid);
    final midPart = msgID.substring(mid + 1, last);
    final tail = msgID.substring(last + 1);
    if (head.length < 6 ||
        !_isAllAsciiDigits(head) ||
        !_isAllAsciiDigits(midPart) ||
        !_isAllAsciiDigits(tail)) {
      return null;
    }
    final ts = int.tryParse(midPart) ?? 0;
    final random = int.tryParse(tail) ?? 0;
    if (ts <= 0 || random <= 0) {
      return null;
    }
    return (ts: ts, random: random);
  }

  /// `^([A-Za-z0-9_-]+)-(\d+)-(\d+)$` → (ts, random)
  static ({int ts, int random})? _tryParseUserIdDashWire(String msgID) {
    final last = msgID.lastIndexOf('-');
    if (last <= 0) {
      return null;
    }
    final mid = msgID.lastIndexOf('-', last - 1);
    if (mid <= 0) {
      return null;
    }
    final head = msgID.substring(0, mid);
    final midPart = msgID.substring(mid + 1, last);
    final tail = msgID.substring(last + 1);
    if (!_isUserIdWireHead(head) ||
        !_isAllAsciiDigits(midPart) ||
        !_isAllAsciiDigits(tail)) {
      return null;
    }
    final ts = int.tryParse(midPart) ?? 0;
    final random = int.tryParse(tail) ?? 0;
    if (ts <= 0 || random <= 0) {
      return null;
    }
    return (ts: ts, random: random);
  }

  /// `^(\d+)_(\d+)_(\d+)$` → (random, ts) 与旧 RegExp group2/group3 一致。
  static ({int random, int ts})? _tryParseArchiveUnderscoreWire(String msgID) {
    final last = msgID.lastIndexOf('_');
    if (last <= 0) {
      return null;
    }
    final mid = msgID.lastIndexOf('_', last - 1);
    if (mid <= 0) {
      return null;
    }
    final head = msgID.substring(0, mid);
    final midPart = msgID.substring(mid + 1, last);
    final tail = msgID.substring(last + 1);
    if (!_isAllAsciiDigits(head) ||
        !_isAllAsciiDigits(midPart) ||
        !_isAllAsciiDigits(tail)) {
      return null;
    }
    final random = int.tryParse(midPart) ?? 0;
    final ts = int.tryParse(tail) ?? 0;
    if (random <= 0 || ts <= 0) {
      return null;
    }
    return (random: random, ts: ts);
  }

  /// C2C 跨源稳定身份：sender + timestampSec + random。
  static ({String sender, int timestampSec, int random})? _c2cWireIdentity(
    V2TimMessage message,
  ) {
    if (!_isC2cConversationMessage(message) && !_isC2cLikeMessage(message)) {
      return null;
    }
    final sender = _normalizedC2cAccountId(
      (message.sender?.trim().isNotEmpty ?? false)
          ? message.sender
          : message.userID,
    );
    var ts = message.timestamp ?? 0;
    if (ts > 1000000000000) {
      ts = ts ~/ 1000;
    }
    var random = message.random ?? 0;
    final msgID = message.msgID?.trim() ?? '';
    // 字段已齐时 msgID 解析是纯空转（旧逻辑只在 <=0 时回填）——跳过 Probe/解析。
    if (msgID.isNotEmpty && (ts <= 0 || random <= 0)) {
      RegExpProbe.measure('msgId.c2cWireIdentity', () {
        final sdk =
            _tryParseTimDigitDashWire(msgID) ?? _tryParseUserIdDashWire(msgID);
        if (sdk != null && !_isArchiveUnderscoreMsgId(msgID)) {
          if (ts <= 0 && sdk.ts > 0) {
            ts = sdk.ts;
          }
          if (random <= 0 && sdk.random > 0) {
            random = sdk.random;
          }
        } else {
          final archive = _tryParseArchiveUnderscoreWire(msgID);
          if (archive != null) {
            if (random <= 0 && archive.random > 0) {
              random = archive.random;
            }
            if (ts <= 0 && archive.ts > 0) {
              ts = archive.ts;
            }
          }
        }
      });
    }
    if (sender.isEmpty || ts <= 0 || random <= 0) {
      return null;
    }
    return (sender: sender, timestampSec: ts, random: random);
  }

  @visibleForTesting
  static ({String sender, int timestampSec, int random})?
      parseC2cWireIdentityForTesting(V2TimMessage message) {
    return _c2cWireIdentity(message);
  }

  /// 历史合并后用于幂等判断的身份签名（wire 优先，否则 messageDedupKey）。
  static String historyIdentitySignature(List<V2TimMessage> messages) {
    final keys = <String>[];
    for (final message in messages) {
      final wire = _c2cWireIdentity(message);
      if (wire != null) {
        keys.add('c2cwi:${wire.sender}:${wire.timestampSec}:${wire.random}');
        continue;
      }
      if (_hasGroupSeqOrdering(message)) {
        final seq = _messageSortSeq(message);
        if (seq > 0) {
          keys.add('gseq:${_normalizedGroupIdForMessage(message)}:$seq');
          continue;
        }
      }
      keys.add(messageDedupKey(message));
    }
    keys.sort();
    return keys.join('|');
  }

  @visibleForTesting
  static String historyIdentitySignatureForTesting(
    List<V2TimMessage> messages,
  ) {
    return historyIdentitySignature(messages);
  }

  /// 胜出行吸收对侧本地媒体路径，并在方向分更高时采纳 isSelf。
  static V2TimMessage _finalizePreferredDedupMessage(
    V2TimMessage preferred,
    V2TimMessage other,
  ) {
    _absorbMediaLocalPaths(preferred, other);
    // 归档↔SDK 不同 msgID：把已测行高粘到保留行，避免短历史 spacer 再估高。
    ChatMessageHeightCache.instance.rememberAliasesBetween(preferred, other);
    if (_isC2cConversationMessage(preferred) &&
        _isC2cConversationMessage(other)) {
      final preferredScore = _c2cDirectionConsistencyScore(preferred);
      final otherScore = _c2cDirectionConsistencyScore(other);
      if (otherScore > preferredScore) {
        preferred.isSelf = other.isSelf;
      }
    }
    return preferred;
  }

  static void _absorbMediaLocalPaths(V2TimMessage winner, V2TimMessage donor) {
    if (winner.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
        donor.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
      final donorPath = donor.imageElem?.path?.trim() ?? '';
      final winnerPath = winner.imageElem?.path?.trim() ?? '';
      if (donorPath.isNotEmpty && winnerPath.isEmpty) {
        winner.imageElem ??= donor.imageElem;
        winner.imageElem?.path = donorPath;
      }
    }
    if (winner.elemType == MessageElemType.V2TIM_ELEM_TYPE_SOUND &&
        donor.elemType == MessageElemType.V2TIM_ELEM_TYPE_SOUND) {
      final donorPath =
          donor.soundElem?.path ?? donor.soundElem?.localUrl ?? '';
      if (donorPath.isNotEmpty) {
        winner.soundElem ??= donor.soundElem;
        winner.soundElem?.path = donor.soundElem?.path ?? donorPath;
        winner.soundElem?.localUrl =
            donor.soundElem?.localUrl ?? winner.soundElem?.localUrl;
      }
    }
    if (winner.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO &&
        donor.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO) {
      final donorPath = donor.videoElem?.localVideoUrl?.trim() ??
          donor.videoElem?.videoPath?.trim() ??
          '';
      final winnerPath = winner.videoElem?.localVideoUrl?.trim() ??
          winner.videoElem?.videoPath?.trim() ??
          '';
      if (donorPath.isNotEmpty && winnerPath.isEmpty) {
        winner.videoElem ??= donor.videoElem;
        if ((winner.videoElem?.localVideoUrl?.trim().isEmpty ?? true) &&
            (donor.videoElem?.localVideoUrl?.trim().isNotEmpty ?? false)) {
          winner.videoElem?.localVideoUrl = donor.videoElem?.localVideoUrl;
        }
        if ((winner.videoElem?.videoPath?.trim().isEmpty ?? true) &&
            (donor.videoElem?.videoPath?.trim().isNotEmpty ?? false)) {
          winner.videoElem?.videoPath = donor.videoElem?.videoPath;
        }
      }
    }
    if (winner.elemType == MessageElemType.V2TIM_ELEM_TYPE_FILE &&
        donor.elemType == MessageElemType.V2TIM_ELEM_TYPE_FILE) {
      final donorPath = donor.fileElem?.localUrl?.trim() ??
          donor.fileElem?.path?.trim() ??
          '';
      final winnerPath = winner.fileElem?.localUrl?.trim() ??
          winner.fileElem?.path?.trim() ??
          '';
      if (donorPath.isNotEmpty && winnerPath.isEmpty) {
        winner.fileElem ??= donor.fileElem;
        winner.fileElem?.localUrl =
            donor.fileElem?.localUrl ?? winner.fileElem?.localUrl;
        winner.fileElem?.path = donor.fileElem?.path ?? winner.fileElem?.path;
      }
    }
  }

  static void _applyDedupPreference(
    List<V2TimMessage> result,
    int index,
    V2TimMessage candidate, {
    String? candidateDedupKey,
    Map<String, int>? dedupKeyToResultIndex,
  }) {
    final existing = result[index];
    if (_preferMessageForDedup(candidate, existing)) {
      result[index] = _finalizePreferredDedupMessage(candidate, existing);
      if (candidateDedupKey != null && dedupKeyToResultIndex != null) {
        dedupKeyToResultIndex[candidateDedupKey] = index;
      }
    } else {
      result[index] = _finalizePreferredDedupMessage(existing, candidate);
    }
  }

  /// 同一 dedupKey 冲突时保留哪条（incoming 为 true 则替换 existing）。
  static bool _preferMessageForDedup(
    V2TimMessage incoming,
    V2TimMessage existing,
  ) {
    final incomingArchive = HistoryPaginationAnchor.isArchiveHistoryMessage(
      incoming,
    );
    final existingArchive = HistoryPaginationAnchor.isArchiveHistoryMessage(
      existing,
    );

    // 后端归档历史 SoT：先于「resolved outgoing」判断，避免 SDK isSelf 压过归档。
    if (incomingArchive != existingArchive) {
      final incomingSeq = _messageSortSeq(incoming);
      final existingSeq = _messageSortSeq(existing);
      final sameGroupSeq = !_isC2cConversationMessage(incoming) &&
          !_isC2cConversationMessage(existing) &&
          incomingSeq > 0 &&
          incomingSeq == existingSeq;
      final c2cPair = _isC2cConversationMessage(incoming) &&
          _isC2cConversationMessage(existing);
      if (sameGroupSeq ||
          c2cPair ||
          messagesCorrelateForDedup(incoming, existing)) {
        return incomingArchive;
      }
    }

    final existingResolved = _isResolvedOutgoingMessage(existing);
    final incomingResolved = _isResolvedOutgoingMessage(incoming);
    if (incomingResolved && !existingResolved) {
      return true;
    }
    if (!incomingResolved && existingResolved) {
      return false;
    }

    // 群历史（含 Web SDK 缺 groupID）：同 seq 时后端归档优先。
    final incomingSeqEarly = _messageSortSeq(incoming);
    final existingSeqEarly = _messageSortSeq(existing);
    if (!_isC2cConversationMessage(incoming) &&
        !_isC2cConversationMessage(existing) &&
        incomingSeqEarly > 0 &&
        incomingSeqEarly == existingSeqEarly) {
      if (incomingArchive && !existingArchive) {
        return true;
      }
      if (!incomingArchive && existingArchive) {
        return false;
      }
    }

    // 群消息：后端归档历史优先于 SDK 漫游副本。
    if (_isGroupLikeMessage(incoming) &&
        _isGroupLikeMessage(existing) &&
        _messageSortSeq(incoming) > 0 &&
        _messageSortSeq(incoming) == _messageSortSeq(existing)) {
      if (incomingArchive && !existingArchive) {
        return true;
      }
      if (!incomingArchive && existingArchive) {
        return false;
      }
    }

    // C2C：后端归档历史为 SoT；SDK 仅覆盖 client echo。
    if (_isC2cConversationMessage(incoming) &&
        _isC2cConversationMessage(existing)) {
      final incomingSdk = _isLikelyTencentSdkMsgId(incoming.msgID);
      final existingSdk = _isLikelyTencentSdkMsgId(existing.msgID);
      if (incomingArchive && existingSdk) {
        return true;
      }
      if (incomingSdk && existingArchive) {
        return false;
      }
      if (incomingArchive && !existingArchive) {
        return true;
      }
      if (!incomingArchive && existingArchive) {
        return false;
      }
      if (incomingSdk && _isC2cClientEchoMessage(existing)) {
        return true;
      }
      if (_isC2cClientEchoMessage(incoming) && existingSdk) {
        return false;
      }
      final incomingScore = _c2cDirectionConsistencyScore(incoming);
      final existingScore = _c2cDirectionConsistencyScore(existing);
      if (incomingScore != existingScore) {
        return incomingScore > existingScore;
      }
    }

    return false;
  }

  static bool _isC2cConversationMessage(V2TimMessage message) {
    return _isC2cLikeMessage(message) &&
        (message.userID?.trim().isNotEmpty ?? false);
  }

  /// 无 C2C userID 即非单聊；群消息也有 sender，不能凭 sender 判 C2C。
  static bool _isC2cLikeMessage(V2TimMessage message) {
    if (_isGroupLikeMessage(message)) {
      return false;
    }
    return message.userID?.trim().isNotEmpty ?? false;
  }

  static bool _isC2cClientEchoMessage(V2TimMessage message) {
    if (_isLikelyTencentSdkMsgId(message.msgID)) {
      return false;
    }
    final id = message.id?.trim() ?? '';
    return id.isNotEmpty;
  }

  /// 同秒同内容：TIM SDK 副本 vs 会话预览/client id echo（userID 可能不一致）。
  static bool _c2cPreviewEchoCorrelate(V2TimMessage a, V2TimMessage b) {
    if (!_isC2cLikeMessage(a) || !_isC2cLikeMessage(b)) {
      return false;
    }
    final tsA = a.timestamp ?? 0;
    final tsB = b.timestamp ?? 0;
    if (tsA <= 0 || tsA != tsB) {
      return false;
    }
    final fpA = _messageContentFingerprint(a);
    final fpB = _messageContentFingerprint(b);
    if (fpA == null || fpB == null || fpA != fpB) {
      return false;
    }
    final aSdk = _isLikelyTencentSdkMsgId(a.msgID);
    final bSdk = _isLikelyTencentSdkMsgId(b.msgID);
    if (aSdk && bSdk) {
      final aMsgID = a.msgID!.trim();
      final bMsgID = b.msgID!.trim();
      return aMsgID == bMsgID;
    }
    if (aSdk || bSdk) {
      return true;
    }
    if (a.isSelf != b.isSelf) {
      return true;
    }
    return _isC2cClientEchoMessage(a) || _isC2cClientEchoMessage(b);
  }

  /// C2C 账号归一化（去 c2c_ 前缀、@ 后缀），与 app 侧 ChatIdFormat 语义对齐。
  static String _normalizedC2cAccountId(String? raw) {
    var id = raw?.trim() ?? '';
    if (id.isEmpty) {
      return '';
    }
    if (id.startsWith('c2c_')) {
      id = id.substring(4);
    }
    final at = id.indexOf('@');
    if (at > 0) {
      id = id.substring(0, at);
    }
    return id.toLowerCase();
  }

  /// sender 与 peer/userID 方向一致时得分更高（3=一致，1=镜像 dup）。
  static int _c2cDirectionConsistencyScore(V2TimMessage message) {
    if (!_isC2cConversationMessage(message)) {
      return 0;
    }
    final peer = _normalizedC2cAccountId(message.userID);
    final sender = _normalizedC2cAccountId(message.sender);
    if (peer.isEmpty || sender.isEmpty) {
      return 0;
    }
    final fromPeer = peer == sender;
    final isSelf = message.isSelf == true;
    if (fromPeer && !isSelf) {
      return 3;
    }
    if (!fromPeer && isSelf) {
      return 3;
    }
    return 1;
  }

  /// C2C 镜像 dup：sender 为 peer 却被标成 isSelf（Web 漫游常见）。
  static bool _isC2cMirrorMislabeledSelf(V2TimMessage message) {
    return message.isSelf == true &&
        _isC2cConversationMessage(message) &&
        _c2cDirectionConsistencyScore(message) < 3;
  }

  V2TimMessage _normalizeInboundC2cDirection(V2TimMessage message) {
    if (!_isC2cMirrorMislabeledSelf(message)) {
      return message;
    }
    final fixed = _cloneMessage(message);
    fixed.isSelf = false;
    return fixed;
  }

  static bool _resolveMergedIsSelf(V2TimMessage a, V2TimMessage b) {
    final scoreA = _c2cDirectionConsistencyScore(a);
    final scoreB = _c2cDirectionConsistencyScore(b);
    if (scoreA > scoreB) {
      return a.isSelf == true;
    }
    if (scoreB > scoreA) {
      return b.isSelf == true;
    }
    final peer = _normalizedC2cAccountId(a.userID ?? b.userID);
    if (peer.isNotEmpty) {
      final senderA = _normalizedC2cAccountId(a.sender);
      final senderB = _normalizedC2cAccountId(b.sender);
      if (senderA == peer && senderB == peer) {
        // 双方 sender 均为 peer：真实方向是 incoming（左收）。
        return false;
      }
      if (senderA == peer && senderB != peer) {
        return a.isSelf == true;
      }
      if (senderB == peer && senderA != peer) {
        return b.isSelf == true;
      }
    }
    return a.isSelf == true && b.isSelf == true;
  }

  static String? _messageContentFingerprint(V2TimMessage message) {
    final text = message.textElem?.text?.trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
    return null;
  }

  /// C2C 跨源去重键：优先 wire identity（ts+random）；无 random 时降级文本指纹。
  static String? _c2cCrossSourceDedupKey(V2TimMessage message) {
    if (!_isC2cConversationMessage(message)) {
      return null;
    }
    final wire = _c2cWireIdentity(message);
    if (wire != null) {
      return 'c2cwi:${wire.sender}:${wire.timestampSec}:${wire.random}';
    }
    final userID = _normalizedC2cAccountId(message.userID);
    final ts = message.timestamp ?? 0;
    if (userID.isEmpty || ts <= 0) {
      return null;
    }
    final fingerprint = _messageContentFingerprint(message);
    if (fingerprint == null || fingerprint.isEmpty) {
      return null;
    }
    return 'c2cx:$userID:$ts:${message.elemType}:$fingerprint';
  }

  static bool _c2cCrossSourceCorrelate(V2TimMessage a, V2TimMessage b) {
    final keyA = _c2cCrossSourceDedupKey(a);
    final keyB = _c2cCrossSourceDedupKey(b);
    if (keyA == null || keyB == null || keyA != keyB) {
      return false;
    }
    // wire identity 已对齐：任意来源组合均视为同一条。
    if (keyA.startsWith('c2cwi:')) {
      return true;
    }
    final aArchive = HistoryPaginationAnchor.isArchiveHistoryMessage(a);
    final bArchive = HistoryPaginationAnchor.isArchiveHistoryMessage(b);
    final aSdk = _isLikelyTencentSdkMsgId(a.msgID);
    final bSdk = _isLikelyTencentSdkMsgId(b.msgID);
    if ((aArchive && bSdk) || (bArchive && aSdk)) {
      return true;
    }
    // 同会话同内容 isSelf 镜像（左收右发）：归档/TIM 或双 SDK echo。
    if (a.isSelf != b.isSelf) {
      return true;
    }
    return false;
  }

  /// 群聊 archive↔SDK 跨源：同 seq 视为同一条（Web SDK 常缺 groupID/@TGS#）。
  static String? _groupCrossSourceDedupKey(V2TimMessage message) {
    if (!_isGroupLikeMessage(message) &&
        !HistoryPaginationAnchor.isArchiveHistoryMessage(message)) {
      return null;
    }
    final seq = _messageSortSeq(message);
    if (seq <= 0) {
      return null;
    }
    if (_isLikelyTencentSdkMsgId(message.msgID) &&
        !_isGroupLikeMessage(message)) {
      // Web SDK 群消息偶发缺 groupID：用 seq-only 键与归档侧配对。
      return 'gseqx:*:$seq';
    }
    final token = _normalizedGroupIdForMessage(message);
    return 'gseqx:${token.isEmpty ? '*' : token}:$seq';
  }

  static bool _groupCrossSourceCorrelate(V2TimMessage a, V2TimMessage b) {
    if (_isC2cConversationMessage(a) || _isC2cConversationMessage(b)) {
      return false;
    }
    final seqA = _messageSortSeq(a);
    final seqB = _messageSortSeq(b);
    if (seqA <= 0 || seqB <= 0 || seqA != seqB) {
      return false;
    }
    final aArchive = HistoryPaginationAnchor.isArchiveHistoryMessage(a);
    final bArchive = HistoryPaginationAnchor.isArchiveHistoryMessage(b);
    final aSdk = _isLikelyTencentSdkMsgId(a.msgID);
    final bSdk = _isLikelyTencentSdkMsgId(b.msgID);
    if ((aArchive && bSdk) || (bArchive && aSdk)) {
      return true;
    }
    return false;
  }

  static String messageDedupKey(V2TimMessage message) {
    // Seq proves group ordering and gap continuity, not exact identity. Keep
    // different server msgIDs distinct; archive↔SDK copies are correlated by
    // the explicit cross-source rule above.
    if (_hasGroupSeqOrdering(message)) {
      final groupToken = _normalizedGroupIdForMessage(message);
      final seq = _messageSortSeq(message);
      final msgID = message.msgID?.trim() ?? '';
      if (msgID.isNotEmpty) {
        return 'gmsg:$groupToken:$seq:$msgID';
      }
      return 'gseq:$groupToken:$seq';
    }
    final msgID = message.msgID?.trim();
    if (msgID != null && msgID.isNotEmpty) {
      return 'msg:$msgID';
    }
    final id = message.id?.trim();
    if (id != null && id.isNotEmpty) {
      return 'id:$id';
    }
    return [
      message.sender ?? message.userID ?? '',
      message.timestamp ?? '',
      message.seq ?? '',
      message.elemType,
      message.random,
    ].join('|');
  }

  static List<V2TimMessage> dedupeMessages(List<V2TimMessage> messages) {
    if (messages.isEmpty) {
      return const <V2TimMessage>[];
    }
    final dedupKeyToResultIndex = <String, int>{};
    final correlationToResultIndex = <String, int>{};
    final crossSourceToResultIndex = <String, int>{};
    final groupCrossSourceToResultIndex = <String, int>{};
    // Every positive rule in messagesCorrelateForDedup has an indexed route.
    // Buckets select candidates only; the existing guards still decide identity.
    // In particular, complete SDK rows do not search unrelated same-second rows.
    final correlationBucketToResultIndexes = <String, Set<int>>{};
    void indexCorrelationBuckets(V2TimMessage message, int resultIndex) {
      for (final bucket in _dedupCorrelationBuckets(message)) {
        correlationBucketToResultIndexes
            .putIfAbsent(bucket, () => <int>{})
            .add(resultIndex);
      }
    }

    final result = <V2TimMessage>[];
    void applyPreference(int index, V2TimMessage candidate, String key) {
      _applyDedupPreference(
        result,
        index,
        candidate,
        candidateDedupKey: key,
        dedupKeyToResultIndex: dedupKeyToResultIndex,
      );
      // An ack can introduce a server ID, local sequence or media path that
      // was absent on its placeholder. Index the winner after every adoption.
      // Sets avoid adding the same row repeatedly when receipts keep it alive.
      indexCorrelationBuckets(result[index], index);
    }

    for (final message in messages) {
      final key = messageDedupKey(message);
      final corr = _outgoingCorrelationKey(message);
      if (corr != null) {
        final existingIdx = correlationToResultIndex[corr];
        if (existingIdx != null &&
            !_areDistinctSdkIdentities(result[existingIdx], message) &&
            !_areDistinctGroupServerIdentities(result[existingIdx], message) &&
            !_areDistinctGroupSequences(result[existingIdx], message)) {
          applyPreference(existingIdx, message, key);
          continue;
        }
      }
      final groupCrossKey = _groupCrossSourceDedupKey(message);
      var groupCrossMatched = false;
      if (groupCrossKey != null) {
        final existingIdx = groupCrossSourceToResultIndex[groupCrossKey];
        if (existingIdx != null) {
          final existing = result[existingIdx];
          if (_groupCrossSourceCorrelate(message, existing)) {
            applyPreference(existingIdx, message, key);
            groupCrossMatched = true;
          }
        }
        if (!groupCrossMatched && groupCrossKey.contains(':*:')) {
          final seqSuffix = groupCrossKey.substring(
            groupCrossKey.lastIndexOf(':'),
          );
          final sameSeq = correlationBucketToResultIndexes[
                  'group_seq:${_messageSortSeq(message)}'] ??
              const <int>{};
          for (final i in sameSeq) {
            final existingKey = _groupCrossSourceDedupKey(result[i]);
            if (existingKey == null || !existingKey.endsWith(seqSuffix)) {
              continue;
            }
            if (_groupCrossSourceCorrelate(message, result[i])) {
              applyPreference(i, message, key);
              groupCrossSourceToResultIndex[groupCrossKey] = i;
              if (existingKey != groupCrossKey) {
                groupCrossSourceToResultIndex[existingKey] = i;
              }
              groupCrossMatched = true;
              break;
            }
          }
        }
        if (groupCrossMatched) {
          continue;
        }
      }
      final crossKey = _c2cCrossSourceDedupKey(message);
      if (crossKey != null) {
        final existingIdx = crossSourceToResultIndex[crossKey];
        if (existingIdx != null) {
          final existing = result[existingIdx];
          if (!_areDistinctSdkIdentities(existing, message) &&
              _c2cCrossSourceCorrelate(message, existing)) {
            applyPreference(existingIdx, message, key);
            continue;
          }
        }
      }
      var correlateIdx = -1;
      final candidateIndexes = <int>{};
      for (final bucket in _dedupCorrelationBuckets(message, forLookup: true)) {
        final indexes = correlationBucketToResultIndexes[bucket];
        if (indexes != null) {
          candidateIndexes.addAll(indexes);
        }
      }
      // Missing metadata is covered by identity/local-sequence/path and the
      // explicit preview partitions below. An empty candidate set proves that
      // none of the correlation rules can match; it must never trigger a scan.
      for (final i in candidateIndexes) {
        if (messagesCorrelateForDedup(message, result[i])) {
          correlateIdx = i;
          break;
        }
      }
      if (correlateIdx >= 0) {
        applyPreference(correlateIdx, message, key);
        if (corr != null) {
          correlationToResultIndex[corr] = correlateIdx;
        }
        if (crossKey != null) {
          crossSourceToResultIndex[crossKey] = correlateIdx;
        }
        if (groupCrossKey != null) {
          groupCrossSourceToResultIndex[groupCrossKey] = correlateIdx;
        }
        continue;
      }
      final existingIdx = dedupKeyToResultIndex[key];
      if (existingIdx != null) {
        applyPreference(existingIdx, message, key);
        if (corr != null) {
          correlationToResultIndex[corr] = existingIdx;
        }
        continue;
      }
      final resultIndex = result.length;
      result.add(message);
      dedupKeyToResultIndex[key] = resultIndex;
      indexCorrelationBuckets(message, resultIndex);
      if (corr != null) {
        correlationToResultIndex[corr] = resultIndex;
      }
      if (crossKey != null) {
        crossSourceToResultIndex[crossKey] = resultIndex;
      }
      if (groupCrossKey != null) {
        groupCrossSourceToResultIndex[groupCrossKey] = resultIndex;
      }
    }
    return result;
  }

  static Iterable<String> _dedupCorrelationBuckets(
    V2TimMessage message, {
    bool forLookup = false,
  }) sync* {
    // msgID/id aliases can match even without sender, timestamp or elemType.
    final msgID = message.msgID?.trim() ?? '';
    final localID = message.id?.trim() ?? '';
    if (msgID.isNotEmpty) yield 'identity:$msgID';
    if (localID.isNotEmpty && localID != msgID) yield 'identity:$localID';

    final elemType = message.elemType;
    if (message.isSelf == true) {
      final corr = _outgoingCorrelationKey(message);
      if (corr != null) yield 'outgoing:$corr';
      final localSeq = _readOutgoingLocalSeq(message);
      if (localSeq != null) yield 'outgoing_seq:$localSeq:$elemType';
      if (elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
        final path = message.imageElem?.path?.trim() ?? '';
        if (path.isNotEmpty) yield 'outgoing_path:$path';
      }
    }

    // Correlation uses the raw timestamp for preview equality. Wire identity
    // separately normalizes seconds/milliseconds and can parse missing fields.
    final timestamp = message.timestamp ?? 0;
    if (_isC2cConversationMessage(message)) {
      final crossKey = _c2cCrossSourceDedupKey(message);
      if (crossKey != null) yield 'cross:$crossKey';
      final fingerprint = _messageContentFingerprint(message);
      if (timestamp > 0 && fingerprint != null) {
        final base = 'c2c_preview:$timestamp:$fingerprint';
        final sdk = _isLikelyTencentSdkMsgId(msgID);
        if (forLookup) {
          // Two different SDK IDs cannot correlate through preview content.
          yield '$base:compat';
          if (!sdk) yield '$base:sdk';
        } else {
          yield '$base:${sdk ? 'sdk' : 'compat'}';
        }
      }
      return;
    }

    final seq = _messageSortSeq(message);
    // No elemType in this key: archive↔SDK seq correlation accepts differing
    // payload shapes, including Web SDK rows that have lost their groupID.
    if (seq > 0) yield 'group_seq:$seq';
    if (timestamp <= 0) return;
    final base = 'group_preview:$timestamp:$elemType';
    if (forLookup) {
      if (seq > 0) {
        yield '$base:seq:$seq';
        yield '$base:seq:0';
      } else {
        yield '$base:all';
      }
    } else {
      // Preview/echo rules reject unequal positive seqs. A legacy row without
      // seq may still match either side and searches just its timestamp/type.
      yield '$base:seq:${seq > 0 ? seq : 0}';
      yield '$base:all';
    }
  }

  @visibleForTesting
  static List<V2TimMessage> dedupeMessagesForTesting(
    List<V2TimMessage> messages,
  ) {
    return dedupeMessages(messages);
  }

  static bool _groupPreviewStubCorrelate(V2TimMessage a, V2TimMessage b) {
    if (_isC2cConversationMessage(a) || _isC2cConversationMessage(b)) {
      return false;
    }
    // preview stub 常缺 textElem（指纹为 null）。若不校验 elemType，
    // 同秒「已发出文字」会与「图片 stub/SDK 头」误并，本地气泡从文字变成图片。
    if (a.elemType != b.elemType) {
      return false;
    }
    final tsA = a.timestamp ?? 0;
    final tsB = b.timestamp ?? 0;
    if (tsA <= 0 || tsA != tsB) {
      return false;
    }
    final seqA = _messageSortSeq(a);
    final seqB = _messageSortSeq(b);
    if (seqA > 0 && seqB > 0 && seqA != seqB) {
      return false;
    }
    final randA = _outgoingRandomValue(a);
    final randB = _outgoingRandomValue(b);
    if (randA != null && randB != null && randA != randB) {
      return false;
    }
    if (_isClientPlaceholderMessage(a) && _isClientPlaceholderMessage(b)) {
      final idA = a.id?.trim() ?? '';
      final idB = b.id?.trim() ?? '';
      if (idA.isNotEmpty && idB.isNotEmpty && idA != idB) {
        return false;
      }
    }
    final aSdk = _isLikelyTencentSdkMsgId(a.msgID);
    final bSdk = _isLikelyTencentSdkMsgId(b.msgID);
    final aStub = seqA <= 0 || !aSdk;
    final bStub = seqB <= 0 || !bSdk;
    if (!aStub && !bStub) {
      return false;
    }
    final senderA = a.sender?.trim() ?? '';
    final senderB = b.sender?.trim() ?? '';
    if (senderA.isNotEmpty && senderB.isNotEmpty && senderA != senderB) {
      return false;
    }
    final fpA = _messageContentFingerprint(a);
    final fpB = _messageContentFingerprint(b);
    if (aStub && bStub) {
      // 双 stub 必须内容指纹一致，避免同秒不同消息误并。
      if (fpA == null || fpB == null || fpA != fpB) {
        return false;
      }
      return true;
    }
    // SDK 头 + 会话 preview stub：允许 preview 缺 textElem。
    if (fpA != null && fpB != null && fpA != fpB) {
      return false;
    }
    return true;
  }

  static bool _sameSelfNonC2cEchoCorrelate(V2TimMessage a, V2TimMessage b) {
    if (a.isSelf != true || b.isSelf != true) {
      return false;
    }
    if (_isC2cConversationMessage(a) || _isC2cConversationMessage(b)) {
      return false;
    }
    if (a.elemType != b.elemType) {
      return false;
    }
    final tsA = a.timestamp ?? 0;
    final tsB = b.timestamp ?? 0;
    if (tsA <= 0 || tsA != tsB) {
      return false;
    }
    final seqA = _messageSortSeq(a);
    final seqB = _messageSortSeq(b);
    // 连发相同文案会共享同一秒 timestamp；seq 不同就是不同消息，不能当 echo 合并。
    if (seqA > 0 && seqB > 0 && seqA != seqB) {
      return false;
    }
    final randA = _outgoingRandomValue(a);
    final randB = _outgoingRandomValue(b);
    if (randA != null && randB != null && randA != randB) {
      return false;
    }
    if (_isClientPlaceholderMessage(a) && _isClientPlaceholderMessage(b)) {
      final idA = a.id?.trim() ?? '';
      final idB = b.id?.trim() ?? '';
      if (idA.isNotEmpty && idB.isNotEmpty && idA != idB) {
        return false;
      }
    }
    final fpA = _messageContentFingerprint(a);
    final fpB = _messageContentFingerprint(b);
    if (fpA == null || fpB == null || fpA != fpB) {
      return false;
    }
    final senderA = a.sender?.trim() ?? '';
    final senderB = b.sender?.trim() ?? '';
    if (senderA.isNotEmpty && senderB.isNotEmpty && senderA != senderB) {
      return false;
    }
    return true;
  }

  /// C2C 两条都已是腾讯 SDK msgID 且不相同：就是两条云端消息，禁止再按
  /// random / 文案 / 同秒指纹并掉（连发 `1`/`2`/`3` 会误并整页）。
  /// 群聊不走这条：同 seq 的 SDK/归档副本 msgID 本来就不同。
  static bool _areDistinctSdkIdentities(V2TimMessage a, V2TimMessage b) {
    if (!_isC2cLikeMessage(a) || !_isC2cLikeMessage(b)) {
      return false;
    }
    final aId = a.msgID?.trim() ?? '';
    final bId = b.msgID?.trim() ?? '';
    if (!_isLikelyTencentSdkMsgId(aId) || !_isLikelyTencentSdkMsgId(bId)) {
      return false;
    }
    return aId != bId;
  }

  /// 群聊的正数 seq 是服务端会话内的唯一顺序标识。只要两条消息属于同一群且
  /// seq 不同，就一定是两条不同消息，不能再按同秒、相同发送者或相同内容合并。
  static bool _areDistinctGroupSequences(V2TimMessage a, V2TimMessage b) {
    if (!_isGroupLikeMessage(a) || !_isGroupLikeMessage(b)) {
      return false;
    }
    final seqA = _messageSortSeq(a);
    final seqB = _messageSortSeq(b);
    if (seqA <= 0 || seqB <= 0 || seqA == seqB) {
      return false;
    }
    final groupA = _normalizedGroupIdForMessage(a);
    final groupB = _normalizedGroupIdForMessage(b);
    return groupA.isNotEmpty &&
        groupB.isNotEmpty &&
        _groupIdsEquivalentForDedup(groupA, groupB);
  }

  static bool _groupSeqScopesCompatible(V2TimMessage a, V2TimMessage b) {
    final groupA = _normalizedGroupIdForMessage(a);
    final groupB = _normalizedGroupIdForMessage(b);
    if (groupA.isEmpty || groupB.isEmpty) {
      return true;
    }
    return _groupIdsEquivalentForDedup(groupA, groupB);
  }

  /// Same Seq is a protocol conflict when both group rows carry different
  /// server identities. Preserve both so diagnostics and later authority can
  /// resolve it. The one allowed exception is a proven archive↔SDK copy.
  static bool _areDistinctGroupServerIdentities(
    V2TimMessage a,
    V2TimMessage b,
  ) {
    if (_isC2cConversationMessage(a) || _isC2cConversationMessage(b)) {
      return false;
    }
    final seqA = _messageSortSeq(a);
    final seqB = _messageSortSeq(b);
    if (seqA <= 0 || seqA != seqB) return false;
    final msgIDA = a.msgID?.trim() ?? '';
    final msgIDB = b.msgID?.trim() ?? '';
    if (msgIDA.isEmpty || msgIDB.isEmpty || msgIDA == msgIDB) return false;
    final aArchive = HistoryPaginationAnchor.isArchiveHistoryMessage(a);
    final bArchive = HistoryPaginationAnchor.isArchiveHistoryMessage(b);
    final aSdk = _isLikelyTencentSdkMsgId(msgIDA);
    final bSdk = _isLikelyTencentSdkMsgId(msgIDB);
    if ((aArchive && bSdk) || (bArchive && aSdk)) {
      return false;
    }
    if (!_groupSeqScopesCompatible(a, b)) {
      return true;
    }
    if (a.elemType == b.elemType && aSdk && bSdk) {
      return false;
    }
    final fpA = _messageContentFingerprint(a);
    final fpB = _messageContentFingerprint(b);
    if (a.elemType == b.elemType && fpA != null && fpA == fpB) {
      return false;
    }
    return true;
  }

  static bool messagesCorrelateForDedup(V2TimMessage a, V2TimMessage b) {
    if (_areDistinctSdkIdentities(a, b) ||
        _areDistinctGroupSequences(a, b) ||
        _areDistinctGroupServerIdentities(a, b)) {
      return false;
    }
    final seqA = _messageSortSeq(a);
    final seqB = _messageSortSeq(b);
    if (seqA > 0 &&
        seqA == seqB &&
        !_isC2cConversationMessage(a) &&
        !_isC2cConversationMessage(b) &&
        _groupSeqScopesCompatible(a, b)) {
      if (a.elemType == b.elemType &&
          (_isGroupLikeMessage(a) ||
              _isGroupLikeMessage(b) ||
              (a.isSelf == true && b.isSelf == true))) {
        return true;
      }
    }
    if (_hasGroupSeqOrdering(a) &&
        _hasGroupSeqOrdering(b) &&
        a.elemType == b.elemType &&
        _groupIdsEquivalentForDedup(
          _normalizedGroupIdForMessage(a),
          _normalizedGroupIdForMessage(b),
        ) &&
        seqA == seqB) {
      return true;
    }
    final aMsgID = a.msgID?.trim() ?? '';
    final bMsgID = b.msgID?.trim() ?? '';
    if (aMsgID.isNotEmpty && bMsgID.isNotEmpty && aMsgID == bMsgID) {
      return true;
    }
    final aId = a.id?.trim() ?? '';
    final bId = b.id?.trim() ?? '';
    if (aId.isNotEmpty && bId.isNotEmpty && aId == bId) {
      return true;
    }
    if (aMsgID.isNotEmpty && bId.isNotEmpty && aMsgID == bId) {
      return true;
    }
    if (aId.isNotEmpty && bMsgID.isNotEmpty && aId == bMsgID) {
      return true;
    }
    if (_c2cCrossSourceCorrelate(a, b)) {
      return true;
    }
    if (_groupCrossSourceCorrelate(a, b)) {
      return true;
    }
    if (_c2cPreviewEchoCorrelate(a, b)) {
      return true;
    }
    if (_sameSelfNonC2cEchoCorrelate(a, b)) {
      return true;
    }
    if (_groupPreviewStubCorrelate(a, b)) {
      return true;
    }
    return _outgoingMessagesCorrelate(a, b);
  }

  /// Merge fetched history with any messages upserted while loading.
  ///
  /// 注意：会保留 [existing] 里的全部历史。首屏若要以会话预览窗口为准，
  /// 请用 [mergePeekWindowWithLiveMemory] + [setMessageList] `replace: true`。
  static List<V2TimMessage> mergeHistoricalWithInMemory({
    List<V2TimMessage>? existing,
    required List<V2TimMessage> fetched,
  }) {
    if (existing == null || existing.isEmpty) {
      return sortMessagesNewestFirst(dedupeMessages(fetched));
    }
    return sortMessagesNewestFirst(
      dedupeMessages(<V2TimMessage>[...existing, ...fetched]),
    );
  }

  /// Merge an older SDK page into an already canonical window.  Pagination
  /// normally overlaps the current oldest row, so running dedupe over the
  /// whole window makes every upward swipe increasingly expensive.  Canonical
  /// keys and group seq identities are stable enough to reject that overlap
  /// using indexes; only the fetched page goes through full correlation.
  static List<V2TimMessage> mergeOlderPageIncrementally({
    required List<V2TimMessage> existing,
    required List<V2TimMessage> olderPage,
  }) {
    if (existing.isEmpty) {
      return sortMessagesNewestFirst(dedupeMessages(olderPage));
    }
    if (olderPage.isEmpty) {
      return List<V2TimMessage>.from(existing);
    }
    final result = List<V2TimMessage>.from(existing);
    final keys = <String>{};
    final identities = <String>{};
    final groupSeqCandidates = <String, List<V2TimMessage>>{};
    for (final message in existing) {
      keys.add(messageDedupKey(message));
      final msgId = message.msgID?.trim() ?? '';
      final localId = message.id?.trim() ?? '';
      if (msgId.isNotEmpty) identities.add('m:$msgId');
      if (localId.isNotEmpty) identities.add('i:$localId');
      final seq = _messageSortSeq(message);
      final group = _normalizedGroupIdForMessage(message);
      if (seq > 0 && group.isNotEmpty) {
        groupSeqCandidates
            .putIfAbsent('$group:$seq', () => <V2TimMessage>[])
            .add(message);
      }
    }
    // A page is small (normally 20-50 rows), so its local dedupe remains
    // cheap and preserves all existing preference/correlation rules.
    for (final message in dedupeMessages(olderPage)) {
      final key = messageDedupKey(message);
      final msgId = message.msgID?.trim() ?? '';
      final localId = message.id?.trim() ?? '';
      final seq = _messageSortSeq(message);
      final group = _normalizedGroupIdForMessage(message);
      final sameGroupSeq = seq > 0 && group.isNotEmpty
          ? (groupSeqCandidates['$group:$seq'] ?? const <V2TimMessage>[])
              .any((candidate) => messagesCorrelateForDedup(candidate, message))
          : false;
      final duplicate = keys.contains(key) ||
          (msgId.isNotEmpty && identities.contains('m:$msgId')) ||
          (localId.isNotEmpty && identities.contains('i:$localId')) ||
          sameGroupSeq;
      if (duplicate) {
        continue;
      }
      result.add(message);
      keys.add(key);
      if (msgId.isNotEmpty) identities.add('m:$msgId');
      if (localId.isNotEmpty) identities.add('i:$localId');
      if (seq > 0 && group.isNotEmpty) {
        groupSeqCandidates
            .putIfAbsent('$group:$seq', () => <V2TimMessage>[])
            .add(message);
      }
    }
    return sortMessagesNewestFirst(result);
  }

  /// C2C 官方旧页：只按 msgID 并集。连发相同数字文案不能走 outgoing/指纹去重，
  /// 否则 20 条云端页只会留下 2 条（`----` / `11111`）。
  static List<V2TimMessage> mergeC2cOfficialOlderPage({
    List<V2TimMessage>? existing,
    required List<V2TimMessage> fetched,
  }) {
    final current = existing ?? const <V2TimMessage>[];
    final seenMsgID = <String>{};
    final keyed = <V2TimMessage>[];
    final placeholders = <V2TimMessage>[];
    void ingest(V2TimMessage message) {
      final msgID = message.msgID?.trim() ?? '';
      if (msgID.isNotEmpty) {
        if (seenMsgID.add(msgID)) {
          keyed.add(message);
        }
        return;
      }
      placeholders.add(message);
    }

    for (final message in current) {
      ingest(message);
    }
    for (final message in fetched) {
      ingest(message);
    }
    if (placeholders.isEmpty) {
      return sortMessagesNewestFirst(keyed);
    }
    return sortMessagesNewestFirst(
      dedupeMessages(<V2TimMessage>[...keyed, ...placeholders]),
    );
  }

  /// 进聊合窗时须保留的本地群灰字（勿被 peek 窗口冲掉）。
  /// 成员变动 tip（member_added/removed/left）已换轨 IM GroupTips，不再保留。
  static bool _isPreservedLocalGroupTip(V2TimMessage message) {
    final raw = message.localCustomData?.trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['localGroupTips'] == true) {
          final action =
              decoded['action']?.toString().trim().toLowerCase() ?? '';
          if (action == 'member_added' ||
              action == 'member_removed' ||
              action == 'member_left') {
            return false;
          }
          return true;
        }
      } catch (_) {}
    }
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.startsWith('local_gt_') ||
        msgID.startsWith('ce_') ||
        msgID.startsWith('local_')) {
      return true;
    }
    final id = message.id?.trim() ?? '';
    return id.startsWith('local_gt_') ||
        id.startsWith('ce_') ||
        id.startsWith('local_');
  }

  /// 整表 replace 或分页 merge 时，保留尚未出现在新窗里的在途/刚回执自己消息。
  /// 已对上 id / msgID / stableId / dedup 的占位符不回插（避免 018 双气泡）。
  @visibleForTesting
  static List<V2TimMessage> collectUncorrelatedInFlightOutgoing({
    required List<V2TimMessage> previous,
    required List<V2TimMessage> incoming,
  }) {
    if (previous.isEmpty) {
      return const <V2TimMessage>[];
    }
    final incomingObjects = Set<V2TimMessage>.identity();
    final incomingIds = <String>{};
    final incomingMsgIDs = <String>{};
    final incomingStableIds = <String>{};
    V2TimMessage? newestIncoming;
    for (final message in incoming) {
      incomingObjects.add(message);
      final id = message.id?.trim() ?? '';
      final msgID = message.msgID?.trim() ?? '';
      final stableId = readOutgoingStableId(message)?.trim() ?? '';
      if (id.isNotEmpty) incomingIds.add(id);
      if (msgID.isNotEmpty) incomingMsgIDs.add(msgID);
      if (stableId.isNotEmpty) incomingStableIds.add(stableId);
      if (newestIncoming == null ||
          compareMessagesChronological(message, newestIncoming) > 0) {
        newestIncoming = message;
      }
    }

    bool coveredByIncoming(V2TimMessage candidate) {
      final candidateId = candidate.id?.trim() ?? '';
      final candidateMsgID = candidate.msgID?.trim() ?? '';
      final candidateStable = readOutgoingStableId(candidate)?.trim() ?? '';
      // These are the same independent identity checks as the old scan.
      // Cross-field aliases must still pass the correlation guards below.
      if ((candidateId.isNotEmpty && incomingIds.contains(candidateId)) ||
          (candidateMsgID.isNotEmpty &&
              incomingMsgIDs.contains(candidateMsgID)) ||
          (candidateStable.isNotEmpty &&
              incomingStableIds.contains(candidateStable))) {
        return true;
      }
      // Anonymous malformed rows need not correlate even with themselves.
      // Keep that compatibility behavior rather than inferring new identity.
      if (incomingObjects.contains(candidate) &&
          messagesCorrelateForDedup(candidate, candidate)) {
        return true;
      }
      // Only eligible outgoing rows without an exact match need the legacy
      // cross-source/placeholder correlation scan.
      for (final row in incoming) {
        if (messagesCorrelateForDedup(candidate, row)) {
          return true;
        }
      }
      return false;
    }

    final extras = <V2TimMessage>[];
    for (final message in previous) {
      if (message.isSelf != true ||
          !_shouldKeepUncorrelatedOutgoing(message, newestIncoming)) {
        continue;
      }
      if (!coveredByIncoming(message)) {
        extras.add(message);
      }
    }
    return extras;
  }

  /// 未被新窗关联的自己消息：在途必留；已成功则留下「比窗新」或本会话刚发出的行。
  ///
  /// 发图 upload 回执时间戳常晚于紧跟着发出的文字。只按 chronological > newest
  /// 会把这条 SEND_SUCC 文字当旧历史丢掉，对端却已收到。
  static bool _shouldKeepUncorrelatedOutgoing(
    V2TimMessage message,
    V2TimMessage? newestIncoming,
  ) {
    if (message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING ||
        _isLiveOutgoingPlaceholder(message)) {
      return true;
    }
    if (message.status != MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
      return false;
    }
    if (newestIncoming != null &&
        compareMessagesChronological(message, newestIncoming) > 0) {
      return true;
    }
    if (_readOutgoingLocalSeq(message) == null) {
      return false;
    }
    if (newestIncoming == null) {
      return true;
    }
    if (compareMessagesChronological(message, newestIncoming) >= 0) {
      return true;
    }
    const maxLagSec = 120;
    final newestTs = newestIncoming.timestamp ?? 0;
    final messageTs = message.timestamp ?? 0;
    if (newestTs > 0 && messageTs > 0 && newestTs - messageTs <= maxLagSec) {
      return true;
    }
    final sentAt = _readOutgoingLocalSentAt(message);
    if (sentAt == null) {
      return false;
    }
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSec >= sentAt && nowSec - sentAt <= maxLagSec;
  }

  /// 把 [collectUncorrelatedInFlightOutgoing] 的 extras 插回 newest 端并去重。
  /// 用于分页 merge、内存窗 trim 之后，避免已回执自己消息被旧页/120 窗裁掉。
  @visibleForTesting
  static List<V2TimMessage> restoreUncorrelatedInFlightOutgoing({
    required List<V2TimMessage> previous,
    required List<V2TimMessage> incoming,
  }) {
    final extras = collectUncorrelatedInFlightOutgoing(
      previous: previous,
      incoming: incoming,
    );
    if (extras.isEmpty) {
      return incoming;
    }
    return sortMessagesNewestFirst(
      dedupeMessages(<V2TimMessage>[...extras, ...incoming]),
    );
  }

  /// 以 peek 窗补齐实时/在途消息；不得驱逐后端归档历史（含窗外独有补洞）。
  /// 历史冲突以后端归档为 SoT，由最终 [dedupeMessages] prefer 收敛。
  static List<V2TimMessage> mergePeekWindowWithLiveMemory({
    List<V2TimMessage>? existing,
    required List<V2TimMessage> fetched,
  }) {
    final window = dedupeMessages(fetched);
    if (existing == null || existing.isEmpty) {
      return sortMessagesNewestFirst(window);
    }
    if (window.isEmpty) {
      return sortMessagesNewestFirst(dedupeMessages(existing));
    }

    V2TimMessage? newestInWindow;
    for (final message in window) {
      if (newestInWindow == null ||
          compareMessagesChronological(message, newestInWindow) > 0) {
        newestInWindow = message;
      }
    }

    final live = <V2TimMessage>[];
    var retainedArchiveCount = 0;
    for (final message in existing) {
      // 后端归档（含校对补洞）：一律保留，禁止 SDK peek 窗整表冲掉后再靠校对灌回。
      if (HistoryPaginationAnchor.isArchiveHistoryMessage(message)) {
        live.add(message);
        retainedArchiveCount++;
        continue;
      }
      final coveredByWindow = window.any(
        (windowMessage) => messagesCorrelateForDedup(message, windowMessage),
      );
      if (coveredByWindow) {
        continue;
      }
      if (_isPreservedLocalGroupTip(message)) {
        live.add(message);
        continue;
      }
      final sending = message.isSelf == true &&
          (message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING ||
              _isLiveOutgoingPlaceholder(message));
      if (sending) {
        live.add(message);
        continue;
      }
      if (newestInWindow != null &&
          compareMessagesChronological(message, newestInWindow) > 0) {
        live.add(message);
      }
    }

    final merged = restoreUncorrelatedInFlightOutgoing(
      previous: existing,
      incoming: sortMessagesNewestFirst(
        dedupeMessages(<V2TimMessage>[...window, ...live]),
      ),
    );
    if (OutgoingVisibleProbe.matches(OutgoingVisibleProbe.lastConvID) ||
        existing.any(OutgoingVisibleProbe.matchesMessage) ||
        fetched.any(OutgoingVisibleProbe.matchesMessage)) {
      final droppedSelf = existing.where((message) {
        if (message.isSelf != true) {
          return false;
        }
        return !merged.any(
          (kept) =>
              ((message.id?.trim() ?? '').isNotEmpty &&
                  kept.id?.trim() == message.id?.trim()) ||
              ((message.msgID?.trim() ?? '').isNotEmpty &&
                  kept.msgID?.trim() == message.msgID?.trim()),
        );
      }).toList(growable: false);
      OutgoingVisibleProbe.log(
        'peek_merge_live',
        extras: <String, Object?>{
          'existingCount': existing.length,
          'fetchedCount': fetched.length,
          'liveKept': live.length,
          'mergedCount': merged.length,
          'droppedSelfCount': droppedSelf.length,
          'droppedSelf':
              droppedSelf.map(OutgoingVisibleProbe.brief).join(' || '),
          'existingTracked': OutgoingVisibleProbe.trackedInList(
            existing,
          ).toString(),
          'fetchedTracked': OutgoingVisibleProbe.trackedInList(
            fetched,
          ).toString(),
          'mergedTracked': OutgoingVisibleProbe.trackedInList(
            merged,
          ).toString(),
        },
      );
    }
    if (retainedArchiveCount > 0) {
      ChatHistoryTrace.log(
        'peek_merge_retained_archive',
        extras: <String, Object?>{
          'retainedArchiveCount': retainedArchiveCount,
          'windowCount': window.length,
          'mergedCount': merged.length,
        },
      );
    }
    return merged;
  }

  static List<V2TimMessage> sortMessagesNewestFirst(
    List<V2TimMessage> messages,
  ) {
    final result = List<V2TimMessage>.from(messages);
    // Writer snapshots and restored windows are usually already ordered.
    // Keep returning an independent list; only skip the redundant sort.
    for (var i = 1; i < result.length; i++) {
      if (compareMessagesChronological(result[i], result[i - 1]) > 0) {
        result.sort((a, b) => compareMessagesChronological(b, a));
        break;
      }
    }
    return result;
  }

  static List<V2TimMessage> _mergePendingIncomingForDedup({
    required List<V2TimMessage> pending,
    required List<V2TimMessage> existing,
  }) {
    return sortMessagesNewestFirst(
      dedupeMessages(<V2TimMessage>[...pending, ...existing]),
    );
  }

  @visibleForTesting
  static List<V2TimMessage> appendDistinctIncomingBatchForTesting({
    required List<V2TimMessage> existing,
    required List<V2TimMessage> incoming,
  }) {
    return _mergePendingIncomingForDedup(pending: incoming, existing: existing);
  }

  @visibleForTesting
  static List<V2TimMessage> filterHiddenProjectionForTesting({
    required Iterable<V2TimMessage> authoritativeMessages,
    required Set<String> hiddenKeys,
  }) {
    final messages = authoritativeMessages.toList(growable: false);
    V2TimMessage? newestVisible;
    for (final message in messages) {
      if (!hiddenKeys.contains(messageDedupKey(message)) &&
          (newestVisible == null ||
              compareMessagesChronological(message, newestVisible) > 0)) {
        newestVisible = message;
      }
    }
    // Pacing may defer the newest tail, but must never punch a hole inside
    // the visible window. A later realtime/self message or history commit can
    // overtake a queued reveal. Expose the intervening rows immediately,
    // using the same group-seq / C2C ordering as the displayed list.
    final boundary = newestVisible;
    return messages
        .where((message) =>
            !hiddenKeys.contains(messageDedupKey(message)) ||
            (boundary != null &&
                compareMessagesChronological(message, boundary) <= 0))
        .toList(growable: false);
  }

  /// Publishes a small realtime batch without rebuilding the entire history
  /// window. Callers must use this only for strictly newer, non destructive
  /// messages; all history/reorder/delete paths continue through setMessageList.
  MessageCommitResult appendRealtimeMessages(
    String conversationID,
    List<V2TimMessage> incoming,
  ) {
    final key = canonicalHistoryStorageKey(conversationID).isNotEmpty
        ? canonicalHistoryStorageKey(conversationID)
        : conversationID.trim();
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: key,
        eventID:
            'realtime:public:${++_nextRealtimeReconciliationEvent}:${incoming.map(messageDedupKey).join(',')}',
        kind: MessageDeltaKind.realtimeUpsert,
        source: MessageDeltaSource.sdkRealtime,
        generation: messageDeltaGenerationFor(key),
        clearEpoch: messageDeltaClearEpochFor(key),
        upserts: _reconciliationRecords(incoming),
      ),
    );
    if (commit != null) {
      if (commit.contentChanged) {
        _bumpMessageListRevisionFor(
          key,
          reason: 'public_realtime_writer_append',
        );
        _markNeedsNotify(conversationID: key);
      }
      return commit;
    }
    final current = _mergedAliasMessageList(key);
    return _messageCommitSnapshot(
      conversationID: key,
      storageKey: key,
      list: current,
      structureChanged: false,
      contentChanged: false,
      recordCommit: false,
    );
  }

  /// Feed rows read an existing window without creating a chat projection,
  /// sorting history, adding dividers, or allocating cache rows for cold chats.
  V2TimMessage? getConversationPreviewMessage(String conversationID) {
    final key = canonicalHistoryStorageKey(conversationID);
    final displayed = _messageListDisplayCache[key];
    final raw = _messageListMap[key] ??
        _messageListMap[conversationID] ??
        _messageListMap[_normalizeConversationID(conversationID)];
    if (displayed == null && (raw == null || raw.isEmpty)) return null;
    // A custom list transform is authoritative. Until the chat has built that
    // projection, retain the SDK conversation preview instead of guessing.
    if (displayed == null && _lifeCycle?.messageListShouldMount != null) {
      return null;
    }
    final hidden = _inboundHiddenKeysByConv[_inboundStateKey(conversationID)];
    V2TimMessage? newest;
    for (final message in displayed ?? raw!) {
      if (message.elemType == 0 ||
          message.elemType == 11 ||
          message.elemType == 101) continue;
      if (displayed == null &&
          ((hidden?.contains(messageDedupKey(message)) ?? false) ||
              !(_lifeCycle?.messageShouldMount(message) ?? true))) continue;
      if (newest == null || compareMessagesChronological(message, newest) > 0) {
        newest = message;
      }
    }
    return newest;
  }

  List<V2TimMessage>? getMessageList(String conversationID) {
    // Every caller must share one display-cache row. During startup the
    // conversation feed can pass both `c2c_<uid>` and the bare uid (and group
    // callers can pass both `group_<id>` and the bare group id); looking up
    // the cache with the raw argument creates duplicate projections and makes
    // scrolling rebuild the same visible list repeatedly.
    final displayKey = canonicalHistoryStorageKey(conversationID).isNotEmpty
        ? canonicalHistoryStorageKey(conversationID)
        : conversationID.trim();
    final cached = _messageListDisplayCache[displayKey];
    if (cached != null) {
      return cached;
    }
    final convKey = _inboundStateKey(conversationID);
    final hidden = _inboundHiddenKeysByConv[convKey];
    final authoritative = _collectAuthoritativeMessages(conversationID);
    // The Writer window is already newest-first. Hidden reveal rows may only
    // defer a newest prefix; never leave a hole behind a newer visible row.
    V2TimMessage? revealBoundary;
    if (hidden?.isNotEmpty == true) {
      for (final message in authoritative) {
        if (!hidden!.contains(messageDedupKey(message))) {
          revealBoundary = message;
          break;
        }
      }
    }
    final visible = <V2TimMessage>[];
    for (final message in authoritative.reversed) {
      if (hidden?.contains(messageDedupKey(message)) == true &&
          (revealBoundary == null ||
              compareMessagesChronological(message, revealBoundary) > 0))
        continue;
      if (_lifeCycle?.messageShouldMount(message) ?? true) visible.add(message);
    }
    final mounted = _lifeCycle?.messageListShouldMount(visible) ?? visible;
    // Business transforms may reorder rows; ordinary SDK windows need neither
    // a second sort nor a copied list for every projection rebuild.
    List<V2TimMessage> chronological = mounted;
    if (_lifeCycle?.messageListShouldMount != null ||
        _lifeCycle?.messageShouldMount != null) {
      for (var i = 1; i < mounted.length; i++) {
        if (compareMessagesChronological(mounted[i - 1], mounted[i]) > 0) {
          chronological = List<V2TimMessage>.from(mounted)
            ..sort(compareMessagesChronological);
          break;
        }
      }
    }
    final interval = chatConfig.timeDividerConfig?.timeInterval ?? 300;
    final result = _ReversedMessageList(
        attachTimeDividersForTesting(chronological, intervalSeconds: interval));
    ChatMainThreadPerf.increment('message_display_projection_built');
    _messageListDisplayCache[displayKey] = result;
    return result;
  }

  /// 无可见行高的消息不参与时间分割线锚点（否则会留下孤儿分割线）。
  @visibleForTesting
  static bool messageAnchorsTimeDivider(V2TimMessage message) {
    if (message.elemType == 11 || message.elemType == 101) {
      return false;
    }
    // 与列表 item 一致：空群 tip 渲染为 SizedBox.shrink。
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS &&
        message.groupTipsElem == null) {
      return false;
    }
    return true;
  }

  /// 按时间升序插入分割线，并去掉「后面没有真实消息」的孤儿分割线。
  @visibleForTesting
  static List<V2TimMessage> attachTimeDividersForTesting(
    List<V2TimMessage> chronologicalAsc, {
    int intervalSeconds = 300,
  }) => attachTimeDividers(chronologicalAsc, intervalSeconds: intervalSeconds);

  /// Shared divider layout for the SDK window and its business overlays.
  static List<V2TimMessage> attachTimeDividers(
    List<V2TimMessage> chronologicalAsc, {
    int intervalSeconds = 300,
  }) {
    final listWithTimestamp = <V2TimMessage>[];
    for (final item in chronologicalAsc) {
      if (!messageAnchorsTimeDivider(item)) {
        continue;
      }
      final lastAnchor = _lastTimeDividerAnchor(listWithTimestamp);
      final crossesCalendarDay = lastAnchor?.timestamp != null &&
          item.timestamp != null &&
          _isDifferentCalendarDay(lastAnchor!.timestamp!, item.timestamp!);
      final shouldInsertDivider = listWithTimestamp.isEmpty ||
          crossesCalendarDay ||
          (lastAnchor?.timestamp != null &&
              item.timestamp != null &&
              item.timestamp! - lastAnchor!.timestamp! > intervalSeconds);
      if (shouldInsertDivider) {
        listWithTimestamp.add(_buildTimeDividerMessage(item.timestamp));
      }
      listWithTimestamp.add(item);
    }
    return listWithTimestamp;
  }

  static bool _isDifferentCalendarDay(int firstTimestamp, int secondTimestamp) {
    final first = DateTime.fromMillisecondsSinceEpoch(firstTimestamp * 1000);
    final second = DateTime.fromMillisecondsSinceEpoch(secondTimestamp * 1000);
    return first.year != second.year ||
        first.month != second.month ||
        first.day != second.day;
  }

  static V2TimMessage _buildTimeDividerMessage(int? timestamp) {
    final ts = timestamp ?? 0;
    final message = V2TimMessage.fromJson(<String, dynamic>{
      'message_server_time': ts,
      'message_msg_id': 'time-divider-$ts',
      'message_is_from_self': false,
      'message_custom_str': '',
      'message_risk_type_identified': 0,
      'message_sender_group_member_info': <String, dynamic>{},
      'message_group_at_user_array': <String>[],
      'elem_type': 11,
    });
    message.elemType = 11;
    message.timestamp = ts;
    message.msgID = 'time-divider-$ts';
    message.isSelf = false;
    message.userID = '';
    return message;
  }

  static V2TimMessage? _lastTimeDividerAnchor(List<V2TimMessage> list) {
    for (var i = list.length - 1; i >= 0; i--) {
      if (messageAnchorsTimeDivider(list[i])) {
        return list[i];
      }
    }
    return null;
  }

  /// 时间升序列表：去掉连续分割线，以及末尾无真实消息的分割线。
  @visibleForTesting
  static List<V2TimMessage> stripOrphanTimeDividersForTesting(
    List<V2TimMessage> chronologicalAsc,
  ) {
    final out = <V2TimMessage>[];
    for (var i = 0; i < chronologicalAsc.length; i++) {
      final item = chronologicalAsc[i];
      if (item.elemType == 11) {
        final next =
            i + 1 < chronologicalAsc.length ? chronologicalAsc[i + 1] : null;
        if (next == null || next.elemType == 11 || next.elemType == 101) {
          continue;
        }
        if (out.isNotEmpty && out.last.elemType == 11) {
          continue;
        }
        out.add(item);
        continue;
      }
      out.add(item);
    }
    return out;
  }

  bool get isMediaPreviewOverlayOpen => _isMediaPreviewOverlayOpen;

  /// 全屏媒体预览打开中 / 关闭后滚动恢复中：聊天列表应禁用手势滚动。
  bool get shouldLockChatScrollForMediaPreview =>
      _isMediaPreviewOverlayOpen || isRestoringScrollAfterMediaPreview;

  bool get isWalletOverlayOpen => _walletOverlayDepth > 0;

  int _mediaPickerOverlayDepth = 0;
  final Map<String, bool> _pendingPinAfterPickerByConv = <String, bool>{};

  /// 长按消息菜单 / tooltip 打开期间禁止列表上推，新消息先缓冲。
  int _messageContextMenuOverlayDepth = 0;
  int _messageContextMenuTransactionGeneration = 0;
  final Set<String> _contextMenuViewportRestoreConversations = <String>{};
  final Map<String, MessageContextMenuViewportAnchor>
      _contextMenuViewportAnchors =
      <String, MessageContextMenuViewportAnchor>{};
  final Map<String, Timer> _contextMenuViewportRestoreTimers =
      <String, Timer>{};
  int _pinToBottomRequestSeq = 0;
  String? _pinToBottomRequestConvId;
  bool _pinToBottomForce = false;
  bool _pinToBottomImmediate = false;
  final Set<String> _pendingImmediatePinByConv = <String>{};
  // A return-to-bottom action is asynchronous (history reload, layout and
  // animation). Keep the routing gate alive until the caller explicitly ends
  // the transaction; the timestamp remains only as a stale-call fallback.
  bool _userScrollToBottomTransactionActive = false;
  String? _userScrollToBottomConvId;
  int _userScrollToBottomUntilMs = 0;

  /// list-push / viewport insert 期间会短暂离开 minScrollExtent；此锁防止
  /// 「回到底部」胶囊被误判点亮后又熄灭。
  String? _inboundViewportPushConvId;
  int _inboundViewportPushUntilMs = 0;

  /// 首屏 hydrate / 第一次贴底完成前，禁止点亮「回到底部」。
  String? _openBottomCapsuleLockConvId;
  int _openBottomCapsuleLockUntilMs = 0;
  bool _openBottomCapsuleHydrateSettled = false;
  bool _openBottomCapsuleFirstPinSettled = false;

  bool get isMediaPickerOverlayOpen => _mediaPickerOverlayDepth > 0;

  bool get isMessageContextMenuOverlayOpen =>
      _messageContextMenuOverlayDepth > 0;

  int get messageContextMenuTransactionGeneration =>
      _messageContextMenuTransactionGeneration;

  bool isContextMenuViewportRestoreActive(String? conversationID) {
    final convId = _safeConversationId(conversationID);
    return convId.isNotEmpty &&
        _contextMenuViewportRestoreConversations.contains(convId);
  }

  MessageContextMenuViewportAnchor? contextMenuViewportAnchorFor(
    String? conversationID,
  ) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty ||
        !_contextMenuViewportRestoreConversations.contains(convId)) {
      return null;
    }
    return _contextMenuViewportAnchors[convId];
  }

  /// Called by the list after it has restored the selected row, or when the
  /// row is no longer mounted. This also releases the physics gate.
  void completeContextMenuViewportRestore(String? conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    _contextMenuViewportRestoreConversations.remove(convId);
    _contextMenuViewportAnchors.remove(convId);
    _contextMenuViewportRestoreTimers.remove(convId)?.cancel();
    _markNeedsNotify();
  }

  int get pinToBottomRequestSeq => _pinToBottomRequestSeq;

  String? get pinToBottomRequestConvId => _pinToBottomRequestConvId;

  bool get pinToBottomForce => _pinToBottomForce;
  bool get pinToBottomImmediate => _pinToBottomImmediate;

  void beginUserScrollToBottom(
    String conversationID, {
    int lockMilliseconds = 700,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    _userScrollToBottomTransactionActive = true;
    final nextUntil = DateTime.now().millisecondsSinceEpoch + lockMilliseconds;
    if (_userScrollToBottomConvId == convId &&
        _userScrollToBottomUntilMs >= nextUntil) {
      return;
    }
    _userScrollToBottomConvId = convId;
    _userScrollToBottomUntilMs = nextUntil;
  }

  bool isUserScrollToBottomInProgress(String? conversationID) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty || _userScrollToBottomConvId != convId) {
      return false;
    }
    return _userScrollToBottomTransactionActive ||
        DateTime.now().millisecondsSinceEpoch < _userScrollToBottomUntilMs;
  }

  void beginInboundViewportPush(
    String conversationID, {
    int lockMilliseconds = 1200,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    final nextUntil = DateTime.now().millisecondsSinceEpoch + lockMilliseconds;
    if (_inboundViewportPushConvId == convId &&
        _inboundViewportPushUntilMs >= nextUntil) {
      return;
    }
    _inboundViewportPushConvId = convId;
    _inboundViewportPushUntilMs = nextUntil;
  }

  void endInboundViewportPush(
    String conversationID, {
    int settleMilliseconds = 320,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty || _inboundViewportPushConvId != convId) {
      return;
    }
    _inboundViewportPushUntilMs =
        DateTime.now().millisecondsSinceEpoch + settleMilliseconds;
  }

  bool isInboundViewportPushActive(String? conversationID) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty || _inboundViewportPushConvId != convId) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch < _inboundViewportPushUntilMs;
  }

  static const int _openBottomCapsuleLockMs = 1800;
  static const int _openBottomCapsuleSettleMs = 160;

  /// 普通进会话：首屏 hydrate 与第一次贴底完成前，右下角「回到底部」不得亮。
  void beginOpenChatBottomCapsuleLock(
    String conversationID, {
    int lockMilliseconds = _openBottomCapsuleLockMs,
  }) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty) {
      return;
    }
    _openBottomCapsuleLockConvId = convId;
    _openBottomCapsuleLockUntilMs =
        DateTime.now().millisecondsSinceEpoch + lockMilliseconds;
    _openBottomCapsuleHydrateSettled = !hasOpenHydrateInFlight(convId);
    _openBottomCapsuleFirstPinSettled = false;
  }

  void markOpenChatHydrateSettled(String conversationID) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty ||
        !_isSameConversationID(_openBottomCapsuleLockConvId, convId)) {
      return;
    }
    _openBottomCapsuleHydrateSettled = true;
    _tryReleaseOpenChatBottomCapsuleLock();
  }

  void markOpenChatFirstPinSettled(String conversationID) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty ||
        !_isSameConversationID(_openBottomCapsuleLockConvId, convId)) {
      return;
    }
    _openBottomCapsuleFirstPinSettled = true;
    _tryReleaseOpenChatBottomCapsuleLock();
  }

  void clearOpenChatBottomCapsuleLock(String conversationID) {
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty ||
        !_isSameConversationID(_openBottomCapsuleLockConvId, convId)) {
      return;
    }
    _openBottomCapsuleLockConvId = null;
    _openBottomCapsuleLockUntilMs = 0;
    _openBottomCapsuleHydrateSettled = false;
    _openBottomCapsuleFirstPinSettled = false;
  }

  void _tryReleaseOpenChatBottomCapsuleLock() {
    final convId = _openBottomCapsuleLockConvId;
    if (convId == null || convId.isEmpty) {
      return;
    }
    if (!_openBottomCapsuleHydrateSettled ||
        !_openBottomCapsuleFirstPinSettled) {
      return;
    }
    _openBottomCapsuleLockUntilMs =
        DateTime.now().millisecondsSinceEpoch + _openBottomCapsuleSettleMs;
  }

  bool isOpenChatBottomCapsuleLocked(String? conversationID) {
    if (isChatListUserScrolling) {
      return false;
    }
    final convId = _inboundStateKey(conversationID);
    if (convId.isEmpty ||
        !_isSameConversationID(_openBottomCapsuleLockConvId, convId)) {
      return false;
    }
    if (!isFollowingLatest(convId) &&
        (getMessageListPosition(convId) != HistoryMessagePosition.bottom ||
            receivedNewMessageCountFor(convId) > 0)) {
      return false;
    }
    if (isSearchJumpPending(convId)) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch <
        _openBottomCapsuleLockUntilMs;
  }

  void endUserScrollToBottom(String conversationID) {
    final convId = _inboundStateKey(conversationID);
    if (_userScrollToBottomConvId != convId) {
      return;
    }
    _userScrollToBottomConvId = null;
    _userScrollToBottomTransactionActive = false;
    _userScrollToBottomUntilMs = 0;
    // Visible receipts sampled during the return were gated. Wake the list
    // after releasing that gate even when the final pixels did not move.
    _markNeedsNotify();
  }

  void requestPinToBottom(String conversationID, {bool force = false, bool immediate = false}) {
    if (isSearchJumpPending(conversationID)) return;
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    if (immediate) {
      force = true;
      _pendingImmediatePinByConv.add(convId);
    }
    // Do not publish a sequence that the covered list can consume and drop.
    // Coalesce the batch and replay after the outermost picker has closed.
    if (isMediaPickerOverlayOpen) {
      _pendingPinAfterPickerByConv[convId] =
          force || (_pendingPinAfterPickerByConv[convId] ?? false);
      return;
    }
    ChatHistoryTrace.log(
      'pin_to_bottom_requested',
      conversationID: convId,
      extras: <String, Object?>{
        'force': force,
        'position': getMessageListPosition(convId).name,
        'readingHistory': isReadingHistory(convId),
        'memorySuppressed': isMemoryWindowSuppressed(convId),
        'bulkSync': isBulkMessageSyncActive(convId),
        'chunkedReveal': isChunkedRevealActive(convId),
      },
    );
    ChatJitterDiag.logFollowingLatest(
      action: 'pin_requested',
      conv: convId,
      extras: <String, Object?>{
        'force': force,
        ...stickToLatestDiagSnapshot(convId),
      },
    );
    if (isBulkMessageSyncActive(convId) || isChunkedRevealActive(convId)) {
      _pendingPinAfterBulkByConv[convId] =
          force || (_pendingPinAfterBulkByConv[convId] ?? false);
      return;
    }
    _pinToBottomRequestConvId = convId;
    _pinToBottomForce = force;
    _pinToBottomImmediate = _pendingImmediatePinByConv.remove(convId);
    _pinToBottomRequestSeq++;
    _markNeedsNotify();
  }

  void beginMediaPickerOverlay() {
    _mediaPickerOverlayDepth++;
  }

  void endMediaPickerOverlay() {
    final wasOpen = _mediaPickerOverlayDepth > 0;
    if (_mediaPickerOverlayDepth > 0) {
      _mediaPickerOverlayDepth--;
    }
    if (wasOpen && _mediaPickerOverlayDepth == 0) {
      // 系统/自定义相册覆盖聊天页期间，底层列表不可能仍由用户拖动。
      // 某些平台关闭 picker 时不会补发此前被打断的 ScrollEnd，若保留
      // scrolling=true，随后发送图片的 force-pin 会被当成手势冲突而取消。
      setChatListUserScrolling(false);
      final convId = _safeConversationId(currentSelectedConv);
      bool? pendingForce;
      var pendingImmediate = false;
      for (final entry in _pendingPinAfterPickerByConv.entries) {
        final immediate = _pendingImmediatePinByConv.remove(entry.key);
        if (convId.isNotEmpty && _isSameConversationID(convId, entry.key)) {
          pendingForce = entry.value || (pendingForce ?? false);
          pendingImmediate = pendingImmediate || immediate;
        }
      }
      _pendingPinAfterPickerByConv.clear();
      // A detached sender may finish in another conversation. Never move the
      // newly opened conversation on behalf of that old send.
      if (pendingForce != null) {
        requestPinToBottom(convId, force: pendingForce, immediate: pendingImmediate);
      }
      _markNeedsNotify();
    }
  }

  void beginMessageContextMenuOverlay({
    String? conversationID,
    String? anchorMessageID,
    String? anchorSeq,
    double? anchorViewportTop,
  }) {
    if (_messageContextMenuOverlayDepth == 0) {
      _messageContextMenuTransactionGeneration++;
    }
    final convId = _safeConversationId(conversationID ?? currentSelectedConv);
    if (_messageContextMenuOverlayDepth == 0 && convId.isNotEmpty) {
      _contextMenuViewportRestoreConversations.remove(convId);
      _contextMenuViewportAnchors.remove(convId);
      _contextMenuViewportRestoreTimers.remove(convId)?.cancel();
      _syncHistoryPositionFromActiveScroll(convId);
      final identity = anchorMessageID?.trim();
      final seq = anchorSeq?.trim();
      if (((identity?.isNotEmpty ?? false) || (seq?.isNotEmpty ?? false)) &&
          anchorViewportTop != null &&
          anchorViewportTop.isFinite) {
        _contextMenuViewportAnchors[convId] = MessageContextMenuViewportAnchor(
          identity: identity,
          seq: seq?.isNotEmpty == true ? seq : null,
          viewportTop: anchorViewportTop,
        );
      }
    }
    _messageContextMenuOverlayDepth++;
    _markNeedsNotify();
  }

  final List<VoidCallback> _contextMenuOverlayDismissers = <VoidCallback>[];

  void registerContextMenuOverlayDismisser(VoidCallback dismiss) {
    // There is only one context menu in the app. Keeping callbacks from every
    // mounted message row caused dismissAllContextMenuOverlays to broadcast
    // closeTooltip to the entire list, triggering hundreds of stale cleanup
    // calls and unnecessary rebuilds. Replace the previous owner atomically.
    _contextMenuOverlayDismissers
      ..clear()
      ..add(dismiss);
  }

  void unregisterContextMenuOverlayDismisser(VoidCallback dismiss) {
    _contextMenuOverlayDismissers.remove(dismiss);
  }

  /// 路由离栈 / 聊天 dispose 时强制移除 root 长按菜单 Overlay，并重置 depth。
  void dismissAllContextMenuOverlays() {
    final pending = List<VoidCallback>.from(_contextMenuOverlayDismissers);
    for (final dismiss in pending) {
      try {
        dismiss();
      } catch (_) {}
    }
    _contextMenuOverlayDismissers.clear();
    // A dismisser normally calls endMessageContextMenuOverlay first, which
    // reduces depth to zero and starts viewport restoration. Route teardown
    // must clear that newly-created restore transaction as well, so cleanup
    // cannot be conditional on depth still being positive here.
    _messageContextMenuOverlayDepth = 0;
    _contextMenuViewportRestoreConversations.clear();
    _contextMenuViewportAnchors.clear();
    for (final timer in _contextMenuViewportRestoreTimers.values) {
      timer.cancel();
    }
    _contextMenuViewportRestoreTimers.clear();
    // A long press can win while a scroll gesture is being cancelled. Flutter
    // does not guarantee a later ScrollEndNotification for that cancelled
    // gesture, so never carry the scrolling latch past overlay teardown.
    setChatListUserScrolling(false);
    _markNeedsNotify();
  }

  void endMessageContextMenuOverlay({String? conversationID}) {
    final wasOpen = _messageContextMenuOverlayDepth > 0;
    if (_messageContextMenuOverlayDepth > 0) {
      _messageContextMenuOverlayDepth--;
    }
    if (!wasOpen || _messageContextMenuOverlayDepth > 0) {
      return;
    }
    // The overlay absorbed/cancelled the pointer sequence. Clear a stale
    // scrolling latch before rebuilding physics, otherwise automatic scroll
    // coordination may continue treating the list as gesture-owned.
    setChatListUserScrolling(false);
    _messageContextMenuTransactionGeneration++;
    final convId = _safeConversationId(conversationID ?? currentSelectedConv);
    if (convId.isNotEmpty) {
      _contextMenuViewportRestoreConversations.add(convId);
      // Closing a context menu must not also be a "return to latest" action.
      // Flushing here combines a newest-edge insert with the overlay removal;
      // on a reverse, virtualized list that can evict the selected row before
      // its viewport anchor is measured. Keep these rows in the unread queue
      // until the user explicitly returns to bottom or taps the unread tongue.
      _markNeedsNotify();
      _contextMenuViewportRestoreTimers[convId]?.cancel();
      // Watchdog only. Normal completion is reported by the list after the
      // identity anchor is geometrically stable for consecutive frames.
      _contextMenuViewportRestoreTimers[convId] = Timer(
        const Duration(seconds: 5),
        () => completeContextMenuViewportRestore(convId),
      );
    } else {
      _markNeedsNotify();
    }
  }

  void beginWalletOverlay({String? conversationID, String? anchorMessageID}) {
    _walletOverlayDepth++;
    saveScrollBeforeRouteOverlay(
      conversationID,
      anchorMessageID: anchorMessageID,
      lockMilliseconds: 1200,
    );
  }

  void endWalletOverlay({String? conversationID}) {
    if (_walletOverlayDepth > 0) {
      _walletOverlayDepth--;
    }
    restoreScrollAfterRouteOverlay(conversationID, lockMilliseconds: 900);
  }

  ScrollController? _activeChatScrollControllerFor(String convId) {
    final exact = _activeChatScrollControllerMap[convId];
    if (exact != null) {
      return exact;
    }
    for (final entry in _activeChatScrollControllerMap.entries) {
      if (_isSameConversationID(entry.key, convId)) {
        return entry.value;
      }
    }
    return null;
  }

  bool _desktopShouldRemainFollowing(String convId) {
    if (isSearchJumpPending(convId)) {
      return false;
    }
    if (isChatListUserScrolling) {
      return false;
    }
    if (isHistoryReadingWindowActive(convId)) {
      return false;
    }
    final controller = _activeChatScrollControllerFor(convId);
    final position =
        controller == null ? null : _singleScrollPositionOrNull(controller);
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return true;
    }
    return position.pixels <=
        position.minScrollExtent + _desktopStickToLatestSlopPx;
  }

  ScrollPosition? _singleScrollPositionOrNull(ScrollController controller) {
    if (!controller.hasClients || controller.positions.length != 1) {
      return null;
    }
    return controller.position;
  }

  void saveScrollBeforeRouteOverlay(
    String? conversationID, {
    String? anchorMessageID,
    int lockMilliseconds = 800,
  }) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    final controller = _activeChatScrollControllerMap[convId];
    final position =
        controller == null ? null : _singleScrollPositionOrNull(controller);
    if (position != null && position.hasPixels) {
      _mediaPreviewScrollOffsetMap[convId] = position.pixels;
    }
    final anchor = anchorMessageID?.trim() ?? '';
    if (anchor.isNotEmpty) {
      _mediaPreviewAnchorMsgIDMap[convId] = anchor;
    }
    _syncHistoryPositionFromActiveScroll(convId);
  }

  void restoreScrollAfterRouteOverlay(
    String? conversationID, {
    int lockMilliseconds = 800,
  }) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      _isRestoringScrollAfterMediaPreview = false;
      return;
    }
    _isRestoringScrollAfterMediaPreview = true;
    _mediaPreviewRestoreVersion++;
    _mediaPreviewRestoreLockUntil =
        DateTime.now().millisecondsSinceEpoch + lockMilliseconds;
    _syncHistoryPositionFromActiveScroll(convId);
    notifyListeners();
  }

  bool get isRestoringScrollAfterMediaPreview {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _isRestoringScrollAfterMediaPreview ||
        now < _mediaPreviewRestoreLockUntil;
  }

  int get mediaPreviewRestoreVersion => _mediaPreviewRestoreVersion;

  void bindActiveChatScrollController({
    required String conversationID,
    required ScrollController scrollController,
  }) {
    if (conversationID.isEmpty) {
      return;
    }
    _activeChatScrollControllerMap[conversationID] = scrollController;
    final convId = _inboundStateKey(conversationID);
    _followingLatestByConversation.putIfAbsent(convId, () => true);
  }

  void clearActiveChatScrollController({String? conversationID}) {
    if (conversationID != null && conversationID.isNotEmpty) {
      _activeChatScrollControllerMap.remove(conversationID);
      clearHistoryLiveWindowFreeze(conversationID: conversationID);
      return;
    }
    _activeChatScrollControllerMap.clear();
    clearHistoryLiveWindowFreeze();
  }

  bool hasPendingScrollRestore(String? conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return false;
    }
    // 仅「正在恢复滚动」时阻塞列表；预览期间保存的 offset 不应改变列表位姿。
    return _isRestoringScrollAfterMediaPreview ||
        DateTime.now().millisecondsSinceEpoch < _mediaPreviewRestoreLockUntil;
  }

  bool isInboundPresentationBottomLocked(String convId) {
    if (isSearchJumpPending(convId)) return false;
    if (isChatListUserScrolling ||
        !_isSameConversationID(convId, currentSelectedConv)) {
      return false;
    }
    if (!isFollowingLatest(convId) && receivedNewMessageCountFor(convId) > 0) {
      return false;
    }
    // list-push 会故意 jump 离底再 animate 回来；这段物理偏移不是用户上滑看历史。
    // 不限 chunked reveal：单条连续收消息同样会误闪「回到底部」。
    if (isInboundViewportPushActive(convId) &&
        (isFollowingLatest(convId) ||
            getMessageListPosition(convId) == HistoryMessagePosition.bottom)) {
      return true;
    }
    if (!isChunkedRevealActive(convId)) {
      return false;
    }
    // A viewport insert deliberately moves pixels away from minScrollExtent
    // while a tall row slides in. That visual offset is not user history
    // navigation, so keep the pre-transaction logical position authoritative.
    return getMessageListPosition(convId) == HistoryMessagePosition.bottom;
  }

  /// During a reverse-list prepend Flutter can briefly expose the minimum
  /// pixels while the new sliver tree is laid out. This is geometry, not a
  /// user return-to-latest gesture. Expose the predicate so the tongue and
  /// other position observers share the same gate as the active list.
  bool isPaginationRestoreTransientNearBottom(
    String convId,
    ScrollPosition position,
  ) {
    final logicalPosition = getMessageListPosition(convId);
    final physicalDistance = position.pixels - position.minScrollExtent;
    return isMemoryWindowSuppressed(convId) &&
        !isChatListUserScrolling &&
        !isUserScrollToBottomInProgress(convId) &&
        (logicalPosition == HistoryMessagePosition.awayTwoScreen ||
            logicalPosition == HistoryMessagePosition.notShowLatest) &&
        physicalDistance <= 80.0;
  }

  // Kept as a private alias for existing diagnostics/tests; all production
  // callers use the public predicate above so the gate is shared cross-widget.
  bool _isPaginationRestoreTransientNearBottom(
    String convId,
    ScrollPosition position,
  ) =>
      isPaginationRestoreTransientNearBottom(convId, position);

  void _syncHistoryPositionFromActiveScroll(String convId) {
    if (isSearchJumpPending(convId)) return;
    // The minimum extent of a historical window is not the conversation tail.
    // Only the history loader/user return flow can establish latest coverage.
    if (memoryWindowMissingNewer(convId) ||
        getMessageListPosition(convId) ==
            HistoryMessagePosition.notShowLatest) {
      return;
    }
    if (isInboundPresentationBottomLocked(convId)) {
      _storeHistoryMessagePosition(convId, HistoryMessagePosition.bottom);
      final controller = _activeChatScrollControllerMap[convId];
      final position =
          controller == null ? null : _singleScrollPositionOrNull(controller);
      if (position != null &&
          position.hasPixels &&
          position.hasContentDimensions &&
          position.pixels > position.minScrollExtent + 80) {
        ChatJitterDiag.logInboundFlow(
          action: 'physical_away_ignored',
          conv: convId,
          extras: <String, Object?>{
            'pixels': position.pixels.toStringAsFixed(1),
            'minExtent': position.minScrollExtent.toStringAsFixed(1),
            'distance':
                (position.pixels - position.minScrollExtent).toStringAsFixed(1),
            'maxExtent': position.maxScrollExtent.toStringAsFixed(1),
            'logicalPosition': HistoryMessagePosition.bottom.name,
            'queue': pendingInboundProjectionCount(convId),
            'waiting': isInboundProjectionRevealWaiting(convId),
          },
          throttleKey: 'physical_away_ignored',
          minIntervalMs: 200,
        );
      }
      return;
    }
    final controller = _activeChatScrollControllerMap[convId];
    final position =
        controller == null ? null : _singleScrollPositionOrNull(controller);
    if (position != null &&
        position.hasPixels &&
        position.hasContentDimensions) {
      // A reverse history prepend can transiently report pixels==0 while the
      // new sliver tree is being laid out. During the protected memory-window
      // transaction that value is not a real return-to-bottom gesture. If we
      // promote it to bottom here, realtime messages are committed into the
      // visible list and their pin/rebuild path races the pagination anchor
      // (the observed awayTwoScreen -> bottom -> old offset oscillation).
      final logicalPosition = getMessageListPosition(convId);
      final physicalDistance = position.pixels - position.minScrollExtent;
      if (isPaginationRestoreTransientNearBottom(convId, position)) {
        ChatHistoryTrace.log(
          'logical_position_sync_ignored_pagination_restore',
          conversationID: convId,
          extras: <String, Object?>{
            'logicalPosition': logicalPosition.name,
            'pixels': position.pixels.toStringAsFixed(1),
            'minExtent': position.minScrollExtent.toStringAsFixed(1),
            'maxExtent': position.maxScrollExtent.toStringAsFixed(1),
            'distance': physicalDistance.toStringAsFixed(1),
            'userScrolling': isChatListUserScrolling,
            'userScrollToBottom': isUserScrollToBottomInProgress(convId),
            'memorySuppressed': true,
          },
        );
        return;
      }
      const nearThreshold = 80.0;
      final viewport = position.viewportDimension;
      final distance = position.pixels - position.minScrollExtent;
      final previous = getMessageListPosition(convId);
      final HistoryMessagePosition next;
      if (viewport > 0 && distance > viewport) {
        next = HistoryMessagePosition.awayTwoScreen;
      } else if (distance > nearThreshold) {
        next = HistoryMessagePosition.inTwoScreen;
      } else {
        next = HistoryMessagePosition.bottom;
      }
      _storeHistoryMessagePosition(convId, next);
      if (previous != next) {
        ChatJitterDiag.logInboundFlow(
          action: 'logical_position_sync',
          conv: convId,
          extras: <String, Object?>{
            'before': previous.name,
            'after': next.name,
            'pixels': position.pixels.toStringAsFixed(1),
            'minExtent': position.minScrollExtent.toStringAsFixed(1),
            'distance': distance.toStringAsFixed(1),
            'viewport': viewport.toStringAsFixed(1),
            'userScrolling': isChatListUserScrolling,
            'chunkActive': isChunkedRevealActive(convId),
          },
        );
      }
    }
  }

  bool _isActiveChatNearBottom(String convId, {double threshold = 80.0}) {
    if (isSearchJumpPending(convId)) return false;
    if (memoryWindowMissingNewer(convId) ||
        getMessageListPosition(convId) ==
            HistoryMessagePosition.notShowLatest) {
      return false;
    }
    if (isInboundPresentationBottomLocked(convId)) {
      return true;
    }
    final controller = _activeChatScrollControllerMap[convId];
    if (controller == null) {
      return false;
    }
    final position = _singleScrollPositionOrNull(controller);
    if (position == null) {
      return false;
    }
    if (!position.hasPixels || !position.hasContentDimensions) {
      return false;
    }
    if (isPaginationRestoreTransientNearBottom(convId, position)) {
      return false;
    }
    return position.pixels <= position.minScrollExtent + threshold;
  }

  Map<String, Object?> stickToLatestDiagSnapshot(String conversationID) {
    final convId = _inboundStateKey(conversationID);
    final controller = _activeChatScrollControllerMap[convId];
    final position =
        controller == null ? null : _singleScrollPositionOrNull(controller);
    final hasGeom = position != null &&
        position.hasPixels &&
        position.hasContentDimensions;
    final distance = hasGeom
        ? position!.pixels - position.minScrollExtent
        : null;
    return <String, Object?>{
      'followingLatest': isFollowingLatest(convId),
      'distance': distance?.toStringAsFixed(1) ?? 'n/a',
      'physicallyAt24': _isActiveChatNearBottom(
        convId,
        threshold: _stickToLatestEpsilonPx,
      ),
      'nearBottom80': _isActiveChatNearBottom(convId),
      'maxExtent':
          hasGeom ? position!.maxScrollExtent.toStringAsFixed(1) : 'n/a',
      'viewport':
          hasGeom ? position!.viewportDimension.toStringAsFixed(1) : 'n/a',
      'rawCount': rawMessageCount(convId),
      'logical': getMessageListPosition(convId).name,
      'pushActive': isInboundViewportPushActive(convId),
      'returning': isUserScrollToBottomInProgress(convId),
      'userScrolling': isChatListUserScrolling,
      'received': receivedNewMessageCountFor(convId),
      'pinSeq': _pinToBottomRequestSeq,
    };
  }

  /// Shared physical near-bottom decision for message routing and list-push.
  /// Logical `bottom` alone is not sufficient because it can lag behind a
  /// short user scroll or an in-flight geometry change.
  bool isActiveChatNearBottom(String conversationID) =>
      _isActiveChatNearBottom(_safeConversationId(conversationID));

  /// 物理滚动已离开底部超过约一屏（与「回到底部」出现阈值对齐）。
  bool _isActiveChatAwayOneScreen(String convId) {
    if (isInboundPresentationBottomLocked(convId)) {
      return false;
    }
    final controller = _activeChatScrollControllerMap[convId];
    if (controller == null) {
      return false;
    }
    final position = _singleScrollPositionOrNull(controller);
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return false;
    }
    final viewport = position.viewportDimension;
    if (viewport <= 0) {
      return false;
    }
    final distance = position.pixels - position.minScrollExtent;
    return distance > viewport;
  }

  void saveScrollBeforeMediaPreview(
    String? conversationID, {
    String? anchorMessageID,
  }) {
    final wasOpen = _isMediaPreviewOverlayOpen;
    _isMediaPreviewOverlayOpen = true;
    saveScrollBeforeRouteOverlay(
      conversationID,
      anchorMessageID: anchorMessageID,
      lockMilliseconds: _mediaPreviewRestoreLockMilliseconds,
    );
    if (!wasOpen) {
      _markNeedsNotify();
    }
  }

  void restoreScrollAfterMediaPreview(String? conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      if (_isMediaPreviewOverlayOpen) {
        _isMediaPreviewOverlayOpen = false;
        _markNeedsNotify();
      }
      return;
    }
    if (!_needsActiveScrollRestoreAfterPreview(convId)) {
      _clearMediaPreviewScrollRestoreState(convId);
      if (_isMediaPreviewOverlayOpen) {
        _isMediaPreviewOverlayOpen = false;
        _markNeedsNotify();
      }
      return;
    }
    restoreScrollAfterRouteOverlay(
      conversationID,
      lockMilliseconds: _mediaPreviewRestoreLockMilliseconds,
    );
    // Keep overlay lock until [finishScrollAfterMediaPreview]: clearing early
    // lets residual slide-dismiss pointers scroll the chat list under the pop.
    //
    // 兜底：列表若未调度到 finish（dispose / 未挂 listener），超时强制解锁，
    // 避免永久 NeverScrollable。
    final restoreVersion = _mediaPreviewRestoreVersion;
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (_mediaPreviewRestoreVersion != restoreVersion) {
        return;
      }
      if (!shouldLockChatScrollForMediaPreview) {
        return;
      }
      finishScrollAfterMediaPreview(convId);
    });
  }

  /// 预览路由已完全 pop 且滚动恢复结束后调用（与 [restoreScrollAfterMediaPreview] 解耦兜底）。
  void endMediaPreviewOverlay() {
    if (!_isMediaPreviewOverlayOpen) {
      return;
    }
    _isMediaPreviewOverlayOpen = false;
    _markNeedsNotify();
  }

  /// 预览关闭后是否需要主动改滚动位置。
  ///
  /// 只认打开时保存的像素 offset：列表在 `opaque:false` 预览下本来就还在，
  /// 仅有锚点消息 id 时不得强制 restore——否则会走
  /// `scrollToIndex(middle)` 把入口气泡拽到屏幕正中。
  bool _needsActiveScrollRestoreAfterPreview(String convId) {
    final offset = _mediaPreviewScrollOffsetMap[convId];
    if (offset == null) {
      return false;
    }
    final controller = _activeChatScrollControllerMap[convId];
    final position =
        controller == null ? null : _singleScrollPositionOrNull(controller);
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      // offset 已存、当前读不到 position：仍要进 restore，等列表就绪后 jump。
      return true;
    }
    final target = offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    return (position.pixels - target).abs() > 0.5;
  }

  void _clearMediaPreviewScrollRestoreState(String convId) {
    final wasRestoring = _isRestoringScrollAfterMediaPreview ||
        DateTime.now().millisecondsSinceEpoch < _mediaPreviewRestoreLockUntil;
    _isRestoringScrollAfterMediaPreview = false;
    _mediaPreviewRestoreLockUntil = 0;
    _mediaPreviewScrollOffsetMap.remove(convId);
    _mediaPreviewAnchorMsgIDMap.remove(convId);
    if (wasRestoring) {
      _markNeedsNotify();
    }
  }

  /// 画廊预览关闭前更新锚点，避免左右滑到别的图后仍滚回入口消息。
  void updateMediaPreviewCloseAnchor(
    String? conversationID,
    String? anchorMessageID,
  ) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    final anchor = anchorMessageID?.trim() ?? '';
    if (anchor.isNotEmpty) {
      _mediaPreviewAnchorMsgIDMap[convId] = anchor;
    }
  }

  String? getScrollRestoreAnchorMsgID(String? conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return null;
    }
    return _mediaPreviewAnchorMsgIDMap[convId];
  }

  double? getScrollRestoreOffset(String? conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return null;
    }
    return _mediaPreviewScrollOffsetMap[convId];
  }

  void finishScrollAfterMediaPreview(String? conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isNotEmpty) {
      final controller = _activeChatScrollControllerMap[convId];
      final position =
          controller == null ? null : _singleScrollPositionOrNull(controller);
      if (position != null &&
          position.hasPixels &&
          position.hasContentDimensions) {
        const threshold = 80.0;
        if (position.pixels > position.minScrollExtent + threshold) {
          _storeHistoryMessagePosition(
            convId,
            HistoryMessagePosition.inTwoScreen,
          );
        } else {
          _storeHistoryMessagePosition(convId, HistoryMessagePosition.bottom);
        }
      }
      _mediaPreviewRestoreLockUntil = DateTime.now().millisecondsSinceEpoch +
          _mediaPreviewRestoreTailLockMilliseconds;
    }
    final wasOpen = _isMediaPreviewOverlayOpen;
    _isMediaPreviewOverlayOpen = false;
    Future<void>.delayed(
      const Duration(milliseconds: _mediaPreviewRestoreTailLockMilliseconds),
      () {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now < _mediaPreviewRestoreLockUntil) {
          return;
        }
        if (convId.isNotEmpty) {
          _clearMediaPreviewScrollRestoreState(convId);
        } else {
          _isRestoringScrollAfterMediaPreview = false;
          _mediaPreviewRestoreLockUntil = 0;
        }
      },
    );
    if (wasOpen) {
      _markNeedsNotify();
    }
  }

  String _safeConversationId(String? conversationID) {
    if (conversationID != null && conversationID.isNotEmpty) {
      return conversationID;
    }
    return currentSelectedConv;
  }

  /// 入站/展示共用的 messageListMap 存储键。
  ///
  /// Web/C2C 常见分裂：历史灌在 `c2c_userId`，`onRecvNewMessage` 算出的是裸
  /// `userId`。若各写各的桶，会话预览（conversation listener）会更新，但聊天
  /// 页 `getMessageList(c2c_…)` 仍读旧桶 → 预览有字、对话页不刷新。
  String _resolveMessageListStorageKey(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final selected = currentSelectedConv.trim();
    if (selected.isNotEmpty &&
        _isSameConversationID(trimmed, selected) &&
        _messageListMap.containsKey(selected)) {
      return selected;
    }

    String? emptyAlias;
    for (final entry in _messageListMap.entries) {
      if (!_isSameConversationID(entry.key, trimmed)) {
        continue;
      }
      final list = entry.value;
      if (list != null && list.isNotEmpty) {
        return entry.key;
      }
      emptyAlias ??= entry.key;
    }
    if (emptyAlias != null) {
      return emptyAlias;
    }

    if (selected.isNotEmpty && _isSameConversationID(trimmed, selected)) {
      return selected;
    }
    return trimmed;
  }

  /// 合并等价会话 ID 下所有非空桶（防御双写残留）。
  List<V2TimMessage> _collectAuthoritativeMessages(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return const <V2TimMessage>[];
    }
    final buckets = <List<V2TimMessage>>[];
    for (final entry in _messageListMap.entries) {
      if (!_isSameConversationID(entry.key, trimmed)) {
        continue;
      }
      final list = entry.value;
      if (list != null && list.isNotEmpty) {
        buckets.add(list);
      }
    }
    if (buckets.isEmpty) {
      return const <V2TimMessage>[];
    }
    if (buckets.length == 1) {
      return buckets.first;
    }
    return sortMessagesNewestFirst(
      dedupeMessages(<V2TimMessage>[for (final bucket in buckets) ...bucket]),
    );
  }

  HistoryMessagePosition getMessageListPosition(String? conversationID) {
    final convId = _safeConversationId(conversationID);
    if (hasPendingScrollRestore(convId)) {
      // During scroll restore lock, return notShowLatest temporarily
      // WITHOUT persisting it. The previous stored position is preserved
      // and will be read again once the lock clears.
      return HistoryMessagePosition.notShowLatest;
    }
    final page = _openPageHistoryPosition;
    final pageConv = _openPageConvId;
    if (page != null &&
        pageConv != null &&
        _isSameConversationID(convId, pageConv)) {
      return page.value;
    }
    final HistoryMessagePosition? position = _historyMessagePositionMap[convId];
    if (position == null) {
      _storeHistoryMessagePosition(convId, HistoryMessagePosition.bottom);
      return HistoryMessagePosition.bottom;
    }
    return position;
  }

  void prepareForOutgoingMessage(String conversationID) {
    final convId = _safeConversationId(conversationID);
    if (convId.isEmpty) {
      return;
    }
    _mediaPreviewScrollOffsetMap.remove(convId);
    _mediaPreviewAnchorMsgIDMap.remove(convId);
    _isRestoringScrollAfterMediaPreview = false;
    _mediaPreviewRestoreLockUntil = 0;
    _storeHistoryMessagePosition(convId, HistoryMessagePosition.bottom);
    flushDeferredIncomingMessages(convId, notify: false, userInitiated: true);
    unlockEntryUnreadForTongue(conversationID: convId, notify: false);
    clearReceivedUnreadState(conversationID: convId, notify: false);
    _outgoingPinScrollSuppressUntilMs =
        DateTime.now().millisecondsSinceEpoch + 350;
  }

  bool shouldSuppressOutgoingPinScroll() {
    return DateTime.now().millisecondsSinceEpoch <
        _outgoingPinScrollSuppressUntilMs;
  }

  void setMessageListPosition(
    String conversationID,
    HistoryMessagePosition position, {
    bool notify = true,
  }) {
    final convId = _safeConversationId(conversationID);
    if (position == HistoryMessagePosition.bottom &&
        (isSearchJumpPending(convId) ||
            (memoryWindowMissingNewer(convId) &&
                !isUserScrollToBottomInProgress(convId)))) {
      return;
    }
    final previous = getMessageListPosition(convId);
    HistoryMessagePosition next = position;
    final controller = _activeChatScrollControllerMap[convId];
    final activeScrollPosition =
        controller == null ? null : _singleScrollPositionOrNull(controller);
    if (position == HistoryMessagePosition.bottom &&
        activeScrollPosition != null &&
        activeScrollPosition.hasPixels &&
        activeScrollPosition.hasContentDimensions &&
        isPaginationRestoreTransientNearBottom(convId, activeScrollPosition)) {
      // A tongue/overlay/background callback can observe the transient zero
      // pixels before the pagination anchor is restored. Keep the prior
      // logical position authoritative; accepting bottom here starts the
      // realtime pin/rebuild path and recreates the 0 -> oldOffset oscillation.
      next = previous;
      ChatHistoryTrace.log(
        'message_list_position_bottom_blocked_pagination_restore',
        conversationID: convId,
        extras: <String, Object?>{
          'previous': previous.name,
          'pixels': activeScrollPosition.pixels.toStringAsFixed(1),
          'minExtent': activeScrollPosition.minScrollExtent.toStringAsFixed(1),
          'maxExtent': activeScrollPosition.maxScrollExtent.toStringAsFixed(1),
          'memorySuppressed': true,
        },
      );
    }
    if (position == HistoryMessagePosition.bottom &&
        _deferredUntilUserBottomConversations.contains(
          _inboundStateKey(convId),
        )) {
      next = HistoryMessagePosition.notShowLatest;
    } else if (position == HistoryMessagePosition.bottom &&
        hasPendingScrollRestore(convId)) {
      next = HistoryMessagePosition.notShowLatest;
    }
    _storeHistoryMessagePosition(convId, next);
    if (previous != next) {
      ChatHistoryTrace.log(
        'message_list_position_changed',
        conversationID: convId,
        extras: <String, Object?>{
          'previous': previous.name,
          'requested': position.name,
          'next': next.name,
          'notify': notify,
          'pendingScrollRestore': hasPendingScrollRestore(convId),
          'readingHistory': isReadingHistory(convId),
          'memorySuppressed': isMemoryWindowSuppressed(convId),
        },
      );
    }
    // Scroll-position churn must not fan out to every Global listener when
    // the logical value is unchanged (page-local UI is SSOT while attached).
    if (notify && previous != next) {
      notifyListeners();
    }
  }
}
