import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The main row is the durable version/terminal anchor. Recovery payloads may
/// be collected or rebuilt without reusing an earlier state version.
Future<void> ensureOutboxStateVersionSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS message_draft_head (
    owner_user_id TEXT NOT NULL, conversation_id TEXT NOT NULL,
    draft_id TEXT NOT NULL, protected_text TEXT NOT NULL,
    accepted_operation_id TEXT,
    PRIMARY KEY(owner_user_id, conversation_id))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS message_draft_acceptance (
    owner_user_id TEXT NOT NULL, conversation_id TEXT NOT NULL,
    draft_id TEXT NOT NULL, operation_id TEXT NOT NULL,
    PRIMARY KEY(owner_user_id, conversation_id, draft_id))''');
  final columns = await db.rawQuery('PRAGMA table_info(message_outbox)');
  for (final column in {
    'retry_of_operation_id': 'TEXT',
    'retry_of_state_version': 'INTEGER'
  }.entries) {
    if (!columns.any((row) => row['name'] == column.key))
      await db.execute(
          'ALTER TABLE message_outbox ADD COLUMN ${column.key} ${column.value}');
  }
  if (!columns.any((row) => row['name'] == 'state_version')) {
    await db.execute(
        'ALTER TABLE message_outbox ADD COLUMN state_version INTEGER NOT NULL DEFAULT 1');
    await db.execute('''UPDATE message_outbox SET state_version = MAX(1,
      COALESCE((SELECT recovery_revision FROM message_outbox_recovery_copy r
        WHERE r.operation_id = message_outbox.operation_id
        AND r.owner_user_id = message_outbox.owner_user_id), 1))''');
  }
  await db.execute('''CREATE TRIGGER IF NOT EXISTS outbox_state_version_update
    AFTER UPDATE ON message_outbox WHEN NEW.state_version <= OLD.state_version
    BEGIN UPDATE message_outbox SET state_version = OLD.state_version + 1
      WHERE operation_id = NEW.operation_id AND owner_user_id = NEW.owner_user_id; END''');
  for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
    final row = event == 'DELETE' ? 'OLD' : 'NEW';
    await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS outbox_copy_version_${event.toLowerCase()}
      AFTER $event ON message_outbox_recovery_copy
      BEGIN UPDATE message_outbox SET state_version = state_version + 1
        WHERE operation_id = $row.operation_id AND owner_user_id = $row.owner_user_id; END''');
  }
}
