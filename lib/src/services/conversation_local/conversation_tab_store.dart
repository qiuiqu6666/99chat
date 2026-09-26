import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';
import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_change_journal.dart';
import 'dart:collection';
import 'dart:convert';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_feed_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_row_view.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_leave_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sdk_window_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/utils/revoked_message_preview.dart';
import 'package:tencent_cloud_chat_demo/src/utils/archive_conversation_lookup.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_unread_utils.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_c2c_show_name_prefer.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_last_message_prefer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_filter.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation_filter.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

/// 腾讯方案 Phase1/3：按 Tab 持有「已从 SDK 分页加载」的会话窗口（内存 Store）。
///
/// 真相源 = IM SDK 本地会话库；本 Store 不持久化。杀进程后重新 [ensurePrimed]。
/// Phase3：主列表窗口排除本地归档 id 集合；分组成员过滤仍在 UI 层（selected folder）。

/// Position metadata for one loaded type. Content-only replacements keep the
/// index; pagination, removal and sorting rebuild it with the new positions.
/// Candidates retain the existing ID predicate as the final authority, so a
/// bare ID can match a group alias without merging explicit C2C/group IDs.
class _ConversationStructureIndex {
  final _candidates = <String, Set<int>>{};
  final _ids = <String>[];
  final _rows = <V2TimConversation>[];
  final _positions = Map<V2TimConversation, int>.identity();

  static Set<String> _keys(String id) {
    final raw = id.trim();
    if (raw.isEmpty) return const <String>{};
    final comparable = MessageConversationId.normalizeComparableKey(raw);
    return <String>{
      'raw:$raw',
      'id:$comparable',
      'group:${ChatIdFormat.groupEquivalenceToken(raw)}',
      'group:${ChatIdFormat.groupEquivalenceToken(comparable)}',
    };
  }

  void rebuild(List<V2TimConversation> rows) {
    _candidates.clear();
    _ids.clear();
    _rows.clear();
    _positions.clear();
    for (final row in rows) {
      append(row);
    }
  }

  void append(V2TimConversation row) {
    final position = _rows.length;
    final id = row.conversationID;
    _rows.add(row);
    _ids.add(id);
    _positions[row] = position;
    for (final key in _keys(id)) {
      (_candidates[key] ??= <int>{}).add(position);
    }
  }

  void replace(int position, V2TimConversation row) {
    final previous = _rows[position];
    final id = row.conversationID;
    if (_ids[position] != id) {
      for (final key in _keys(_ids[position])) {
        final positions = _candidates[key];
        positions?.remove(position);
        if (positions?.isEmpty == true) _candidates.remove(key);
      }
      _ids[position] = id;
      for (final key in _keys(id)) {
        (_candidates[key] ??= <int>{}).add(position);
      }
    }
    if (!identical(previous, row)) {
      if (_positions[previous] == position) _positions.remove(previous);
      _rows[position] = row;
    }
    _positions[row] = position;
  }

  int find(
    String id, {
    V2TimConversation? incoming,
    bool preferLastComparable = false,
  }) {
    // SDK callbacks can return the same mutable object after changing its ID.
    // Repair that single identity before consulting its former ID candidates.
    final knownPosition = incoming == null ? null : _positions[incoming];
    if (knownPosition != null) replace(knownPosition, incoming!);
    final candidates = <int>{};
    for (final key in _keys(id)) {
      candidates.addAll(_candidates[key] ?? const <int>{});
    }
    var first = -1;
    var lastComparable = -1;
    final comparable = MessageConversationId.normalizeComparableKey(id);
    for (final position in candidates) {
      final row = _rows[position];
      replace(position, row);
      final currentId = _ids[position];
      if (!MessageConversationId.sameConversation(currentId, id)) continue;
      if (first < 0 || position < first) first = position;
      if (preferLastComparable &&
          MessageConversationId.normalizeComparableKey(currentId) ==
              comparable &&
          position > lastComparable) {
        lastComparable = position;
      }
    }
    if (lastComparable >= 0) return lastComparable;
    if (first >= 0) return first;
    // An exported SDK row can have been mutated without a callback carrying
    // that identity. Keep the old miss fallback for this compatibility case;
    // ordinary existing-row patches and equivalent aliases never scan here.
    for (var position = 0; position < _rows.length; position++) {
      final row = _rows[position];
      replace(position, row);
      if (MessageConversationId.sameConversation(_ids[position], id)) {
        return position;
      }
    }
    return -1;
  }
}

/// Only lives while one bounded SDK ByIDs request is outstanding.
class _SdkRestoreRead {
  _SdkRestoreRead(this.ids);
  final List<String> ids;
  final changes = <String, ({V2TimConversation? row, bool draft, bool last})>{};
}

class ConversationTabStore extends ChangeNotifier {
  ConversationTabStore._() {
    ConversationUnreadAggregate.instance.sdkCalibrationRevision
        .addListener(_reconcileSdkUnread);
  }

  static final ConversationTabStore instance = ConversationTabStore._();

  void _reconcileSdkUnread() {
    final aggregate = ConversationUnreadAggregate.instance;
    if (!aggregate.usesSdkUnread) return;
    flushRealtimePatches();
    final patches = <V2TimConversation>[];
    for (final rows in _items.values) {
      for (final row in rows) {
        final count = aggregate.sdkUnreadCountFor(row.conversationID);
        if (count == null || count == row.unreadCount) continue;
        patches.add(mergePatchRow(
          existing: row,
          incoming: V2TimConversation(
              conversationID: row.conversationID, unreadCount: count),
          useIncomingUnread: true,
        ));
      }
    }
    applyPatches(patches,
        reason: 'sdk_unread_calibration',
        explicitUnreadIds: patches.map((row) => row.conversationID).toSet(),
        preserveOrder: true,
        preserveStructureFields: true,
        allowNew: false);
  }

  final ConversationChangeJournal _contentChanges = ConversationChangeJournal();

  Set<String>? contentChangesSince(int revision) {
    flushRealtimePatches();
    return _contentChanges.changesSince(revision);
  }

  // Only the SDK callback entry buffers work. User mutations and synchronous
  // reads drain it first, so older callbacks cannot overwrite later actions.
  final Map<String, V2TimConversation> _pendingRealtimeRows = {};
  Timer? _realtimeBatchTimer;
  bool _realtimePreserveOrder = false;
  bool _flushingRealtimeBatch = false;

  void enqueueRealtimePatches(
    List<V2TimConversation> incoming, {
    required String reason,
    bool preserveOrder = false,
  }) {
    if (incoming.isEmpty) return;
    if (!ConversationPerfFlags.tabStoreNotifyCoalesceEnabled) {
      applyPatches(incoming,
          reason: reason,
          explicitUnreadIds: incoming.map((row) => row.conversationID).toSet(),
          preserveOrder: preserveOrder);
      return;
    }
    if (_pendingRealtimeRows.isNotEmpty &&
        _realtimePreserveOrder != preserveOrder) {
      flushRealtimePatches();
    }
    _realtimePreserveOrder = preserveOrder;
    for (final raw in incoming) {
      final key =
          _deferredProjectionKey(raw.conversationID, convType: _typeOf(raw));
      if (raw.conversationID.trim().isEmpty) continue;
      final previous = _pendingRealtimeRows[key];
      final row = previous == null
          ? mergePatchRow(
              existing: raw,
              incoming: raw,
              useIncomingUnread: true,
              useIncomingDraft: true,
              useIncomingLastMessage: true,
            )
          : mergePatchRow(
              existing: previous,
              incoming: raw,
              useIncomingUnread: true,
            );
      // Do not read conversationForId here: it flushes the pending batch and
      // would turn a multi-conversation burst into one rebuild per message.
      // Keep an absent count absent until the SDK cache/existing row resolves it.
      row.unreadCount = raw.unreadCount ??
          previous?.unreadCount ??
          ConversationUnreadAggregate.instance
              .sdkUnreadCountFor(raw.conversationID);
      _pendingRealtimeRows[key] = row;
      // ByIDs restores may finish before the publication timer fires.
      _recordRestorePatch(row, draft: false, last: false);
    }
    if (_pendingRealtimeRows.isEmpty || _realtimeBatchTimer != null) return;
    final generation = _sessionGeneration;
    // A fixed deadline, not a trailing debounce: a busy stream must publish.
    _realtimeBatchTimer = Timer(
      ConversationPerfFlags.tabStoreNotifyCoalesceDelay,
      () {
        if (generation == _sessionGeneration) flushRealtimePatches();
      },
    );
  }

  void flushRealtimePatches() {
    if (_flushingRealtimeBatch || _pendingRealtimeRows.isEmpty) return;
    _realtimeBatchTimer?.cancel();
    _realtimeBatchTimer = null;
    final rows = _pendingRealtimeRows.values.toList(growable: false);
    final preserveOrder = _realtimePreserveOrder;
    _pendingRealtimeRows.clear();
    _flushingRealtimeBatch = true;
    try {
      applyPatches(rows,
          reason: 'sdk_realtime_batch',
          explicitUnreadIds: rows.map((row) => row.conversationID).toSet(),
          preserveOrder: preserveOrder);
    } finally {
      _flushingRealtimeBatch = false;
    }
  }

  // The typed SDK windows are the only mutable conversation collections.
  // The combined feed is a cached, read-only projection owned here as well.
  List<V2TimConversation> _displayRows = const [];
  final Map<String, int> _displayPositions = {};
  bool _displayDirty = true;
  bool _displayStructureDirty = true;
  final Set<String> _displayChangedIds = {};
  int _structureRevision = 0;
  int _contentRevision = 0;
  String _ownerScope = '';
  final Map<String, ConversationRowView> _rowViews =
      <String, ConversationRowView>{};
  final Map<String, _ScopedRowViewNotifier> _rowViewNotifiers =
      <String, _ScopedRowViewNotifier>{};

  /// When true, unread=0 drops the row from the current structure (unread filter).
  @visibleForTesting
  bool excludeReadFromStructure = false;

  @visibleForTesting
  int workChangedIdCount = 0;
  @visibleForTesting
  int workRowProjectedCount = 0;
  @visibleForTesting
  int workRowNotifyCount = 0;
  @visibleForTesting
  int workStructureNotifyCount = 0;
  @visibleForTesting
  int workFullSortCount = 0;
  @visibleForTesting
  int lastProjectionCpuUs = 0;

  @visibleForTesting
  int get workActiveRowSubscriptionCount => _rowViewNotifiers.length;

  @visibleForTesting
  void resetWorkCounters() {
    workChangedIdCount = 0;
    workRowProjectedCount = 0;
    workRowNotifyCount = 0;
    workStructureNotifyCount = 0;
    workFullSortCount = 0;
    lastProjectionCpuUs = 0;
  }

  @visibleForTesting
  int get sessionGeneration => _sessionGeneration;

  @visibleForTesting
  String get ownerScope => _ownerScope;

  @visibleForTesting
  void bindOwnerScopeForTest(String owner) {
    final next = owner.trim();
    if (_ownerScope == next) return;
    _ownerScope = next;
    clear();
  }

  bool _pinSortDeferred = false;
  final Expando<List<V2TimConversation>> _readViews = Expando();

  int get structureRevision => _structureRevision;
  int get contentRevision => _contentRevision;
  bool get hasLocalData => _items.values.any((rows) => rows.isNotEmpty);
  List<V2TimConversation> get conversations {
    _resolveDisplayRows();
    return _displayRows;
  }

  /// Exact identity from the committed display projection. Visible feeds
  /// already hold these IDs; resolving them must not scan another SDK window
  /// through the legacy bare-ID / unannounced-ID-mutation compatibility path.
  /// Folder rows absent from this projection are owned by their supplement.
  V2TimConversation? displayConversationForId(String conversationId) {
    _resolveDisplayRows();
    final position = _displayPositions[conversationId.trim()];
    return position == null ? null : _displayRows[position];
  }

  int displayIndexOf(String conversationId) {
    _resolveDisplayRows();
    final row = conversationForId(conversationId);
    return row == null
        ? -1
        : (_displayPositions[row.conversationID.trim()] ?? -1);
  }

  void invalidateDisplay(
      {bool structureChanged = false, Iterable<String> changedIds = const []}) {
    _displayDirty = true;
    _displayStructureDirty |= structureChanged;
    _displayChangedIds.addAll(changedIds);
    _contentRevision++;
    _contentChanges.record(
      _contentRevision,
      // SDK aliases can differ from the ID retained by the display snapshot.
      // Consumers index that retained ID, so publish the accepted row's ID.
      structureChanged || changedIds.isEmpty
          ? null
          : changedIds.map((id) =>
              conversationForId(id)?.conversationID.trim() ?? id.trim()),
    );
    if (structureChanged) _structureRevision++;
  }

  void notifyDisplayFields(Iterable<String> ids, {required String reason}) {
    flushRealtimePatches();
    _lastApplyPatchesReason = reason;
    _lastNotificationStructureChanged = false;
    _lastNotificationChangedIds = ids.toSet();
    notifyListeners();
  }

  void _resolveDisplayRows() {
    flushRealtimePatches();
    if (!_displayDirty) return;
    List<V2TimConversation>? next;
    if (!_displayStructureDirty && _displayChangedIds.isNotEmpty) {
      next = List<V2TimConversation>.of(_displayRows);
      for (final id in _displayChangedIds) {
        final index = _displayPositions[id];
        final row = conversationForId(id);
        if (index == null || row == null) {
          next = null;
          break;
        }
        next![index] = row;
      }
    }
    next ??= ConversationLocalStore.mergeConversationsForUi(
      _items[1]!,
      _items[2]!,
      preserveOrder: _sortFrozenByScroll || _pinSortDeferred,
      previousOrder: _displayRows,
    );
    _displayRows = UnmodifiableListView(next);
    _displayPositions
      ..clear()
      ..addEntries(next.indexed
          .map((entry) => MapEntry(entry.$2.conversationID.trim(), entry.$1)));
    _displayDirty = false;
    _displayStructureDirty = false;
    _displayChangedIds.clear();
  }

  void setPinReorderDeferred(bool deferred) {
    flushRealtimePatches();
    if (_pinSortDeferred == deferred) return;
    _pinSortDeferred = deferred;
    if (deferred) return;
    for (final type in const [1, 2]) {
      if (_sortFrozenByScroll) {
        _sortDirtyTypes.add(type);
      } else {
        _items[type]!.sort(ConversationLocalStore.compareConversationsForUi);
        _rebuildStructureIndex(type);
      }
    }
    _lastApplyPatchesReason = 'pin_reorder';
    _lastNotificationStructureChanged = true;
    _lastNotificationChangedIds = const {};
    notifyListeners();
  }

  static const int defaultPageSize = 50;

  /// 冷启动首屏窗：拉到 30 个就够，覆盖第一屏 + 缓存几屏。
  /// 比 defaultPageSize=50 少处理 40% 的 SDK 会话行。
  static const int coldStartFirstPageSize = 30;

  final Map<int, List<V2TimConversation>> _items =
      <int, List<V2TimConversation>>{
    ConversationType.V2TIM_C2C: <V2TimConversation>[],
    ConversationType.V2TIM_GROUP: <V2TimConversation>[],
  };
  final _structureIndexes = <int, _ConversationStructureIndex>{
    ConversationType.V2TIM_C2C: _ConversationStructureIndex(),
    ConversationType.V2TIM_GROUP: _ConversationStructureIndex(),
  };

  void _rebuildStructureIndex(int type) {
    _structureIndexes[type]!.rebuild(_items[type]!);
    final retained = <String>{
      for (final rows in _items.values)
        for (final row in rows) row.conversationID.trim(),
    };
    _rowViews.removeWhere((id, _) =>
        !retained.contains(id) && !_rowViewNotifiers.containsKey(id));
    ConversationFeedPerf.gauge('conversation_window_rows', retained.length);
    ConversationFeedPerf.gauge(
        'conversation_detached_ids',
        _detachedHeadIds.values.fold<int>(0, (n, ids) => n + ids.length) +
            _detachedTailIds.values.fold<int>(0, (n, ids) => n + ids.length));
  }

  final Map<int, String> _nextSeq = <int, String>{
    ConversationType.V2TIM_C2C: '0',
    ConversationType.V2TIM_GROUP: '0',
  };
  final Set<int> _primedTypes = <int>{};
  final Set<int> _failedLoadTypes = <int>{};
  final Map<int, ConversationTypePageCursor?> _pageCursors =
      <int, ConversationTypePageCursor?>{
    ConversationType.V2TIM_C2C: null,
    ConversationType.V2TIM_GROUP: null,
  };
  // SDK pagination completion is independent of the in-memory window length.
  // Realtime patches can add rows without advancing the SDK cursor.
  final Map<int, bool> _finished = <int, bool>{
    ConversationType.V2TIM_C2C: false,
    ConversationType.V2TIM_GROUP: false,
  };
  final Map<int, bool> _windowTrimmed = <int, bool>{
    ConversationType.V2TIM_C2C: false,
    ConversationType.V2TIM_GROUP: false,
  };
  final Map<int, List<String>> _detachedHeadIds = <int, List<String>>{
    ConversationType.V2TIM_C2C: <String>[],
    ConversationType.V2TIM_GROUP: <String>[],
  };
  final Map<int, List<String>> _detachedTailIds = <int, List<String>>{
    ConversationType.V2TIM_C2C: <String>[],
    ConversationType.V2TIM_GROUP: <String>[],
  };
  final Map<int, Set<String>> _detachedHeadIdSet = <int, Set<String>>{
    ConversationType.V2TIM_C2C: <String>{},
    ConversationType.V2TIM_GROUP: <String>{},
  };
  final Map<int, Set<String>> _detachedTailIdSet = <int, Set<String>>{
    ConversationType.V2TIM_C2C: <String>{},
    ConversationType.V2TIM_GROUP: <String>{},
  };
  final Map<int, Map<String, V2TimConversation>> _detachedRows =
      <int, Map<String, V2TimConversation>>{
    ConversationType.V2TIM_C2C: <String, V2TimConversation>{},
    ConversationType.V2TIM_GROUP: <String, V2TimConversation>{},
  };
  final Map<int, Future<void>?> _loadInFlight = <int, Future<void>?>{};
  // Only retain changes while a page is in flight. A late page must not
  // resurrect deletes or replace a newer SDK callback with older fields.
  final Map<int, Map<String, ({V2TimConversation? row, bool draft, bool last})>>
      _pageChanges = {};
  final Set<int> _resetRequested = <int>{};
  int _sessionGeneration = 0;
  int _acceptedPatchRevision = 0;
  // Weak keys retain an immutable value for admitted rows, including SDK
  // objects subsequently mutated in place. Only touched rows are serialized.
  final Expando<String> _patchRowStates = Expando<String>();
  // Null is a committed clear, not an absent field. Keep the accepted draft
  // beside the row so stale SDK snapshots (including in-place mutations)
  // cannot undo it. Weak keys follow the lifetime of the bounded row cache.
  static final _explicitDraftStates =
      Expando<({String? text, int? timestamp})>();
  final Expando<({bool pinned, int active, int order})> _patchRowOrders =
      Expando<({bool pinned, int active, int order})>();

  static ({bool pinned, int active, int order}) _patchRowOrder(
    V2TimConversation row,
  ) =>
      (
        pinned: row.isPinned == true,
        active: ConversationLocalStore.activeTimeMs(row),
        order: row.orderkey ?? 0,
      );

  static String _patchRowState(V2TimConversation row) {
    final message = row.lastMessage;
    return jsonEncode([
      row.conversationID, row.type, row.userID, row.groupID,
      row.showName ?? '', row.faceUrl ?? '', row.groupType,
      row.unreadCount ?? 0, row.isPinned == true, row.recvOpt ?? 0,
      row.orderkey ?? 0, row.draftText ?? '', row.draftTimestamp ?? 0,
      row.groupAtInfoList?.map((value) => value?.toJson()).toList(),
      row.markList, row.customData, row.conversationGroupList,
      row.c2cReadTimestamp ?? 0, row.groupReadSequence ?? 0,
      // Native SDK toJson uses elemList; local preview edits often update the
      // typed element directly. Include both to preserve edits/withdrawals.
      message?.toJson(), message?.textElem?.toJson(),
      message?.customElem?.toJson(), message?.imageElem?.toJson(),
      message?.soundElem?.toJson(), message?.videoElem?.toJson(),
      message?.fileElem?.toJson(), message?.locationElem?.toJson(),
      message?.faceElem?.toJson(), message?.mergerElem?.toJson(),
      message?.groupTipsElem?.toJson(), message?.nickName,
      message?.friendRemark, message?.nameCard,
      message?.timestamp, message?.userID, message?.groupID,
      message?.revokerInfo?.toJson(),
    ]);
  }

  void _rememberPatchRowState(V2TimConversation row) {
    _patchRowStates[row] ??= _patchRowState(row);
    _patchRowOrders[row] ??= _patchRowOrder(row);
  }

  /// Store-owned accepted writes advance the comparison baseline. Read paths
  /// deliberately keep using _rememberPatchRowState, so an SDK mutation of a
  /// shared object still differs from the last accepted/published value.
  void _refreshPatchRowState(V2TimConversation row) {
    _patchRowStates[row] = _patchRowState(row);
    _patchRowOrders[row] = _patchRowOrder(row);
  }

  void _refreshPagePatchRows(
    Iterable<V2TimConversation> committed,
    Iterable<V2TimConversation> fetched,
  ) {
    final touchedKeys = {
      for (final row in fetched) _projectionKey(row.conversationID),
    };
    for (final row in committed) {
      if (touchedKeys.contains(_projectionKey(row.conversationID))) {
        _refreshPatchRowState(row);
      }
    }
  }

  bool _notificationStructureChanged = true;
  Set<String> _notificationChangedIds = const <String>{};
  bool _lastNotificationAppendOnly = false;
  bool get _lastNotificationStructureChanged => _notificationStructureChanged;
  set _lastNotificationStructureChanged(bool value) {
    _notificationStructureChanged = value;
    if (value) invalidateDisplay(structureChanged: true);
  }

  Set<String> get _lastNotificationChangedIds => _notificationChangedIds;
  set _lastNotificationChangedIds(Set<String> value) {
    _notificationChangedIds = value;
    _displayChangedIds.addAll(value);
    // Content-only commits publish after their IDs are known. Publishing in
    // the structure setter would record an unknown delta and force a rebuild.
    if (!_notificationStructureChanged) {
      invalidateDisplay(changedIds: value);
    }
  }

  bool get lastNotificationStructureChanged =>
      _lastNotificationStructureChanged;

  Set<String> get lastNotificationChangedIds =>
      Set<String>.unmodifiable(_lastNotificationChangedIds);

  bool get lastNotificationAppendOnly => _lastNotificationAppendOnly;

  @override
  void notifyListeners() {
    super.notifyListeners();
    _lastNotificationAppendOnly = false;
  }

  V2TimConversation? conversationForId(String conversationID) {
    flushRealtimePatches();
    final id = conversationID.trim();
    if (id.isEmpty) return null;
    for (final type in const <int>[
      ConversationType.V2TIM_C2C,
      ConversationType.V2TIM_GROUP,
    ]) {
      final index = _structureIndexes[type]!.find(
        id,
        preferLastComparable: true,
      );
      final rows = _items[type]!;
      if (index >= 0 && index < rows.length) return rows[index];
    }
    return null;
  }

  ConversationRowView? rowViewOf(String conversationID) {
    flushRealtimePatches();
    final id = conversationID.trim();
    if (id.isEmpty) return null;
    return _rowViews[id];
  }

  /// Per-row channel. Created only when a mounted row subscribes.
  ValueListenable<ConversationRowView?> rowViewListenable(
      String conversationID) {
    // Subscription setup/teardown must not publish buffered SDK work. Account
    // reset removes listeners before discarding the previous owner's queue.
    final id = conversationID.trim();
    return _rowViewNotifiers.putIfAbsent(id, () {
      return _ScopedRowViewNotifier(
        _rowViews[id],
        onCancel: () {
          final notifier = _rowViewNotifiers.remove(id);
          notifier?.detach();
          notifier?.dispose();
        },
      );
    });
  }

  String rowIdentityKey(String conversationID) {
    final id = conversationID.trim();
    if (_ownerScope.isEmpty) return id;
    return '$_ownerScope|$id';
  }

  List<String> structureIdsForType(int convType) {
    flushRealtimePatches();
    return List<String>.unmodifiable(
      _items[_normalizeType(convType)]!
          .map((row) => row.conversationID.trim())
          .where((id) => id.isNotEmpty),
    );
  }

  /// v18：上一次 `applyPatches` 的 reason，给 listener 用于做 coalesce vs immediate 决策。
  /// 例如 SDK push (`sdk_realtime_authoritative*`) 应 coalesce；用户行为
  /// (`pin_local` / `recv_opt_local` / `c2c_show_name_batch` / `face_url_local` /
  /// `last_message_local` / `archive_restore`) 保持 immediate 避免 48ms 延迟。
  /// 仅在 `applyPatches` 实际触发 patch 时被覆盖（冷启动首屏首次设置）。
  String _lastApplyPatchesReason = 'patch';

  String get lastApplyPatchesReason => _lastApplyPatchesReason;

  // SQLite and unread aggregation commit before this UI-only buffer is used.
  // Keep only each conversation's final projection while a Chat route is open.
  final Map<String, V2TimConversation> _deferredCommittedUpserts =
      <String, V2TimConversation>{};
  final Set<String> _deferredCommittedDeletes = <String>{};
  final Set<String> _deferredCommittedForceAdmitIds = <String>{};
  final Set<String> _deferredCommittedDraftIds = <String>{};
  final Set<String> _deferredCommittedLastMessageIds = <String>{};
  final Set<String> _deferredCommittedUnreadIds = <String>{};
  final Map<String, ConversationUiMove> _deferredCommittedMoves =
      <String, ConversationUiMove>{};
  bool _deferredCommittedStructureChanged = false;
  int _deferredCommittedGeneration = 0;

  bool _coldStartWindowActive = true;
  DateTime? _coldStartWindowOpenedAt;

  // 项 7：暴露冷启动期开关给 SDK push 直塞路径使用。
  //
  // 读取时按时长自愈：正常关窗由 post-home 同步跑完时 [notifyColdStartEnded]
  // 负责，但那条链路依赖实时连接就绪信号，一旦不到达，窗口会永久挂着让 SDK
  // push 始终 preserveOrder，列表既不重排也不通知。这里的副作用是刻意的，
  // 且判定幂等——不用定时器是因为窗口会被 clear 反复重开，没有可靠的挂载点。
  bool get isColdStartWindowActive {
    if (!_coldStartWindowActive) return false;
    final openedAt = _coldStartWindowOpenedAt;
    if (openedAt == null) {
      _coldStartWindowOpenedAt = DateTime.now();
      return true;
    }
    final delay = ConversationPerfFlags.coldStartWindowFallbackDelay;
    if (DateTime.now().difference(openedAt) < delay) return true;
    ConversationPerfGateLog.log(
      'cold_start_window_fallback',
      extras: <String, Object?>{'delayMs': delay.inMilliseconds},
    );
    notifyColdStartEnded();
    return false;
  }

  // 项 9：滚动期冻结 sort。滚动期间 SDK push 不应触发 list.sort，
  // 否则同一会话在 build 之间位置反复跳变。
  // 解冻时只重排排序字段发生变化的类型；无变化的滚动不额外通知。
  final Set<int> _sortDirtyTypes = {};
  bool _sortFrozenByScroll = false;
  bool get isSortFrozenByScroll => _sortFrozenByScroll;

  void setSortFrozenByScroll(bool frozen) {
    flushRealtimePatches();
    if (_sortFrozenByScroll == frozen) return;
    _sortFrozenByScroll = frozen;
    BackgroundMediaGate.instance.setBusy(this, frozen);
    if (frozen || _pinSortDeferred) {
      return;
    }
    // 解冻：仅提交需要重排的类型。
    var any = false;
    for (final type in const [
      ConversationType.V2TIM_C2C,
      ConversationType.V2TIM_GROUP,
    ]) {
      if (!_sortDirtyTypes.remove(type)) continue;
      final list = _items[type];
      if (list == null) continue;
      if (list.length > 1) {
        list.sort(ConversationLocalStore.compareConversationsForUi);
        _rebuildStructureIndex(type);
      }
      // A one-row type can still move relative to the other type in the
      // combined feed. Publish its order change when the freeze ends too.
      any = true;
    }
    if (any) {
      _lastApplyPatchesReason = 'scroll_unfreeze';
      _lastNotificationStructureChanged = true;
      ConversationPerfGateLog.log(
        'tab_store_unfreeze_resort',
        extras: <String, Object?>{
          'c2c': countForType(ConversationType.V2TIM_C2C),
          'group': countForType(ConversationType.V2TIM_GROUP),
        },
      );
      notifyListeners();
    }
  }

  /// 单测注入分页。
  @visibleForTesting
  static Future<
          ({
            List<V2TimConversation> conversationList,
            String nextSeq,
            bool isFinished,
            int code,
            String desc,
          })>
      Function({
    required int convType,
    required String nextSeq,
    required int count,
  })? debugFetchOverride;

  @visibleForTesting
  static Future<({List<V2TimConversation> conversationList, int code})>
      Function(List<String> ids)? debugFetchByIdsOverride;

  /// One bounded SDK read shared by main-list restore and archive hydration.
  /// Callers own their session fence and decide how to project the response.
  Future<({List<V2TimConversation> conversationList, int code})>
      readSdkConversationsByIds(List<String> ids) async {
    if (ids.length > 100) {
      throw ArgumentError.value(
          ids.length, 'ids.length', 'SDK ByIDs limit is 100');
    }
    if (ids.isEmpty) return (conversationList: <V2TimConversation>[], code: 0);
    final override = debugFetchByIdsOverride;
    if (override != null) return override(ids);
    final response = await TencentImSDKPlugin.v2TIMManager
        .getConversationManager()
        .getConversationListByConversationIds(conversationIDList: ids);
    return (
      conversationList: response.data ?? <V2TimConversation>[],
      code: response.code
    );
  }

  final _restoreReads = <_SdkRestoreRead>{};

  /// Unarchive restores current SDK rows, without consulting the archive mirror.
  Future<int> restoreSdkConversationsByIds(Iterable<String> restoredIds) async {
    final ids = restoredIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final generation = _sessionGeneration;
    final admitted = <String>{};
    for (var start = 0; start < ids.length; start += 100) {
      final end = start + 100 < ids.length ? start + 100 : ids.length;
      final read = _SdkRestoreRead(ids.sublist(start, end));
      final unreadRevision =
          ConversationUnreadAggregate.instance.sdkPageRevision;
      _restoreReads.add(read);
      try {
        final result = await readSdkConversationsByIds(read.ids);
        if (generation != _sessionGeneration) return 0;
        if (result.code != 0) continue;
        final rows = <V2TimConversation>[];
        final draftIds = <String>{};
        final lastIds = <String>{};
        for (final sdkRow in result.conversationList) {
          String? requestedId;
          for (final id in read.ids) {
            if (MessageConversationId.sameConversation(
                id, sdkRow.conversationID)) {
              requestedId = id;
              break;
            }
          }
          if (requestedId == null) continue;
          final change = read.changes[requestedId];
          if (change != null && change.row == null) continue;
          final row = change?.row == null
              ? sdkRow
              : mergePatchRow(
                  existing: sdkRow,
                  incoming: change!.row!,
                  useIncomingUnread: change.row!.unreadCount != null,
                  useIncomingDraft: change.draft,
                  useIncomingLastMessage: change.last,
                );
          if (_isExcludedFromMainList(row)) continue;
          rows.add(row);
          if (change?.draft == true) draftIds.add(row.conversationID);
          if (change?.last == true) lastIds.add(row.conversationID);
        }
        // Raw counts are captured before UI decoration; a newer listener wins.
        ConversationUnreadAggregate.instance
            .applySdkPage(rows, startedAtRevision: unreadRevision);
        _restoreReads.remove(read);
        applyPatches(rows,
            reason: 'archive_restore_sdk',
            forceAdmitIds: rows.map((row) => row.conversationID).toSet(),
            explicitUnreadIds: rows
                .where((row) => row.unreadCount != null)
                .map((row) => row.conversationID)
                .toSet(),
            explicitDraftIds: draftIds,
            explicitLastMessageIds: lastIds);
        for (final row in rows) {
          if (_structureIndexes[_typeOf(row)]!.find(row.conversationID) >= 0) {
            admitted.add(row.conversationID);
          }
        }
      } catch (error) {
        if (generation != _sessionGeneration) return 0;
        debugPrint('[ConversationTabStore] SDK restore failed: $error');
      } finally {
        _restoreReads.remove(read);
      }
    }
    return admitted.length;
  }

  void _recordRestorePatch(V2TimConversation raw,
      {required bool draft, required bool last}) {
    for (final read in _restoreReads) {
      for (final id in read.ids) {
        if (!MessageConversationId.sameConversation(id, raw.conversationID)) {
          continue;
        }
        final previous = read.changes[id];
        final snapshot = mergePatchRow(
            existing: previous?.row ?? raw,
            incoming: raw,
            useIncomingUnread: raw.unreadCount != null,
            useIncomingDraft: draft,
            useIncomingLastMessage: last);
        // A metadata-only callback must not invent an explicit zero count.
        snapshot.unreadCount = raw.unreadCount ?? previous?.row?.unreadCount;
        read.changes[id] = (
          row: snapshot,
          draft: (previous?.draft ?? false) || draft,
          last: (previous?.last ?? false) || last,
        );
      }
    }
  }

  List<V2TimConversation> itemsForType(int convType) {
    flushRealtimePatches();
    final type = _normalizeType(convType);
    for (final row in _items[type] ?? const <V2TimConversation>[]) {
      _rememberPatchRowState(row);
    }
    final rows = _items[type]!;
    return _readViews[rows] ??= UnmodifiableListView(rows);
  }

  int countForType(int convType) {
    flushRealtimePatches();
    return (_items[_normalizeType(convType)] ?? const <V2TimConversation>[])
        .length;
  }

  bool finishedForType(int convType) =>
      _finished[_normalizeType(convType)] ?? false;

  bool windowTrimmedForType(int convType) =>
      _windowTrimmed[_normalizeType(convType)] ?? false;

  @visibleForTesting
  List<String> detachedHeadIdsForTest(int convType) =>
      List<String>.from(_detachedHeadIds[_normalizeType(convType)]!);

  @visibleForTesting
  List<String> detachedTailIdsForTest(int convType) =>
      List<String>.from(_detachedTailIds[_normalizeType(convType)]!);

  String nextSeqForType(int convType) =>
      _nextSeq[_normalizeType(convType)] ?? '0';

  bool primedForType(int convType) =>
      _primedTypes.contains(_normalizeType(convType));
  bool lastLoadFailedForType(int convType) =>
      _failedLoadTypes.contains(_normalizeType(convType));
  bool get isLoading => _loadInFlight.values.any((task) => task != null);

  /// 聊天期间是否还有被缓冲、未投影到 TabStore 的已提交批次
  /// （与 [flushDeferredCommittedProjection] 的空判定一致）。
  bool get hasDeferredCommittedProjection =>
      _deferredCommittedUpserts.isNotEmpty ||
      _deferredCommittedDeletes.isNotEmpty ||
      _deferredCommittedMoves.isNotEmpty;

  @visibleForTesting
  int get deferredCommittedProjectionCount =>
      _deferredCommittedUpserts.length + _deferredCommittedDeletes.length;

  ConversationTypePageCursor? pageCursorForType(int convType) =>
      _pageCursors[_normalizeType(convType)];

  String _projectionKey(String conversationID) {
    final raw = conversationID.trim();
    if (raw.isEmpty) return '';
    final normalized = MessageConversationId.normalizeComparableKey(raw);
    return normalized.isEmpty ? raw : normalized;
  }

  String _deferredProjectionKey(String conversationID, {int? convType}) {
    final raw = conversationID.trim();
    if (raw.isEmpty) return '';
    final type = convType ??
        (raw.startsWith('group_') || raw.startsWith('@TGS')
            ? ConversationType.V2TIM_GROUP
            : raw.startsWith('c2c_')
                ? ConversationType.V2TIM_C2C
                : 0);
    return '$type:${_projectionKey(raw)}';
  }

  void invalidateViewPages({required String conversationID, int? convType}) {
    final id = conversationID.trim();
    if (id.isEmpty) return;
    final types =
        convType == 1 || convType == 2 ? <int>[convType!] : const [1, 2];
    for (final type in types) {
      final index = _structureIndexes[type]!.find(id);
      if (index >= 0) {
        _pageCursors[type] = null;
      }
    }
  }

  V2TimConversation? atTypeIndex(int convType, int index) {
    flushRealtimePatches();
    final list = _items[_normalizeType(convType)];
    if (list == null || index < 0 || index >= list.length) {
      return null;
    }
    _rememberPatchRowState(list[index]);
    return list[index];
  }

  int? typeIndexOf(int convType, String conversationId) {
    flushRealtimePatches();
    final id = conversationId.trim();
    if (id.isEmpty) {
      return null;
    }
    final index = _structureIndexes[_normalizeType(convType)]!.find(id);
    return index < 0 ? null : index;
  }

  /// 冷启 / Tab 首次：拉第一页（reset）。
  /// All default first-page callers share one bounded size. Explicit counts
  /// remain authoritative; later pages retain [defaultPageSize].
  Future<void> ensurePrimed({
    int? convType,
    int? count,
    bool coldStart = false,
    String caller = '',
  }) async {
    final effectiveCount = count ?? coldStartFirstPageSize;
    if (convType != null) {
      final type = _normalizeType(convType);
      // Realtime patches may arrive before the first SDK page. Only an actual
      // successful page marks this type primed; later entry preserves its cursor.
      if (_primedTypes.contains(type) && !_failedLoadTypes.contains(type)) {
        StartupPerfLog.markTagged(
          'ensurePrimed_already',
          category: 'cold_start',
          details: <String, Object>{
            'convType': type,
            'caller': caller,
            'coldStart': coldStart,
          },
        );
        return;
      }
      // Entry, login and the post-home stage share the same first request.
      // Reusing it must not enqueue another reset after that page succeeds.
      final pending = _loadInFlight[type];
      if (pending != null) {
        StartupPerfLog.markTagged(
          'ensurePrimed_join',
          category: 'cold_start',
          details: <String, Object>{
            'convType': type,
            'caller': caller,
            'coldStart': coldStart,
          },
        );
        await pending;
        return;
      }
      StartupPerfLog.markTagged(
        'ensurePrimed_real_start',
        category: 'cold_start',
        details: <String, Object>{
          'convType': type,
          'caller': caller,
          'coldStart': coldStart,
        },
      );
      await loadFirstPage(convType: type, count: effectiveCount);
      StartupPerfLog.markTagged(
        'ensurePrimed_real_finish',
        category: 'cold_start',
        details: <String, Object>{
          'convType': type,
          'caller': caller,
          'coldStart': coldStart,
        },
      );
      return;
    }
    await Future.wait<void>([
      ensurePrimed(
        convType: ConversationType.V2TIM_C2C,
        count: effectiveCount,
        coldStart: coldStart,
        caller: caller,
      ),
      ensurePrimed(
        convType: ConversationType.V2TIM_GROUP,
        count: effectiveCount,
        coldStart: coldStart,
        caller: caller,
      ),
    ]);
  }

  Future<void> loadFirstPage({
    required int convType,
    int count = defaultPageSize,
  }) {
    final type = _normalizeType(convType);
    return _load(type: type, reset: true, count: count);
  }

  Future<void> loadMore({
    required int convType,
    int count = defaultPageSize,
    String? viewportAnchorId,
  }) {
    final type = _normalizeType(convType);
    if (_finished[type] == true) {
      return Future<void>.value();
    }
    return _load(
      type: type,
      reset: false,
      count: count,
      viewportAnchorId: viewportAnchorId,
    );
  }

  /// User-visible pagination uses this store's cursor, independently of the
  /// legacy SQLite sync lane. Skip a bounded number of wholly filtered pages.
  Future<bool> loadMoreForViewport({
    required int convType,
    String? viewportAnchorId,
  }) async {
    final type = _normalizeType(convType);
    final generation = _sessionGeneration;
    if (_detachedTailIds[type]!.isNotEmpty) {
      final restored = await restoreOlderSuffixForViewport(convType: type);
      if (generation != _sessionGeneration) return false;
      if (restored > 0) return true;
    }
    var advanced = false;
    for (var attempt = 0; attempt < 3 && !finishedForType(type); attempt++) {
      final before = countForType(type);
      final cursor = nextSeqForType(type);
      await loadMore(
        convType: type,
        viewportAnchorId: viewportAnchorId,
      );
      if (generation != _sessionGeneration) return false;
      final grew = countForType(type) > before;
      final moved = nextSeqForType(type) != cursor;
      advanced = advanced || grew || moved || finishedForType(type);
      if (grew || finishedForType(type) || !moved) break;
    }
    return advanced;
  }

  /// Prepend a contiguous newer page from IDs trimmed off the window head.
  Future<int> restoreNewerPrefixForViewport({
    required int convType,
    int? count,
  }) async {
    flushRealtimePatches();
    final type = _normalizeType(convType);
    final head = _detachedHeadIds[type]!;
    if (head.isEmpty) {
      return 0;
    }
    final pageSize = (count != null && count > 0)
        ? count
        : ConversationPerfFlags.uiAppendOlderHotHeadReserve;
    final take = pageSize < head.length ? pageSize : head.length;
    final pageIds = head.sublist(head.length - take);
    final rows = await _hydrateDetachedRows(type, pageIds);
    if (rows.isEmpty) {
      return 0;
    }
    final recovered = <String>{
      for (final row in rows) row.conversationID.trim(),
    }..removeWhere((id) => id.isEmpty);
    head.removeRange(head.length - take, head.length);
    _detachedHeadIdSet[type]!.removeAll(pageIds);
    for (final id in pageIds.reversed) {
      if (!recovered.contains(id) && id.isNotEmpty) {
        head.add(id);
        _detachedHeadIdSet[type]!.add(id);
      }
    }
    for (final id in recovered) {
      _detachedRows[type]!.remove(id);
    }
    final current = _items[type] ?? const <V2TimConversation>[];
    _items[type] = ConversationLocalStore.mergeConversationsForUi(
      rows,
      current,
    );
    _capWindowFromEnd(type);
    _rebuildStructureIndex(type);
    _refreshPagePatchRows(_items[type]!, rows);
    _syncWindowTrimmed(type);
    _lastApplyPatchesReason = 'restore_newer_prefix';
    _lastNotificationStructureChanged = true;
    _lastNotificationChangedIds = recovered;
    notifyListeners();
    return rows.length;
  }

  /// Append a contiguous older page from IDs trimmed off the window tail.
  Future<int> restoreOlderSuffixForViewport({
    required int convType,
    int? count,
  }) async {
    flushRealtimePatches();
    final type = _normalizeType(convType);
    final tail = _detachedTailIds[type]!;
    if (tail.isEmpty) {
      return 0;
    }
    final pageSize = (count != null && count > 0)
        ? count
        : ConversationPerfFlags.uiAppendOlderHotHeadReserve;
    final take = pageSize < tail.length ? pageSize : tail.length;
    final pageIds = tail.sublist(0, take);
    final rows = await _hydrateDetachedRows(type, pageIds);
    if (rows.isEmpty) {
      return 0;
    }
    final recovered = <String>{
      for (final row in rows) row.conversationID.trim(),
    }..removeWhere((id) => id.isEmpty);
    tail.removeRange(0, take);
    _detachedTailIdSet[type]!.removeAll(pageIds);
    for (final id in pageIds.reversed) {
      if (!recovered.contains(id) && id.isNotEmpty) {
        tail.insert(0, id);
        _detachedTailIdSet[type]!.add(id);
      }
    }
    for (final id in recovered) {
      _detachedRows[type]!.remove(id);
    }
    final current = _items[type] ?? const <V2TimConversation>[];
    _items[type] = ConversationLocalStore.mergeConversationsForUi(
      current,
      rows,
    );
    _capWindowFromStart(type);
    _rebuildStructureIndex(type);
    _refreshPagePatchRows(_items[type]!, rows);
    _syncWindowTrimmed(type);
    _lastApplyPatchesReason = 'restore_older_suffix';
    _lastNotificationStructureChanged = true;
    _lastNotificationChangedIds = recovered;
    notifyListeners();
    return rows.length;
  }

  /// Listener / 发送预览：只改已加载窗内行；热消息可插入头部。
  void applyPatches(
    List<V2TimConversation> incoming, {
    String reason = 'patch',
    Set<String> forceAdmitIds = const <String>{},
    Set<String> explicitDraftIds = const <String>{},
    Set<String> explicitLastMessageIds = const <String>{},
    Set<String> explicitUnreadIds = const <String>{},
    bool allowNew = true,
    bool preserveOrder = false,
    bool preserveStructureFields = false,
    bool notify = true,
    String? ownerScope,
    int? expectedSessionGeneration,
  }) {
    flushRealtimePatches();
    ConversationPerfGateLog.log(
      'patch_enter',
      extras: <String, Object?>{
        'reason': reason,
        'count': incoming.length,
        'notify': notify,
        'preserveOrder': preserveOrder,
      },
    );
    if (expectedSessionGeneration != null &&
        expectedSessionGeneration != _sessionGeneration) {
      return;
    }
    if (_ownerScope.isNotEmpty &&
        ownerScope != null &&
        ownerScope.trim() != _ownerScope) {
      return;
    }
    if (incoming.isEmpty) {
      return;
    }
    final projectionWatch = Stopwatch()..start();
    // Assign the reason only after a semantic change is accepted.
    final rowsByType = <int, List<V2TimConversation>>{};
    final forceAdmitKeys =
        forceAdmitIds.map(_projectionKey).where((id) => id.isNotEmpty).toSet();
    final explicitDraftKeys = explicitDraftIds
        .map(_projectionKey)
        .where((id) => id.isNotEmpty)
        .toSet();
    final explicitLastMessageKeys = explicitLastMessageIds
        .map(_projectionKey)
        .where((id) => id.isNotEmpty)
        .toSet();
    final explicitUnreadKeys = explicitUnreadIds
        .map(_projectionKey)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final incomingRow in incoming) {
      final aggregate = ConversationUnreadAggregate.instance;
      final count = aggregate.sdkUnreadCountFor(incomingRow.conversationID);
      final raw = aggregate.usesSdkUnread && count != null
          ? mergePatchRow(
              existing: incomingRow,
              incoming: V2TimConversation(
                  conversationID: incomingRow.conversationID,
                  unreadCount: count),
              useIncomingUnread: true,
            )
          : incomingRow;
      final id = raw.conversationID.trim();
      if (id.isEmpty) continue;
      if (explicitDraftKeys.contains(_projectionKey(id))) {
        _explicitDraftStates[raw] =
            (text: raw.draftText, timestamp: raw.draftTimestamp);
      }
      if (aggregate.usesSdkUnread && count != null) {
        explicitUnreadKeys.add(_projectionKey(id));
      }
      _recordRestorePatch(raw,
          draft: explicitDraftKeys.contains(_projectionKey(id)),
          last: explicitLastMessageKeys.contains(_projectionKey(id)));
      ConversationLocalStore.decorateConversationForUi(raw);
      ConversationPinSyncService.instance.applySdkPinProjection(raw);
      final changes = _pageChanges[_typeOf(raw)];
      if (changes != null) {
        final key = _projectionKey(id);
        final previous = changes[key];
        changes[key] = (
          row: previous?.row == null
              ? raw
              : mergePatchRow(
                  existing: previous!.row!,
                  incoming: raw,
                  useIncomingUnread: raw.unreadCount != null,
                  useIncomingDraft: explicitDraftKeys.contains(key),
                  useIncomingLastMessage:
                      explicitLastMessageKeys.contains(key)),
          draft: (previous?.draft ?? false) || explicitDraftKeys.contains(key),
          last:
              (previous?.last ?? false) || explicitLastMessageKeys.contains(key)
        );
      }
      rowsByType
          .putIfAbsent(_typeOf(raw), () => <V2TimConversation>[])
          .add(raw);
    }

    var any = false;
    var structureChanged = false;
    final changedIds = <String>{};
    final orderChangedIds = <String>{};
    final droppedIds = <String>{};
    for (final entry in rowsByType.entries) {
      final type = entry.key;
      final previousList = _items[type] ?? const <V2TimConversation>[];
      var list = previousList;
      void ensureWritable() {
        if (identical(list, previousList)) {
          list = List<V2TimConversation>.from(previousList);
        }
      }

      final structureIndex = _structureIndexes[type]!;
      var changed = false;
      var orderChanged = false;
      final typeOrderChangedIds = <String>{};
      // SDK can emit a large initial changed-list immediately after auth.
      // During the cold-start window, admit only the sorted first-screen
      // budget; the rest remains reachable through typed pagination. Existing
      // rows are still fully patched, and explicit hot rows may bypass this
      // budget so a new/unread conversation is never lost.
      final boundedColdStartBatch =
          isColdStartWindowActive && list.length < coldStartFirstPageSize;
      final rows = List<V2TimConversation>.from(entry.value);
      if (boundedColdStartBatch && rows.length > 1) {
        rows.sort(ConversationLocalStore.compareConversationsForUi);
      }
      var admissionBudget = isColdStartWindowActive
          ? coldStartFirstPageSize - list.length
          : rows.length;
      if (admissionBudget < 0) admissionBudget = 0;
      final unreadRows = <V2TimConversation>[];
      for (final raw in rows) {
        final id = raw.conversationID.trim();
        final key = _projectionKey(id);
        final index = structureIndex.find(
          id,
          incoming: raw,
          preferLastComparable: true,
        );
        if (_isExcludedFromMainList(raw)) {
          if (index >= 0) {
            ensureWritable();
            list.removeAt(index);
            structureIndex.rebuild(list);
            changed = true;
            structureChanged = true;
            changedIds.add(id);
            droppedIds.add(id);
          }
          continue;
        }
        if (index >= 0) {
          final existing = list[index];
          if (explicitDraftKeys.contains(key)) {
            // An explicit clear can equal the current empty row. Preserve
            // its authority even when the value comparison skips rebuilding.
            _explicitDraftStates[existing] =
                (text: raw.draftText, timestamp: raw.draftTimestamp);
          }
          final currentState = _patchRowState(existing);
          final beforeState = _patchRowStates[existing] ?? currentState;
          final beforeOrder =
              _patchRowOrders[existing] ?? _patchRowOrder(existing);
          final incomingState =
              identical(existing, raw) ? currentState : _patchRowState(raw);
          // SDK models are mutable. A patch equal to the last accepted state
          // still has work to do when the current shared object differs.
          if (beforeState == incomingState && currentState == incomingState) {
            _patchRowStates[existing] = beforeState;
            continue;
          }
          final merged = mergePatchRow(
            existing: existing,
            incoming: raw,
            useIncomingDraft: explicitDraftKeys.contains(key),
            useIncomingLastMessage: explicitLastMessageKeys.contains(key),
            useIncomingUnread: explicitUnreadKeys.contains(key),
            preserveStructureFields: preserveStructureFields,
          );
          final afterState = _patchRowState(merged);
          if (beforeState == afterState && currentState == afterState) {
            _patchRowStates[existing] = beforeState;
            continue;
          }
          _patchRowStates[merged] = afterState;
          final afterOrder = _patchRowOrder(merged);
          _patchRowOrders[merged] = afterOrder;
          if (!preserveStructureFields &&
              afterOrder.pinned != beforeOrder.pinned) {
            structureChanged = true;
          }
          orderChanged = orderChanged || beforeOrder != afterOrder;
          if (beforeOrder != afterOrder) {
            orderChangedIds.add(id);
            typeOrderChangedIds.add(id);
          }
          ensureWritable();
          list[index] = merged;
          structureIndex.replace(index, merged);
          unreadRows.add(merged);
          changed = true;
          changedIds.add(id);
          continue;
        }
        // 未在已加载窗：仅热会话（置顶/未读/比窗头更新）插入，避免冷会话撑爆内存。
        final explicitlyAdmitted = forceAdmitKeys.contains(key);
        final cap = ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType;
        final admitAtHead = !_sortFrozenByScroll &&
            !preserveOrder &&
            _detachedHeadIds[type]!.isEmpty &&
            list.isNotEmpty &&
            ConversationLocalStore.compareConversationsForUi(raw, list.first) <
                0;
        if (cap > 0 &&
            list.length >= cap &&
            !admitAtHead &&
            !explicitlyAdmitted) {
          // Keep the current viewport stable. New rows remain reachable through
          // detached pagination and still contribute to account unread totals.
          if (allowNew || explicitlyAdmitted) {
            if (list.isNotEmpty &&
                ConversationLocalStore.compareConversationsForUi(
                        raw, list.last) >
                    0) {
              _prependDetachedTail(type, [raw]);
            } else {
              _insertDetachedHeadFront(type, id, raw);
            }
            ConversationUnreadAggregate.instance
                .updateSdkProjectionIfActive([raw]);
            ConversationFeedPerf.increment(
                'conversation_patch_deferred_at_capacity');
          }
          continue;
        }
        if (_windowTrimmed[type] == true &&
            !admitAtHead &&
            list.isNotEmpty &&
            !explicitlyAdmitted) {
          final vsHead =
              ConversationLocalStore.compareConversationsForUi(raw, list.first);
          if (vsHead < 0) {
            _insertDetachedHeadFront(type, id, raw);
            continue;
          }
          final vsTail =
              ConversationLocalStore.compareConversationsForUi(raw, list.last);
          if (vsTail > 0) {
            continue;
          }
          if (!allowNew) {
            continue;
          }
          ensureWritable();
          list.add(raw);
          if (_detachedHeadIdSet[type]!.remove(id))
            _detachedHeadIds[type]!.remove(id);
          if (_detachedTailIdSet[type]!.remove(id))
            _detachedTailIds[type]!.remove(id);
          _detachedRows[type]!.remove(id);
          _syncWindowTrimmed(type);
          _refreshPatchRowState(raw);
          orderChanged = true;
          typeOrderChangedIds.add(id);
          orderChangedIds.add(id);
          unreadRows.add(raw);
          structureIndex.append(raw);
          changed = true;
          structureChanged = true;
          changedIds.add(id);
          continue;
        }
        if (allowNew &&
            (explicitlyAdmitted ||
                (admissionBudget > 0 &&
                    (boundedColdStartBatch || _shouldAdmitHot(raw, list))))) {
          ensureWritable();
          list.add(raw);
          if (_detachedHeadIdSet[type]!.remove(id))
            _detachedHeadIds[type]!.remove(id);
          if (_detachedTailIdSet[type]!.remove(id))
            _detachedTailIds[type]!.remove(id);
          _detachedRows[type]!.remove(id);
          _syncWindowTrimmed(type);
          _refreshPatchRowState(raw);
          orderChanged = true;
          typeOrderChangedIds.add(id);
          orderChangedIds.add(id);
          unreadRows.add(raw);
          structureIndex.append(raw);
          if (!explicitlyAdmitted && admissionBudget > 0) {
            admissionBudget--;
          }
          changed = true;
          structureChanged = true;
          changedIds.add(id);
        }
      }
      if (!changed) continue;
      // 项 9：滚动期冻结 sort。滚动期间不重排，避免会话原地跳变。
      // 解冻时由 setSortFrozenByScroll(false) 触发重排。
      if (_sortFrozenByScroll && orderChanged) _sortDirtyTypes.add(type);
      // A row can move across the C2C/group boundary even when its order
      // within its own type stays unchanged (including a one-row type).
      if (orderChanged &&
          !preserveOrder &&
          !_sortFrozenByScroll &&
          !_pinSortDeferred &&
          (_items[type == 1 ? 2 : 1]?.isNotEmpty ?? false)) {
        structureChanged = true;
      }
      if (!preserveOrder &&
          !_sortFrozenByScroll &&
          !_pinSortDeferred &&
          list.length > 1 &&
          (orderChanged || _sortDirtyTypes.contains(type))) {
        final previous = _items[type] ?? const <V2TimConversation>[];
        final previousIds = <String>[
          for (final row in previous) row.conversationID,
        ];
        final relocated = !_sortDirtyTypes.contains(type) &&
            _tryRelocateAffected(list, typeOrderChangedIds);
        if (!relocated) {
          list.sort(ConversationLocalStore.compareConversationsForUi);
          workFullSortCount++;
          ConversationFeedPerf.increment('conversation_full_sort_count');
        }
        if (previous.length != list.length) {
          structureChanged = true;
        } else {
          for (var i = 0; i < list.length; i++) {
            if (previousIds[i] != list[i].conversationID) {
              structureChanged = true;
              break;
            }
          }
        }
        _sortDirtyTypes.remove(type);
        structureIndex.rebuild(list);
      }
      _items[type] = list;
      if (list.length >
              ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType &&
          ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType > 0) {
        _capWindowFromEnd(type);
        if (forceAdmitKeys.isNotEmpty) {
          final window = _items[type]!;
          for (final raw in rows) {
            final id = raw.conversationID.trim();
            if (id.isEmpty ||
                !forceAdmitKeys.contains(_projectionKey(id))) {
              continue;
            }
            if (window.any((row) => MessageConversationId.sameConversation(
                  row.conversationID,
                  id,
                ))) {
              continue;
            }
            window.add(raw);
            if (_detachedHeadIdSet[type]!.remove(id)) {
              _detachedHeadIds[type]!.remove(id);
            }
            if (_detachedTailIdSet[type]!.remove(id)) {
              _detachedTailIds[type]!.remove(id);
            }
            _detachedRows[type]!.remove(id);
          }
          final capLimit =
              ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType;
          while (window.length > capLimit && capLimit > 0) {
            final dropIndex = window.lastIndexWhere(
              (row) => !forceAdmitKeys.contains(
                _projectionKey(row.conversationID.trim()),
              ),
            );
            if (dropIndex < 0) {
              break;
            }
            final dropped = window.removeAt(dropIndex);
            _prependDetachedTail(type, [dropped]);
          }
          _syncWindowTrimmed(type);
        }
        _rebuildStructureIndex(type);
      }
      ConversationUnreadAggregate.instance
          .updateSdkProjectionIfActive(unreadRows);
      any = true;
    }
    if (!any) {
      lastProjectionCpuUs = projectionWatch.elapsedMicroseconds;
      ConversationFeedPerf.recordDurationMicros(
        'conversation_projection_cpu',
        lastProjectionCpuUs,
      );
      return;
    }
    for (final id in droppedIds) {
      _dropRowView(id);
    }
    _projectChangedRows(changedIds.difference(droppedIds));
    _acceptedPatchRevision++;
    _lastApplyPatchesReason = reason;
    String? focusedPatchId;
    for (final raw in incoming) {
      if (ConversationDraftLeaveTrace.isFocused(raw.conversationID)) {
        focusedPatchId = raw.conversationID;
        break;
      }
    }
    if (focusedPatchId == null) {
      for (final id in changedIds) {
        if (ConversationDraftLeaveTrace.isFocused(id)) {
          focusedPatchId = id;
          break;
        }
      }
    }
    if (focusedPatchId != null) {
      final matchedId = focusedPatchId;
      final row = conversationForId(matchedId);
      final patched = changedIds.any(
        (id) => MessageConversationId.sameConversation(id, matchedId),
      );
      ConversationDraftLeaveTrace.stage(
        'tabstore_draft',
        conversationId: focusedPatchId,
        draftText: row?.draftText,
        extras: <String, Object?>{
          'reason': _lastApplyPatchesReason,
          'patched': patched,
        },
      );
    }
    ConversationPerfGateLog.log(
      'tab_store_patch',
      extras: <String, Object?>{
        'reason': reason,
        'count': incoming.length,
        'c2c': countForType(ConversationType.V2TIM_C2C),
        'group': countForType(ConversationType.V2TIM_GROUP),
        'ui_source': 'sdk_store',
      },
    );
    workChangedIdCount += changedIds.length;
    ConversationFeedPerf.increment(
      'conversation_changed_id_count',
      amount: changedIds.length,
    );
    ConversationFeedPerf.gauge(
      'conversation_active_row_subscription_count',
      _rowViewNotifiers.length,
    );
    _lastNotificationStructureChanged = structureChanged;
    _lastNotificationChangedIds = changedIds;
    lastProjectionCpuUs = projectionWatch.elapsedMicroseconds;
    ConversationFeedPerf.recordDurationMicros(
      'conversation_projection_cpu',
      lastProjectionCpuUs,
    );
    ConversationPerfGateLog.log(
      'patch_exit',
      extras: <String, Object?>{
        'reason': reason,
        'notified': notify && structureChanged,
      },
    );
    if (notify && structureChanged) {
      workStructureNotifyCount++;
      ConversationFeedPerf.increment('conversation_structure_notify_count');
      notifyListeners();
    }
  }

  /// SDK listener / 置顶回写：合并 patch，禁止元数据-only 更新抹掉预览与未读。
  @visibleForTesting
  static V2TimConversation mergePatchRow({
    required V2TimConversation existing,
    required V2TimConversation incoming,
    bool useIncomingDraft = false,
    bool useIncomingLastMessage = false,
    bool useIncomingUnread = false,
    bool preserveStructureFields = false,
  }) {
    final id = existing.conversationID.trim();
    final existingUnread = existing.unreadCount ?? 0;
    // Only an SDK count source may change unread. Preview recency and local
    // read watermarks cannot establish whether another device has read it.
    final resolvedUnread = useIncomingUnread
        ? ((incoming.unreadCount ?? existingUnread) < 0
            ? 0
            : (incoming.unreadCount ?? existingUnread))
        : existingUnread;

    var incomingLast = incoming.lastMessage;
    if (!MessageConversationId.messageBelongsToConversation(
      incomingLast,
      id,
    )) {
      incomingLast = null;
    }
    final readBarrier = existingUnread == 0 && resolvedUnread > 0
        ? ConversationLocalStore.instance.readBarrierFor(id)
        : null;
    // A distinct SDK-unread message in the read anchor's second must carry
    // its identity into the row. Keeping the old preview here makes its late
    // read ACK indistinguishable from an ACK for the newly arrived message.
    final unreadAfterReadAnchor = readBarrier != null &&
        readBarrier.lastMessageId.isNotEmpty &&
        readBarrier.lastMessageId == existing.lastMessage?.msgID &&
        (incomingLast?.msgID?.isNotEmpty ?? false) &&
        incomingLast!.msgID != readBarrier.lastMessageId &&
        (incomingLast.timestamp ?? 0) >= readBarrier.lastMessageTimestamp;
    final preferredLast = useIncomingLastMessage || unreadAfterReadAnchor
        ? incomingLast
        : ConversationLastMessagePrefer.preferLastMessage(
            existing: existing.lastMessage,
            incoming: incomingLast,
          );
    if (preferredLast != null) {
      preservePeerReadLastMessageState(
        existing: existing.lastMessage,
        incoming: incomingLast,
        preferred: preferredLast,
      );
    }
    final existingActive = ConversationLocalStore.activeTimeMs(existing);
    final incomingActive = ConversationLocalStore.activeTimeMs(incoming);
    // 项 6-3：mergePatchRow 内部对 orderkey 做单位归一化（毫秒），
    // 与 activeTimeMs 口径一致，避免 tie-break 时数值差 1000 倍。
    final int incomingOrderKeyRaw = incoming.orderkey ?? 0;
    final int incomingOrderKeyNormalized = incomingOrderKeyRaw <= 0
        ? 0
        : (incomingOrderKeyRaw >= 1000000000000
            ? incomingOrderKeyRaw
            : incomingOrderKeyRaw * 1000);
    final int existingOrderKeyRaw = existing.orderkey ?? 0;
    final int existingOrderKeyNormalized = existingOrderKeyRaw <= 0
        ? 0
        : (existingOrderKeyRaw >= 1000000000000
            ? existingOrderKeyRaw
            : existingOrderKeyRaw * 1000);
    final orderkey = incomingActive >= existingActive
        ? (incomingOrderKeyNormalized > 0
            ? incomingOrderKeyNormalized
            : incomingActive)
        : (existingOrderKeyNormalized > 0
            ? existingOrderKeyNormalized
            : existingActive);

    var showName = incoming.showName?.trim().isNotEmpty == true
        ? incoming.showName!.trim()
        : (existing.showName?.trim() ?? '');
    if (id.startsWith('c2c_') ||
        (incoming.userID?.trim().isNotEmpty ?? false)) {
      showName = ConversationC2cShowNamePrefer.preferForConversationIds(
        conversationID: id,
        userID: incoming.userID ?? existing.userID,
        existingShowName: existing.showName,
        incomingShowName: incoming.showName,
        readStore: DisplayNameStore.instance.c2c,
      );
    }

    final acceptedDraft = useIncomingDraft
        ? (text: incoming.draftText, timestamp: incoming.draftTimestamp)
        : _explicitDraftStates[existing];
    final merged = V2TimConversation(
      conversationID: existing.conversationID,
      type: incoming.type ?? existing.type,
      userID: incoming.userID ?? existing.userID,
      groupID: incoming.groupID ?? existing.groupID,
      showName: showName,
      faceUrl: (incoming.faceUrl?.trim().isNotEmpty == true)
          ? incoming.faceUrl
          : existing.faceUrl,
      recvOpt: incoming.recvOpt ?? existing.recvOpt,
      unreadCount: resolvedUnread,
      lastMessage: preferredLast,
      draftText: acceptedDraft != null
          ? acceptedDraft.text
          : (existing.draftText ?? incoming.draftText),
      draftTimestamp: acceptedDraft != null
          ? acceptedDraft.timestamp
          : (existing.draftTimestamp ?? incoming.draftTimestamp),
      isPinned: preserveStructureFields
          ? existing.isPinned
          : (incoming.isPinned ?? existing.isPinned),
      orderkey: preserveStructureFields ? existing.orderkey : orderkey,
      groupType: incoming.groupType ?? existing.groupType,
      groupAtInfoList: incoming.groupAtInfoList ?? existing.groupAtInfoList,
      markList: incoming.markList ?? existing.markList,
      customData: incoming.customData ?? existing.customData,
      conversationGroupList:
          incoming.conversationGroupList ?? existing.conversationGroupList,
      c2cReadTimestamp: incoming.c2cReadTimestamp ?? existing.c2cReadTimestamp,
      groupReadSequence:
          incoming.groupReadSequence ?? existing.groupReadSequence,
    );
    if (acceptedDraft != null) _explicitDraftStates[merged] = acceptedDraft;
    return merged;
  }

  void applyDeleted(List<String> ids, {bool notify = true}) {
    flushRealtimePatches();
    if (ids.isEmpty) {
      return;
    }
    ConversationUnreadAggregate.instance.removeSdkConversations(ids);
    for (final read in _restoreReads) {
      for (final requestedId in read.ids) {
        if (ids.any(
            (id) => MessageConversationId.sameConversation(id, requestedId))) {
          read.changes[requestedId] = (row: null, draft: false, last: false);
        }
      }
    }
    for (final entry in _pageChanges.entries) {
      for (final id in ids) {
        if (id.startsWith('c2c_') && entry.key != ConversationType.V2TIM_C2C)
          continue;
        if (id.startsWith('group_') &&
            entry.key != ConversationType.V2TIM_GROUP) continue;
        entry.value[_projectionKey(id)] =
            (row: null, draft: false, last: false);
      }
    }
    var any = false;
    for (final type in const [
      ConversationType.V2TIM_C2C,
      ConversationType.V2TIM_GROUP,
    ]) {
      for (final id in ids) {
        invalidateViewPages(conversationID: id, convType: type);
      }
      final list = _items[type];
      if (list == null || list.isEmpty) {
        continue;
      }
      final next = list
          .where(
            (c) => !ids.any(
              (id) => MessageConversationId.sameConversation(
                c.conversationID,
                id,
              ),
            ),
          )
          .toList();
      if (next.length != list.length) {
        _items[type] = next;
        _rebuildStructureIndex(type);
        final tail = ConversationLocalStore.oldestPagingCursor(next);
        if (tail != null) {
          _pageCursors[type] = ConversationTypePageCursor(
            pinned: tail.isPinned == true,
            activeTime: ConversationLocalStore.pagingAnchorMs(tail),
            orderKey: tail.orderkey ?? 0,
            // 项 8-1：构造 cursor 时填 sdkOrderKey，与 SQL ORDER BY 对齐。
            sdkOrderKey: tail.orderkey ?? 0,
            conversationID: tail.conversationID,
          );
        }
        any = true;
      }
    }
    if (any) _acceptedPatchRevision++;
    if (any) {
      for (final id in ids) {
        _dropRowView(id.trim());
      }
      _lastApplyPatchesReason = 'conversation_delete';
      _lastNotificationStructureChanged = true;
      _lastNotificationChangedIds = ids.toSet();
      if (notify) {
        workStructureNotifyCount++;
        ConversationFeedPerf.increment('conversation_structure_notify_count');
        notifyListeners();
      }
    }
  }

  /// Applies committed local business changes alongside SDK-owned pages and
  /// callbacks, coalescing row patches, deletes and cursor invalidation.
  void applyCommittedViewBatch(
    ConversationUiSnapshotBatch<V2TimConversation> batch, {
    Set<String> forceAdmitIds = const <String>{},
    Set<String> explicitDraftIds = const <String>{},
    Set<String> explicitLastMessageIds = const <String>{},
  }) {
    flushRealtimePatches();
    if (batch.isEmpty && batch.unreadDeltas.isEmpty) return;
    final committedDraftIds = <String>{...explicitDraftIds};
    final committedLastMessageIds = <String>{...explicitLastMessageIds};
    final committedUnreadIds = <String>{};
    for (final entry in batch.changedFieldMasks.entries) {
      if (entry.value.contains(ConversationMutationField.draft)) {
        committedDraftIds.add(entry.key);
      }
      if (entry.value.contains(ConversationMutationField.lastMessage)) {
        committedLastMessageIds.add(entry.key);
      }
      if (entry.value.contains(ConversationMutationField.unread)) {
        committedUnreadIds.add(entry.key);
      }
    }
    // 冷启动期节流：先 apply unreadDeltas（badge 立即刷新），再延迟 tabStore rebuild。
    // 与 active-chat 节流互斥：active chat 由下一段判断接管。

    if (!ConversationPerfFlags.deferTabStoreProjectionWhileActiveChat ||
        !ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat ||
        batch.isEmpty) {
      _applyCommittedViewBatchNow(
        batch,
        forceAdmitIds: forceAdmitIds,
        explicitDraftIds: committedDraftIds,
        explicitLastMessageIds: committedLastMessageIds,
        explicitUnreadIds: committedUnreadIds,
      );
      return;
    }

    final immediateContentRows = <V2TimConversation>[];
    final deferredRows = <V2TimConversation>[];
    const contentFields = <ConversationMutationField>{
      ConversationMutationField.lastMessage,
      ConversationMutationField.unread,
      ConversationMutationField.draft,
      ConversationMutationField.name,
      ConversationMutationField.avatar,
      ConversationMutationField.mute,
    };
    const structureFields = <ConversationMutationField>{
      ConversationMutationField.pin,
      ConversationMutationField.order,
    };
    final changedFieldsFor = <String, Set<ConversationMutationField>>{
      for (final entry in batch.changedFieldMasks.entries)
        _projectionKey(entry.key): entry.value,
    };
    for (final row in batch.upsertedSnapshots) {
      final key = _projectionKey(row.conversationID);
      final fields =
          changedFieldsFor[key] ?? const <ConversationMutationField>{};
      final exists = typeIndexOf(_typeOf(row), row.conversationID) != null;
      final isActiveConversation = ActiveChatRegistry.instance
          .matchesOpenConversation(row.conversationID);
      final hasContentMask = fields.isNotEmpty &&
          fields.any(contentFields.contains) &&
          fields.every(
            (field) =>
                contentFields.contains(field) ||
                structureFields.contains(field),
          );
      final canProjectContent = !_isExcludedFromMainList(row) &&
          batch.deletedCanonicalIds.isEmpty &&
          ((exists && hasContentMask) || isActiveConversation);
      if (canProjectContent) {
        immediateContentRows.add(row);
      }
      final needsDeferredStructure = !canProjectContent ||
          fields.any(structureFields.contains) ||
          (batch.structureChanged && fields.isEmpty && !isActiveConversation);
      if (needsDeferredStructure) {
        deferredRows.add(row);
      }
    }
    for (final row in deferredRows) {
      if (ConversationDraftLeaveTrace.isFocused(row.conversationID)) {
        ConversationDraftLeaveTrace.stage(
          'tabstore_draft_deferred',
          conversationId: row.conversationID,
          draftText: row.draftText,
          extras: const <String, Object?>{'reason': 'active_chat'},
        );
        break;
      }
    }
    final deferredDeletes = <String>[];
    final deferredMoves = <ConversationUiMove>[];
    deferredDeletes.addAll(batch.deletedCanonicalIds);
    deferredMoves.addAll(batch.moves);

    // Badges are a committed aggregate, not a conversation-list projection.
    // Apply them now even though their corresponding list rows are deferred.
    _applyUnreadDeltas(batch.unreadDeltas);

    final deferredForceAdmit = Set<String>.of(forceAdmitIds);
    if (immediateContentRows.isNotEmpty) {
      final immediateContentIds =
          immediateContentRows.map((row) => row.conversationID).toSet();
      _applyCommittedViewBatchNow(
        ConversationUiSnapshotBatch<V2TimConversation>(
          upsertedSnapshots: immediateContentRows,
          deletedCanonicalIds: const <String>[],
          structureChanged: false,
          changedFieldMasks: <String, Set<ConversationMutationField>>{
            for (final row in immediateContentRows)
              if (changedFieldsFor[_projectionKey(row.conversationID)]
                      ?.isNotEmpty ==
                  true)
                row.conversationID:
                    changedFieldsFor[_projectionKey(row.conversationID)]!
                        .where(contentFields.contains)
                        .toSet(),
          },
          commitGeneration: batch.commitGeneration,
          moves: const <ConversationUiMove>[],
          // The aggregate was committed immediately above. Passing the
          // original delta here would count the active row twice.
          unreadDeltas: const <ConversationUiUnreadDelta>[],
          unreadProjectionComplete: batch.unreadProjectionComplete,
        ),
        forceAdmitIds: const <String>{},
        explicitDraftIds:
            committedDraftIds.where(immediateContentIds.contains).toSet(),
        explicitLastMessageIds:
            committedLastMessageIds.where(immediateContentIds.contains).toSet(),
        explicitUnreadIds:
            committedUnreadIds.where(immediateContentIds.contains).toSet(),
        preserveOrder: true,
        allowNew: true,
        preserveStructureFields: true,
      );
    }

    final hasDeferredProjection = deferredRows.isNotEmpty ||
        deferredDeletes.isNotEmpty ||
        deferredMoves.isNotEmpty;
    if (!hasDeferredProjection) return;
    _enqueueDeferredCommittedProjection(
      upserted: deferredRows,
      deletedIds: deferredDeletes,
      moves: deferredMoves,
      forceAdmitIds: deferredForceAdmit,
      structureChanged: batch.structureChanged,
      generation: batch.commitGeneration,
      explicitDraftIds: committedDraftIds,
      explicitLastMessageIds: committedLastMessageIds,
      explicitUnreadIds: committedUnreadIds,
    );
  }

  void _enqueueDeferredCommittedProjection({
    required Iterable<V2TimConversation> upserted,
    required Iterable<String> deletedIds,
    required Iterable<ConversationUiMove> moves,
    required Set<String> forceAdmitIds,
    required bool structureChanged,
    required int generation,
    required Set<String> explicitDraftIds,
    required Set<String> explicitLastMessageIds,
    required Set<String> explicitUnreadIds,
  }) {
    for (final id in deletedIds) {
      final key = _deferredProjectionKey(id);
      if (key.isEmpty) continue;
      _deferredCommittedDeletes.add(id.trim());
      _deferredCommittedUpserts.remove(key);
      _deferredCommittedMoves.remove(key);
    }
    for (final row in upserted) {
      final key = _deferredProjectionKey(
        row.conversationID,
        convType: _typeOf(row),
      );
      if (key.isEmpty) continue;
      _deferredCommittedDeletes.removeWhere(
        (id) => _deferredProjectionKey(id) == key,
      );
      final previous = _deferredCommittedUpserts[key];
      _deferredCommittedUpserts[key] = _preserveDeferredDraftOnLaterSnapshot(
        previous: previous,
        incoming: row,
        thisBatchSetsDraft: _deferredDraftAppliesToRow(row, explicitDraftIds),
      );
      // A later snapshot supplies the final sort position. An earlier
      // explicit move uses positions from an obsolete window and must not be
      // replayed during the eventual flush.
      _deferredCommittedMoves.remove(key);
    }
    for (final move in moves) {
      final key = _deferredProjectionKey(
        move.conversationID,
        convType: _normalizeType(move.convType),
      );
      if (key.isEmpty ||
          _deferredCommittedUpserts.containsKey(key) ||
          _deferredCommittedDeletes.any(
            (id) => _deferredProjectionKey(id) == key,
          )) {
        continue;
      }
      _deferredCommittedMoves[key] = move;
    }
    _deferredCommittedForceAdmitIds.addAll(forceAdmitIds);
    _deferredCommittedDraftIds.addAll(explicitDraftIds);
    _deferredCommittedLastMessageIds.addAll(explicitLastMessageIds);
    _deferredCommittedUnreadIds.addAll(explicitUnreadIds);
    _deferredCommittedStructureChanged =
        _deferredCommittedStructureChanged || structureChanged;
    if (generation > _deferredCommittedGeneration) {
      _deferredCommittedGeneration = generation;
    }
    ConversationPerfGateLog.log(
      'tab_store_projection_deferred_active_chat',
      extras: <String, Object?>{
        'upserted': _deferredCommittedUpserts.length,
        'deleted': _deferredCommittedDeletes.length,
        'moves': _deferredCommittedMoves.length,
        'generation': _deferredCommittedGeneration,
      },
    );
  }

  bool _deferredDraftAppliesToRow(
    V2TimConversation row,
    Set<String> explicitDraftIds,
  ) {
    final rowKey = _projectionKey(row.conversationID);
    if (rowKey.isEmpty) {
      return false;
    }
    for (final id in explicitDraftIds) {
      if (_projectionKey(id) == rowKey) {
        return true;
      }
      if (MessageConversationId.sameConversation(id, row.conversationID)) {
        return true;
      }
    }
    return false;
  }

  V2TimConversation _preserveDeferredDraftOnLaterSnapshot({
    required V2TimConversation? previous,
    required V2TimConversation incoming,
    required bool thisBatchSetsDraft,
  }) {
    if (thisBatchSetsDraft || previous == null) {
      return incoming;
    }
    final preserved = previous.draftText?.trim() ?? '';
    final hasExplicitDraft =
        _deferredDraftAppliesToRow(previous, _deferredCommittedDraftIds);
    if (!hasExplicitDraft &&
        (preserved.isEmpty || (incoming.draftText?.trim().isNotEmpty ?? false))) {
      return incoming;
    }
    ConversationLocalStore.applyLocalDraftToConversation(
      incoming,
      text: previous.draftText ?? preserved,
      updatedAtMs: (previous.draftTimestamp ?? 0) * 1000,
    );
    return incoming;
  }

  /// Flushes the durable committed view after Chat releases the foreground.
  /// The final row per conversation is applied once, so a burst of SDK events
  /// cannot trigger one list copy/sort per callback.
  void flushDeferredCommittedProjection({String reason = 'chat_leave'}) {
    flushRealtimePatches();
    if (_deferredCommittedUpserts.isEmpty &&
        _deferredCommittedDeletes.isEmpty &&
        _deferredCommittedMoves.isEmpty) {
      return;
    }
    final upserted = _deferredCommittedUpserts.values.toList(growable: false);
    final deleted = _deferredCommittedDeletes.toList(growable: false);
    final moves = _deferredCommittedMoves.values.toList(growable: false);
    final forceAdmit = Set<String>.of(_deferredCommittedForceAdmitIds);
    final explicitDraftIds = Set<String>.of(_deferredCommittedDraftIds);
    final explicitLastMessageIds =
        Set<String>.of(_deferredCommittedLastMessageIds);
    final explicitUnreadIds = Set<String>.of(_deferredCommittedUnreadIds);
    final structureChanged = _deferredCommittedStructureChanged;
    final generation = _deferredCommittedGeneration;
    _clearDeferredCommittedProjection();
    ConversationPerfGateLog.log(
      'tab_store_projection_flush',
      extras: <String, Object?>{
        'reason': reason,
        'upserted': upserted.length,
        'deleted': deleted.length,
        'moves': moves.length,
        'generation': generation,
      },
    );
    _applyCommittedViewBatchNow(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: upserted,
        deletedCanonicalIds: deleted,
        structureChanged: structureChanged,
        changedFieldMasks: <String, Set<ConversationMutationField>>{
          for (final id in explicitUnreadIds)
            id: const <ConversationMutationField>{
              ConversationMutationField.unread,
            },
        },
        commitGeneration: generation,
        moves: moves,
      ),
      forceAdmitIds: forceAdmit,
      explicitDraftIds: explicitDraftIds,
      explicitLastMessageIds: explicitLastMessageIds,
      explicitUnreadIds: explicitUnreadIds,
    );
  }

  void _clearDeferredCommittedProjection() {
    _deferredCommittedUpserts.clear();
    _deferredCommittedDeletes.clear();
    _deferredCommittedForceAdmitIds.clear();
    _deferredCommittedDraftIds.clear();
    _deferredCommittedLastMessageIds.clear();
    _deferredCommittedUnreadIds.clear();
    _deferredCommittedMoves.clear();
    _deferredCommittedStructureChanged = false;
    _deferredCommittedGeneration = 0;
  }

  void _applyUnreadDeltas(Iterable<ConversationUiUnreadDelta> deltas) {
    final values = deltas.toList(growable: false);
    if (values.isEmpty) return;
    ConversationUnreadAggregate.instance.applyNotifiableDeltas(
      values
          .map((delta) => ConversationUnreadDelta(
                conversationKey: delta.conversationKey,
                isGroup: delta.isGroup,
                oldNotifiable: delta.oldNotifiable,
                newNotifiable: delta.newNotifiable,
              ))
          .toList(growable: false),
    );
  }

  void _applyCommittedViewBatchNow(
    ConversationUiSnapshotBatch<V2TimConversation> batch, {
    Set<String> forceAdmitIds = const <String>{},
    Set<String> explicitDraftIds = const <String>{},
    Set<String> explicitLastMessageIds = const <String>{},
    Set<String> explicitUnreadIds = const <String>{},
    bool preserveOrder = false,
    bool allowNew = true,
    bool preserveStructureFields = false,
  }) {
    if (batch.isEmpty && batch.unreadDeltas.isEmpty) return;
    final previousPatchRevision = _acceptedPatchRevision;
    final authoritativeUnreadIds = <String>{...explicitUnreadIds};
    for (final entry in batch.changedFieldMasks.entries) {
      if (entry.value.contains(ConversationMutationField.unread)) {
        authoritativeUnreadIds.add(entry.key);
      }
    }
    final changedTypes = <int>{};
    final oldPositions = <String, int>{};
    for (final row in batch.upsertedSnapshots) {
      final type = _normalizeType(row.type ?? ConversationType.V2TIM_C2C);
      changedTypes.add(type);
      oldPositions[row.conversationID.trim()] =
          typeIndexOf(type, row.conversationID) ?? -1;
    }
    for (final id in batch.deletedCanonicalIds) {
      for (final type in const [
        ConversationType.V2TIM_C2C,
        ConversationType.V2TIM_GROUP
      ]) {
        invalidateViewPages(conversationID: id, convType: type);
      }
    }
    if (batch.upsertedSnapshots.isNotEmpty) {
      final aggregate = ConversationUnreadAggregate.instance;
      final snapshots = aggregate.usesSdkUnread
          ? batch.upsertedSnapshots.map((row) {
              // SQLite is a business/cache mirror, not an unread authority.
              // A delayed local read/pin/preview commit must not overwrite
              // a more recent SDK count, including a cross-device read.
              final count = aggregate.sdkUnreadCountFor(row.conversationID) ??
                  conversationForId(row.conversationID)?.unreadCount ?? 0;
              return mergePatchRow(
                existing: row,
                incoming: V2TimConversation(
                    conversationID: row.conversationID, unreadCount: count),
                useIncomingUnread: true,
              );
            }).toList(growable: false)
          : batch.upsertedSnapshots;
      applyPatches(
        snapshots,
        reason: 'committed_view_batch',
        forceAdmitIds: forceAdmitIds,
        explicitDraftIds: explicitDraftIds,
        explicitLastMessageIds: explicitLastMessageIds,
        explicitUnreadIds: authoritativeUnreadIds,
        preserveOrder: preserveOrder,
        preserveStructureFields: preserveStructureFields,
        allowNew: allowNew,
        notify: false,
      );
    }
    final patchStructureChanged =
        _acceptedPatchRevision != previousPatchRevision &&
            _lastNotificationStructureChanged;
    final derivedMoves = <ConversationUiMove>[];
    for (final row in batch.upsertedSnapshots) {
      final type = _normalizeType(row.type ?? ConversationType.V2TIM_C2C);
      final oldIndex = oldPositions[row.conversationID.trim()] ?? -1;
      final newIndex = typeIndexOf(type, row.conversationID) ?? -1;
      if (oldIndex >= 0 && newIndex >= 0 && oldIndex != newIndex) {
        derivedMoves.add(ConversationUiMove(
          conversationID: row.conversationID,
          convType: type,
          oldIndex: oldIndex,
          newIndex: newIndex,
          reason: 'committed_batch',
        ));
      }
    }
    for (final move in batch.moves) {
      final list = _items[_normalizeType(move.convType)];
      if (list == null || list.isEmpty) continue;
      final type = _normalizeType(move.convType);
      final from = _structureIndexes[type]!.find(move.conversationID);
      if (from < 0) continue;
      final target = move.newIndex.clamp(0, list.length - 1);
      if (target == from) continue;
      final row = list.removeAt(from);
      list.insert(target, row);
      _acceptedPatchRevision++;
      _items[type] = list;
      _rebuildStructureIndex(type);
    }
    if (batch.deletedCanonicalIds.isNotEmpty) {
      applyDeleted(batch.deletedCanonicalIds, notify: false);
    }
    if (batch.structureChanged) {
      for (final type in changedTypes) {
        _pageCursors[type] = null;
      }
      ConversationPerfGateLog.log(
        'conversation_view_move_batch',
        extras: <String, Object?>{
          'rows': batch.upsertedSnapshots.length,
          'deleted': batch.deletedCanonicalIds.length,
          'generation': batch.commitGeneration,
          'types': changedTypes.toList(growable: false),
        },
      );
    }
    final moves = <ConversationUiMove>[...batch.moves, ...derivedMoves];
    if (moves.isNotEmpty) {
      ConversationPerfGateLog.log(
        'conversation_view_precise_move',
        extras: <String, Object?>{
          'count': moves.length,
          'moves': moves
              .map((m) => <String, Object?>{
                    'id': m.conversationID,
                    'type': m.convType,
                    'from': m.oldIndex,
                    'to': m.newIndex,
                    'reason': m.reason,
                  })
              .toList(growable: false),
        },
      );
    }
    if (batch.unreadDeltas.isNotEmpty) {
      ConversationUnreadAggregate.instance.applyNotifiableDeltas(
        batch.unreadDeltas
            .map((d) => ConversationUnreadDelta(
                  conversationKey: d.conversationKey,
                  isGroup: d.isGroup,
                  oldNotifiable: d.oldNotifiable,
                  newNotifiable: d.newNotifiable,
                ))
            .toList(growable: false),
      );
    }
    if (_acceptedPatchRevision == previousPatchRevision) return;
    _lastNotificationStructureChanged = patchStructureChanged ||
        batch.structureChanged ||
        batch.deletedCanonicalIds.isNotEmpty ||
        batch.moves.isNotEmpty ||
        derivedMoves.isNotEmpty;
    notifyListeners();
  }

  /// 批量已读的即时 UI 投影。SDK primary 模式下列表行来自本 Store，
  /// 不能只更新 UI 兼容镜像。
  void zeroUnreadLocallyMany(Iterable<String> conversationIds) {
    flushRealtimePatches();
    if (ConversationUnreadAggregate.instance.usesSdkUnread) {
      ConversationUnreadAggregate.instance.zeroSdkUnreadCounts(conversationIds);
      return;
    }
    final ids = conversationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      return;
    }
    ConversationUnreadGuard.clearOptimisticUnreadMany(ids);
    ConversationUnreadAggregate.instance.zeroSdkUnreadCounts(ids);
    // A ByIDs restore is also a pending SDK read. An explicit local read
    // action must win over its older unread snapshot, including absent rows.
    for (final read in _restoreReads) {
      for (final requestedId in read.ids) {
        if (!ids.any(
            (id) => MessageConversationId.sameConversation(id, requestedId)))
          continue;
        final previous = read.changes[requestedId];
        if (previous != null && previous.row == null) continue;
        final zero = V2TimConversation(
            conversationID: requestedId,
            type: previous?.row?.type ??
                (requestedId.startsWith('group_') ? 2 : 1),
            unreadCount: 0);
        read.changes[requestedId] = (
          row: previous?.row == null
              ? zero
              : mergePatchRow(
                  existing: previous!.row!,
                  incoming: zero,
                  useIncomingUnread: true),
          draft: previous?.draft ?? false,
          last: previous?.last ?? false,
        );
      }
    }
    for (final entry in _pageChanges.entries) {
      for (final id in ids) {
        if (id.startsWith('c2c_') && entry.key != 1) continue;
        if (id.startsWith('group_') && entry.key != 2) continue;
        final key = _projectionKey(id);
        final previous = entry.value[key];
        if (previous != null && previous.row == null) continue;
        final cleared = V2TimConversation(
            conversationID: id, type: entry.key, unreadCount: 0);
        entry.value[key] = (
          row: previous?.row == null
              ? cleared
              : mergePatchRow(
                  existing: previous!.row!,
                  incoming: cleared,
                  useIncomingUnread: true),
          draft: previous?.draft ?? false,
          last: previous?.last ?? false
        );
      }
    }
    var changed = false;
    final unreadDeltas = <ConversationUnreadDelta>[];
    final cleared = <String>[];
    for (final type in const [
      ConversationType.V2TIM_C2C,
      ConversationType.V2TIM_GROUP,
    ]) {
      final current = _items[type];
      if (current == null || current.isEmpty) {
        continue;
      }
      final next = List<V2TimConversation>.from(current);
      for (var i = 0; i < next.length; i++) {
        final row = next[i];
        final hit = ids.contains(row.conversationID.trim()) ||
            ids.any((id) =>
                MessageConversationId.sameConversation(id, row.conversationID));
        if (!hit || (row.unreadCount ?? 0) == 0) {
          continue;
        }
        final oldNotifiable =
            ConversationUnreadUtils.notifiableUnreadCount(row);
        if (oldNotifiable > 0) {
          unreadDeltas.add(
            ConversationUnreadDelta(
              conversationKey: row.conversationID,
              isGroup: type == ConversationType.V2TIM_GROUP,
              oldNotifiable: oldNotifiable,
              newNotifiable: 0,
            ),
          );
        }
        cleared.add(row.conversationID.trim());
        row.unreadCount = 0;
        _refreshPatchRowState(row);
        next[i] = row;
        changed = true;
      }
      if (changed) {
        _items[type] = next;
      }
    }
    if (unreadDeltas.isNotEmpty) {
      ConversationUnreadAggregate.instance.applyNotifiableDeltas(unreadDeltas);
    }
    if (changed) {
      var structureChanged = false;
      if (excludeReadFromStructure) {
        for (final type in const [
          ConversationType.V2TIM_C2C,
          ConversationType.V2TIM_GROUP,
        ]) {
          final current = _items[type];
          if (current == null || current.isEmpty) continue;
          final next =
              current.where((row) => !_isExcludedFromMainList(row)).toList();
          if (next.length != current.length) {
            _items[type] = next;
            _rebuildStructureIndex(type);
            structureChanged = true;
          }
        }
        for (final id in cleared) {
          if (conversationForId(id) == null) {
            _dropRowView(id);
          }
        }
      }
      _projectChangedRows(cleared.where((id) => conversationForId(id) != null));
      _lastApplyPatchesReason = 'zero_unread_local';
      _lastNotificationStructureChanged = structureChanged;
      _lastNotificationChangedIds = cleared.toSet();
      if (structureChanged) {
        workStructureNotifyCount++;
        ConversationFeedPerf.increment('conversation_structure_notify_count');
        notifyListeners();
      }
    }
  }

  /// Phase3：按本地归档 id 集合从已加载窗 purge（主列表不得双显）。
  void purgeArchived({bool notify = true}) {
    flushRealtimePatches();
    if (!ConversationPerfFlags.virtualListExcludeArchivedEnabled) {
      return;
    }
    final c2cLookup = buildArchiveLookupTokenSet(
      archivedConversationC2cIDsNotifier.value,
    );
    final groupLookup = buildArchiveLookupTokenSet(
      archivedConversationGroupIDsNotifier.value,
    );
    final unreadDeltas = <ConversationUnreadDelta>[];
    final removedIds = <String>{};
    var any = false;
    for (final type in const [
      ConversationType.V2TIM_C2C,
      ConversationType.V2TIM_GROUP,
    ]) {
      final list = _items[type];
      if (list == null || list.isEmpty) {
        continue;
      }
      final lookup =
          type == ConversationType.V2TIM_GROUP ? groupLookup : c2cLookup;
      final next = <V2TimConversation>[];
      for (final c in list) {
        if (conversationIdInArchivedLookup(lookup, c.conversationID)) {
          removedIds.add(c.conversationID.trim());
          final oldN = ConversationUnreadUtils.notifiableUnreadCount(c);
          if (oldN > 0) {
            unreadDeltas.add(
              ConversationUnreadDelta(
                conversationKey: c.conversationID,
                isGroup: type == ConversationType.V2TIM_GROUP,
                oldNotifiable: oldN,
                newNotifiable: 0,
              ),
            );
          }
          any = true;
          continue;
        }
        next.add(c);
      }
      if (next.length != list.length) {
        _items[type] = next;
        _rebuildStructureIndex(type);
        any = true;
      }
    }
    if (unreadDeltas.isNotEmpty) {
      ConversationUnreadAggregate.instance.applyNotifiableDeltas(unreadDeltas);
    }
    if (any) {
      _lastApplyPatchesReason = 'archive_purge';
      _lastNotificationStructureChanged = true;
      _lastNotificationChangedIds = removedIds;
      ConversationPerfGateLog.log(
        'tab_store_purge_archived',
        extras: <String, Object?>{
          'c2c': countForType(ConversationType.V2TIM_C2C),
          'group': countForType(ConversationType.V2TIM_GROUP),
          'ui_source': 'sdk_store',
        },
      );
      if (notify) notifyListeners();
    }
  }

  void clear() {
    _realtimeBatchTimer?.cancel();
    _realtimeBatchTimer = null;
    _pendingRealtimeRows.clear();
    _realtimePreserveOrder = false;
    _clearRowViewScope();
    _displayRows = const [];
    _displayPositions.clear();
    _displayChangedIds.clear();
    _pinSortDeferred = false;
    _structureRevision = 0;
    _contentRevision = 0;
    _contentChanges.reset();
    _primedTypes.clear();
    _failedLoadTypes.clear();
    _sortDirtyTypes.clear();
    _sortFrozenByScroll = false;
    BackgroundMediaGate.instance.setBusy(this, false);
    _sessionGeneration++;
    _restoreReads.clear();
    _loadInFlight.clear();
    _resetRequested.clear();
    _clearDeferredCommittedProjection();
    _coldStartWindowActive = true;
    _coldStartWindowOpenedAt = DateTime.now();
    _items[ConversationType.V2TIM_C2C] = <V2TimConversation>[];
    _items[ConversationType.V2TIM_GROUP] = <V2TimConversation>[];
    _rebuildStructureIndex(ConversationType.V2TIM_C2C);
    _rebuildStructureIndex(ConversationType.V2TIM_GROUP);
    _nextSeq[ConversationType.V2TIM_C2C] = '0';
    _nextSeq[ConversationType.V2TIM_GROUP] = '0';
    _finished[ConversationType.V2TIM_C2C] = false;
    _finished[ConversationType.V2TIM_GROUP] = false;
    _windowTrimmed[ConversationType.V2TIM_C2C] = false;
    _windowTrimmed[ConversationType.V2TIM_GROUP] = false;
    _clearDetached(ConversationType.V2TIM_C2C);
    _clearDetached(ConversationType.V2TIM_GROUP);
    _pageCursors[ConversationType.V2TIM_C2C] = null;
    _pageCursors[ConversationType.V2TIM_GROUP] = null;
    _lastNotificationStructureChanged = true;
    _lastNotificationChangedIds = const <String>{};
    notifyListeners();
  }

  @visibleForTesting
  void setItemsForTest({
    required int convType,
    required List<V2TimConversation> items,
    String nextSeq = '0',
    bool finished = false,
  }) {
    flushRealtimePatches();
    final type = _normalizeType(convType);
    _primedTypes.add(type);
    _items[type] = List<V2TimConversation>.from(items);
    _rebuildStructureIndex(type);
    for (final row in _items[type]!) {
      _refreshPatchRowState(row);
      final id = row.conversationID.trim();
      if (id.isEmpty) continue;
      _rowViews[id] = ConversationRowView.fromConversation(row);
      final notifier = _rowViewNotifiers[id];
      if (notifier != null) {
        notifier.value = _rowViews[id];
      }
    }
    _nextSeq[type] = nextSeq;
    _finished[type] = finished;
    final tail = ConversationLocalStore.oldestPagingCursor(_items[type]!);
    _pageCursors[type] = tail == null
        ? null
        : ConversationTypePageCursor(
            pinned: tail.isPinned == true,
            activeTime: ConversationLocalStore.pagingAnchorMs(tail),
            orderKey: tail.orderkey ?? 0,
            // 项 8-1：构造 cursor 时填 sdkOrderKey。
            sdkOrderKey: tail.orderkey ?? 0,
            conversationID: tail.conversationID,
          );
    _lastNotificationStructureChanged = true;
    notifyListeners();
  }

  Future<void> _load({
    required int type,
    required bool reset,
    required int count,
    String? viewportAnchorId,
  }) async {
    final existing = _loadInFlight[type];
    if (existing != null) {
      if (reset) {
        _resetRequested.add(type);
      }
      await existing;
      if (reset && _resetRequested.remove(type)) {
        await _load(
          type: type,
          reset: true,
          count: count,
          viewportAnchorId: viewportAnchorId,
        );
      }
      return;
    }
    final generation = _sessionGeneration;
    final task = _loadOnce(
      type: type,
      reset: reset,
      count: count,
      generation: generation,
      viewportAnchorId: viewportAnchorId,
    );
    _loadInFlight[type] = task;
    try {
      await task;
    } catch (_) {
      if (generation == _sessionGeneration) _failedLoadTypes.add(type);
      rethrow;
    } finally {
      if (identical(_loadInFlight[type], task)) {
        _loadInFlight[type] = null;
      }
    }
  }

  bool _canAppendOlderPage(
    List<V2TimConversation> current,
    List<V2TimConversation> filteredPage,
  ) {
    if (current.isEmpty || filteredPage.isEmpty) return false;
    for (var i = 1; i < filteredPage.length; i++) {
      if (ConversationLocalStore.compareConversationsForUi(
            filteredPage[i - 1],
            filteredPage[i],
          ) >
          0) {
        return false;
      }
    }
    final last = current.last;
    for (final row in filteredPage) {
      if (ConversationLocalStore.compareConversationsForUi(last, row) > 0) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadOnce({
    required int type,
    required bool reset,
    required int count,
    required int generation,
    String? viewportAnchorId,
  }) async {
    flushRealtimePatches();
    final pageCount = count > 0 ? count : defaultPageSize;
    final seq = reset ? '0' : (_nextSeq[type] ?? '0');
    if (!reset && (_finished[type] == true)) {
      return;
    }

    final unreadPageRevision =
        ConversationUnreadAggregate.instance.sdkPageRevision;
    final changes =
        <String, ({V2TimConversation? row, bool draft, bool last})>{};
    _pageChanges[type] = changes;
    final ({
      List<V2TimConversation> conversationList,
      String nextSeq,
      bool isFinished,
      int code,
      String desc
    }) fetched;
    try {
      fetched = await _fetch(
        convType: type,
        nextSeq: seq,
        count: pageCount,
      );
      // Commit pending callbacks while this page's change journal is live.
      // Otherwise a fast SDK response could install an older snapshot first.
      flushRealtimePatches();
    } finally {
      if (identical(_pageChanges[type], changes)) _pageChanges.remove(type);
    }
    if (generation != _sessionGeneration) {
      return;
    }
    if (fetched.code != 0) {
      _failedLoadTypes.add(type);
      ConversationPerfGateLog.log(
        'tab_store_fetch_fail',
        extras: <String, Object?>{
          'convType': type,
          'code': fetched.code,
          'desc': fetched.desc,
          'ui_source': 'sdk_store',
        },
      );
      return;
    }
    _primedTypes.add(type);
    _failedLoadTypes.remove(type);
    final page = <V2TimConversation>[];
    for (final fetchedRow in fetched.conversationList) {
      final key = _projectionKey(fetchedRow.conversationID);
      final changed = changes[key];
      if (changed != null && changed.row == null) continue;
      final c = changed == null
          ? fetchedRow
          : mergePatchRow(
              existing: fetchedRow,
              incoming: changed.row!,
              useIncomingUnread: changed.row!.unreadCount != null,
              useIncomingDraft: changed.draft,
              useIncomingLastMessage: changed.last);
      ConversationLocalStore.decorateConversationForUi(c);
      ConversationPinSyncService.instance.applySdkPinProjection(c);
      if (_isExcludedFromMainList(c)) {
        continue;
      }
      page.add(c);
    }
    if (page.length > 1) {
      page.sort(ConversationLocalStore.compareConversationsForUi);
    }
    var appendOnly = false;
    var skipRebuild = false;
    var appendedPageIds = const <String>{};
    if (reset) {
      _clearDetached(type);
      // A realtime patch may have landed while the SDK request was in
      // flight. Merge matching rows and retain unmatched hot rows until the
      // SDK page catches up. Dropping those rows here makes a newly arrived
      // conversation disappear and then jump back on the next callback.
      final current = _items[type] ?? const <V2TimConversation>[];
      final currentById = <String, V2TimConversation>{
        for (final item in current) _projectionKey(item.conversationID): item,
      };
      final pageKeys = <String>{};
      final mergedPage = <V2TimConversation>[
        for (final item in page)
          (() {
            final key = _projectionKey(item.conversationID);
            pageKeys.add(key);
            final existing = currentById[key];
            return existing == null
                ? item
                : mergePatchRow(
                    existing: existing,
                    incoming: item,
                    useIncomingUnread: true,
                    useIncomingDraft: changes[key]?.draft == true,
                    useIncomingLastMessage: changes[key]?.last == true,
                  );
          })(),
      ];
      final retainedHot = <V2TimConversation>[
        for (final item in current)
          if (!pageKeys.contains(_projectionKey(item.conversationID)) &&
              _shouldAdmitHot(item, mergedPage))
            item,
      ];
      _items[type] = ConversationLocalStore.mergeConversationsForUi(
        mergedPage,
        retainedHot,
      );
    } else {
      final current = _items[type] ?? const <V2TimConversation>[];
      final seen = <String>{
        for (final c in current) _projectionKey(c.conversationID),
      };
      final filteredPage = <V2TimConversation>[];
      for (final c in page) {
        final id = c.conversationID.trim();
        final key = _projectionKey(id);
        if (key.isEmpty || seen.contains(key)) {
          continue;
        }
        seen.add(key);
        filteredPage.add(c);
      }
      var indexReady = false;
      if (filteredPage.isEmpty) {
        indexReady = true;
      } else if (_canAppendOlderPage(current, filteredPage)) {
        _items[type] = List<V2TimConversation>.from(current)
          ..addAll(filteredPage);
        for (final row in filteredPage) {
          _structureIndexes[type]!.append(row);
        }
        indexReady = true;
        appendOnly = true;
      } else {
        _items[type] = ConversationLocalStore.mergeConversationsForUi(
          current,
          filteredPage,
        );
      }
      if (filteredPage.isNotEmpty &&
          ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType > 0) {
        final window = ConversationSdkWindowPolicy.trimAroundAnchor(
          _items[type]!,
          type: type,
          viewportAnchorId: viewportAnchorId,
        );
        _items[type] = window.rows;
        _appendDetachedHead(type, window.droppedFromStart);
        _prependDetachedTail(type, window.droppedFromEnd);
        _syncWindowTrimmed(type);
        if (window.trimmed) {
          indexReady = false;
          appendOnly = false;
        }
      }
      final tail = ConversationLocalStore.oldestPagingCursor(_items[type]!);
      if (tail != null) {
        _pageCursors[type] = ConversationTypePageCursor(
          pinned: tail.isPinned == true,
          activeTime: ConversationLocalStore.pagingAnchorMs(tail),
          orderKey: tail.orderkey ?? 0,
          // 项 8-1：构造 cursor 时填 sdkOrderKey。
          sdkOrderKey: tail.orderkey ?? 0,
          conversationID: tail.conversationID,
        );
      }
      if (indexReady) {
        skipRebuild = true;
      }
      if (appendOnly) {
        appendedPageIds = <String>{
          for (final row in filteredPage)
            if (row.conversationID.trim().isNotEmpty) row.conversationID.trim(),
        };
      }
    }
    if (reset) _capWindowFromEnd(type);
    if (!skipRebuild) {
      _rebuildStructureIndex(type);
    }
    // Page decoration/pin hydration and overlapping merge preferences can
    // mutate retained SDK objects. Refresh only rows touched by this page.
    _refreshPagePatchRows(_items[type]!, fetched.conversationList);
    // A page can be empty after archive/membership filtering even when the
    // SDK has more pages. Only the SDK cursor can establish end-of-list.
    final finished = fetched.isFinished;
    // The page is SDK-owned; SQLite is not populated in SDK-primary mode.
    ConversationUnreadAggregate.instance.applySdkPage(
      fetched.conversationList,
      startedAtRevision: unreadPageRevision,
    );
    _reconcileSdkUnread();
    _finished[type] = finished;
    final next = fetched.nextSeq.trim().isEmpty ? '0' : fetched.nextSeq.trim();
    if (finished || next == '0' || next == seq) {
      _finished[type] = true;
      _nextSeq[type] = '0';
      _pageCursors[type] = null;
    } else {
      _nextSeq[type] = next;
    }
    ConversationPerfGateLog.log(
      'tab_store_page',
      extras: <String, Object?>{
        'convType': type,
        'reset': reset,
        'page': page.length,
        'total': countForType(type),
        'finished': _finished[type],
        'nextSeq': _nextSeq[type],
        'ui_source': 'sdk_store',
      },
    );
    _lastApplyPatchesReason = 'sdk_page';
    _lastNotificationStructureChanged = true;
    if (appendOnly) {
      _lastNotificationChangedIds = appendedPageIds;
      _lastNotificationAppendOnly = true;
    } else {
      _lastNotificationChangedIds = const <String>{};
    }
    notifyListeners();
  }

  Future<
      ({
        List<V2TimConversation> conversationList,
        String nextSeq,
        bool isFinished,
        int code,
        String desc,
      })> _fetch({
    required int convType,
    required String nextSeq,
    required int count,
  }) async {
    final override = debugFetchOverride;
    if (override != null) {
      return override(
        convType: convType,
        nextSeq: nextSeq,
        count: count,
      );
    }
    final seqInt = int.tryParse(nextSeq.trim()) ?? 0;
    final res = await TencentImSDKPlugin.v2TIMManager
        .getConversationManager()
        .getConversationListByFilter(
          filter: V2TimConversationFilter(conversationType: convType),
          nextSeq: seqInt,
          count: count,
        );
    final data = res.data;
    final list = <V2TimConversation>[];
    for (final item in data?.conversationList ?? const <V2TimConversation?>[]) {
      if (item != null) {
        list.add(item);
      }
    }
    return (
      conversationList: list,
      nextSeq: data?.nextSeq?.toString() ?? '0',
      isFinished: data?.isFinished == true,
      code: res.code,
      desc: res.desc,
    );
  }

  bool _isExcludedFromMainList(V2TimConversation conversation) {
    if (excludeReadFromStructure && (conversation.unreadCount ?? 0) <= 0) {
      return true;
    }
    if (GroupMembershipSyncService.instance
        .isExplicitlyRemovedConversation(conversation)) return true;
    if (!ConversationPerfFlags.virtualListExcludeArchivedEnabled) {
      return false;
    }
    final id = conversation.conversationID.trim();
    if (id.isEmpty) {
      return false;
    }
    if (_typeOf(conversation) == ConversationType.V2TIM_GROUP) {
      return conversationIdInArchivedLookup(
        cachedArchiveLookupTokenSet(archivedConversationGroupIDsNotifier.value),
        id,
      );
    }
    return conversationIdInArchivedLookup(
      cachedArchiveLookupTokenSet(archivedConversationC2cIDsNotifier.value),
      id,
    );
  }

  void _clearDetached(int type) {
    _detachedHeadIds[type]!.clear();
    _detachedTailIds[type]!.clear();
    _detachedHeadIdSet[type]!.clear();
    _detachedTailIdSet[type]!.clear();
    _detachedRows[type]!.clear();
    _windowTrimmed[type] = false;
  }

  void _syncWindowTrimmed(int type) {
    _windowTrimmed[type] = _detachedHeadIds[type]!.isNotEmpty ||
        _detachedTailIds[type]!.isNotEmpty;
  }

  void _trimDetachedRowCache(int type) {
    final keep = ConversationPerfFlags.uiAppendOlderHotHeadReserve;
    final head = _detachedHeadIds[type]!;
    final allowed = keep >= head.length
        ? head.toSet()
        : head.sublist(head.length - keep).toSet();
    _detachedRows[type]!.removeWhere((id, _) => !allowed.contains(id));
  }

  void _appendDetachedHead(int type, List<V2TimConversation> rows) {
    if (rows.isEmpty) return;
    for (final row in rows) {
      final id = row.conversationID.trim();
      if (id.isEmpty) continue;
      _detachedTailIds[type]!.remove(id);
      _detachedTailIdSet[type]!.remove(id);
      if (_detachedHeadIdSet[type]!.add(id)) {
        _detachedHeadIds[type]!.add(id);
      }
      _detachedRows[type]![id] = row;
    }
    _trimDetachedRowCache(type);
    _syncWindowTrimmed(type);
  }

  void _prependDetachedTail(int type, List<V2TimConversation> rows) {
    if (rows.isEmpty) return;
    final ids = <String>[];
    for (final row in rows) {
      final id = row.conversationID.trim();
      if (id.isEmpty) continue;
      _detachedHeadIds[type]!.remove(id);
      _detachedHeadIdSet[type]!.remove(id);
      if (_detachedTailIdSet[type]!.add(id)) {
        ids.add(id);
      }
      _detachedRows[type]![id] = row;
    }
    if (ids.isNotEmpty) {
      _detachedTailIds[type]!.insertAll(0, ids);
    }
    _trimDetachedRowCache(type);
    _syncWindowTrimmed(type);
  }

  void _insertDetachedHeadFront(
    int type,
    String id,
    V2TimConversation row,
  ) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    _detachedTailIds[type]!.remove(trimmed);
    _detachedTailIdSet[type]!.remove(trimmed);
    _detachedHeadIds[type]!.remove(trimmed);
    _detachedHeadIdSet[type]!.add(trimmed);
    _detachedHeadIds[type]!.insert(0, trimmed);
    _detachedRows[type]![trimmed] = row;
    _trimDetachedRowCache(type);
    _syncWindowTrimmed(type);
  }

  void _capWindowFromEnd(int type) {
    final cap = ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType;
    final list = _items[type]!;
    if (cap <= 0 || list.length <= cap) {
      return;
    }
    final dropped = list.sublist(cap);
    _items[type] = list.sublist(0, cap);
    _prependDetachedTail(type, dropped);
    final tail = ConversationLocalStore.oldestPagingCursor(_items[type]!);
    if (tail != null) {
      _pageCursors[type] = ConversationTypePageCursor(
        pinned: tail.isPinned == true,
        activeTime: ConversationLocalStore.pagingAnchorMs(tail),
        orderKey: tail.orderkey ?? 0,
        sdkOrderKey: tail.orderkey ?? 0,
        conversationID: tail.conversationID,
      );
    }
  }

  void _capWindowFromStart(int type) {
    final cap = ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType;
    final list = _items[type]!;
    if (cap <= 0 || list.length <= cap) {
      return;
    }
    final dropped = list.sublist(0, list.length - cap);
    _items[type] = list.sublist(list.length - cap);
    _appendDetachedHead(type, dropped);
  }

  List<V2TimConversation> _orderHydratedRows(
    List<String> ids,
    List<V2TimConversation> rows,
  ) {
    final byId = <String, V2TimConversation>{};
    for (final row in rows) {
      final id = row.conversationID.trim();
      if (id.isEmpty) continue;
      byId[id] = row;
      for (final requested in ids) {
        if (MessageConversationId.sameConversation(requested, id)) {
          byId[requested] = row;
        }
      }
    }
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<List<V2TimConversation>> _hydrateDetachedRows(
    int type,
    List<String> ids,
  ) async {
    if (ids.isEmpty) {
      return const <V2TimConversation>[];
    }
    final out = <V2TimConversation>[];
    final missing = <String>[];
    final cache = _detachedRows[type]!;
    for (final id in ids) {
      final cached = cache[id];
      if (cached != null) {
        out.add(cached);
      } else {
        missing.add(id);
      }
    }
    if (missing.isNotEmpty) {
      final still = <String>[];
      for (final id in missing) {
        try {
          final local =
              await ConversationLocalStore.instance.conversationById(id);
          if (local != null) {
            out.add(local);
            cache[id] = local;
          } else {
            still.add(id);
          }
        } catch (_) {
          still.add(id);
        }
      }
      for (var start = 0; start < still.length; start += 100) {
        final end = start + 100 < still.length ? start + 100 : still.length;
        final chunk = still.sublist(start, end);
        final result = await readSdkConversationsByIds(chunk);
        if (result.code != 0) continue;
        for (final row in result.conversationList) {
          final id = row.conversationID.trim();
          if (id.isEmpty) continue;
          cache[id] = row;
          out.add(row);
        }
      }
    }
    return _orderHydratedRows(ids, out);
  }

  bool _shouldAdmitHot(
    V2TimConversation incoming,
    List<V2TimConversation> current,
  ) {
    if (incoming.isPinned == true) {
      return true;
    }
    if ((incoming.unreadCount ?? 0) > 0) {
      return true;
    }
    if (current.isEmpty) {
      return true;
    }
    final incomingActive = ConversationLocalStore.activeTimeMs(incoming);
    final headActive = ConversationLocalStore.activeTimeMs(current.first);
    return incomingActive > headActive;
  }

  int _typeOf(V2TimConversation c) {
    if (c.type == ConversationType.V2TIM_GROUP ||
        (c.groupID?.trim().isNotEmpty == true)) {
      return ConversationType.V2TIM_GROUP;
    }
    return ConversationType.V2TIM_C2C;
  }

  int _normalizeType(int convType) {
    return convType == ConversationType.V2TIM_GROUP
        ? ConversationType.V2TIM_GROUP
        : ConversationType.V2TIM_C2C;
  }

  void notifyColdStartEnded() {
    _coldStartWindowOpenedAt = null;
    _coldStartWindowActive = false;
  }

  void reopenColdStartWindow() {
    _coldStartWindowOpenedAt = DateTime.now();
    _coldStartWindowActive = true;
  }

  void _projectChangedRows(Iterable<String> ids) {
    for (final rawId in ids) {
      final id = rawId.trim();
      if (id.isEmpty) continue;
      final row = conversationForId(id);
      if (row == null) {
        _dropRowView(id);
        continue;
      }
      final next = ConversationRowView.fromConversation(row);
      final previous = _rowViews[id];
      if (previous == next) {
        continue;
      }
      _rowViews[id] = next;
      workRowProjectedCount++;
      ConversationFeedPerf.increment('conversation_row_projected_count');
      final notifier = _rowViewNotifiers[id];
      if (notifier != null && notifier.value != next) {
        notifier.value = next;
        workRowNotifyCount++;
        ConversationFeedPerf.increment('conversation_row_notify_count');
      }
    }
  }

  void _dropRowView(String id) {
    if (id.isEmpty) return;
    _rowViews.remove(id);
    final notifier = _rowViewNotifiers[id];
    if (notifier != null && notifier.value != null) {
      notifier.value = null;
      workRowNotifyCount++;
      ConversationFeedPerf.increment('conversation_row_notify_count');
    }
  }

  void _clearRowViewScope() {
    for (final notifier in _rowViewNotifiers.values) {
      notifier.detach();
      notifier.dispose();
    }
    _rowViewNotifiers.clear();
    _rowViews.clear();
  }

  bool _tryRelocateAffected(
    List<V2TimConversation> list,
    Set<String> movedIds,
  ) {
    const maxRelocate = 8;
    if (movedIds.isEmpty || movedIds.length > maxRelocate || list.length <= 2) {
      return false;
    }
    final compare = ConversationLocalStore.compareConversationsForUi;
    for (final id in movedIds) {
      final index = list.indexWhere((row) => row.conversationID == id);
      if (index < 0) continue;
      final row = list.removeAt(index);
      var lo = 0;
      var hi = list.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (compare(list[mid], row) <= 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      list.insert(lo, row);
    }
    for (var i = 1; i < list.length; i++) {
      if (compare(list[i - 1], list[i]) > 0) {
        return false;
      }
    }
    return true;
  }
}

class _ScopedRowViewNotifier extends ValueNotifier<ConversationRowView?> {
  _ScopedRowViewNotifier(
    super.value, {
    required this.onCancel,
  });

  final VoidCallback onCancel;
  bool _detached = false;

  void detach() {
    _detached = true;
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!_detached && !hasListeners) {
      onCancel();
    }
  }
}
