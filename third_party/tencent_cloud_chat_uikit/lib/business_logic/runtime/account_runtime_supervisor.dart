import 'dart:async';
import 'dart:collection';

import 'runtime_protocol.dart';

/// Phase-one shadow runtime. It computes transitions and effect intents only.
/// No SDK, database, UI, timers for retries, or effect executor is reachable here.
/// Authority must not be handed over until the durable commit adapter exists.
class AccountRuntimeSupervisor {
  AccountRuntimeSupervisor.shadow(
      {required this.scope,
      required RuntimeReducer reducer,
      required RuntimeDocument Function(String conversationKey) initialState,
      this.eventsPerTurn = 32})
      : _reducer = reducer,
        _initialState = initialState {
    if (eventsPerTurn < 1) throw ArgumentError.value(eventsPerTurn);
  }

  final RuntimeAccountScope scope;
  final RuntimeReducer _reducer;
  final RuntimeDocument Function(String) _initialState;
  final int eventsPerTurn;
  final Map<String, ConversationActor> _actors = {};
  final Map<int, (String, int)> _visits = {};
  final StreamController<RuntimeReceipt> _receipts =
      StreamController.broadcast();
  int _ingressSequence = 0;
  int _visitSequence = 0;
  bool _closed = false;

  Stream<RuntimeReceipt> get receipts => _receipts.stream;
  bool get isClosed => _closed;
  int get actorCount => _actors.length;

  ConversationActor _actor(String conversationKey) {
    if (_closed) throw StateError('Runtime is closed');
    final key = conversationKey.trim();
    if (key.isEmpty) throw ArgumentError.value(conversationKey);
    return _actors.putIfAbsent(
        key,
        () => ConversationActor._(
            supervisor: this,
            snapshot: RuntimeSnapshot(
                scope: scope,
                conversationKey: key,
                clearEpoch: 0,
                revision: 0,
                document: _initialState(key))));
  }

  RuntimeSnapshot snapshotFor(String conversationKey) =>
      _actor(conversationKey).snapshot;

  /// Every view receives a fresh identity, including reopening the same route.
  int openView(String conversationKey) {
    if (_closed) throw StateError('Runtime is closed');
    final actor = _actor(conversationKey);
    final visit = ++_visitSequence;
    _visits[visit] = (actor.snapshot.conversationKey, 0);
    return visit;
  }

  int beginViewOperation(int visitID) {
    final current = _visits[visitID];
    if (_closed || current == null) throw StateError('View is closed');
    final operation = current.$2 + 1;
    _visits[visitID] = (current.$1, operation);
    return operation;
  }

  void closeView(int visitID) => _visits.remove(visitID);

  Future<RuntimeReceipt> dispatch(RuntimeEnvelope event) {
    if (_closed || event.scope != scope) {
      // A stale account must not allocate or reopen a conversation actor.
      return Future.value(RuntimeReceipt(
          eventID: event.eventID,
          ingressSequence: ++_ingressSequence,
          disposition: RuntimeDisposition.staleAccount,
          snapshot: RuntimeSnapshot(
              scope: event.scope,
              conversationKey: event.conversationKey,
              clearEpoch: event.clearEpoch,
              revision: 0,
              document: RuntimeDocument({}))));
    }
    return _actor(event.conversationKey)._enqueue(event, ++_ingressSequence);
  }

  /// An accepted clear is an immediate fence, even while older events wait in
  /// the mailbox. Its state transition remains in admission order in the queue.
  Future<RuntimeReceipt> clearConversation(
      {required String conversationKey,
      required String eventID,
      required int nextEpoch}) {
    if (_closed) throw StateError('Runtime is closed');
    final actor = _actor(conversationKey);
    final id = eventID.trim();
    final existing = actor._clearRequests[id];
    if (existing != null) {
      if (existing.$1 != nextEpoch) {
        throw ArgumentError('A clear event cannot be reused for another epoch');
      }
      return existing.$2;
    }
    if (id.isEmpty ||
        nextEpoch <= actor._clearFence ||
        actor._committedEventIDs.contains(id) ||
        actor._pending.any((pending) => pending.event.eventID == id)) {
      throw ArgumentError(
          'Clear identity or epoch conflicts with admitted work');
    }
    // Preparing the reset may fail. Never move the fence until it succeeds.
    final initial = _initialState(actor.snapshot.conversationKey);
    actor._clearFence = nextEpoch;
    final result = actor._enqueue(
        RuntimeEnvelope(
            scope: scope,
            conversationKey: actor.snapshot.conversationKey,
            eventID: id,
            operationID: id,
            correlationID: id,
            source: 'runtime',
            kind: 'runtime.clear',
            clearEpoch: nextEpoch,
            payload: RuntimeDocument({})),
        ++_ingressSequence,
        clearDocument: initial);
    actor._clearRequests[id] = (nextEpoch, result);
    return result;
  }

  RuntimeDisposition? _invalid(RuntimeEnvelope event, ConversationActor actor) {
    if (_closed || event.scope != scope) return RuntimeDisposition.staleAccount;
    if (event.clearEpoch != actor._clearFence) {
      return RuntimeDisposition.staleClear;
    }
    final visit = event.visitID;
    if (visit != null &&
        _visits[visit] != (event.conversationKey, event.viewOperation)) {
      return RuntimeDisposition.staleView;
    }
    if (event.expectedRevision != null &&
        event.expectedRevision != actor.snapshot.revision) {
      return RuntimeDisposition.staleRevision;
    }
    return null;
  }

  /// Invalidates queued results synchronously; already dispatched remote writes
  /// belong to their original durable operation and are not reclassified here.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _visits.clear();
    for (final actor in _actors.values) {
      actor._drainClosed();
    }
    await _receipts.close();
  }
}

class _RuntimePending {
  _RuntimePending(this.event, this.sequence, this.clearDocument);
  final RuntimeEnvelope event;
  final int sequence;
  final RuntimeDocument? clearDocument;
  final Completer<RuntimeReceipt> completer = Completer();
}

/// A mailbox is per conversation; there is no network await or global queue
/// inside a reducer turn. Bounded batches yield to other conversations and UI.
class ConversationActor {
  ConversationActor._(
      {required AccountRuntimeSupervisor supervisor,
      required RuntimeSnapshot snapshot})
      : _supervisor = supervisor,
        _snapshot = snapshot;
  final AccountRuntimeSupervisor _supervisor;
  RuntimeSnapshot _snapshot;
  final Queue<_RuntimePending> _pending = Queue();
  final Set<String> _committedEventIDs = {};
  final Map<String, (int, Future<RuntimeReceipt>)> _clearRequests = {};
  int _clearFence = 0;
  bool _scheduled = false;

  RuntimeSnapshot get snapshot => _snapshot;

  Future<RuntimeReceipt> _enqueue(RuntimeEnvelope event, int sequence,
      {RuntimeDocument? clearDocument}) {
    final pending = _RuntimePending(event, sequence, clearDocument);
    _pending.add(pending);
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_drain);
    }
    return pending.completer.future;
  }

  void _drain() {
    for (var processed = 0;
        processed < _supervisor.eventsPerTurn && _pending.isNotEmpty;
        processed++) {
      _commit(_pending.removeFirst());
    }
    if (_pending.isEmpty) {
      _scheduled = false;
    } else {
      Timer.run(_drain);
    }
  }

  void _drainClosed() {
    while (_pending.isNotEmpty) {
      _commit(_pending.removeFirst());
    }
  }

  void _commit(_RuntimePending pending) {
    final event = pending.event;
    var disposition = _supervisor._invalid(event, this);
    Object? failure;
    StackTrace? stackTrace;
    List<RuntimeEffectIntent> effects = const [];
    if (disposition == null && _committedEventIDs.contains(event.eventID)) {
      disposition = RuntimeDisposition.duplicate;
    }
    if (disposition == null) {
      try {
        // Construct everything before publishing; throwing reducers leave the
        // previous snapshot and idempotency ledger intact for a retry.
        final transition = pending.clearDocument != null
            ? RuntimeTransition(document: pending.clearDocument!)
            : _supervisor._reducer(_snapshot, event);
        disposition = _supervisor._invalid(event, this);
        if (disposition == null) {
          final next = RuntimeSnapshot(
              scope: _snapshot.scope,
              conversationKey: _snapshot.conversationKey,
              clearEpoch: event.clearEpoch,
              revision: _snapshot.revision + 1,
              document: transition.document);
          _snapshot = next;
          _committedEventIDs.add(event.eventID);
          effects = transition.effects;
          disposition = RuntimeDisposition.committed;
        }
      } catch (error, stack) {
        failure = error;
        stackTrace = stack;
        disposition = RuntimeDisposition.rejected;
      }
    }
    final receipt = RuntimeReceipt(
        eventID: event.eventID,
        ingressSequence: pending.sequence,
        disposition: disposition,
        snapshot: _snapshot,
        effects: effects,
        error: failure,
        stackTrace: stackTrace);
    pending.completer.complete(receipt);
    if (!_supervisor._receipts.isClosed) _supervisor._receipts.add(receipt);
  }
}
