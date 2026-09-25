import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old outbox schema reopens repeatedly without granting a new retry',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final directory = await Directory.systemTemp.createTemp('round3-old-db-');
    final path = '${directory.path}/${MessageCoreStore.dbName}';
    final core = MessageCoreStore.instance;
    await core.closeIfOpen();
    await databaseFactory.setDatabasesPath(directory.path);
    try {
      final store = ConversationLocalImIngressStore(core: core);
      await store.transaction((_) async {});
      for (final (operation, state, copyState)
          in <(String, ImOutboxState, ImOutboxCopyState?)>[
        (
          'failed-old',
          ImOutboxState.failedTerminal,
          ImOutboxCopyState.resultRecorded
        ),
        (
          'prepared-old',
          ImOutboxState.prepared,
          ImOutboxCopyState.copyPrepared
        ),
        (
          'unknown-old',
          ImOutboxState.outcomeUnknown,
          ImOutboxCopyState.outcomeUnknown
        ),
        ('completed-old', ImOutboxState.completed, null),
      ]) {
        await store.transaction((tx) async {
          await tx.insertOutboxIfAbsent(ImOutboxRecord(
              operationId: operation,
              ownerUserId: 'alice',
              conversationId: 'alice|c2c_bob',
              clientCorrelationId: 'corr-$operation',
              messageType: 1,
              payloadReference: 'legacy-payload',
              payloadHash: 'legacy-hash',
              state: state,
              createdAtMs: 10,
              updatedAtMs: 10));
          if (copyState != null) {
            await tx.insertOutboxRecoveryIfAbsent(ImOutboxRecoveryRecord(
                ownerUserId: 'alice',
                operationId: operation,
                clientCorrelationId: 'corr-$operation',
                conversationId: 'alice|c2c_bob',
                messageType: 1,
                recoveryRevision: 1,
                state: copyState,
                payloadReferenceOrCiphertext: 'legacy-payload',
                payloadHash: 'legacy-hash',
                checksum: 'legacy-hash',
                updatedAtMs: 10));
          }
        });
      }
      await core.closeIfOpen();
      final db = await openDatabase(path);
      for (final trigger in <String>[
        'outbox_state_version_update',
        'outbox_copy_version_insert',
        'outbox_copy_version_update',
        'outbox_copy_version_delete',
      ]) {
        await db.execute('DROP TRIGGER IF EXISTS $trigger');
      }
      for (final column in <String>[
        'state_version',
        'retry_of_operation_id',
        'retry_of_state_version',
      ]) {
        await db.execute('ALTER TABLE message_outbox DROP COLUMN $column');
      }
      await db.close();

      for (var open = 0; open < 2; open++) {
        final persistence =
            Im05Persistence(store: ConversationLocalImIngressStore(core: core));
        final failed = await persistence.readOutboxResult(
            ownerUserId: 'alice', operationId: 'failed-old');
        expect(failed.currentState, ImOutboxState.failedTerminal);
        expect(failed.canRetry, isFalse);
        final prepared = await persistence.recoverOutbox(
            ownerUserId: 'alice', operationId: 'prepared-old');
        expect(prepared.canDispatch, isTrue);
        final unknown = await persistence.recoverOutbox(
            ownerUserId: 'alice', operationId: 'unknown-old');
        expect(unknown.requiresOutcomeQuery, isTrue);
        final completed = await persistence.readOutboxResult(
            ownerUserId: 'alice', operationId: 'completed-old');
        expect(completed.deliveryConfirmed, isTrue);
        expect(failed.stateVersion, greaterThanOrEqualTo(1));
        await core.closeIfOpen();
        if (open == 0) {
          // Model a restart after the two parent-link columns landed but
          // before the version column and triggers finished migrating.
          final partiallyUpgraded = await openDatabase(path);
          for (final trigger in <String>[
            'outbox_state_version_update',
            'outbox_copy_version_insert',
            'outbox_copy_version_update',
            'outbox_copy_version_delete',
          ]) {
            await partiallyUpgraded.execute('DROP TRIGGER IF EXISTS $trigger');
          }
          await partiallyUpgraded.execute(
              'ALTER TABLE message_outbox DROP COLUMN state_version');
          await partiallyUpgraded.close();
        }
      }
    } finally {
      await core.closeIfOpen();
      await databaseFactory.deleteDatabase(path);
      await databaseFactory.setDatabasesPath(original);
      await directory.delete();
    }
  });
}
