import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_mapper.dart';

void main() {
  test('remark null with key present is a known clear', () {
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'e1',
      'peerUserId': 'u1',
      'itemVersion': 13,
      'operation': 'upsert',
      'remark': null,
    });
    final record = meFriendRecordFromSyncChangeEvent(event)!;
    expect(record.friendUserId, 'u1');
    expect(record.remarkKnown, isTrue);
    expect(record.remark, '');
    expect(record.itemVersion, 13);
  });

  test('missing remark is not a known clear', () {
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'e2',
      'peerUserId': 'u1',
      'itemVersion': 11,
      'operation': 'upsert',
      'nickname': '新昵称',
    });
    final record = meFriendRecordFromSyncChangeEvent(event)!;
    expect(record.remarkKnown, isFalse);
    expect(record.friendNickname, '新昵称');
  });

  test('contactsEntityIdFromSyncJson uses peerUserId', () {
    expect(
      contactsEntityIdFromSyncJson(<String, dynamic>{'peerUserId': 'u_peer'}),
      'u_peer',
    );
  });

  test('snapshot item maps peer id and version', () {
    const item = SyncProtocolItem(
      id: 'u1',
      itemVersion: 4,
      updatedAt: 1,
      data: <String, dynamic>{
        'remark': 'A',
        'friendNickname': 'n',
      },
    );
    final record = meFriendRecordFromSyncProtocolItem(item);
    expect(record.friendUserId, 'u1');
    expect(record.remark, 'A');
    expect(record.remarkKnown, isTrue);
    expect(record.itemVersion, 4);
  });
}
