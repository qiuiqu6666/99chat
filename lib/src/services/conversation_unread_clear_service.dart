import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/im/conversation_read_policy.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_conversation_read_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/web_read_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

enum SdkUnreadCleanTrigger { open, chatVisible, leave, recovery }

/// 编辑态「全部已读 / 选中已读」模式。
enum MarkReadEditMode { selected, scopeAll, archivedAll }

/// 与会话列表 Tab 对齐的清未读 scope（避免 ClearService 依赖 UI 文件）。
enum MarkReadListScope { all, c2c, group }

class _LeaveFinalizeFlight {
  const _LeaveFinalizeFlight({required this.generation, required this.future});

  final int generation;
  final Future<void> future;
}

/// [ConversationUnreadClearService.markReadForEditAction] 结果。
class MarkReadEditResult {
  const MarkReadEditResult({
    required this.conversationCount,
    required this.unreadSumBefore,
    required this.sdkPath,
    required this.durationMs,
  });

  final int conversationCount;
  final int unreadSumBefore;
  final String sdkPath; // type | queue | none
  final int durationMs;

  bool get isEmpty => conversationCount <= 0;
}

/// 多选全选且类型单一时，走 SDK `"c2c"` / `"group"` 一次清类型未读。
class TypeBulkCleanDecision {
  const TypeBulkCleanDecision({required this.isGroup});

  final bool isGroup;
}

class _ConversationReadWatermark {
  const _ConversationReadWatermark({
    required this.timestamp,
    required this.sequence,
  });

  final int timestamp;
  final int sequence;

  bool get isValid => timestamp > 0 || sequence > 0;
}

/// 会话未读清零：进聊天、离开聊天共用，含 SDK 重试。
class ConversationUnreadClearService {
  ConversationUnreadClearService._();

  static const openSdkRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 300),
    Duration(milliseconds: 800),
  ];

  static const leaveSdkRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 600),
    Duration(milliseconds: 1500),
  ];

  static const sdkCleanTypeC2c = 'c2c';
  static const sdkCleanTypeGroup = 'group';

  static const _sdkCleanMinInterval = Duration(seconds: 5);
  static const _frequencyBlockBackoff = Duration(seconds: 12);
  static const _leaveSkipAfterSuccess = Duration(seconds: 3);
  static const int _sdkFrequencyBlockCode = -10113;
  static const Duration _defaultQueuedSdkCleanInterval = Duration(
    milliseconds: 400,
  );

  /// 未读合计达到该阈值时，UI 应二次确认。
  static const int confirmUnreadSumThreshold = 200;

  /// Large batches yield after this many rows so the producer remains
  /// bounded. It is not a truncation limit: every captured conversation must
  /// eventually be offered to the SDK queue.
  static const int sdkQueueCap = 500;

  static final Map<String, Future<void>> _sdkCleanInFlight =
      <String, Future<void>>{};
  static final Set<String> _sdkCleanTrailingRequested = <String>{};
  static final Map<String, int> _sdkCleanIntentVersion = <String, int>{};
  static final Map<String, int> _sdkCleanObservedIntentVersion =
      <String, int>{};
  static final Map<String, DateTime> _frequencyBlockUntil =
      <String, DateTime>{};
  static final Map<String, DateTime> _lastSuccessfulSdkClean =
      <String, DateTime>{};
  // A missing watermark is a state transition, not a transient SDK failure.
  // Avoid rescanning the native message database on every recovery tick until
  // a meaningful event (open/read sync) explicitly requests another attempt.
  static final Map<String, DateTime> _watermarkUnavailableUntil =
      <String, DateTime>{};
  static final Map<String, int> _leaveSessionGenerationById = <String, int>{};
  static final Map<String, int> _leaveFinalizedGenerationById = <String, int>{};
  static final Map<String, _LeaveFinalizeFlight> _leaveFinalizeInFlightById =
      <String, _LeaveFinalizeFlight>{};

  static Future<void> _queueTail = Future<void>.value();
  static DateTime? _lastQueuedSdkCleanAt;
  static Future<void>? _readOutboxRecoveryInFlight;
  static bool _readOutboxRecoveryRequested = false;
  static bool _readOutboxReconnectRequested = false;
  static Timer? _readOutboxRetryTimer;
  static int _readOutboxRetryTimerGeneration = 0;

  static bool _isCurrentSession(int generation) {
    return SessionIdentityService.instance.isGenerationCurrent(generation);
  }

  /// Invalidates account-scoped SDK cleanups before the next account starts.
  /// In-flight native calls cannot be cancelled, but their retry tails and
  /// post-success local writes must not cross the account boundary.
  static void clearSession() {
    _sdkCleanInFlight.clear();
    _sdkCleanTrailingRequested.clear();
    _sdkCleanIntentVersion.clear();
    _sdkCleanObservedIntentVersion.clear();
    _frequencyBlockUntil.clear();
    _lastSuccessfulSdkClean.clear();
    _watermarkUnavailableUntil.clear();
    _leaveSessionGenerationById.clear();
    _leaveFinalizedGenerationById.clear();
    _leaveFinalizeInFlightById.clear();
    _queueTail = Future<void>.value();
    _lastQueuedSdkCleanAt = null;
    _readOutboxRecoveryInFlight = null;
    _readOutboxRecoveryRequested = false;
    _readOutboxReconnectRequested = false;
    _readOutboxRetryTimerGeneration++;
    _readOutboxRetryTimer?.cancel();
    _readOutboxRetryTimer = null;
  }

  @visibleForTesting
  static Future<V2TimCallback> Function(String conversationID)?
      sdkCleanOverride;

  @visibleForTesting
  static Duration queuedSdkCleanInterval = _defaultQueuedSdkCleanInterval;

  @visibleForTesting
  static void resetCoordinatorStateForTesting() {
    clearSession();
    sdkCleanOverride = null;
    _queueTail = Future<void>.value();
    _lastQueuedSdkCleanAt = null;
    queuedSdkCleanInterval = _defaultQueuedSdkCleanInterval;
  }

  /// 与会话列表 scope 判定一致：群会话 type==2 或 groupID 非空。
  static bool isGroupConversation(V2TimConversation conversation) {
    final groupID = conversation.groupID?.trim() ?? '';
    return conversation.type == 2 || groupID.isNotEmpty;
  }

  static _ConversationReadWatermark _watermarkFor(
    V2TimConversation? conversation, {
    String? expectedLastMessageId,
  }) {
    if (conversation == null) {
      return const _ConversationReadWatermark(timestamp: 0, sequence: 0);
    }
    final expected = expectedLastMessageId?.trim() ?? '';
    final actual = conversation.lastMessage?.msgID?.trim() ?? '';
    if (expected.isNotEmpty && expected != actual) {
      return const _ConversationReadWatermark(timestamp: 0, sequence: 0);
    }
    if (isGroupConversation(conversation)) {
      return _ConversationReadWatermark(
        timestamp: 0,
        sequence:
            int.tryParse(conversation.lastMessage?.seq?.trim() ?? '') ?? 0,
      );
    }
    final rawTimestamp = conversation.lastMessage?.timestamp ?? 0;
    return _ConversationReadWatermark(
      timestamp: ConversationReadPolicy.conservativeTimestamp(rawTimestamp),
      sequence: 0,
    );
  }

  /// 可见列表全部勾选且类型单一 → bulk；否则 null（走逐条限速）。
  static TypeBulkCleanDecision? shouldUseTypeBulkClean({
    required List<V2TimConversation> visible,
    required Set<String> selectedIds,
  }) {
    if (visible.isEmpty) {
      return null;
    }
    for (final conversation in visible) {
      final id = conversation.conversationID.trim();
      if (id.isEmpty || !selectedIds.contains(id)) {
        return null;
      }
    }
    bool? isGroup;
    for (final conversation in visible) {
      final group = isGroupConversation(conversation);
      if (isGroup == null) {
        isGroup = group;
      } else if (isGroup != group) {
        return null;
      }
    }
    if (isGroup == null) {
      return null;
    }
    return TypeBulkCleanDecision(isGroup: isGroup);
  }

  static MarkReadLocalScope _toStoreScope(MarkReadListScope scope) {
    switch (scope) {
      case MarkReadListScope.all:
        return MarkReadLocalScope.all;
      case MarkReadListScope.c2c:
        return MarkReadLocalScope.c2c;
      case MarkReadListScope.group:
        return MarkReadLocalScope.group;
    }
  }

  /// 确认框预估：不写库。
  static Future<MarkReadBatchResult> previewMarkReadForEditAction({
    required MarkReadEditMode mode,
    required MarkReadListScope listScope,
    Set<String> selectedIds = const <String>{},
    Set<String> archivedIds = const <String>{},
  }) {
    switch (mode) {
      case MarkReadEditMode.selected:
        return ConversationLocalStore.instance.previewUnreadForMarkRead(
          conversationIds: selectedIds,
        );
      case MarkReadEditMode.archivedAll:
        return ConversationLocalStore.instance.previewUnreadForMarkRead(
          conversationIds: archivedIds,
          scope: listScope == MarkReadListScope.all
              ? null
              : _toStoreScope(listScope),
        );
      case MarkReadEditMode.scopeAll:
        return ConversationLocalStore.instance.previewUnreadForMarkRead(
          scope: _toStoreScope(listScope),
        );
    }
  }

  /// 编辑态统一入口：批量本地清未读 + 按策略清 SDK。
  static Future<MarkReadEditResult> markReadForEditAction({
    required MarkReadEditMode mode,
    required MarkReadListScope listScope,
    Set<String> selectedIds = const <String>{},
    Set<String> archivedIds = const <String>{},
    void Function(String conversationID)? markViewModelReadLocally,
  }) async {
    final started = DateTime.now();
    final sessionGeneration = SessionIdentityService.instance.generation;
    late final MarkReadBatchResult local;
    switch (mode) {
      case MarkReadEditMode.selected:
        local = await ConversationLocalStore.instance.previewUnreadForMarkRead(
          conversationIds: selectedIds,
        );
        break;
      case MarkReadEditMode.archivedAll:
        local = await ConversationLocalStore.instance.previewUnreadForMarkRead(
          conversationIds: archivedIds,
          scope: listScope == MarkReadListScope.all
              ? null
              : _toStoreScope(listScope),
        );
        break;
      case MarkReadEditMode.scopeAll:
        local = await ConversationLocalStore.instance.previewUnreadForMarkRead(
          scope: _toStoreScope(listScope),
        );
        break;
    }

    if (!_isCurrentSession(sessionGeneration)) {
      return const MarkReadEditResult(
        conversationCount: 0,
        unreadSumBefore: 0,
        sdkPath: 'none',
        durationMs: 0,
      );
    }

    final durableOwner = ConversationLocalStore.instance.resolvedOwnerUserId();
    final durableReadAtMs = DateTime.now().millisecondsSinceEpoch;
    if (durableOwner.isEmpty) {
      return MarkReadEditResult(
        conversationCount: 0,
        unreadSumBefore: local.unreadSumBefore,
        sdkPath: 'none',
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
    }
    try {
      if (mode == MarkReadEditMode.scopeAll) {
        // Type-wide clean is intentionally a provider-side linearization at
        // dispatch time, so per-conversation watermarks are not used here.
        await ConversationReadOutboxStore.instance.enqueueMany(
          ownerUserId: durableOwner,
          conversationIds: local.clearedIds,
          lastReadAtMs: durableReadAtMs,
        );
      } else {
        final snapshots =
            await ConversationLocalStore.instance.conversationsByIds(
          local.clearedIds.toList(growable: false),
          ownerUserId: durableOwner,
          caller: 'markReadForEditAction',
        );
        final snapshotById = <String, V2TimConversation>{
          for (final item in snapshots) item.conversationID.trim(): item,
        };
        for (final id in local.clearedIds) {
          final snapshot = snapshotById[id.trim()];
          final watermark = _watermarkFor(snapshot);
          await ConversationReadOutboxStore.instance.enqueue(
            ownerUserId: durableOwner,
            conversationId: id,
            lastReadMessageId: snapshot?.lastMessage?.msgID ?? '',
            cleanTimestamp: watermark.timestamp,
            cleanSequence: watermark.sequence,
            lastReadAtMs: durableReadAtMs,
          );
        }
      }
    } catch (e) {
      debugPrint(
        'persist conversation read outbox failed '
        'errorType=${e.runtimeType}',
      );
      return MarkReadEditResult(
        conversationCount: 0,
        unreadSumBefore: local.unreadSumBefore,
        sdkPath: 'none',
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
    }

    await ConversationSyncService.instance.markConversationsReadLocallyBatch(
      local.clearedIds,
    );
    if (!_isCurrentSession(sessionGeneration)) {
      return const MarkReadEditResult(
        conversationCount: 0,
        unreadSumBefore: 0,
        sdkPath: 'none',
        durationMs: 0,
      );
    }

    ChatSessionController.instance.zeroUnreadLocallyMany(
      local.clearedIds,
      forceAggregateRefresh: true,
    );
    if (mode == MarkReadEditMode.scopeAll) {
      switch (listScope) {
        case MarkReadListScope.c2c:
          ConversationUnreadAggregate.instance.clearScopeOptimistically(
            isGroup: false,
          );
          break;
        case MarkReadListScope.group:
          ConversationUnreadAggregate.instance.clearScopeOptimistically(
            isGroup: true,
          );
          break;
        case MarkReadListScope.all:
          ConversationUnreadAggregate.instance
            ..clearScopeOptimistically(isGroup: false)
            ..clearScopeOptimistically(isGroup: true);
          break;
      }
    }
    for (final id in local.clearedIds) {
      markViewModelReadLocally?.call(id);
    }

    var sdkPath = 'none';
    if (local.clearedIds.isNotEmpty) {
      if (mode == MarkReadEditMode.selected ||
          mode == MarkReadEditMode.archivedAll) {
        sdkPath = 'queue';
        unawaited(enqueueSdkUnreadCleanBatch(local.clearedIds));
      } else {
        // scopeAll：按 Tab 走类型 bulk（真·全部），禁止误用「可见全选」旧判定。
        sdkPath = 'type';
        switch (listScope) {
          case MarkReadListScope.c2c:
            unawaited(
              cleanSdkUnreadForType(
                isGroup: false,
                markViewModelReadLocally: markViewModelReadLocally,
                markLocalAllOnSuccess: false,
                durableConversationIds: local.clearedIds,
                durableOwnerUserId: durableOwner,
                durableReadAtMs: durableReadAtMs,
              ),
            );
            break;
          case MarkReadListScope.group:
            unawaited(
              cleanSdkUnreadForType(
                isGroup: true,
                markViewModelReadLocally: markViewModelReadLocally,
                markLocalAllOnSuccess: false,
                durableConversationIds: local.clearedIds,
                durableOwnerUserId: durableOwner,
                durableReadAtMs: durableReadAtMs,
              ),
            );
            break;
          case MarkReadListScope.all:
            unawaited(() async {
              await cleanSdkUnreadForType(
                isGroup: false,
                markViewModelReadLocally: markViewModelReadLocally,
                markLocalAllOnSuccess: false,
                durableConversationIds: local.clearedIds.where(
                  (id) => !id.startsWith('group_'),
                ),
                durableOwnerUserId: durableOwner,
                durableReadAtMs: durableReadAtMs,
              );
              await cleanSdkUnreadForType(
                isGroup: true,
                markViewModelReadLocally: markViewModelReadLocally,
                markLocalAllOnSuccess: false,
                durableConversationIds: local.clearedIds.where(
                  (id) => id.startsWith('group_'),
                ),
                durableOwnerUserId: durableOwner,
                durableReadAtMs: durableReadAtMs,
              );
            }());
            break;
        }
      }
    }

    final durationMs = DateTime.now().difference(started).inMilliseconds;
    MarkSelectedReadLog.log('mark_read_edit_done', {
      'mode': mode.name,
      'listScope': listScope.name,
      'localCleared': local.conversationCount,
      'unreadSum': local.unreadSumBefore,
      'sdkPath': sdkPath,
      'durationMs': durationMs,
      'clearedIds': MarkSelectedReadLog.summarizeIds(local.clearedIds),
    });
    return MarkReadEditResult(
      conversationCount: local.conversationCount,
      unreadSumBefore: local.unreadSumBefore,
      sdkPath: sdkPath,
      durationMs: durationMs,
    );
  }

  /// 新开聊天会话时调用，允许该会话在离开时执行一次 finalize。
  static void beginConversationChatSession(String conversationID) {
    final id = conversationID.trim();
    if (id.isNotEmpty) {
      _leaveSessionGenerationById[id] =
          (_leaveSessionGenerationById[id] ?? 0) + 1;
    }
  }

  /// 离开聊天的唯一写库入口（幂等）：未读清零、已读锚点、本地持久化、可选 SDK 清未读。
  static Future<void> finalizeConversationLeaveOnce({
    required String conversationID,
    String? lastMessageId,
    int entryUnreadCount = 0,
    void Function(String conversationID)? markViewModelReadLocally,
    bool scheduleSdkUnreadCleanOnLeave = true,
  }) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    if (!_isCurrentSession(sessionGeneration)) {
      return;
    }
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }

    final generation = _leaveSessionGenerationById[id] ?? 0;
    if (_leaveFinalizedGenerationById[id] == generation) {
      ConversationUnreadTrace.log(
        'finalize_leave_skip',
        conversationID: id,
        extras: <String, Object?>{
          'reason': 'already_finalized',
          'generation': generation,
        },
      );
      return;
    }

    final existingFlight = _leaveFinalizeInFlightById[id];
    if (existingFlight != null) {
      ConversationUnreadTrace.log(
        'finalize_leave_join',
        conversationID: id,
        extras: <String, Object?>{
          'flightGeneration': existingFlight.generation,
          'requestedGeneration': generation,
        },
      );
      await existingFlight.future;
      // A newer Chat session may have started while the previous generation
      // was committing. In that case it still needs its own finalize.
      if (!_isCurrentSession(sessionGeneration)) {
        return;
      }
      if ((_leaveSessionGenerationById[id] ?? 0) != existingFlight.generation) {
        return finalizeConversationLeaveOnce(
          conversationID: id,
          lastMessageId: lastMessageId,
          entryUnreadCount: entryUnreadCount,
          markViewModelReadLocally: markViewModelReadLocally,
          scheduleSdkUnreadCleanOnLeave: scheduleSdkUnreadCleanOnLeave,
        );
      }
      return;
    }

    final task = _finalizeConversationLeave(
      conversationID: id,
      generation: generation,
      lastMessageId: lastMessageId,
      entryUnreadCount: entryUnreadCount,
      markViewModelReadLocally: markViewModelReadLocally,
      scheduleSdkUnreadCleanOnLeave: scheduleSdkUnreadCleanOnLeave,
      sessionGeneration: sessionGeneration,
    );
    final flight = _LeaveFinalizeFlight(generation: generation, future: task);
    _leaveFinalizeInFlightById[id] = flight;
    try {
      await task;
      if (_isCurrentSession(sessionGeneration)) {
        _leaveFinalizedGenerationById[id] = generation;
      }
    } finally {
      if (identical(_leaveFinalizeInFlightById[id], flight)) {
        _leaveFinalizeInFlightById.remove(id);
      }
    }
  }

  static Future<void> _finalizeConversationLeave({
    required String conversationID,
    required int generation,
    required String? lastMessageId,
    required int entryUnreadCount,
    required void Function(String conversationID)? markViewModelReadLocally,
    required bool scheduleSdkUnreadCleanOnLeave,
    required int sessionGeneration,
  }) async {
    if (!_isCurrentSession(sessionGeneration)) {
      return;
    }
    if (scheduleSdkUnreadCleanOnLeave && entryUnreadCount > 0) {
      final owner = ConversationLocalStore.instance.resolvedOwnerUserId();
      if (owner.isEmpty) return;
      try {
        final snapshot = await ConversationLocalStore.instance.conversationById(
          conversationID,
        );
        final watermark = _watermarkFor(
          snapshot,
          expectedLastMessageId: lastMessageId,
        );
        await ConversationReadOutboxStore.instance.enqueue(
          ownerUserId: owner,
          conversationId: conversationID,
          lastReadMessageId: lastMessageId ?? '',
          cleanTimestamp: watermark.timestamp,
          cleanSequence: watermark.sequence,
        );
        _recordReadIntent(conversationID);
      } catch (e) {
        debugPrint(
          'persist leave read outbox failed errorType=${e.runtimeType}',
        );
        return;
      }
    }
    ConversationUnreadTrace.log(
      'finalize_leave_start',
      conversationID: conversationID,
      extras: <String, Object?>{
        'entryUnreadCount': entryUnreadCount,
        'generation': generation,
      },
    );
    ChatSessionController.instance.zeroUnreadLocally(conversationID);
    ConversationLocalStore.instance.recordReadClearedAnchor(
      conversationID,
      lastMessageId: lastMessageId,
    );
    await ConversationSyncService.instance.markConversationReadLocally(
      conversationID,
    );
    if (!_isCurrentSession(sessionGeneration)) {
      return;
    }
    markViewModelReadLocally?.call(conversationID);
    if (scheduleSdkUnreadCleanOnLeave) {
      unawaited(
        scheduleSdkUnreadClean(
          conversationID: conversationID,
          trigger: SdkUnreadCleanTrigger.leave,
          hadUnread: entryUnreadCount > 0,
        ),
      );
    }
    ConversationUnreadTrace.log(
      'finalize_leave_done',
      conversationID: conversationID,
      unreadAfter: 0,
      extras: <String, Object?>{'generation': generation},
    );
  }

  /// 进聊天前快速清零未读：内存同帧清零，持久化完成后立即上报 SDK。
  static Future<void> clearLocalForOpenFast({
    required V2TimConversation conversation,
    void Function(String conversationID)? markViewModelReadLocally,
  }) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final conversationID = conversation.conversationID.trim();
    if (conversationID.isEmpty) {
      return;
    }
    final unreadBefore = conversation.unreadCount ?? 0;
    final aggregate = ConversationUnreadAggregate.instance;
    final aggregateBefore =
        '${aggregate.c2cNotifiableUnreadSum}/${aggregate.groupNotifiableUnreadSum}';
    final owner = ConversationLocalStore.instance.resolvedOwnerUserId();
    final watermark = _watermarkFor(conversation);
    beginConversationChatSession(conversationID);
    aggregate.clearSdkTotalForLocalProjection();
    ChatSessionController.instance.zeroUnreadLocally(conversationID);
    conversation.unreadCount = 0;
    ConversationLocalStore.instance.recordReadClearedAnchor(
      conversationID,
      lastMessageId: conversation.lastMessage?.msgID,
    );
    markViewModelReadLocally?.call(conversationID);
    ConversationUnreadTrace.log(
      'clear_local_open_fast',
      conversationID: conversationID,
      unreadBefore: unreadBefore,
      unreadAfter: 0,
      extras: <String, Object?>{
        'path': 'fast',
        'scope': isGroupConversation(conversation) ? 'group' : 'c2c',
        'aggregateBefore': aggregateBefore,
        'aggregateAfter':
            '${aggregate.c2cNotifiableUnreadSum}/${aggregate.groupNotifiableUnreadSum}',
      },
    );
    unawaited(
      ConversationSyncService.instance.markConversationReadLocally(
        conversationID,
        forceImmediateUi: true,
      ),
    );
    if (owner.isEmpty || unreadBefore <= 0) {
      return;
    }
    unawaited(
      _persistOpenReadIntentAndDispatch(
        ownerUserId: owner,
        conversationID: conversationID,
        lastReadMessageId: conversation.lastMessage?.msgID ?? '',
        watermark: watermark,
        sessionGeneration: sessionGeneration,
      ),
    );
  }

  static Future<void> _persistOpenReadIntentAndDispatch({
    required String ownerUserId,
    required String conversationID,
    required String lastReadMessageId,
    required _ConversationReadWatermark watermark,
    required int sessionGeneration,
  }) async {
    try {
      await ConversationReadOutboxStore.instance.enqueue(
        ownerUserId: ownerUserId,
        conversationId: conversationID,
        lastReadMessageId: lastReadMessageId,
        cleanTimestamp: watermark.timestamp,
        cleanSequence: watermark.sequence,
      );
      _recordReadIntent(conversationID);
      if (!_isCurrentSession(sessionGeneration)) return;
      await scheduleSdkUnreadClean(
        conversationID: conversationID,
        trigger: SdkUnreadCleanTrigger.open,
        hadUnread: true,
      );
    } catch (e) {
      debugPrint('persist open read outbox failed errorType=${e.runtimeType}');
      await _armReadOutboxRetryTimer();
    }
  }

  /// 进聊天前清零未读：仅写本地已读锚点，不阻塞导航等待 SDK。
  static Future<void> clearLocalForOpen({
    required V2TimConversation conversation,
    void Function(String conversationID)? markViewModelReadLocally,
  }) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final conversationID = conversation.conversationID.trim();
    if (conversationID.isEmpty) {
      return;
    }
    final aggregate = ConversationUnreadAggregate.instance;
    final aggregateBefore =
        '${aggregate.c2cNotifiableUnreadSum}/${aggregate.groupNotifiableUnreadSum}';
    final owner = ConversationLocalStore.instance.resolvedOwnerUserId();
    if (owner.isEmpty) return;
    final watermark = _watermarkFor(conversation);
    try {
      await ConversationReadOutboxStore.instance.enqueue(
        ownerUserId: owner,
        conversationId: conversationID,
        lastReadMessageId: conversation.lastMessage?.msgID ?? '',
        cleanTimestamp: watermark.timestamp,
        cleanSequence: watermark.sequence,
      );
      _recordReadIntent(conversationID);
    } catch (e) {
      debugPrint(
        'persist awaited open read outbox failed '
        'errorType=${e.runtimeType}',
      );
      return;
    }
    aggregate.clearSdkTotalForLocalProjection();
    ChatSessionController.instance.zeroUnreadLocally(conversationID);
    conversation.unreadCount = 0;
    ConversationLocalStore.instance.recordReadClearedAnchor(
      conversationID,
      lastMessageId: conversation.lastMessage?.msgID,
    );
    await ConversationSyncService.instance.markConversationReadLocally(
      conversationID,
      forceImmediateUi: true,
    );
    if (!_isCurrentSession(sessionGeneration)) {
      return;
    }
    markViewModelReadLocally?.call(conversationID);
    ConversationUnreadTrace.log(
      'clear_local_open_done',
      conversationID: conversationID,
      unreadAfter: 0,
      extras: <String, Object?>{
        'path': 'awaited',
        'aggregateBefore': aggregateBefore,
        'aggregateAfter':
            '${aggregate.c2cNotifiableUnreadSum}/${aggregate.groupNotifiableUnreadSum}',
      },
    );
  }

  /// 进聊天后异步清 SDK 未读。
  static Future<void> clearSdkUnreadAsync({
    required String conversationID,
    bool hadUnread = true,
  }) {
    return scheduleSdkUnreadClean(
      conversationID: conversationID,
      trigger: SdkUnreadCleanTrigger.open,
      hadUnread: hadUnread,
    );
  }

  /// 多选全选：一次清理全部单聊或全部群聊 SDK 未读；成功后本地同类型一并清零。
  static Future<void> cleanSdkUnreadForType({
    required bool isGroup,
    void Function(String conversationID)? markViewModelReadLocally,
    bool markLocalAllOnSuccess = true,
    Iterable<String> durableConversationIds = const <String>[],
    String durableOwnerUserId = '',
    int durableReadAtMs = 0,
  }) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final typeId = isGroup ? sdkCleanTypeGroup : sdkCleanTypeC2c;
    MarkSelectedReadLog.log('sdk_type_clean_begin', {
      'typeId': typeId,
      'isGroup': isGroup,
      'isWeb': kIsWeb,
      'markLocalAllOnSuccess': markLocalAllOnSuccess,
    });
    if (kIsWeb) {
      ConversationUnreadTrace.log(
        'sdk_clean_type_skip',
        conversationID: typeId,
        extras: <String, Object?>{'reason': 'web'},
      );
      MarkSelectedReadLog.log('sdk_type_clean_skip_web', {'typeId': typeId});
      return;
    }
    ConversationUnreadTrace.log(
      'sdk_clean_type_start',
      conversationID: typeId,
      extras: <String, Object?>{'isGroup': isGroup},
    );
    final lastCode = await _cleanSdkWithRetry(
      typeId,
      delays: openSdkRetryDelays,
      breakOnSuccess: true,
      sessionGeneration: sessionGeneration,
      allowFullTypeClean: true,
    );
    if (!_isCurrentSession(sessionGeneration)) {
      return;
    }
    if (lastCode == 0) {
      _lastSuccessfulSdkClean[typeId] = DateTime.now();
      if (durableOwnerUserId.isNotEmpty && durableReadAtMs > 0) {
        await ConversationReadOutboxStore.instance.acknowledgeMany(
          ownerUserId: durableOwnerUserId,
          conversationIds: durableConversationIds,
          lastReadAtMs: durableReadAtMs,
        );
      }
      if (markLocalAllOnSuccess) {
        MarkSelectedReadLog.log('sdk_type_clean_ok_mark_local_all', {
          'typeId': typeId,
          'isGroup': isGroup,
        });
        await markAllLocalConversationsReadByType(
          isGroup: isGroup,
          markViewModelReadLocally: markViewModelReadLocally,
          sessionGeneration: sessionGeneration,
        );
      } else {
        MarkSelectedReadLog.log('sdk_type_clean_ok_skip_local', {
          'typeId': typeId,
          'isGroup': isGroup,
        });
      }
      // SDK 类型级全部已读完成后再次确认清零。点击时的乐观清零可能被
      // SDK 在请求完成前回调的旧未读快照覆盖，导致底部 Tab 残留角标。
      ConversationUnreadAggregate.instance.clearScopeOptimistically(
        isGroup: isGroup,
      );
    } else {
      MarkSelectedReadLog.log('sdk_type_clean_failed', {
        'typeId': typeId,
        'sdkCode': lastCode,
        'isGroup': isGroup,
      });
    }
    ConversationUnreadTrace.log(
      'sdk_clean_type_done',
      conversationID: typeId,
      extras: <String, Object?>{'sdkCode': lastCode, 'isGroup': isGroup},
    );
    MarkSelectedReadLog.log('sdk_type_clean_end', {
      'typeId': typeId,
      'sdkCode': lastCode,
      'isGroup': isGroup,
    });
  }

  /// Bulk 成功后：本地同类型会话全部写已读（含归档/不可见）。
  static Future<void> markAllLocalConversationsReadByType({
    required bool isGroup,
    void Function(String conversationID)? markViewModelReadLocally,
    int? sessionGeneration,
  }) async {
    final generation =
        sessionGeneration ?? SessionIdentityService.instance.generation;
    final result =
        await ConversationLocalStore.instance.previewUnreadForMarkRead(
      scope: isGroup ? MarkReadLocalScope.group : MarkReadLocalScope.c2c,
    );
    if (!_isCurrentSession(generation)) {
      return;
    }
    await ConversationSyncService.instance.markConversationsReadLocallyBatch(
      result.clearedIds,
    );
    if (!_isCurrentSession(generation)) {
      return;
    }
    ChatSessionController.instance.zeroUnreadLocallyMany(
      result.clearedIds,
      forceAggregateRefresh: true,
    );
    ConversationUnreadAggregate.instance.clearSdkTotalForLocalProjection();
    for (final id in result.clearedIds) {
      markViewModelReadLocally?.call(id);
    }
    MarkSelectedReadLog.log('mark_all_local_by_type_batch', {
      'isGroup': isGroup,
      'cleared': result.conversationCount,
      'unreadSum': result.unreadSumBefore,
    });
  }

  /// 多选非全选：跨会话串行清 SDK 未读，间隔限速，撞频控则等到 block 结束再继续。
  static Future<void> enqueueSdkUnreadCleanBatch(
    Iterable<String> conversationIDs,
  ) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    var processed = 0;
    for (final conversationID in conversationIDs) {
      if (!_isCurrentSession(sessionGeneration)) return;
      await enqueueSdkUnreadClean(conversationID, hadUnread: true);
      processed++;
      if (processed % sdkQueueCap == 0) {
        // Release the producer turn between bounded chunks. Unlike the old
        // take(500), rows after the first chunk are never discarded.
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// 多选非全选：跨会话串行清 SDK 未读，间隔限速，撞频控则等到 block 结束再继续。
  static Future<void> enqueueSdkUnreadClean(
    String conversationID, {
    bool hadUnread = true,
  }) {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final id = conversationID.trim();
    if (id.isEmpty || !hadUnread) {
      MarkSelectedReadLog.log('queue_skip', {
        'conv': id,
        'hadUnread': hadUnread,
        'reason': id.isEmpty ? 'empty_id' : 'no_unread',
      });
      return Future<void>.value();
    }
    if (kIsWeb) {
      MarkSelectedReadLog.log('queue_skip', {'conv': id, 'reason': 'web'});
      return Future<void>.value();
    }
    MarkSelectedReadLog.log('queue_enqueue', {
      'conv': id,
      'intervalMs': queuedSdkCleanInterval.inMilliseconds,
    });
    final previous = _queueTail;
    final task = previous.then(
      (_) => _runQueuedSdkUnreadClean(id, sessionGeneration: sessionGeneration),
    );
    _queueTail = task.catchError((Object _) {});
    return task;
  }

  static Future<void> _runQueuedSdkUnreadClean(
    String conversationID, {
    required int sessionGeneration,
  }) async {
    if (!_isCurrentSession(sessionGeneration)) {
      return;
    }
    final lastAt = _lastQueuedSdkCleanAt;
    if (lastAt != null) {
      final elapsed = DateTime.now().difference(lastAt);
      final wait = queuedSdkCleanInterval - elapsed;
      if (wait > Duration.zero) {
        MarkSelectedReadLog.log('queue_rate_wait', {
          'conv': conversationID,
          'waitMs': wait.inMilliseconds,
        });
        await Future<void>.delayed(wait);
        if (!_isCurrentSession(sessionGeneration)) {
          return;
        }
      }
    }

    final blockUntil = _frequencyBlockUntil[conversationID];
    if (blockUntil != null) {
      final remaining = blockUntil.difference(DateTime.now());
      if (remaining > Duration.zero) {
        ConversationUnreadTrace.log(
          'sdk_clean_queue_wait_frequency_block',
          conversationID: conversationID,
          extras: <String, Object?>{'waitMs': remaining.inMilliseconds},
        );
        MarkSelectedReadLog.log('queue_freq_block_wait', {
          'conv': conversationID,
          'waitMs': remaining.inMilliseconds,
        });
        await Future<void>.delayed(remaining);
        if (!_isCurrentSession(sessionGeneration)) {
          return;
        }
      }
    }

    if (!_isCurrentSession(sessionGeneration)) {
      return;
    }

    MarkSelectedReadLog.log('queue_run_sdk_clean', {'conv': conversationID});
    _lastQueuedSdkCleanAt = DateTime.now();
    await scheduleSdkUnreadClean(
      conversationID: conversationID,
      trigger: SdkUnreadCleanTrigger.open,
      hadUnread: true,
    );
    if (!_isCurrentSession(sessionGeneration)) {
      return;
    }
    MarkSelectedReadLog.log('queue_run_sdk_clean_done', {
      'conv': conversationID,
    });
  }

  /// 协调同一会话的 SDK 清未读：去重、频控退避、leave 兜底。
  static Future<void> scheduleSdkUnreadClean({
    required String conversationID,
    required SdkUnreadCleanTrigger trigger,
    bool hadUnread = true,
  }) {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final id = conversationID.trim();
    if (id.isEmpty) {
      return Future<void>.value();
    }
    if (kIsWeb) {
      return Future<void>.value();
    }
    if (!_isCurrentSession(sessionGeneration)) {
      return Future<void>.value();
    }
    if (!hadUnread && !_lastSuccessfulSdkClean.containsKey(id)) {
      ConversationUnreadTrace.log(
        'sdk_clean_skip',
        conversationID: id,
        extras: <String, Object?>{
          'trigger': trigger.name,
          'reason': 'no_had_unread',
        },
      );
      return Future<void>.value();
    }

    final now = DateTime.now();
    if (trigger == SdkUnreadCleanTrigger.open) {
      _watermarkUnavailableUntil.remove(id);
    }
    final watermarkBlockedUntil = _watermarkUnavailableUntil[id];
    if (trigger == SdkUnreadCleanTrigger.recovery &&
        watermarkBlockedUntil != null &&
        now.isBefore(watermarkBlockedUntil)) {
      ConversationUnreadTrace.log(
        'sdk_clean_skip',
        conversationID: id,
        extras: <String, Object?>{
          'trigger': trigger.name,
          'reason': 'watermark_unavailable_cooldown',
          'until': watermarkBlockedUntil.toIso8601String(),
        },
      );
      return Future<void>.value();
    }
    final blockUntil = _frequencyBlockUntil[id];
    if (blockUntil != null && now.isBefore(blockUntil)) {
      final inFlight = _sdkCleanInFlight[id];
      if (inFlight != null) {
        _sdkCleanTrailingRequested.add(id);
        ConversationUnreadTrace.log(
          'sdk_clean_join_inflight',
          conversationID: id,
          extras: <String, Object?>{
            'trigger': trigger.name,
            'reason': 'frequency_block',
          },
        );
        return inFlight;
      }
      unawaited(_armReadOutboxRetryTimer(notBefore: blockUntil));
      ConversationUnreadTrace.log(
        'sdk_clean_skip',
        conversationID: id,
        extras: <String, Object?>{
          'trigger': trigger.name,
          'reason': 'frequency_block',
        },
      );
      return Future<void>.value();
    }

    final inFlight = _sdkCleanInFlight[id];
    if (inFlight != null) {
      if ((_sdkCleanIntentVersion[id] ?? 0) >
          (_sdkCleanObservedIntentVersion[id] ?? 0)) {
        _sdkCleanTrailingRequested.add(id);
      }
      ConversationUnreadTrace.log(
        'sdk_clean_join_inflight',
        conversationID: id,
        extras: <String, Object?>{'trigger': trigger.name},
      );
      return inFlight;
    }

    if (trigger == SdkUnreadCleanTrigger.leave) {
      final lastSuccess = _lastSuccessfulSdkClean[id];
      if (lastSuccess != null &&
          now.difference(lastSuccess) < _leaveSkipAfterSuccess) {
        ConversationUnreadTrace.log(
          'sdk_clean_skip',
          conversationID: id,
          extras: <String, Object?>{
            'trigger': trigger.name,
            'reason': 'recent_success',
          },
        );
        return Future<void>.value();
      }
    }

    if (trigger == SdkUnreadCleanTrigger.chatVisible) {
      final lastSuccess = _lastSuccessfulSdkClean[id];
      if (lastSuccess != null &&
          now.difference(lastSuccess) < _sdkCleanMinInterval) {
        ConversationUnreadTrace.log(
          'sdk_clean_skip',
          conversationID: id,
          extras: <String, Object?>{
            'trigger': trigger.name,
            'reason': 'min_interval',
          },
        );
        return Future<void>.value();
      }
    }

    ConversationUnreadTrace.log(
      'sdk_clean_start',
      conversationID: id,
      extras: <String, Object?>{
        'trigger': trigger.name,
        'hadUnread': hadUnread,
      },
    );

    final delays = trigger == SdkUnreadCleanTrigger.leave
        ? leaveSdkRetryDelays
        : openSdkRetryDelays;
    final task = _drainSdkClean(
      id,
      delays: delays,
      sessionGeneration: sessionGeneration,
      // SDK success is authoritative for the current unread state. Retrying a
      // successful leave clean can incorrectly consume messages that arrive
      // after the user has left and also multiplies group read reports.
      breakOnSuccess: true,
      // Only entering a conversation has the explicit "read everything now"
      // product semantics. Leave/recovery/passive visibility require a saved
      // provider watermark and never invent a 0/0 clear.
      allowFullConversationFallback: trigger == SdkUnreadCleanTrigger.open,
    );
    _sdkCleanObservedIntentVersion[id] = _sdkCleanIntentVersion[id] ?? 0;
    _sdkCleanInFlight[id] = task;
    return task.whenComplete(() {
      if (identical(_sdkCleanInFlight[id], task)) {
        _sdkCleanInFlight.remove(id);
        if (_sdkCleanTrailingRequested.remove(id)) {
          unawaited(_restartTrailingSdkCleanIfDue(id));
        }
      }
    });
  }

  static Future<void> _restartTrailingSdkCleanIfDue(
    String conversationID,
  ) async {
    final owner = ConversationLocalStore.instance.resolvedOwnerUserId();
    if (owner.isEmpty) return;
    final row = await ConversationReadOutboxStore.instance.find(
      ownerUserId: owner,
      conversationId: conversationID,
    );
    if (row == null ||
        row.nextRetryAtMs > DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    await scheduleSdkUnreadClean(
      conversationID: conversationID,
      trigger: SdkUnreadCleanTrigger.open,
      hadUnread: true,
    );
  }

  static void _recordReadIntent(String conversationID) {
    final id = conversationID.trim();
    if (id.isEmpty) return;
    _sdkCleanIntentVersion[id] = (_sdkCleanIntentVersion[id] ?? 0) + 1;
  }

  static Future<void> _drainSdkClean(
    String conversationID, {
    required List<Duration> delays,
    required bool breakOnSuccess,
    required int sessionGeneration,
    required bool allowFullConversationFallback,
  }) async {
    final owner = ConversationLocalStore.instance.resolvedOwnerUserId();
    if (owner.isEmpty) return;
    while (_isCurrentSession(sessionGeneration)) {
      _sdkCleanTrailingRequested.remove(conversationID);
      await _runSdkClean(
        conversationID,
        delays: delays,
        breakOnSuccess: breakOnSuccess,
        sessionGeneration: sessionGeneration,
        allowFullConversationFallback: allowFullConversationFallback,
      );
      if (!_isCurrentSession(sessionGeneration)) return;
      if (!_sdkCleanTrailingRequested.remove(conversationID)) return;
      ConversationUnreadTrace.log(
        'sdk_clean_trailing',
        conversationID: conversationID,
        extras: const <String, Object?>{
          'reason': 'newer_intent_while_inflight',
        },
      );
    }
  }

  static Future<void> _runSdkClean(
    String conversationID, {
    required List<Duration> delays,
    required bool breakOnSuccess,
    required int sessionGeneration,
    bool allowFullConversationFallback = false,
  }) async {
    final owner = ConversationLocalStore.instance.resolvedOwnerUserId();
    if (owner.isEmpty) return;
    try {
      if (sdkCleanOverride != null) {
        final code = await _cleanSdkWithRetry(
          conversationID,
          delays: const <Duration>[Duration.zero],
          breakOnSuccess: breakOnSuccess,
          sessionGeneration: sessionGeneration,
          allowFullTypeClean: true,
        );
        if (code == 0) {
          _lastSuccessfulSdkClean[conversationID] = DateTime.now();
        }
        return;
      }
      var row = await ConversationReadOutboxStore.instance.find(
        ownerUserId: owner,
        conversationId: conversationID,
      );
      if (row != null && row.nextRetryAtMs < 0) return;
      if (row != null &&
          row.lastReadMessageId.isNotEmpty &&
          row.cleanTimestamp <= 0 &&
          row.cleanSequence <= 0) {
        var snapshot = await ConversationLocalStore.instance.conversationById(
          conversationID,
        );
        var watermark = _watermarkFor(
          snapshot,
          expectedLastMessageId: row.lastReadMessageId,
        );
        if (!watermark.isValid && _isCurrentSession(sessionGeneration)) {
          snapshot = await TencentConversationReadService.conversationSnapshot(
            conversationID: conversationID,
            capturedIdentity: SessionIdentity(
              ownerUserId: owner,
              generation: sessionGeneration,
            ),
          );
          watermark = _watermarkFor(
            snapshot,
            expectedLastMessageId: row.lastReadMessageId,
          );
        }
        final readAtMs = row.lastReadAtMs;
        if (watermark.isValid) {
          await ConversationReadOutboxStore.instance.enqueue(
            ownerUserId: owner,
            conversationId: conversationID,
            lastReadMessageId: row.lastReadMessageId,
            cleanTimestamp: watermark.timestamp,
            cleanSequence: watermark.sequence,
            lastReadAtMs: readAtMs,
          );
          row = await ConversationReadOutboxStore.instance.find(
            ownerUserId: owner,
            conversationId: conversationID,
          );
        }
      }
      final useFullConversationFallback =
          row == null || (row.cleanTimestamp <= 0 && row.cleanSequence <= 0);
      if (useFullConversationFallback) {
        ConversationUnreadTrace.log(
          'sdk_clean_deferred',
          conversationID: conversationID,
          extras: <String, Object?>{'reason': 'read_watermark_unavailable'},
        );
        if (row != null) {
          await ConversationReadOutboxStore.instance
              .markRetry(row, reason: 'blocked:watermark_unavailable');
        }
        _watermarkUnavailableUntil[conversationID] =
            DateTime.now().add(const Duration(seconds: 30));
        await _armReadOutboxRetryTimer(
          notBefore: _watermarkUnavailableUntil[conversationID],
        );
        return;
      }
      if (!_isCurrentSession(sessionGeneration)) return;
      final lastCode = await _cleanSdkWithRetry(
        conversationID,
        // Only replay the precise, persisted target captured above.
        delays: delays,
        breakOnSuccess: breakOnSuccess,
        sessionGeneration: sessionGeneration,
        cleanTimestamp: row.cleanTimestamp,
        cleanSequence: row.cleanSequence,
        allowFullTypeClean: false,
      );
      if (!_isCurrentSession(sessionGeneration)) return;
      if (lastCode == 0) {
        _watermarkUnavailableUntil.remove(conversationID);
        _lastSuccessfulSdkClean[conversationID] = DateTime.now();
        await ConversationReadOutboxStore.instance.acknowledge(
          ownerUserId: owner,
          conversationId: conversationID,
          lastReadAtMs: row.lastReadAtMs,
        );
      } else {
        await ConversationReadOutboxStore.instance.markRetry(row,
            sdkCode: lastCode,
            notBeforeAtMs: lastCode == _sdkFrequencyBlockCode
                ? _frequencyBlockUntil[conversationID]?.millisecondsSinceEpoch
                : null);
        await _armReadOutboxRetryTimer();
      }
      ConversationUnreadTrace.log(
        'sdk_clean_done',
        conversationID: conversationID,
        extras: <String, Object?>{
          'sdkCode': lastCode,
          'cleanTimestamp': row.cleanTimestamp,
          'cleanSequence': row.cleanSequence,
          'fullFallback': false,
        },
      );
    } catch (e) {
      debugPrint(
        'persist read outbox before SDK clean failed '
        'errorType=${e.runtimeType}',
      );
      await _armReadOutboxRetryTimer();
    }
  }

  /// Replays durable mark-read rows after a real SDK socket connection.
  static Future<void> recoverPendingReadOutbox({bool afterReconnect = false}) {
    final running = _readOutboxRecoveryInFlight;
    if (running != null) {
      _readOutboxRecoveryRequested = true;
      _readOutboxReconnectRequested |= afterReconnect;
      return running;
    }
    _readOutboxRetryTimerGeneration++;
    _readOutboxRetryTimer?.cancel();
    _readOutboxRetryTimer = null;
    late final Future<void> task;
    task = (() async {
      if (afterReconnect)
        await ConversationReadOutboxStore.instance.resumeAfterReconnect(
            SessionIdentityService.instance.capture().ownerUserId);
      await _recoverPendingReadOutbox();
    })()
        .whenComplete(() {
      if (identical(_readOutboxRecoveryInFlight, task)) {
        _readOutboxRecoveryInFlight = null;
        if (_readOutboxRecoveryRequested) {
          final reconnect = _readOutboxReconnectRequested;
          _readOutboxRecoveryRequested = false;
          _readOutboxReconnectRequested = false;
          unawaited(recoverPendingReadOutbox(afterReconnect: reconnect)
              .catchError((Object error) {
            debugPrint('read outbox trailing recovery failed '
                'errorType=${error.runtimeType}');
          }));
        } else {
          unawaited(_armReadOutboxRetryTimer());
        }
      }
    });
    _readOutboxRecoveryInFlight = task;
    return task;
  }

  static Future<void> _recoverPendingReadOutbox() async {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    var cursor = '';
    for (var page = 0; page < 20; page++) {
      final rows = await ConversationReadOutboxStore.instance.listDue(
        ownerUserId: identity.ownerUserId,
        limit: sdkQueueCap,
        afterConversationId: cursor,
      );
      if (rows.isEmpty ||
          !SessionIdentityService.instance.isCurrent(identity)) {
        return;
      }
      for (final row in rows) {
        if (!SessionIdentityService.instance.isCurrent(identity)) return;
        cursor = row.conversationId;
        if (ConversationReadPolicy.validTarget(
          row.conversationId,
          row.cleanTimestamp,
          row.cleanSequence,
        )) {
          _watermarkUnavailableUntil.remove(row.conversationId);
        }
        await scheduleSdkUnreadClean(
          conversationID: row.conversationId,
          trigger: SdkUnreadCleanTrigger.recovery,
          hadUnread: true,
        );
        final frequencyUntil = _frequencyBlockUntil[row.conversationId];
        if (frequencyUntil != null && frequencyUntil.isAfter(DateTime.now())) {
          await ConversationReadOutboxStore.instance.deferUntilIfCurrent(
            row,
            frequencyUntil.millisecondsSinceEpoch,
          );
        }
      }
      if (rows.length < sdkQueueCap) return;
      await Future<void>.delayed(Duration.zero);
    }
  }

  static Future<void> _armReadOutboxRetryTimer({DateTime? notBefore}) async {
    if (kIsWeb) return;
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    final armGeneration = ++_readOutboxRetryTimerGeneration;
    final nextRetryAt = await ConversationReadOutboxStore.instance
        .earliestNextRetryAt(ownerUserId: identity.ownerUserId);
    if (armGeneration != _readOutboxRetryTimerGeneration ||
        !SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    _readOutboxRetryTimer?.cancel();
    _readOutboxRetryTimer = null;
    if (nextRetryAt == null) return;
    var target = DateTime.fromMillisecondsSinceEpoch(nextRetryAt);
    if (notBefore != null && notBefore.isAfter(target)) {
      target = notBefore;
    }
    final now = DateTime.now();
    final delay = target.isAfter(now) ? target.difference(now) : Duration.zero;
    _readOutboxRetryTimer = Timer(delay, () {
      _readOutboxRetryTimer = null;
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      unawaited(recoverPendingReadOutbox());
    });
  }

  /// 兼容旧调用：本地 + SDK 同步清未读。
  static Future<void> clearForOpen({
    required V2TimConversation conversation,
    void Function(String conversationID)? markViewModelReadLocally,
  }) async {
    final unreadCount = conversation.unreadCount ?? 0;
    await clearLocalForOpen(
      conversation: conversation,
      markViewModelReadLocally: markViewModelReadLocally,
    );
    if (unreadCount <= 0) {
      return;
    }
    if (kIsWeb) {
      await WebReadService.instance.markConversationRead(conversation);
      return;
    }
    await scheduleSdkUnreadClean(
      conversationID: conversation.conversationID,
      trigger: SdkUnreadCleanTrigger.open,
      hadUnread: true,
    );
  }

  /// 离开聊天：仅刷新本地已读锚点，不触发 SDK 清未读。
  static Future<void> clearLocalOnLeave({
    required String conversationID,
    void Function(String conversationID)? markViewModelReadLocally,
  }) async {
    await finalizeConversationLeaveOnce(
      conversationID: conversationID,
      markViewModelReadLocally: markViewModelReadLocally,
      scheduleSdkUnreadCleanOnLeave: false,
    );
  }

  static Future<int> _cleanSdkWithRetry(
    String conversationID, {
    required List<Duration> delays,
    required bool breakOnSuccess,
    required int sessionGeneration,
    int cleanTimestamp = 0,
    int cleanSequence = 0,
    bool allowFullTypeClean = false,
  }) async {
    var lastCode = 1;
    var attempt = 0;
    for (final delay in delays) {
      if (!_isCurrentSession(sessionGeneration)) {
        return 1;
      }
      attempt++;
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (!_isCurrentSession(sessionGeneration)) {
        return 1;
      }
      try {
        MarkSelectedReadLog.log('sdk_clean_attempt', {
          'conv': conversationID,
          'attempt': attempt,
          'delayMs': delay.inMilliseconds,
        });
        final result = await _invokeSdkClean(
          conversationID,
          sessionGeneration: sessionGeneration,
          cleanTimestamp: cleanTimestamp,
          cleanSequence: cleanSequence,
          allowFullTypeClean: allowFullTypeClean,
        );
        if (!_isCurrentSession(sessionGeneration)) {
          return 1;
        }
        lastCode = result.code;
        MarkSelectedReadLog.log('sdk_clean_attempt_result', {
          'conv': conversationID,
          'attempt': attempt,
          'sdkCode': result.code,
          'sdkDesc': result.desc,
        });
        if (result.code == _sdkFrequencyBlockCode) {
          _frequencyBlockUntil[conversationID] = DateTime.now().add(
            _frequencyBlockBackoff,
          );
          ConversationUnreadTrace.log(
            'sdk_clean_frequency_block',
            conversationID: conversationID,
            extras: <String, Object?>{
              'sdkCode': result.code,
              'sdkDesc': result.desc,
            },
          );
          MarkSelectedReadLog.log('sdk_clean_freq_block', {
            'conv': conversationID,
            'backoffSec': _frequencyBlockBackoff.inSeconds,
            'sdkDesc': result.desc,
          });
          break;
        }
        if (result.code != 0 &&
            !ConversationReadPolicy.failureReason(result.code)
                .startsWith('transient:')) {
          break;
        }
        if (shouldStopSdkRetry(
          breakOnSuccess: breakOnSuccess,
          resultCode: result.code,
        )) {
          break;
        }
      } catch (e) {
        debugPrint('cleanConversationUnread failed errorType=${e.runtimeType}');
        MarkSelectedReadLog.log('sdk_clean_attempt_exception', {
          'conv': conversationID,
          'attempt': attempt,
          'error': '$e',
        });
      }
    }
    return lastCode;
  }

  static Future<V2TimCallback> _invokeSdkClean(
    String conversationID, {
    required int sessionGeneration,
    required int cleanTimestamp,
    required int cleanSequence,
    required bool allowFullTypeClean,
  }) {
    final override = sdkCleanOverride;
    if (override != null) {
      return override(conversationID);
    }
    final identity = SessionIdentity(
      ownerUserId: '',
      generation: sessionGeneration,
    );
    return TencentConversationReadService.cleanUnread(
      conversationID: conversationID,
      capturedIdentity: identity,
      cleanTimestamp: cleanTimestamp,
      cleanSequence: cleanSequence,
      allowFullTypeClean: allowFullTypeClean,
    );
  }

  @visibleForTesting
  static bool shouldStopSdkRetry({
    required bool breakOnSuccess,
    required int resultCode,
  }) {
    return breakOnSuccess && resultCode == 0;
  }
}
