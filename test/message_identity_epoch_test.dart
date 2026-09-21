import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart'
    as web;

void main() {
  test('native identity epoch tracks changes, not same-value writes or status', () {
    final row = V2TimMessage.fromJson({
      'message_msg_id': 'server',
      'message_server_time': 123,
      'message_risk_type_identified': 0,
    })..id = 'local';
    final beforeJson = row.toJson();
    var epoch = V2TimMessage.identityMutationEpoch;
    row.msgID = row.msgID;
    row.id = row.id;
    row.seq = row.seq;
    row.status = 2;
    expect(V2TimMessage.identityMutationEpoch, epoch);
    for (final change in <void Function()>[
      () => row.msgID = 'server-2',
      () => row.id = 'local-2',
      () => row.seq = '2',
      () => row.msgID = null,
      () => row.id = null,
      () => row.seq = null,
    ]) {
      change();
      expect(V2TimMessage.identityMutationEpoch, ++epoch);
    }
    expect(beforeJson.keys.any((key) => key.contains('MutationEpoch')), isFalse);
    final roundTrip = V2TimMessage.fromJson(row.toJson());
    expect(roundTrip.msgID, row.msgID);
    expect(roundTrip.id, row.id);
    expect(roundTrip.seq, row.seq);
  });

  test('web constructors and wire JSON preserve identity/null semantics', () {
    final row = web.V2TimMessage(elemType: 1, msgID: 'server', id: 'local', seq: '7');
    expect([row.msgID, row.id, row.seq], ['server', 'local', '7']);
    var epoch = web.V2TimMessage.identityMutationEpoch;
    row.msgID = 'server';
    row.id = 'local';
    row.seq = '7';
    expect(web.V2TimMessage.identityMutationEpoch, epoch);
    row.id = null;
    expect(web.V2TimMessage.identityMutationEpoch, ++epoch);
    row.msgID = null;
    expect(web.V2TimMessage.identityMutationEpoch, ++epoch);
    row.seq = null;
    expect(web.V2TimMessage.identityMutationEpoch, ++epoch);
    final encoded = row.toJson();
    expect(encoded['msgID'], isNull);
    expect(encoded['id'], isNull);
    expect(encoded['seq'], isNull);
    expect(encoded.keys.any((key) => key.contains('MutationEpoch')), isFalse);
    final decoded = web.V2TimMessage.fromJson({'msgID': 'a', 'id': 'b', 'seq': '3'});
    expect([decoded.msgID, decoded.id, decoded.seq], ['a', 'b', '3']);
    final empty = web.V2TimMessage.fromJson({});
    expect([empty.msgID, empty.id, empty.seq], [null, null, null]);
  });
}
