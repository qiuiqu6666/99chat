import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v6 database adds fingerprint column in place and keeps legacy rows',
      () async {
    final basePath = await getDatabasesPath();
    final dbPath = '$basePath${Platform.pathSeparator}conversation_index.db';
    await deleteDatabase(dbPath);

    final legacyConversation = V2TimConversation(
      conversationID: 'c2c_migration_peer',
      type: 1,
      userID: 'migration_peer',
      showName: 'Migration peer',
      unreadCount: 3,
      orderkey: 99,
      customData: 'legacy-data',
    );
    final legacyTextElem = V2TimTextElem(text: '升级后的本地预览');
    final legacyMessage = V2TimMessage.fromJson(<String, dynamic>{
      'message_msg_id': 'legacy-server-message',
      'message_server_time': 1700000100,
      'message_is_from_self': true,
      'message_status': MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      'message_is_peer_read': true,
      'message_risk_type_identified': 0,
      'message_sender_group_member_info': <String, dynamic>{},
      'message_group_at_user_array': <String>[],
    })
      ..msgID = 'legacy-server-message'
      ..id = 'legacy-client-message'
      ..isSelf = true
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL
      ..isPeerRead = true
      ..elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT
      ..textElem = legacyTextElem
      ..elemList = <dynamic>[legacyTextElem];
    legacyConversation.lastMessage = legacyMessage;
    final rawJson = jsonEncode(legacyConversation.toJson());

    final legacyDb = await openDatabase(
      dbPath,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            owner_user_id TEXT NOT NULL,
            conversation_id TEXT NOT NULL,
            conv_type INTEGER NOT NULL DEFAULT 0,
            user_id TEXT NOT NULL DEFAULT '',
            group_id TEXT NOT NULL DEFAULT '',
            show_name TEXT NOT NULL DEFAULT '',
            face_url TEXT NOT NULL DEFAULT '',
            unread_count INTEGER NOT NULL DEFAULT 0,
            recv_opt INTEGER NOT NULL DEFAULT 0,
            group_type TEXT NOT NULL DEFAULT '',
            is_pinned INTEGER NOT NULL DEFAULT 0,
            order_key INTEGER NOT NULL DEFAULT 0,
            active_time INTEGER NOT NULL DEFAULT 0,
            raw_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0,
            read_cleared_at INTEGER NOT NULL DEFAULT 0,
            history_cleared_at INTEGER NOT NULL DEFAULT 0,
            local_draft_text TEXT NOT NULL DEFAULT '',
            local_draft_updated_at INTEGER NOT NULL DEFAULT 0,
            last_msg_id TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (owner_user_id, conversation_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE conversation_sync_meta (
            owner_user_id TEXT PRIMARY KEY,
            next_seq TEXT NOT NULL DEFAULT '0',
            have_more INTEGER NOT NULL DEFAULT 1,
            has_synced_once INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    await legacyDb.insert('conversations', <String, Object?>{
      'owner_user_id': 'migration_owner',
      'conversation_id': legacyConversation.conversationID,
      'conv_type': legacyConversation.type,
      'user_id': legacyConversation.userID,
      'show_name': legacyConversation.showName,
      'unread_count': legacyConversation.unreadCount,
      'order_key': legacyConversation.orderkey,
      'active_time': legacyConversation.orderkey,
      'raw_json': rawJson,
    });
    await legacyDb.close();

    ConversationLocalStore.bypassUpsertCoalesceForTest = true;
    ConversationLocalStore.instance.debugOwnerUserId = 'migration_owner';
    ConversationLocalStore.postFirstScreenMaintenanceDelayForTest =
        Duration.zero;
    addTearDown(() async {
      ConversationLocalStore.instance.debugOwnerUserId = null;
      ConversationLocalStore.bypassUpsertCoalesceForTest = false;
      ConversationLocalStore.postFirstScreenMaintenanceDelayForTest =
          const Duration(seconds: 10);
      await ConversationLocalStore.instance.closeDatabaseForTest();
    });

    final restored = await ConversationLocalStore.instance.conversationById(
      legacyConversation.conversationID,
    );
    expect(restored?.customData, 'legacy-data');
    expect(restored?.unreadCount, 3);

    final inspectionDb = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false,
    );
    final versionRows = await inspectionDb.rawQuery('PRAGMA user_version');
    final version = versionRows.single.values.single as int;
    final columns = await inspectionDb.rawQuery(
      'PRAGMA table_info(conversations)',
    );
    expect(version, 20);
    expect(
      columns.any((row) => row['name'] == 'raw_json_fingerprint'),
      isTrue,
    );
    expect(
      columns.any((row) => row['name'] == 'preview_text'),
      isTrue,
    );
    expect(
      columns.any((row) => row['name'] == 'preview_timestamp'),
      isTrue,
    );
    expect(
      columns.any((row) => row['name'] == 'preview_status'),
      isTrue,
    );
    expect(
      columns.any((row) => row['name'] == 'preview_is_self'),
      isTrue,
    );
    expect(
      columns.any((row) => row['name'] == 'preview_client_id'),
      isTrue,
    );
    expect(
      columns.any((row) => row['name'] == 'preview_is_peer_read'),
      isTrue,
    );
    expect(
      columns.any((row) => row['name'] == 'preview_projection_version'),
      isTrue,
    );
    final countRows =
        await inspectionDb.rawQuery('SELECT COUNT(*) FROM conversations');
    expect(countRows.single.values.single, 1);
    await inspectionDb.close();

    // The first read is intentionally immediate and must not wait for the
    // migration. The test then explicitly joins the bounded idle pass; the
    // production delay is controlled by the test-only hook above.
    final beforeBackfill =
        await ConversationLocalStore.instance.loadLocalFirstScreen(
      ownerUserId: 'migration_owner',
      convType: 1,
      limit: 1,
    );
    expect(beforeBackfill, hasLength(1));
    await ConversationLocalStore.instance
        .waitForPostFirstScreenMaintenanceForTest();
    final afterBackfill =
        await ConversationLocalStore.instance.loadLocalFirstScreen(
      ownerUserId: 'migration_owner',
      convType: 1,
      limit: 1,
    );
    await ConversationLocalStore.instance
        .waitForPostFirstScreenMaintenanceForTest();
    final preview = afterBackfill.single.lastMessage;
    expect(preview?.textElem?.text, '升级后的本地预览');
    expect(preview?.status, MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
    expect(preview?.isSelf, isTrue);
    expect(preview?.id, 'legacy-client-message');
    expect(preview?.isPeerRead, isTrue);

    final migrated = await ConversationLocalStore.instance.upsertBatch(
      conversations: [legacyConversation],
    );
    expect(migrated, hasLength(1));

    final fingerprintDb = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false,
    );
    final rows = await fingerprintDb.query(
      'conversations',
      columns: const ['raw_json', 'raw_json_fingerprint'],
      where: 'owner_user_id = ? AND conversation_id = ?',
      whereArgs: const ['migration_owner', 'c2c_migration_peer'],
    );
    expect(rows, hasLength(1));
    final persistedJson =
        jsonDecode(rows.single['raw_json']! as String) as Map<String, dynamic>;
    expect(persistedJson['conv_custom_data'], 'legacy-data');
    expect(persistedJson['conv_unread_num'], 3);
    expect(rows.single['raw_json_fingerprint'], isNotEmpty);
    await fingerprintDb.close();

    // Re-run the complete historical upgrade chain against the already
    // upgraded schema. This simulates a version marker written before a
    // process interruption and proves the ALTER guards are repeatable.
    await ConversationLocalStore.instance.closeDatabaseForTest();
    final resetVersionDb = await openDatabase(
      dbPath,
      version: 20,
      singleInstance: false,
    );
    await resetVersionDb.execute('PRAGMA user_version = 6');
    await resetVersionDb.close();

    final reopened = await ConversationLocalStore.instance.conversationById(
      legacyConversation.conversationID,
    );
    expect(reopened?.customData, 'legacy-data');
    expect(reopened?.unreadCount, 3);
    await ConversationLocalStore.instance.closeDatabaseForTest();
  });
}
