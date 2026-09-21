import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

V2TimMessage hit(String id, int timestamp) => V2TimMessage.fromJson({
      'message_risk_type_identified': 0,
      'message_msg_id': id,
      'message_server_time': timestamp,
    });

V2TimMessageSearchResultItem conv(
  String conversationId, {
  int? count,
  required List<V2TimMessage> messages,
}) {
  return V2TimMessageSearchResultItem(
    conversationID: conversationId,
    messageCount: count ?? messages.length,
    messageList: messages,
  );
}

void main() {
  test('same conversation keeps one row and takes the later merged timestamp',
      () {
    final local = [
      conv('c2c_a', messages: [hit('m1', 100)]),
    ];
    final cloud = [
      conv('c2c_a',
          count: 2,
          messages: [hit('m1', 100), hit('m2', 150)]),
    ];
    final merged = mergeGlobalMessageSearchResults(local, cloud);
    expect(merged, hasLength(1));
    expect(merged.single.conversationID, 'c2c_a');
    expect(merged.single.messageCount, 2);
    expect(globalMessageSearchLatestTimestamp(merged.single), 150);
  });

  test('same message id is not inserted twice from a new instance', () {
    final local = [
      conv('c2c_a', messages: [hit('m1', 100)]),
    ];
    final cloud = [
      conv('c2c_a', messages: [hit('m1', 100)]),
    ];
    final merged = mergeGlobalMessageSearchResults(local, cloud);
    expect(merged.single.messageList, hasLength(1));
    expect(searchMessageStableId(merged.single.messageList!.single), 'm1');
  });

  test('today single hit ranks above older high messageCount', () {
    final older = conv(
      'c2c_old',
      count: 20,
      messages: [hit('old', 100)],
    );
    final newer = conv(
      'c2c_new',
      count: 1,
      messages: [hit('new', 100000)],
    );
    final sorted = sortGlobalMessageSearchResults([older, newer]);
    expect(
      sorted.map((item) => item.conversationID),
      ['c2c_new', 'c2c_old'],
    );
  });

  test('invalid timestamps sort after valid ones then by conversationID', () {
    final invalidB = conv('c2c_b', messages: [hit('b', 0)]);
    final invalidA = conv('c2c_a', messages: const []);
    final valid = conv('c2c_z', messages: [hit('z', 10)]);
    final sorted =
        sortGlobalMessageSearchResults([invalidB, valid, invalidA]);
    expect(
      sorted.map((item) => item.conversationID),
      ['c2c_z', 'c2c_a', 'c2c_b'],
    );
  });

  test('local-first and cloud-first merges share the same final order', () {
    final local = [
      conv('c2c_a', messages: [hit('a', 50)]),
      conv('c2c_b', messages: [hit('b', 40)]),
      conv('c2c_c', messages: [hit('c', 30)]),
      conv('c2c_d', messages: [hit('d', 20)]),
      conv('c2c_e', messages: [hit('e', 10)]),
    ];
    final cloud = [
      conv('c2c_x', messages: [hit('x', 45)]),
      conv('c2c_y', messages: [hit('y', 5)]),
    ];
    final localFirst = sortGlobalMessageSearchResults(
      mergeGlobalMessageSearchResults(local, cloud),
    );
    final cloudFirst = sortGlobalMessageSearchResults(
      mergeGlobalMessageSearchResults(cloud, local),
    );
    expect(
      localFirst.map((item) => item.conversationID).toList(),
      cloudFirst.map((item) => item.conversationID).toList(),
    );
    expect(
      localFirst.map((item) => item.conversationID).toList(),
      ['c2c_a', 'c2c_x', 'c2c_b', 'c2c_c', 'c2c_d', 'c2c_e', 'c2c_y'],
    );
  });

  test('homepage take 5 uses sorted order so X can enter top 5', () {
    final local = [
      conv('c2c_a', messages: [hit('a', 50)]),
      conv('c2c_b', messages: [hit('b', 40)]),
      conv('c2c_c', messages: [hit('c', 30)]),
      conv('c2c_d', messages: [hit('d', 20)]),
      conv('c2c_e', messages: [hit('e', 10)]),
    ];
    final cloud = [
      conv('c2c_x', messages: [hit('x', 45)]),
    ];
    final sorted = sortGlobalMessageSearchResults(
      mergeGlobalMessageSearchResults(local, cloud),
    );
    expect(
      takeSearchHomePreview(sorted.map((item) => item.conversationID).toList()),
      ['c2c_a', 'c2c_x', 'c2c_b', 'c2c_c', 'c2c_d'],
    );
  });
}
