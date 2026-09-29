import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reducer.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

V2TimConversation conversation(String id, {String? name}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    showName: name ?? id,
  );
}

void main() {
  test('reducer deletes by canonical id and updates existing rows', () {
    final result = ConversationProjectionReducer.reduce(
      current: [conversation('c2c_a'), conversation('c2c_b')],
      upserted: [conversation('c2c_a', name: 'updated')],
      deletedIds: {'c2c_b'},
      forceAdmitIds: const <String>{},
      keyOf: (item) => item.conversationID,
      keyOfId: (id) => id,
      shouldAdmit: (_, __) => false,
      mergeExisting: (_, incoming) => incoming,
    );

    expect(result.conversations, hasLength(1));
    expect(result.conversations.single.showName, 'updated');
    expect(result.deleted, contains('c2c_b'));
    expect(result.updated, contains('c2c_a'));
    expect(result.inserted, isEmpty);
  });

  test('reducer admits forced and policy-approved rows only', () {
    final result = ConversationProjectionReducer.reduce(
      current: const [],
      upserted: [conversation('c2c_forced'), conversation('c2c_hot')],
      deletedIds: const <String>{},
      forceAdmitIds: {'c2c_forced'},
      keyOf: (item) => item.conversationID,
      keyOfId: (id) => id,
      shouldAdmit: (item, _) => item.conversationID == 'c2c_hot',
      mergeExisting: (_, incoming) => incoming,
    );

    expect(
      result.conversations.map((item) => item.conversationID),
      containsAllInOrder(['c2c_forced', 'c2c_hot']),
    );
    expect(result.inserted, containsAll(<String>['c2c_forced', 'c2c_hot']));
  });
}
