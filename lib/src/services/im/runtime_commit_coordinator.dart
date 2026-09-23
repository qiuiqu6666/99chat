import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_protocol.dart';

import 'message_core_store.dart';
import 'message_persist_coordinator.dart';
import 'writer_lease.dart';

enum RuntimeCommitFailure {
  staleLease,
  staleAccount,
  staleRevision,
  staleClear,
  identityConflict,
}

class RuntimeCommitRejected implements Exception {
  const RuntimeCommitRejected(this.reason);
  final RuntimeCommitFailure reason;
  @override
  String toString() => 'RuntimeCommitRejected(${reason.name})';
}

class RuntimeDurableCommit {
  const RuntimeDurableCommit({required this.snapshot, required this.duplicate});
  final RuntimeSnapshot snapshot;
  final bool duplicate;
}

enum RuntimeDurableEffectState {
  pending,
  dispatching,
  unknown,
  succeeded,
  failed,
  cancelled,
}

class RuntimeDurableEffect {
  RuntimeDurableEffect._(Map<String, Object?> row)
      : scope = RuntimeAccountScope(
            ownerUserID: row['owner_user_id']! as String,
            accountEpoch: row['account_epoch']! as int,
            sdkDomainEpoch: row['sdk_domain_epoch']! as int),
        conversationKey = row['conversation_key']! as String,
        operationID = row['operation_id']! as String,
        kind = row['effect_kind']! as String,
        eventID = row['event_id']! as String,
        clearEpoch = row['clear_epoch']! as int,
        revision = row['revision']! as int,
        state =
            RuntimeDurableEffectState.values.byName(row['state']! as String),
        attemptID = row['attempt_id'] as String?,
        payload = _decodeDocument(row['payload']! as String),
        result = row['result'] == null
            ? null
            : _decodeDocument(row['result']! as String);

  final RuntimeAccountScope scope;
  final String conversationKey;
  final String operationID;
  final String kind;
  final String eventID;
  final int clearEpoch;
  final int revision;
  final RuntimeDurableEffectState state;
  final String? attemptID;
  final RuntimeDocument payload;
  final RuntimeDocument? result;
}

/// Durable commit boundary for the new runtime, not a second production writer.
///
/// All methods reuse MessageCore's SQLite transaction and writer lease. No SDK,
/// network, reducer, UI publication or effect executor runs inside a transaction.
/// The host must first freeze/drain the old authority before activating a scope.
/// Sends continue to require the existing Outbox protocol; an effect references
/// its operation, and is not itself permission to dispatch a message.
///
/// The shadow supervisor deliberately does not call this adapter. Production
/// cutover requires migrating clear/mutation/read authority and wiring the actor.
class RuntimeCommitCoordinator {
  RuntimeCommitCoordinator({
    MessageCoreStore? core,
    int Function()? nowMs,
  })  : _core = core ?? MessageCoreStore.instance,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final MessageCoreStore _core;
  final int Function() _nowMs;

  /// Within one lease, epochs only advance. A new fenced owner can rebind
  /// process-local generations after restart; conversation revision survives.
  Future<void> activateAccount({
    required RuntimeAccountScope scope,
    required ImWriterLease lease,
  }) =>
      _core.runTransaction((db) async {
        await _requireLease(db, scope, lease);
        final rows = await db.query('chat_runtime_account',
            where: 'owner_user_id = ?', whereArgs: [scope.ownerUserID]);
        if (rows.isNotEmpty) {
          final current = rows.single;
          final sameLease = current['lease_owner_id'] == lease.leaseOwnerId &&
              current['fencing_token'] == lease.fencingToken;
          if (sameLease &&
              ((current['account_epoch']! as int) > scope.accountEpoch ||
                  ((current['account_epoch']! as int) == scope.accountEpoch &&
                      (current['sdk_domain_epoch']! as int) >
                          scope.sdkDomainEpoch))) {
            throw const RuntimeCommitRejected(
                RuntimeCommitFailure.staleAccount);
          }
        }
        await db.insert(
            'chat_runtime_account',
            {
              'owner_user_id': scope.ownerUserID,
              'account_epoch': scope.accountEpoch,
              'sdk_domain_epoch': scope.sdkDomainEpoch,
              'lease_owner_id': lease.leaseOwnerId,
              'fencing_token': lease.fencingToken,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        // Pending work survives restart but retains its original scope/lease.
        // The host must explicitly revalidate it before obtaining a new claim.
        // A fenced-away executor may have sent its request. Preserve identity
        // and attempt; recovery must reconcile, never blindly retry it.
        await db.rawUpdate('''
          UPDATE chat_runtime_effect SET state = 'unknown'
          WHERE owner_user_id = ? AND state = 'dispatching'
            AND (lease_owner_id <> ? OR fencing_token <> ?)
        ''', [scope.ownerUserID, lease.leaseOwnerId, lease.fencingToken]);
        await _requireLease(db, scope, lease);
      });

  Future<RuntimeSnapshot?> load({
    required RuntimeAccountScope scope,
    required String conversationKey,
    required ImWriterLease lease,
  }) =>
      _core.runTransaction((db) async {
        await _requireAccount(db, scope, lease);
        return _load(db, scope, _key(conversationKey));
      },
          conversationId: conversationKey,
          accountGeneration: scope.accountEpoch);

  /// Commits the supplied pure transition by revision CAS. Receipt is returned
  /// only after SQLite commits; callers must not publish the proposal earlier.
  /// Duplicate identity returns the latest snapshot, never replays effects.
  Future<RuntimeDurableCommit> commit({
    required RuntimeEnvelope event,
    required RuntimeSnapshot before,
    required RuntimeTransition transition,
    required ImWriterLease lease,
    bool clearing = false,
  }) {
    if (before.scope != event.scope ||
        before.conversationKey != event.conversationKey ||
        before.revision < 0 ||
        before.clearEpoch < 0) {
      throw ArgumentError('Transition belongs to another runtime scope');
    }
    final nextClear = clearing ? event.clearEpoch : before.clearEpoch;
    final effectKeys = <(String, String)>{};
    for (final effect in transition.effects) {
      if (!effectKeys.add((effect.operationID, effect.kind))) {
        throw const RuntimeCommitRejected(
            RuntimeCommitFailure.identityConflict);
      }
    }
    // Encoding is outside the writer lock. Canonical keys distinguish identity
    // conflicts while accepting the same immutable payload with reordered keys.
    final fingerprint = _encode({
      'conversation': event.conversationKey,
      'id': event.eventID,
      'operation': event.operationID,
      'correlation': event.correlationID,
      'cause': event.causeID,
      'source': event.source,
      'kind': event.kind,
      'clear': event.clearEpoch,
      'clearing': clearing,
      'payload': event.payload.values,
    });
    final document = _encode(transition.document.values);
    final effectPayloads = transition.effects
        .map((effect) => _encode(effect.payload.values))
        .toList();
    return _core.runTransaction((db) async {
      await _requireAccount(db, event.scope, lease);
      final owner = event.scope.ownerUserID;
      final key = event.conversationKey;
      final current = await _load(db, event.scope, key);
      final duplicates = await db.query('chat_runtime_event',
          where: 'owner_user_id = ? AND conversation_key = ? AND event_id = ?',
          whereArgs: [owner, key, event.eventID]);
      if (duplicates.isNotEmpty) {
        if (duplicates.single['fingerprint'] != fingerprint ||
            current == null) {
          throw const RuntimeCommitRejected(
              RuntimeCommitFailure.identityConflict);
        }
        return RuntimeDurableCommit(snapshot: current, duplicate: true);
      }
      if ((!clearing && event.clearEpoch != before.clearEpoch) ||
          (clearing && event.clearEpoch <= before.clearEpoch)) {
        throw const RuntimeCommitRejected(RuntimeCommitFailure.staleClear);
      }
      if ((current?.revision ?? 0) != before.revision ||
          (event.expectedRevision != null &&
              event.expectedRevision != before.revision)) {
        throw const RuntimeCommitRejected(RuntimeCommitFailure.staleRevision);
      }
      if ((current?.clearEpoch ?? 0) != before.clearEpoch) {
        throw const RuntimeCommitRejected(RuntimeCommitFailure.staleClear);
      }
      final next = RuntimeSnapshot(
          scope: event.scope,
          conversationKey: key,
          clearEpoch: nextClear,
          revision: before.revision + 1,
          document: transition.document);
      await db.insert(
          'chat_runtime_snapshot',
          {
            'owner_user_id': owner,
            'conversation_key': key,
            'revision': next.revision,
            'clear_epoch': next.clearEpoch,
            'document': document,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('chat_runtime_event', {
        'owner_user_id': owner,
        'conversation_key': key,
        'event_id': event.eventID,
        'fingerprint': fingerprint,
        'revision': next.revision,
      });
      if (clearing) {
        await db.update('chat_runtime_effect', {'state': 'cancelled'},
            where: 'owner_user_id = ? AND conversation_key = ? '
                "AND clear_epoch < ? AND state = 'pending'",
            whereArgs: [owner, key, nextClear]);
      }
      for (var i = 0; i < transition.effects.length; i++) {
        final effect = transition.effects[i];
        // A different event cannot steal/reuse an operation identity.
        final exists = await db.query('chat_runtime_effect',
            columns: ['operation_id'],
            where: 'owner_user_id = ? AND conversation_key = ? '
                'AND operation_id = ? AND effect_kind = ?',
            whereArgs: [owner, key, effect.operationID, effect.kind]);
        if (exists.isNotEmpty) {
          throw const RuntimeCommitRejected(
              RuntimeCommitFailure.identityConflict);
        }
        await db.insert('chat_runtime_effect', {
          'owner_user_id': owner,
          'conversation_key': key,
          'operation_id': effect.operationID,
          'effect_kind': effect.kind,
          'event_id': event.eventID,
          'account_epoch': event.scope.accountEpoch,
          'sdk_domain_epoch': event.scope.sdkDomainEpoch,
          'clear_epoch': nextClear,
          'revision': next.revision,
          'payload': effectPayloads[i],
          'state': 'pending',
          'lease_owner_id': lease.leaseOwnerId,
          'fencing_token': lease.fencingToken,
        });
      }
      // Expiry during a slow transaction rolls everything back.
      await _requireAccount(db, event.scope, lease);
      return RuntimeDurableCommit(snapshot: next, duplicate: false);
    },
        conversationId: event.conversationKey,
        accountGeneration: event.scope.accountEpoch,
        persistPriority: MessagePersistPriority.realtime,
        persistSource: MessagePersistSource.realtime,
        itemCount: 1 + transition.effects.length);
  }

  /// Marks dispatch durably BEFORE starting external I/O. Calling twice cannot
  /// yield two dispatch permissions. A lost claim response is reconciled later.
  Future<RuntimeDurableEffect?> claimEffect({
    required RuntimeAccountScope scope,
    required String conversationKey,
    required String operationID,
    required String kind,
    required String attemptID,
    required ImWriterLease lease,
  }) {
    _key(attemptID);
    return _core.runTransaction((db) async {
      await _requireAccount(db, scope, lease);
      final args = [scope.ownerUserID, conversationKey, operationID, kind];
      final count = await db.rawUpdate('''
        UPDATE chat_runtime_effect SET state = 'dispatching', attempt_id = ?,
          lease_owner_id = ?, fencing_token = ?
        WHERE owner_user_id = ? AND conversation_key = ?
          AND operation_id = ? AND effect_kind = ? AND state = 'pending'
          AND account_epoch = ? AND sdk_domain_epoch = ?
          AND lease_owner_id = ? AND fencing_token = ?
          AND clear_epoch = (SELECT clear_epoch FROM chat_runtime_snapshot
            WHERE owner_user_id = ? AND conversation_key = ?)
      ''', [
        attemptID,
        lease.leaseOwnerId,
        lease.fencingToken,
        ...args,
        scope.accountEpoch,
        scope.sdkDomainEpoch,
        lease.leaseOwnerId,
        lease.fencingToken,
        scope.ownerUserID,
        conversationKey
      ]);
      if (count == 0) return null;
      final rows = await db.query('chat_runtime_effect',
          where: 'owner_user_id = ? AND conversation_key = ? '
              'AND operation_id = ? AND effect_kind = ?',
          whereArgs: args);
      await _requireAccount(db, scope, lease);
      return RuntimeDurableEffect._(rows.single);
    }, conversationId: conversationKey, accountGeneration: scope.accountEpoch);
  }

  /// Explicit host approval after validating operation policy in a new session.
  /// This never resets dispatching/unknown work, or revives a cleared operation.
  Future<bool> revalidatePendingEffect({
    required RuntimeAccountScope scope,
    required String conversationKey,
    required String operationID,
    required String kind,
    required int expectedClearEpoch,
    required ImWriterLease lease,
  }) =>
      _core.runTransaction((db) async {
        await _requireAccount(db, scope, lease);
        final count = await db.rawUpdate('''
          UPDATE chat_runtime_effect SET account_epoch = ?, sdk_domain_epoch = ?,
            lease_owner_id = ?, fencing_token = ?
          WHERE owner_user_id = ? AND conversation_key = ?
            AND operation_id = ? AND effect_kind = ? AND state = 'pending'
            AND clear_epoch = ? AND clear_epoch = (
              SELECT clear_epoch FROM chat_runtime_snapshot
              WHERE owner_user_id = ? AND conversation_key = ?)
        ''', [
          scope.accountEpoch,
          scope.sdkDomainEpoch,
          lease.leaseOwnerId,
          lease.fencingToken,
          scope.ownerUserID,
          conversationKey,
          operationID,
          kind,
          expectedClearEpoch,
          scope.ownerUserID,
          conversationKey
        ]);
        await _requireAccount(db, scope, lease);
        return count == 1;
      },
          conversationId: conversationKey,
          accountGeneration: scope.accountEpoch);

  /// A late definite response can resolve an unknown original attempt even
  /// after a clear. This updates the ledger only; projection still needs a
  /// separately admitted, scoped runtime event.
  Future<bool> recordEffectResult({
    required RuntimeAccountScope scope,
    required String conversationKey,
    required String operationID,
    required String kind,
    required String attemptID,
    required RuntimeDurableEffectState state,
    required RuntimeDocument result,
    required ImWriterLease lease,
  }) {
    if (state != RuntimeDurableEffectState.succeeded &&
        state != RuntimeDurableEffectState.failed &&
        state != RuntimeDurableEffectState.unknown) {
      throw ArgumentError(
          'Only an observed outcome may settle a dispatched effect');
    }
    final encoded = _encode(result.values);
    return _core.runTransaction((db) async {
      await _requireAccount(db, scope, lease);
      final count = await db.update(
          'chat_runtime_effect', {'state': state.name, 'result': encoded},
          where: 'owner_user_id = ? AND conversation_key = ? '
              'AND operation_id = ? AND effect_kind = ? AND attempt_id = ? '
              "AND state IN ('dispatching','unknown')",
          whereArgs: [
            scope.ownerUserID,
            conversationKey,
            operationID,
            kind,
            attemptID
          ]);
      await _requireAccount(db, scope, lease);
      return count == 1;
    }, conversationId: conversationKey, accountGeneration: scope.accountEpoch);
  }

  /// Bounded recovery with a keyset cursor. Completed rows cannot hide pending
  /// or unknown work, and this method never grants dispatch permission.
  Future<List<RuntimeDurableEffect>> listEffects({
    required RuntimeAccountScope scope,
    required String conversationKey,
    required ImWriterLease lease,
    required RuntimeDurableEffectState state,
    int afterRevision = 0,
    String afterOperationID = '',
    String afterKind = '',
    int limit = 100,
  }) {
    if (limit < 1 || limit > 500 || afterRevision < 0) {
      throw ArgumentError('Invalid recovery window');
    }
    return _core.runTransaction((db) async {
      await _requireAccount(db, scope, lease);
      final rows = await db.query('chat_runtime_effect',
          where: 'owner_user_id = ? AND conversation_key = ? AND state = ? AND '
              '(revision > ? OR (revision = ? AND (operation_id > ? OR '
              '(operation_id = ? AND effect_kind > ?))))',
          whereArgs: [
            scope.ownerUserID,
            conversationKey,
            state.name,
            afterRevision,
            afterRevision,
            afterOperationID,
            afterOperationID,
            afterKind
          ],
          orderBy: 'revision, operation_id, effect_kind',
          limit: limit);
      return List<RuntimeDurableEffect>.unmodifiable(
          rows.map(RuntimeDurableEffect._));
    }, conversationId: conversationKey, accountGeneration: scope.accountEpoch);
  }

  Future<RuntimeSnapshot?> _load(DatabaseExecutor db, RuntimeAccountScope scope,
      String conversationKey) async {
    final rows = await db.query('chat_runtime_snapshot',
        where: 'owner_user_id = ? AND conversation_key = ?',
        whereArgs: [scope.ownerUserID, conversationKey]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    return RuntimeSnapshot(
        scope: scope,
        conversationKey: conversationKey,
        clearEpoch: row['clear_epoch']! as int,
        revision: row['revision']! as int,
        document: _decodeDocument(row['document']! as String));
  }

  Future<void> _requireLease(DatabaseExecutor db, RuntimeAccountScope scope,
      ImWriterLease lease) async {
    final rows = await db.query('message_writer_lease',
        where: 'owner_user_id = ? AND lease_owner_id = ? AND fencing_token = ? '
            'AND expires_at > ?',
        whereArgs: [
          scope.ownerUserID,
          lease.leaseOwnerId,
          lease.fencingToken,
          _nowMs()
        ]);
    if (lease.ownerUserId != scope.ownerUserID || rows.length != 1) {
      throw const RuntimeCommitRejected(RuntimeCommitFailure.staleLease);
    }
  }

  Future<void> _requireAccount(DatabaseExecutor db, RuntimeAccountScope scope,
      ImWriterLease lease) async {
    await _requireLease(db, scope, lease);
    final rows = await db.query('chat_runtime_account',
        where:
            'owner_user_id = ? AND account_epoch = ? AND sdk_domain_epoch = ? '
            'AND lease_owner_id = ? AND fencing_token = ?',
        whereArgs: [
          scope.ownerUserID,
          scope.accountEpoch,
          scope.sdkDomainEpoch,
          lease.leaseOwnerId,
          lease.fencingToken
        ]);
    if (rows.length != 1) {
      throw const RuntimeCommitRejected(RuntimeCommitFailure.staleAccount);
    }
  }
}

String _key(String value) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError('Runtime identity must be nonempty and canonical');
  }
  return value;
}

RuntimeDocument _decodeDocument(String encoded) =>
    RuntimeDocument((jsonDecode(encoded) as Map).cast<String, Object?>());

String _encode(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
