import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const receiptRecoveryOperationPrefix = 'receipt-compat-batch:';
bool isReceiptRecoveryOperation(String? value) =>
    value?.startsWith(receiptRecoveryOperationPrefix) == true;

class ReceiptRecoveryCopy {
  const ReceiptRecoveryCopy(this.eventId, this.recoveryRef);
  final String eventId;
  final String recoveryRef;
}

/// Both fields are understood by the pre-batching binary: receipt-json and
/// c2c-read/message-read. The live aggregate is only an optimization; these
/// copies remain sufficient after a crash or a downgrade.
List<ReceiptRecoveryCopy> legacyReceiptRecoveryCopies({
  required String operationId,
  required Iterable<Map> receipts,
  required bool watermark,
}) {
  final copies = <String, ReceiptRecoveryCopy>{};
  for (final receipt in receipts) {
    final json = jsonEncode(receipt);
    final digest = sha256.convert(utf8.encode(json)).toString();
    final isC2C = receipt.containsKey('msg_receipt_conv_type')
        ? receipt['msg_receipt_conv_type'] == 1
        : (receipt['groupID']?.toString().isEmpty ?? true);
    for (final prefix in <String>[
      if (watermark && isC2C) 'c2c-read',
      'message-read',
    ]) {
      final id = '$prefix:$operationId:$digest';
      copies[id] = ReceiptRecoveryCopy(id, 'receipt-json:$json');
    }
  }
  return copies.values.toList(growable: false);
}

/// Upgrade the previous batch format before exposing the database to writers.
/// The parent is made disposable only in the transaction that inserts every
/// legacy-readable copy. Completed history is deliberately not rewritten.
Future<void> migratePendingReceiptBatches(Database db) async {
  var afterRowId = 0;
  while (true) {
    final lastRowId = await db.transaction<int?>((tx) async {
      final rows = await tx.rawQuery('''
        SELECT rowid AS migration_rowid, * FROM message_event_inbox
        WHERE status <> 'completed' AND recovery_mode = 'commandArguments'
          AND recovery_ref LIKE 'receipt-batch-json:%' AND rowid > ?
        ORDER BY rowid LIMIT 32
      ''', <Object?>[afterRowId]);
      if (rows.isEmpty) return null;
      for (final row in rows) {
        final ref = row['recovery_ref']! as String;
        dynamic decoded;
        try {
          decoded = jsonDecode(ref.substring('receipt-batch-json:'.length));
        } on FormatException {
          continue;
        }
        if (decoded is! Map ||
            decoded['watermark'] is! bool ||
            decoded['receipts'] is! List ||
            (decoded['receipts'] as List).isEmpty ||
            !(decoded['receipts'] as List).every((value) => value is Map)) {
          // Keep malformed data recoverable for investigation; never mark it
          // disposable when we cannot construct the complete recovery set.
          continue;
        }
        final owner = row['owner_user_id']! as String;
        final scope = row['conversation_id']! as String;
        final operation = '$receiptRecoveryOperationPrefix${row['event_id']}';
        final copies = legacyReceiptRecoveryCopies(
          operationId: operation,
          receipts: (decoded['receipts'] as List).cast<Map>(),
          watermark: decoded['watermark'] as bool,
        );
        for (final copy in copies) {
          final existing = await tx.query('message_event_inbox',
              columns: ['event_id'],
              where:
                  'owner_user_id = ? AND event_namespace = ? AND event_id = ?',
              whereArgs: [owner, row['event_namespace'], copy.eventId],
              limit: 1);
          if (existing.isNotEmpty) continue;
          final now = row['observed_at'] as int;
          final values = Map<String, Object?>.from(row)
            ..remove('migration_rowid');
          values.addAll({
            'event_id': copy.eventId,
            'operation_id': operation,
            'account_ingress_sequence': await _allocate(tx, owner, '', now),
            'scope_ingress_sequence':
                scope.isEmpty ? 0 : await _allocate(tx, owner, scope, now),
            'recovery_ref': copy.recoveryRef,
            'payload_hash':
                sha256.convert(utf8.encode(copy.recoveryRef)).toString(),
            'status': 'prepared',
            'committed_at': null,
            'processing_started_at': null,
          });
          await tx.insert('message_event_inbox', values);
        }
        await tx.update('message_event_inbox', {'recovery_mode': 'ephemeralUi'},
            where: 'owner_user_id = ? AND event_namespace = ? AND event_id = ?',
            whereArgs: [owner, row['event_namespace'], row['event_id']]);
      }
      return rows.last['migration_rowid'] as int;
    });
    if (lastRowId == null) return;
    afterRowId = lastRowId;
    await Future<void>.delayed(Duration.zero);
  }
}

Future<int> _allocate(
    DatabaseExecutor tx, String owner, String scope, int now) async {
  final rows = await tx.query('message_ingress_counter',
      where: 'owner_user_id = ? AND scope_key = ?', whereArgs: [owner, scope]);
  // Counter repair also covers a partially restored database.
  final column =
      scope.isEmpty ? 'account_ingress_sequence' : 'scope_ingress_sequence';
  final maxRows = await tx.rawQuery(
      'SELECT MAX($column) AS n FROM message_event_inbox '
      'WHERE owner_user_id = ?${scope.isEmpty ? '' : ' AND conversation_id = ?'}',
      [owner, if (scope.isNotEmpty) scope]);
  final counter = rows.isEmpty ? 0 : rows.first['next_sequence'] as int;
  final seen = maxRows.first['n'] as int? ?? 0;
  final next = (counter > seen ? counter : seen) + 1;
  await tx.insert(
      'message_ingress_counter',
      {
        'owner_user_id': owner,
        'scope_key': scope,
        'next_sequence': next,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace);
  return next;
}
