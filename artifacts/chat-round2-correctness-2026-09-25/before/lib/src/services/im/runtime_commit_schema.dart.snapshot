import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Additive MessageCore schema. No legacy authority is copied or activated here.
class RuntimeCommitSchema {
  static const objects = <String>{
    'chat_runtime_account',
    'chat_runtime_snapshot',
    'chat_runtime_event',
    'chat_runtime_effect',
    'idx_chat_runtime_effect_recovery',
  };

  static void addTo(Batch batch) {
    batch.execute('''
      CREATE TABLE IF NOT EXISTS chat_runtime_account (
        owner_user_id TEXT PRIMARY KEY,
        account_epoch INTEGER NOT NULL,
        sdk_domain_epoch INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL,
        fencing_token INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS chat_runtime_snapshot (
        owner_user_id TEXT NOT NULL,
        conversation_key TEXT NOT NULL,
        revision INTEGER NOT NULL CHECK(revision > 0),
        clear_epoch INTEGER NOT NULL CHECK(clear_epoch >= 0),
        document TEXT NOT NULL,
        PRIMARY KEY(owner_user_id, conversation_key)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS chat_runtime_event (
        owner_user_id TEXT NOT NULL,
        conversation_key TEXT NOT NULL,
        event_id TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        revision INTEGER NOT NULL,
        PRIMARY KEY(owner_user_id, conversation_key, event_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS chat_runtime_effect (
        owner_user_id TEXT NOT NULL,
        conversation_key TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        effect_kind TEXT NOT NULL,
        event_id TEXT NOT NULL,
        account_epoch INTEGER NOT NULL,
        sdk_domain_epoch INTEGER NOT NULL,
        clear_epoch INTEGER NOT NULL,
        revision INTEGER NOT NULL,
        payload TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN
          ('pending','dispatching','unknown','succeeded','failed','cancelled')),
        attempt_id TEXT,
        lease_owner_id TEXT NOT NULL,
        fencing_token INTEGER NOT NULL,
        result TEXT,
        PRIMARY KEY(owner_user_id, conversation_key, operation_id, effect_kind),
        UNIQUE(owner_user_id, attempt_id)
      )
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_runtime_effect_recovery
      ON chat_runtime_effect(owner_user_id, state, conversation_key, revision)
    ''');
  }
}
