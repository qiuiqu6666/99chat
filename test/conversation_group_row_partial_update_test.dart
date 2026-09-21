import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';

V2TimMessage _text(
  String text, {
  String msgID = 'msg',
  int timestamp = 1700000000,
  int status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': msgID,
    'message_server_time': timestamp,
    'message_is_from_self': true,
    'message_status': status,
    'message_custom_str': '',
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.msgID = msgID;
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
  message.textElem = V2TimTextElem(text: text);
  message.timestamp = timestamp;
  message.status = status;
  return message;
}

V2TimConversation _group(
  String id, {
  int unread = 0,
  int order = 0,
  int time = 1700000000,
  String? face,
  String? name,
  V2TimMessage? last,
}) {
  return V2TimConversation(
    conversationID: 'group_$id',
    type: 2,
    groupID: id,
    unreadCount: unread,
    orderkey: order,
    showName: name ?? id,
    faceUrl: face,
    lastMessage: last ?? _text('hi', msgID: 'msg_$id', timestamp: time),
  );
}

void main() {
  final tab = ConversationTabStore.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tab.excludeReadFromStructure = false;
    tab.bindOwnerScopeForTest('');
    tab.setItemsForTest(convType: 2, items: const []);
    tab.resetWorkCounters();
  });

  tearDown(() {
    tab.excludeReadFromStructure = false;
  });

  test('avatar-only change updates one row view and not the structure', () {
    tab.setItemsForTest(
      convType: 2,
      items: [
        _group('a', order: 3, time: 30),
        _group('b', order: 2, time: 20),
        _group('c', order: 1, time: 10),
      ],
    );
    final structureBefore = tab.structureRevision;
    tab.resetWorkCounters();
    var otherNotifies = 0;
    final other = tab.rowViewListenable('group_b');
    void onOther() => otherNotifies++;
    other.addListener(onOther);
    var structureNotifies = 0;
    void onStructure() => structureNotifies++;
    tab.addListener(onStructure);

    tab.applyPatches([_group('a', order: 3, time: 30, face: 'https://cdn/a.png')]);

    other.removeListener(onOther);
    tab.removeListener(onStructure);
    expect(tab.workRowProjectedCount, 1);
    expect(tab.workFullSortCount, 0);
    expect(tab.workStructureNotifyCount, 0);
    expect(structureNotifies, 0);
    expect(otherNotifies, 0);
    expect(tab.structureRevision, structureBefore);
    expect(tab.lastNotificationStructureChanged, isFalse);
    expect(tab.rowViewOf('group_a')?.avatarKey, 'https://cdn/a.png');
    expect(
      tab.structureIdsForType(2),
      ['group_a', 'group_b', 'group_c'],
    );
  });

  test('new message relocates one group without projecting the whole window', () {
    tab.setItemsForTest(
      convType: 2,
      items: [
        _group('a', order: 30, time: 30),
        _group('b', order: 20, time: 20),
        _group('c', order: 10, time: 10),
      ],
    );
    tab.resetWorkCounters();
    tab.applyPatches([
      _group(
        'c',
        order: 40,
        time: 40,
        last: _text('newer', msgID: 'msg_c_new', timestamp: 40),
      ),
    ]);

    expect(tab.workRowProjectedCount, 1);
    expect(tab.workFullSortCount, 0);
    expect(tab.workStructureNotifyCount, 1);
    expect(tab.lastNotificationStructureChanged, isTrue);
    expect(tab.structureIdsForType(2), ['group_c', 'group_a', 'group_b']);
    expect(tab.rowViewOf('group_c')?.lastMessagePreview, 'newer');
    expect(tab.rowViewOf('group_a')?.lastMessagePreview, 'hi');
  });

  test('unread 1 to 0 updates the row and badge, not the default structure', () {
    ConversationUnreadAggregate.instance.setSumsForTest(c2c: 0, group: 1);
    tab.setItemsForTest(
      convType: 2,
      items: [_group('a', unread: 1, order: 2, time: 20)],
    );
    tab.resetWorkCounters();
    final unreadBefore = ConversationUnreadAggregate.instance.sdkUnreadRevision.value;
    tab.applyPatches(
      [_group('a', unread: 0, order: 2, time: 20)],
      explicitUnreadIds: const {'group_a'},
    );

    expect(tab.workRowProjectedCount, 1);
    expect(tab.workStructureNotifyCount, 0);
    expect(tab.lastNotificationStructureChanged, isFalse);
    expect(tab.rowViewOf('group_a')?.unreadCount, 0);
    expect(tab.structureIdsForType(2), ['group_a']);
    expect(
      ConversationUnreadAggregate.instance.sdkUnreadRevision.value >= unreadBefore,
      isTrue,
    );
  });

  test('unread-only structure drops a conversation that becomes read', () {
    tab.excludeReadFromStructure = true;
    tab.setItemsForTest(
      convType: 2,
      items: [
        _group('a', unread: 1, order: 2, time: 20),
        _group('b', unread: 3, order: 1, time: 10),
      ],
    );
    tab.resetWorkCounters();
    tab.applyPatches(
      [_group('a', unread: 0, order: 2, time: 20)],
      explicitUnreadIds: const {'group_a'},
    );

    expect(tab.structureIdsForType(2), ['group_b']);
    expect(tab.workStructureNotifyCount, 1);
    expect(tab.lastNotificationStructureChanged, isTrue);
    expect(tab.rowViewOf('group_a'), isNull);
  });

  test('identical group payload does not republish row or structure', () {
    final row = _group('a', order: 2, time: 20, face: 'https://cdn/a.png');
    tab.setItemsForTest(convType: 2, items: [row]);
    tab.applyPatches([_group('a', order: 2, time: 20, face: 'https://cdn/a.png')]);
    tab.resetWorkCounters();
    var rowNotifies = 0;
    final listen = tab.rowViewListenable('group_a');
    void onRow() => rowNotifies++;
    listen.addListener(onRow);
    tab.applyPatches([_group('a', order: 2, time: 20, face: 'https://cdn/a.png')]);
    listen.removeListener(onRow);

    expect(tab.workRowProjectedCount, 0);
    expect(tab.workRowNotifyCount, 0);
    expect(tab.workStructureNotifyCount, 0);
    expect(rowNotifies, 0);
  });

  test('one batch of A and B projects only those rows and notifies structure once', () {
    tab.setItemsForTest(
      convType: 2,
      items: [
        _group('a', order: 30, time: 30),
        _group('b', order: 20, time: 20),
        _group('c', order: 10, time: 10),
      ],
    );
    tab.resetWorkCounters();
    tab.applyPatches([
      _group(
        'a',
        order: 21,
        time: 21,
        last: _text('a-new', msgID: 'a2', timestamp: 21),
      ),
      _group(
        'b',
        order: 40,
        time: 40,
        last: _text('b-new', msgID: 'b2', timestamp: 40),
      ),
    ]);

    expect(tab.workRowProjectedCount, 2);
    expect(tab.workChangedIdCount, 2);
    expect(tab.workStructureNotifyCount, 1);
    expect(tab.structureIdsForType(2).first, 'group_b');
    expect(tab.rowViewOf('group_c')?.lastMessagePreview, 'hi');
  });

  test('unrelated member writes do not rebuild conversation row views', () async {
    tab.setItemsForTest(
      convType: 2,
      items: [_group('visible', order: 1, time: 10)],
    );
    tab.resetWorkCounters();
    await GroupMemberLocalStore.instance.upsertMany(
      ownerUserId: 'partial-owner',
      groupId: '@TGS#hidden',
      records: [
        GroupMemberRecord(
          userId: 'member-1',
          nickname: 'Hidden',
          avatarUrl: '',
          friendRemark: '',
          nameCard: '',
          role: 200,
          joinedAt: 1,
          isSelf: false,
        ),
      ],
    );

    expect(tab.workRowProjectedCount, 0);
    expect(tab.workStructureNotifyCount, 0);
    expect(tab.rowViewOf('group_visible')?.displayName, 'visible');
  });

  test('message arrival during page append keeps unique order', () {
    tab.setItemsForTest(
      convType: 2,
      items: [
        for (var i = 0; i < 8; i++)
          _group('g$i', order: 100 - i, time: 100 - i),
      ],
    );
    tab.resetWorkCounters();
    tab.applyPatches(
      [_group('page', order: 1, time: 1)],
      forceAdmitIds: const {'group_page'},
    );
    tab.applyPatches([
      _group(
        'g7',
        order: 200,
        time: 200,
        last: _text('hot', msgID: 'hot', timestamp: 200),
      ),
    ]);

    final ids = tab.structureIdsForType(2);
    expect(ids.toSet().length, ids.length);
    expect(ids.first, 'group_g7');
    expect(ids, contains('group_page'));
    expect(ids, contains('group_g0'));
  });

  test('late patch from a previous account scope cannot mutate the new list', () {
    tab.bindOwnerScopeForTest('acct-a');
    tab.setItemsForTest(
      convType: 2,
      items: [_group('old', order: 1, time: 10)],
    );
    final oldGeneration = tab.sessionGeneration;
    tab.bindOwnerScopeForTest('acct-b');
    tab.setItemsForTest(
      convType: 2,
      items: [_group('new', order: 5, time: 50)],
    );
    tab.resetWorkCounters();
    tab.applyPatches(
      [_group('old', order: 99, time: 99, face: 'https://cdn/old.png')],
      ownerScope: 'acct-a',
      expectedSessionGeneration: oldGeneration,
    );

    expect(tab.structureIdsForType(2), ['group_new']);
    expect(tab.rowViewOf('group_old'), isNull);
    expect(tab.rowViewOf('group_new')?.displayName, 'new');
    expect(tab.workRowProjectedCount, 0);
  });
}
