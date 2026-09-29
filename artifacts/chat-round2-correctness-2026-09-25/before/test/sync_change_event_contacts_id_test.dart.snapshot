import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';

void main() {
  test('SyncChangeEvent.id falls back to peerUserId', () {
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'e1',
      'peerUserId': 'u_peer',
      'itemVersion': 3,
      'operation': 'upsert',
      'data': <String, dynamic>{'remark': 'A'},
    });
    expect(event.id, 'u_peer');
    expect(event.eventId, 'e1');
    expect(event.itemVersion, 3);
  });

  test('SyncChangeEvent.id still uses groupId when that is the entity', () {
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'e2',
      'groupId': 'g_room',
      'itemVersion': 1,
      'operation': 'upsert',
      'data': <String, dynamic>{'groupName': 'room'},
    });
    expect(event.id, 'g_room');
  });
}
