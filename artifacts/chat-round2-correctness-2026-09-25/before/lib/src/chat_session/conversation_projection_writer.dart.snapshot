import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_guard.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_unread_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_c2c_show_name_prefer.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_last_message_prefer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'conversation_projection_reducer.dart';

typedef ConversationProjectionPublished = void Function(
    ConversationProjectionWriteResult result);

/// Describes the smallest UI update implied by one projection commit.
/// Consumers can use this to separate feed changes from row-only changes.
class ConversationProjectionDiff {
  const ConversationProjectionDiff({
    this.insertedIds = const <String>{},
    this.removedIds = const <String>{},
    this.rowChangedIds = const <String>{},
    this.visibilityChanged = false,
    this.orderChanged = false,
  });

  final Set<String> insertedIds;
  final Set<String> removedIds;
  final Set<String> rowChangedIds;
  final bool visibilityChanged;
  final bool orderChanged;

  bool get structureChanged =>
      insertedIds.isNotEmpty || removedIds.isNotEmpty;
  bool get feedChanged =>
      structureChanged || visibilityChanged || orderChanged;
  bool get isEmpty => !feedChanged && rowChangedIds.isEmpty;
}

/// The compatibility boundary used by [ConversationProjectionWriter].
///
/// The writer owns projection state and merge decisions. The host only exposes
/// policies or side effects that are still specific to the old virtual-list
/// adapter. Keeping those callbacks here makes the merge algorithm testable
/// without constructing a ChangeNotifier or a page.
abstract class ConversationProjectionWriterHost {
  bool get hasOpenChatNow;
  bool get uiNotifyPendingWhileActiveChat;
  bool get deferringPinReorder;
  bool get slidingWindowUserExpanded;

  String keyOfConversation(V2TimConversation conversation);
  String keyOfId(String id);
  bool isArchivedForMainList(V2TimConversation conversation);
  bool shouldAdmitToUiWindow(
    V2TimConversation incoming,
    List<V2TimConversation> current,
  );
  int notifiableUnread(V2TimConversation conversation);
  int uiFingerprint(V2TimConversation conversation);
  bool sameConversation(
    V2TimConversation left,
    V2TimConversation right,
  );

  /// Decorates an SDK/store row and applies local optimistic fields.
  void prepareIncoming(V2TimConversation conversation);

  /// Persists a strong last-message preview before a later weak SDK patch can
  /// overwrite the row in memory.
  void putStrongPreviewCache(String conversationId, V2TimMessage message);

  /// Sorts and applies the current window policy. [skipTrim] is used after a
  /// user has expanded the list through pagination.
  List<V2TimConversation> sortAndTrim(
    List<V2TimConversation> conversations, {
    required bool skipTrim,
  });

  /// Keeps the old virtual hydrate window coherent with the new projection.
  /// Returns whether the hydrate data changed.
  bool applyHydrateProjection({
    required List<V2TimConversation> next,
    required Iterable<String> deletedIds,
    required Iterable<V2TimConversation> upserted,
    required bool reorder,
  });

  void markActiveChatDirty(Iterable<String> ids);

  void commitUnreadProjection(ConversationProjectionWriteResult result);

  /// Mirrors the writer state into the compatibility adapter and emits the
  /// legacy notification if [result.shouldPublish] is true.
  void publishProjection(ConversationProjectionWriteResult result);
}

class ConversationProjectionWriteResult {
  const ConversationProjectionWriteResult({
    required this.conversations,
    required this.storeHasAnyRow,
    required this.structureRevision,
    required this.contentRevision,
    required this.deletedIds,
    required this.upserted,
    required this.orderChanged,
    required this.shouldPublish,
    required this.hydrateDirty,
    required this.reason,
    required this.contentOnly,
    required this.unreadDeltas,
    required this.needsOutOfWindowUnreadRefresh,
    required this.committedUnreadDeltas,
    required this.unreadProjectionComplete,
  });

  final List<V2TimConversation> conversations;
  final bool storeHasAnyRow;
  final int structureRevision;
  final int contentRevision;
  final Set<String> deletedIds;
  final List<V2TimConversation> upserted;
  final bool orderChanged;
  final bool shouldPublish;
  final bool hydrateDirty;
  final String reason;
  final bool contentOnly;
  final List<ConversationUnreadDelta> unreadDeltas;
  final bool needsOutOfWindowUnreadRefresh;
  final List<ConversationUiUnreadDelta>? committedUnreadDeltas;
  final bool? unreadProjectionComplete;

  /// Batch-level diff for future feed/row-specific notification routing.
  /// Upserted rows are row changes; insertion/removal and ordering are feed
  /// changes. Visibility is supplied by the membership/archive layer later.
  ConversationProjectionDiff get diff {
    final removed = deletedIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    final rows = upserted
        .map((conversation) => conversation.conversationID.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    return ConversationProjectionDiff(
      insertedIds: const <String>{},
      removedIds: removed,
      rowChangedIds: rows,
      orderChanged: orderChanged,
    );
  }
}

/// Single writer for the store-backed conversation UI projection.
///
/// This is deliberately independent from any widget/list adapter. The
/// controller publishes the projection and UI adapters consume that snapshot.
class ConversationProjectionWriter {
  ConversationProjectionWriter({
    ConversationProjectionWriterHost? host,
    ConversationProjectionPublished? onPublished,
  })  : _host = host,
        _onPublished = onPublished;

  ConversationProjectionWriterHost? _host;
  ConversationProjectionPublished? _onPublished;
  List<V2TimConversation> _conversations = const [];
  bool _storeHasAnyRow = false;
  int _structureRevision = 0;
  int _contentRevision = 0;

  List<V2TimConversation> get conversations =>
      List<V2TimConversation>.unmodifiable(_conversations);
  bool get storeHasAnyRow => _storeHasAnyRow;
  int get structureRevision => _structureRevision;
  int get contentRevision => _contentRevision;

  void attachHost(ConversationProjectionWriterHost host) {
    _host = host;
  }

  void setPublishedCallback(ConversationProjectionPublished callback) {
    _onPublished = callback;
  }

  Future<void> apply({
    required String reason,
    required List<V2TimConversation> current,
    required bool currentStoreHasAnyRow,
    required int currentStructureRevision,
    required int currentContentRevision,
    required List<V2TimConversation> upserted,
    List<String> deletedIds = const [],
    Set<String> forceAdmitIds = const <String>{},
    Map<String, Set<ConversationMutationField>> changedFieldMasks =
        const <String, Set<ConversationMutationField>>{},
    List<ConversationUiUnreadDelta>? committedUnreadDeltas,
    bool? unreadProjectionComplete,
    Set<String> explicitDraftIds = const <String>{},
  }) async {
    final host = _host;
    if (host == null) {
      throw StateError('ConversationProjectionWriter host is not attached');
    }
    // The virtual-list adapter still has non-writer pagination mutations. Read
    // that compatibility snapshot at the boundary, then keep all merge work
    // and the resulting state inside this writer. This is intentionally an
    // input to apply, not a second mutable projection store.
    _conversations = List<V2TimConversation>.from(current);
    _storeHasAnyRow = currentStoreHasAnyRow;
    _structureRevision = currentStructureRevision;
    _contentRevision = currentContentRevision;
    if (upserted.isEmpty &&
        deletedIds.isEmpty &&
        (committedUnreadDeltas == null || committedUnreadDeltas.isEmpty)) {
      return;
    }

    final normalizedDeletedIds = deletedIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final deletedSet = normalizedDeletedIds
        .map(host.keyOfId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final explicitLastMessageKeys = changedFieldMasks.entries
        .where(
          (entry) =>
              entry.value.contains(ConversationMutationField.lastMessage),
        )
        .map((entry) => host.keyOfId(entry.key))
        .where((key) => key.isNotEmpty)
        .toSet();
    final unreadDeltas = <ConversationUnreadDelta>[];
    var needsOutOfWindowUnreadRefresh = false;
    final currentProjection = List<V2TimConversation>.from(_conversations);

    if (deletedSet.isNotEmpty) {
      if (host.hasOpenChatNow || host.uiNotifyPendingWhileActiveChat) {
        host.markActiveChatDirty(normalizedDeletedIds);
      }
      for (final existing in _conversations) {
        if (!deletedSet.contains(host.keyOfConversation(existing))) {
          continue;
        }
        final oldNotifiable = host.notifiableUnread(existing);
        if (oldNotifiable > 0) {
          unreadDeltas.add(
            ConversationUnreadDelta(
              conversationKey: existing.conversationID,
              isGroup: ConversationUnreadUtils.isGroupConversation(existing),
              oldNotifiable: oldNotifiable,
              newNotifiable: 0,
            ),
          );
        }
      }
    }

    final archivedKeys = <String>{};
    final preparedUpserted = <V2TimConversation>[];
    for (final incoming in upserted) {
      final id = incoming.conversationID.trim();
      if (id.isEmpty) continue;
      if (host.isArchivedForMainList(incoming)) {
        archivedKeys.add(host.keyOfConversation(incoming));
        if (host.hasOpenChatNow || host.uiNotifyPendingWhileActiveChat) {
          host.markActiveChatDirty(<String>[id]);
        }
        continue;
      }
      if (host.hasOpenChatNow || host.uiNotifyPendingWhileActiveChat) {
        host.markActiveChatDirty(<String>[id]);
      }
      host.prepareIncoming(incoming);
      preparedUpserted.add(incoming);
      _storeHasAnyRow = true;
    }

    final reduction = ConversationProjectionReducer.reduce(
      current: currentProjection,
      upserted: preparedUpserted,
      deletedIds: {...deletedSet, ...archivedKeys},
      forceAdmitIds: forceAdmitIds,
      keyOf: host.keyOfConversation,
      keyOfId: host.keyOfId,
      shouldAdmit: host.shouldAdmitToUiWindow,
      mergeExisting: (existing, incoming) {
        final id = incoming.conversationID.trim();
        final canonical = host.keyOfConversation(incoming);
        final oldUnread = existing.unreadCount ?? 0;
        incoming.unreadCount = ConversationUnreadGuard.resolveForListApply(
          conversationId: id,
          existingUnread: oldUnread,
          incoming: incoming,
          existingLastMessage: existing.lastMessage,
        );
        incoming.conversationID = existing.conversationID;
        if (!explicitLastMessageKeys.contains(canonical)) {
          incoming.lastMessage =
              ConversationLastMessagePrefer.preferLastMessage(
            existing: existing.lastMessage,
            incoming: incoming.lastMessage,
          );
        }
        if (id.startsWith('c2c_') ||
            (incoming.userID?.trim().isNotEmpty ?? false)) {
          incoming.showName =
              ConversationC2cShowNamePrefer.preferForConversationIds(
            conversationID: id,
            userID: incoming.userID ?? existing.userID,
            existingShowName: existing.showName,
            incomingShowName: incoming.showName,
            readStore: DisplayNameStore.instance.c2c,
          );
        }
        final strongLast = incoming.lastMessage;
        if (strongLast != null) {
          host.putStrongPreviewCache(id, strongLast);
        }
        final oldNotifiable = host.notifiableUnread(existing);
        final newNotifiable = host.notifiableUnread(incoming);
        if (oldNotifiable != newNotifiable) {
          unreadDeltas.add(
            ConversationUnreadDelta(
              conversationKey: incoming.conversationID,
              isGroup: ConversationUnreadUtils.isGroupConversation(incoming),
              oldNotifiable: oldNotifiable,
              newNotifiable: newNotifiable,
            ),
          );
        }
        return host.uiFingerprint(existing) != host.uiFingerprint(incoming)
            ? incoming
            : existing;
      },
    );

    var next = reduction.conversations;
    final nextIndexByKey = <String, int>{
      for (var i = 0; i < next.length; i++) host.keyOfConversation(next[i]): i,
    };
    final previousKeys = currentProjection.map(host.keyOfConversation).toSet();
    for (final key in reduction.inserted) {
      final index = nextIndexByKey[key] ?? -1;
      if (index < 0) continue;
      final incoming = next[index];
      final id = incoming.conversationID.trim();
      incoming.unreadCount = ConversationUnreadGuard.resolveForListApply(
        conversationId: id,
        existingUnread: 0,
        incoming: incoming,
      );
      final newNotifiable = host.notifiableUnread(incoming);
      if (newNotifiable > 0) {
        unreadDeltas.add(
          ConversationUnreadDelta(
            conversationKey: incoming.conversationID,
            isGroup: ConversationUnreadUtils.isGroupConversation(incoming),
            oldNotifiable: 0,
            newNotifiable: newNotifiable,
          ),
        );
      }
    }
    for (final incoming in preparedUpserted) {
      final key = host.keyOfConversation(incoming);
      final existed = previousKeys.contains(key);
      if (key.isNotEmpty && !existed && !reduction.inserted.contains(key)) {
        needsOutOfWindowUnreadRefresh = true;
      }
    }

    final deferring = host.deferringPinReorder;
    if (!deferring) {
      next = host.sortAndTrim(
        next,
        skipTrim: host.slidingWindowUserExpanded,
      );
    }

    final orderChanged = !_sameOrder(currentProjection, next, host);
    final hydrateDirty = host.applyHydrateProjection(
      next: next,
      deletedIds: deletedIds,
      upserted: upserted,
      reorder: orderChanged && !deferring,
    );
    final uiChanged = !_listsEqual(currentProjection, next, host);
    final shouldPublish = uiChanged || hydrateDirty;
    if (shouldPublish) {
      _conversations = List<V2TimConversation>.from(next);
      _contentRevision++;
      if (orderChanged) _structureRevision++;
    }

    final result = ConversationProjectionWriteResult(
      conversations: List<V2TimConversation>.from(
        shouldPublish ? _conversations : currentProjection,
      ),
      storeHasAnyRow: _storeHasAnyRow,
      structureRevision: _structureRevision,
      contentRevision: _contentRevision,
      deletedIds: deletedSet,
      upserted: List<V2TimConversation>.from(upserted),
      orderChanged: orderChanged,
      shouldPublish: shouldPublish,
      hydrateDirty: hydrateDirty,
      reason: deferring ? '${reason}_defer' : reason,
      contentOnly: !orderChanged && deletedSet.isEmpty,
      unreadDeltas: unreadDeltas,
      needsOutOfWindowUnreadRefresh: needsOutOfWindowUnreadRefresh,
      committedUnreadDeltas: committedUnreadDeltas,
      unreadProjectionComplete: unreadProjectionComplete,
    );
    if (shouldPublish) {
      _onPublished?.call(result);
      host.publishProjection(result);
    }
    host.commitUnreadProjection(result);
  }

  static bool _sameOrder(
    List<V2TimConversation> left,
    List<V2TimConversation> right,
    ConversationProjectionWriterHost host,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!host.sameConversation(left[i], right[i])) return false;
    }
    return true;
  }

  static bool _listsEqual(
    List<V2TimConversation> left,
    List<V2TimConversation> right,
    ConversationProjectionWriterHost host,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (host.uiFingerprint(left[i]) != host.uiFingerprint(right[i])) {
        return false;
      }
    }
    return true;
  }
}
