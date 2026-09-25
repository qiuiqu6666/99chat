import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'im05_contracts.dart';
import 'im05_persistence.dart';
import 'outbox_draft_submission.dart';
import 'im_ingress_store.dart';
import 'inbox_recovery_policy.dart';
import 'message_persist_coordinator.dart';

ImIngressStore createPlatformImIngressStore() => WebImIngressStore();

class WebImIngressStore implements ImIngressStore, ImOutboxObservationScope {
  static final Object _observationScope = Object();
  @override
  Object get outboxObservationScope => _observationScope;
  static const _dbName = 'xj_chat_message_ingress_v1';
  static const _storeName = 'state';
  static const _dbVersion = 1;
  Future<void> _tail = Future<void>.value();

  Future<IDBDatabase> _openDb() {
    final completer = Completer<IDBDatabase>();
    final request = window.indexedDB.open(_dbName, _dbVersion);
    request.onupgradeneeded = ((Event _) {
      final db = request.result as IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;
    request.onsuccess = ((Event _) {
      if (!completer.isCompleted) {
        completer.complete(request.result as IDBDatabase);
      }
    }).toJS;
    request.onerror = ((Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(request.error?.message ?? 'IndexedDB open failed'),
        );
      }
    }).toJS;
    return completer.future;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(ImIngressTransaction transaction) action, {
    MessagePersistPriority persistPriority = MessagePersistPriority.realtime,
  }) {
    final next = _tail.then<T>((_) => _run(action));
    _tail = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<T> _run<T>(
    Future<T> Function(ImIngressTransaction transaction) action,
  ) async {
    final db = await _openDb();
    final native = db.transaction(_storeName.toJS, 'readwrite');
    final completion = _transactionCompletion(native);
    final transaction = _WebImIngressTransaction(
      native.objectStore(_storeName),
    );
    try {
      final result = await action(transaction);
      final snapshots = await transaction.committedOutboxes();
      await completion;
      for (final (main, copy) in snapshots) {
        Im05Persistence.publishCommitted(outboxObservationScope, main, copy);
      }
      return result;
    } catch (error) {
      try {
        native.abort();
      } catch (_) {}
      rethrow;
    } finally {
      db.close();
    }
  }
}

class _WebImIngressTransaction
    with ImOutboxCommitTracking
    implements ImIngressTransaction, ImDraftTransaction {
  _WebImIngressTransaction(this._store);

  final IDBObjectStore _store;

  /// Walks keys without materializing the object store. The callback is
  /// synchronous so every cursor continuation remains inside the same
  /// IndexedDB transaction.
  Future<void> _scanPrefix(
    String prefix,
    bool Function(String key, String value) visit, {
    String? afterKey,
  }) {
    final completer = Completer<void>();
    final request = _store.openCursor(
      IDBKeyRange.lowerBound((afterKey ?? prefix).toJS, afterKey != null),
    );
    request.onsuccess = ((Event _) {
      if (completer.isCompleted) return;
      try {
        final result = request.result;
        if (result == null || result.isUndefinedOrNull) {
          completer.complete();
          return;
        }
        final cursor = result as IDBCursorWithValue;
        final key = (cursor.key as JSString).toDart;
        if (!key.startsWith(prefix)) {
          completer.complete();
          return;
        }
        final raw = cursor.value;
        if (raw != null &&
            !raw.isUndefinedOrNull &&
            !visit(key, (raw as JSString).toDart)) {
          completer.complete();
          return;
        }
        cursor.continue_();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    }).toJS;
    request.onerror = ((Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(request.error?.message ?? 'IndexedDB cursor failed'),
        );
      }
    }).toJS;
    return completer.future;
  }

  @override
  Future<Map<String, Object?>?> findDraftHead(
          String owner, String conversation) async =>
      _decodeMap(await _get('draft|' + owner + '|' + conversation));
  @override
  Future<void> saveDraftHead(ImDraftAcceptance draft) async {
    final old = await findDraftHead(draft.ownerUserId, draft.conversationId);
    final acceptedOperation = await _get('draft-accepted|' +
        draft.ownerUserId +
        '|' +
        draft.conversationId +
        '|' +
        draft.draftId);
    if (acceptedOperation != null && old != null) return;
    await _put(
        'draft|' + draft.ownerUserId + '|' + draft.conversationId,
        jsonEncode({
          'draft_id': draft.draftId,
          'protected_text': draft.protectedText,
          'accepted_operation_id': acceptedOperation
        }));
  }

  @override
  Future<void> acceptDraft(ImDraftAcceptance draft, String operationId) async {
    final key = 'draft-accepted|' +
        draft.ownerUserId +
        '|' +
        draft.conversationId +
        '|' +
        draft.draftId;
    final old = await _get(key);
    if (old != null && old != operationId)
      throw StateError('draft already accepted by another operation');
    await _put(key, operationId);
    var head = await findDraftHead(draft.ownerUserId, draft.conversationId);
    if (head == null) {
      await saveDraftHead(draft);
      head = await findDraftHead(draft.ownerUserId, draft.conversationId);
    }
    if (head!['draft_id'] == draft.draftId)
      await _put('draft|' + draft.ownerUserId + '|' + draft.conversationId,
          jsonEncode({...head, 'accepted_operation_id': operationId}));
  }

  String _inboxKey(String owner, String namespace, String eventId) =>
      'inbox|$owner|$namespace|$eventId';

  String _counterKey(String owner, String scopeKey) =>
      'counter|$owner|$scopeKey';

  String _leaseKey(String owner) => 'lease|$owner';

  String _journalKey(String owner, String journalId) =>
      'journal|$owner|$journalId';

  String _checkpointKey(String owner, String scope) =>
      'checkpoint|$owner|$scope';

  String _effectKey(String owner, String effectId) => 'effect|$owner|$effectId';

  // operationId is globally unique by contract, matching the SQLite
  // primary key and the in-memory implementation.
  String _outboxKey(String owner, String operationId) => 'outbox|$operationId';

  String _outboxRecoveryKey(String owner, String operationId) =>
      'outbox-recovery|$operationId';

  @override
  Future<ImInboxRecord?> findInbox({
    required String ownerUserId,
    required String eventNamespace,
    required String eventId,
  }) async {
    final raw = await _get(
      _inboxKey(ownerUserId, eventNamespace, eventId),
    );
    final map = _decodeMap(raw);
    return map == null ? null : imInboxRecordFromStorageMap(map);
  }

  @override
  Future<int> allocateAccountIngressSequence({
    required String ownerUserId,
    required int nowMs,
  }) =>
      _allocate(ownerUserId, '');

  @override
  Future<int> allocateScopeIngressSequence({
    required String ownerUserId,
    required String scopeKey,
    required int nowMs,
  }) =>
      _allocate(ownerUserId, scopeKey);

  Future<int> _allocate(String owner, String scopeKey) async {
    final key = _counterKey(owner, scopeKey);
    final current = int.tryParse(await _get(key) ?? '') ?? 0;
    final next = current + 1;
    await _put(key, '$next');
    return next;
  }

  @override
  Future<void> insertInbox(ImInboxRecord record) {
    return _put(
      _inboxKey(
        record.event.ownerUserId,
        record.event.eventNamespace,
        record.event.eventId,
      ),
      jsonEncode(imInboxRecordToStorageMap(record)),
    );
  }

  @override
  Future<List<ImInboxRecord>> listInboxForRecovery({
    required String ownerUserId,
    required int accountGeneration,
    int? domainGeneration,
    required int nowMs,
    required int processingTimeoutMs,
    required int limit,
  }) async {
    final staleBefore = nowMs - processingTimeoutMs;
    final records = <ImInboxRecord>[];
    await _scanPrefix('inbox|$ownerUserId|', (_, value) {
      final map = _decodeMap(value);
      if (map == null) return true;
      final record = imInboxRecordFromStorageMap(map);
      final event = record.event;
      if (event.ownerUserId != ownerUserId ||
          event.accountGeneration != accountGeneration ||
          (domainGeneration != null &&
              event.domainGeneration != domainGeneration)) {
        return true;
      }
      if (isInboxRecordDue(
        record,
        nowMs: nowMs,
        staleBeforeMs: staleBefore,
      )) {
        records.add(record);
      }
      return true;
    });
    records.sort((left, right) {
      final priority = left.recoveryPriority.compareTo(right.recoveryPriority);
      if (priority != 0) return priority;
      final retry = left.nextRetryAtMs.compareTo(right.nextRetryAtMs);
      if (retry != 0) return retry;
      return left.event.accountIngressSequence
          .compareTo(right.event.accountIngressSequence);
    });
    return records.take(limit).toList(growable: false);
  }

  @override
  Future<InboxRecoveryCounts> countInboxRecovery({
    required String ownerUserId,
    required int accountGeneration,
    int? domainGeneration,
    required int nowMs,
    required int processingTimeoutMs,
  }) async {
    var pending = 0;
    var due = 0;
    int? oldest;
    final staleBefore = nowMs - processingTimeoutMs;
    await _scanPrefix('inbox|$ownerUserId|', (_, value) {
      final map = _decodeMap(value);
      if (map == null) return true;
      final record = imInboxRecordFromStorageMap(map);
      final event = record.event;
      if (event.ownerUserId != ownerUserId ||
          event.accountGeneration != accountGeneration ||
          (domainGeneration != null &&
              event.domainGeneration != domainGeneration) ||
          record.status == ImInboxStatus.completed ||
          record.status == ImInboxStatus.abandoned) return true;
      pending++;
      final observed = event.observedAtMs;
      if (oldest == null || observed < oldest!) oldest = observed;
      if (isInboxRecordDue(record, nowMs: nowMs, staleBeforeMs: staleBefore))
        due++;
      return true;
    });
    return InboxRecoveryCounts(
      pendingCount: pending,
      dueCount: due,
      oldestPendingAgeMs:
          oldest == null ? 0 : (nowMs - oldest!).clamp(0, 1 << 31),
    );
  }

  @override
  Future<bool> updateInboxRetry({
    required String ownerUserId,
    required String eventNamespace,
    required String eventId,
    required int retryCount,
    required int nextRetryAtMs,
    required String lastErrorClass,
    ImInboxStatus? nextStatus,
    int? processingStartedAtMs,
  }) async {
    if (nextStatus == ImInboxStatus.completed) return false;
    final current = await findInbox(
      ownerUserId: ownerUserId,
      eventNamespace: eventNamespace,
      eventId: eventId,
    );
    if (current == null || current.status == ImInboxStatus.completed) {
      return false;
    }
    await insertInbox(
      current.copyWith(
        retryCount: retryCount,
        nextRetryAtMs: nextRetryAtMs,
        lastErrorClass: lastErrorClass,
        status: nextStatus,
        processingStartedAtMs: processingStartedAtMs,
      ),
    );
    return true;
  }

  @override
  Future<ImInboxRecord?> claimInboxForWriter({
    required String ownerUserId,
    required String eventNamespace,
    required String eventId,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
    bool allowStaleProcessing = false,
    int processingTimeoutMs = 30000,
  }) async {
    final currentLease = await findWriterLease(ownerUserId);
    if (currentLease == null ||
        currentLease.leaseOwnerId != leaseOwnerId ||
        currentLease.fencingToken != fencingToken ||
        currentLease.isExpiredAt(nowMs)) {
      return null;
    }
    final current = await findInbox(
      ownerUserId: ownerUserId,
      eventNamespace: eventNamespace,
      eventId: eventId,
    );
    if (current == null) {
      return current;
    }
    if (current.status == ImInboxStatus.processing) {
      if (!allowStaleProcessing ||
          (current.processingStartedAtMs != null &&
              current.processingStartedAtMs! > nowMs - processingTimeoutMs)) {
        return null;
      }
      final claimed = current.copyWith(processingStartedAtMs: nowMs);
      await insertInbox(claimed);
      return claimed;
    }
    if (current.status != ImInboxStatus.prepared) {
      return current;
    }
    final claimed = current.copyWith(
      status: ImInboxStatus.processing,
      processingStartedAtMs: nowMs,
    );
    await insertInbox(claimed);
    return claimed;
  }

  @override
  Future<bool> advanceInboxStatusIfCurrent({
    required String ownerUserId,
    required String eventNamespace,
    required String eventId,
    required ImInboxStatus expectedStatus,
    required ImInboxStatus nextStatus,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
    int? committedAtMs,
    bool completeRecoveryCopies = false,
  }) async {
    if (!isValidImInboxTransition(expectedStatus, nextStatus)) return false;
    final currentLease = await findWriterLease(ownerUserId);
    if (currentLease == null ||
        currentLease.leaseOwnerId != leaseOwnerId ||
        currentLease.fencingToken != fencingToken ||
        currentLease.isExpiredAt(nowMs)) {
      return false;
    }
    final current = await findInbox(
      ownerUserId: ownerUserId,
      eventNamespace: eventNamespace,
      eventId: eventId,
    );
    if (current == null || current.status != expectedStatus) return false;
    await insertInbox(
      current.copyWith(
        status: nextStatus,
        committedAtMs: committedAtMs,
      ),
    );
    if (completeRecoveryCopies && nextStatus == ImInboxStatus.completed) {
      final operation = current.event.operationId;
      if (operation?.startsWith('receipt-compat-batch:') != true) {
        throw StateError('invalid recovery aggregate completion');
      }
      final siblings = <ImInboxRecord>[];
      await _scanPrefix('inbox|$ownerUserId|$eventNamespace|', (_, value) {
        final map = _decodeMap(value);
        if (map == null ||
            !map.containsKey('event_id') ||
            map['owner_user_id'] != ownerUserId ||
            map['event_namespace'] != eventNamespace ||
            map['operation_id'] != operation ||
            map['event_id'] == eventId ||
            map['status'] == ImInboxStatus.completed.name) return true;
        siblings.add(imInboxRecordFromStorageMap(map));
        return true;
      });
      for (final sibling in siblings) {
        await insertInbox(sibling.copyWith(
            status: ImInboxStatus.completed, committedAtMs: nowMs));
      }
    }
    return true;
  }

  @override
  Future<bool> insertWriterLeaseIfAbsent(ImWriterLeaseRecord record) async {
    final key = _leaseKey(record.ownerUserId);
    if (await _get(key) != null) return false;
    await _put(key, jsonEncode(imWriterLeaseToStorageMap(record)));
    return true;
  }

  @override
  Future<ImWriterLeaseRecord?> findWriterLease(String ownerUserId) async {
    final map = _decodeMap(await _get(_leaseKey(ownerUserId)));
    return map == null ? null : imWriterLeaseFromStorageMap(map);
  }

  @override
  Future<bool> replaceWriterLeaseIfCurrent({
    required String ownerUserId,
    required String expectedLeaseOwnerId,
    required int expectedFencingToken,
    required ImWriterLeaseRecord replacement,
  }) async {
    final current = await findWriterLease(ownerUserId);
    if (current == null ||
        current.leaseOwnerId != expectedLeaseOwnerId ||
        current.fencingToken != expectedFencingToken) {
      return false;
    }
    await _put(
      _leaseKey(ownerUserId),
      jsonEncode(imWriterLeaseToStorageMap(replacement)),
    );
    return true;
  }

  @override
  Future<bool> deleteWriterLeaseIfCurrent({
    required String ownerUserId,
    required String leaseOwnerId,
    required int fencingToken,
  }) async {
    final current = await findWriterLease(ownerUserId);
    if (current == null ||
        current.leaseOwnerId != leaseOwnerId ||
        current.fencingToken != fencingToken) {
      return false;
    }
    await _put(
      _leaseKey(ownerUserId),
      jsonEncode(
        imWriterLeaseToStorageMap(
          ImWriterLeaseRecord(
            ownerUserId: current.ownerUserId,
            leaseOwnerId: current.leaseOwnerId,
            fencingToken: current.fencingToken,
            acquiredAtMs: current.acquiredAtMs,
            expiresAtMs: 0,
            heartbeatAtMs: 0,
          ),
        ),
      ),
    );
    return true;
  }

  @override
  Future<ImCommitJournalRecord?> findCommitJournal({
    required String ownerUserId,
    required String journalId,
  }) async {
    final map = _decodeMap(await _get(_journalKey(ownerUserId, journalId)));
    return map == null ? null : imCommitJournalFromStorageMap(map);
  }

  @override
  Future<bool> insertCommitJournalIfAbsent(ImCommitJournalRecord record) async {
    final key = _journalKey(record.ownerUserId, record.journalId);
    if (await _get(key) != null) return false;
    await _put(key, jsonEncode(imCommitJournalToStorageMap(record)));
    return true;
  }

  @override
  Future<bool> updateCommitJournalIfCurrent({
    required ImCommitJournalRecord record,
    required ImCommitJournalState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) async {
    if (!isValidImCommitJournalTransition(expectedState, record.state) ||
        !await _hasCurrentLease(
            record.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
      return false;
    }
    final current = await findCommitJournal(
      ownerUserId: record.ownerUserId,
      journalId: record.journalId,
    );
    if (current == null || current.state != expectedState) return false;
    await _put(
      _journalKey(record.ownerUserId, record.journalId),
      jsonEncode(imCommitJournalToStorageMap(record)),
    );
    return true;
  }

  @override
  Future<ImProjectionCheckpointRecord?> findProjectionCheckpoint({
    required String ownerUserId,
    required String scope,
  }) async {
    final map = _decodeMap(await _get(_checkpointKey(ownerUserId, scope)));
    return map == null ? null : imProjectionCheckpointFromStorageMap(map);
  }

  @override
  Future<bool> saveProjectionCheckpointIfCurrent({
    required ImProjectionCheckpointRecord record,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) async {
    if (!await _hasCurrentLease(
        record.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
      return false;
    }
    final current = await findProjectionCheckpoint(
      ownerUserId: record.ownerUserId,
      scope: record.scope,
    );
    if (current != null && record.commitRevision < current.commitRevision) {
      return false;
    }
    if (current != null &&
        current.commitRevision == record.commitRevision &&
        _sameCheckpoint(current, record)) {
      return true;
    }
    if (current != null && record.commitRevision <= current.commitRevision) {
      return false;
    }
    await _put(
      _checkpointKey(record.ownerUserId, record.scope),
      jsonEncode(imProjectionCheckpointToStorageMap(record)),
    );
    return true;
  }

  @override
  Future<ImEffectLedgerRecord?> findEffect({
    required String ownerUserId,
    required String effectId,
  }) async {
    final map = _decodeMap(await _get(_effectKey(ownerUserId, effectId)));
    return map == null ? null : imEffectLedgerFromStorageMap(map);
  }

  @override
  Future<bool> insertEffectIfAbsent(ImEffectLedgerRecord record) async {
    final key = _effectKey(record.ownerUserId, record.effectId);
    if (await _get(key) != null) return false;
    await _put(key, jsonEncode(imEffectLedgerToStorageMap(record)));
    return true;
  }

  @override
  Future<bool> updateEffectIfCurrent({
    required ImEffectLedgerRecord record,
    required ImEffectLedgerState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) async {
    if (!isValidImEffectTransition(expectedState, record.state) ||
        !await _hasCurrentLease(
            record.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
      return false;
    }
    final current = await findEffect(
      ownerUserId: record.ownerUserId,
      effectId: record.effectId,
    );
    if (current == null || current.state != expectedState) return false;
    await _put(
      _effectKey(record.ownerUserId, record.effectId),
      jsonEncode(imEffectLedgerToStorageMap(record)),
    );
    return true;
  }

  @override
  Future<ImOutboxRecord?> findOutbox({
    required String ownerUserId,
    required String operationId,
  }) async {
    observedOutboxes.add((ownerUserId, operationId));
    final map = _decodeMap(await _get(_outboxKey(ownerUserId, operationId)));
    if (map == null || map['owner_user_id'] != ownerUserId) return null;
    return imOutboxFromStorageMap(map);
  }

  @override
  Future<ImOutboxRecord?> findOutboxBySdkLocalId({
    required String ownerUserId,
    required String conversationId,
    required String sdkLocalId,
  }) async {
    ImOutboxRecord? latest;
    await _scanPrefix('outbox|', (_, value) {
      final map = _decodeMap(value);
      if (map == null || !map.containsKey('operation_id')) return true;
      final record = imOutboxFromStorageMap(map);
      if (record.ownerUserId == ownerUserId &&
          record.conversationId == conversationId &&
          record.sdkMessageId == sdkLocalId &&
          (latest == null || record.updatedAtMs > latest!.updatedAtMs)) {
        latest = record;
      }
      return true;
    });
    return latest;
  }

  @override
  Future<bool> hasOtherRetryChild({
    required String ownerUserId,
    required String parentOperationId,
    required String excludingOperationId,
  }) async {
    // Retry records predate a parent index. Visit the complete outbox range,
    // but stop as soon as one conflicting child is found.
    var found = false;
    await _scanPrefix('outbox|', (_, value) {
      final map = _decodeMap(value);
      if (map != null &&
          map['owner_user_id'] == ownerUserId &&
          map['retry_of_operation_id'] == parentOperationId &&
          map['operation_id'] != excludingOperationId) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Future<List<ImOutboxRecord>> listOutboxesForRecovery({
    required String ownerUserId,
    required List<ImOutboxState> states,
    required int limit,
    String? afterOperationId,
  }) async {
    if (states.isEmpty || limit <= 0) return const <ImOutboxRecord>[];
    final allowed = states.toSet();
    final records = <ImOutboxRecord>[];
    await _scanPrefix('outbox|', (_, value) {
      final map = _decodeMap(value);
      if (map == null || !map.containsKey('operation_id')) return true;
      final record = imOutboxFromStorageMap(map);
      if (record.ownerUserId == ownerUserId && allowed.contains(record.state)) {
        records.add(record);
        if (afterOperationId != null && records.length >= limit) return false;
      }
      return true;
    }, afterKey: afterOperationId == null ? null : 'outbox|$afterOperationId');
    if (afterOperationId == null) {
      records.sort((a, b) => a.updatedAtMs.compareTo(b.updatedAtMs));
    }
    return records.take(limit).toList(growable: false);
  }

  @override
  Future<bool> insertOutboxIfAbsent(ImOutboxRecord record) async {
    final key = _outboxKey(record.ownerUserId, record.operationId);
    if (await _get(key) != null) return false;
    await _put(key, jsonEncode(imOutboxToStorageMap(record)));
    return true;
  }

  @override
  Future<bool> updateOutboxIfCurrent({
    required ImOutboxRecord record,
    required ImOutboxState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) async {
    if (!isValidImOutboxTransition(expectedState, record.state) ||
        !await _hasCurrentLease(
            record.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
      return false;
    }
    final current = await findOutbox(
      ownerUserId: record.ownerUserId,
      operationId: record.operationId,
    );
    if (current == null || current.state != expectedState) return false;
    await _put(
      _outboxKey(record.ownerUserId, record.operationId),
      jsonEncode(imOutboxToStorageMap(
          record.copyWith(stateVersion: current.stateVersion + 1))),
    );
    return true;
  }

  @override
  Future<ImOutboxRecoveryRecord?> findOutboxRecovery({
    required String ownerUserId,
    required String operationId,
  }) async {
    final map = _decodeMap(
      await _get(_outboxRecoveryKey(ownerUserId, operationId)),
    );
    return map == null || map['owner_user_id'] != ownerUserId
        ? null
        : imOutboxRecoveryFromStorageMap(map);
  }

  @override
  Future<bool> insertOutboxRecoveryIfAbsent(
    ImOutboxRecoveryRecord record,
  ) async {
    final key = _outboxRecoveryKey(record.ownerUserId, record.operationId);
    if (await _get(key) != null) return false;
    await _put(key, jsonEncode(imOutboxRecoveryToStorageMap(record)));
    await _bumpMainVersion(record);
    return true;
  }

  @override
  Future<bool> updateOutboxRecoveryIfCurrent({
    required ImOutboxRecoveryRecord record,
    required ImOutboxCopyState expectedState,
    required String leaseOwnerId,
    required int fencingToken,
    required int nowMs,
  }) async {
    if (!isValidImOutboxRecoveryTransition(expectedState, record.state) ||
        !await _hasCurrentLease(
            record.ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
      return false;
    }
    final current = await findOutboxRecovery(
      ownerUserId: record.ownerUserId,
      operationId: record.operationId,
    );
    if (current == null || current.state != expectedState) return false;
    await _put(
      _outboxRecoveryKey(record.ownerUserId, record.operationId),
      jsonEncode(imOutboxRecoveryToStorageMap(record)),
    );
    await _bumpMainVersion(record);
    return true;
  }

  Future<void> _bumpMainVersion(ImOutboxRecoveryRecord copy) async {
    final main = await findOutbox(
        ownerUserId: copy.ownerUserId, operationId: copy.operationId);
    if (main != null)
      await _put(
          _outboxKey(main.ownerUserId, main.operationId),
          jsonEncode(imOutboxToStorageMap(
              main.copyWith(stateVersion: main.stateVersion + 1))));
  }

  Future<bool> _hasCurrentLease(
    String ownerUserId,
    String leaseOwnerId,
    int fencingToken,
    int nowMs,
  ) async {
    final lease = await findWriterLease(ownerUserId);
    return lease != null &&
        lease.leaseOwnerId == leaseOwnerId &&
        lease.fencingToken == fencingToken &&
        !lease.isExpiredAt(nowMs);
  }

  Future<String?> _get(String key) async {
    final result = await _request(_store.get(key.toJS));
    if (result == null || result.isUndefinedOrNull) return null;
    return (result as JSString).toDart;
  }

  Future<void> _put(String key, String value) async {
    await _request(_store.put(value.toJS, key.toJS));
  }
}

Future<JSAny?> _request(IDBRequest request) {
  final completer = Completer<JSAny?>();
  request.onsuccess = ((Event _) {
    if (!completer.isCompleted) completer.complete(request.result);
  }).toJS;
  request.onerror = ((Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(request.error?.message ?? 'IndexedDB request failed'),
      );
    }
  }).toJS;
  return completer.future;
}

Future<void> _transactionCompletion(IDBTransaction transaction) {
  final completer = Completer<void>();
  transaction.oncomplete = ((Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  transaction.onabort = ((Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(transaction.error?.message ?? 'IndexedDB aborted'),
      );
    }
  }).toJS;
  transaction.onerror = ((Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(transaction.error?.message ?? 'IndexedDB failed'),
      );
    }
  }).toJS;
  return completer.future;
}

Map<String, Object?>? _decodeMap(String? value) {
  if (value == null || value.isEmpty) return null;
  final decoded = jsonDecode(value);
  if (decoded is! Map) return null;
  return Map<String, Object?>.from(decoded);
}

bool _sameCheckpoint(
  ImProjectionCheckpointRecord left,
  ImProjectionCheckpointRecord right,
) {
  return left.ownerUserId == right.ownerUserId &&
      left.scope == right.scope &&
      left.commitRevision == right.commitRevision &&
      left.lastJournalId == right.lastJournalId &&
      left.coverageRevision == right.coverageRevision &&
      left.watermarkRevision == right.watermarkRevision &&
      left.barrierRevision == right.barrierRevision &&
      left.projectionVersion == right.projectionVersion;
}
