import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sdk_window_policy.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

V2TimConversation _row(int index, {bool pinned = false, int unread = 0}) =>
    V2TimConversation(
      conversationID: 'c2c_$index',
      type: 1,
      userID: '$index',
      isPinned: pinned,
      unreadCount: unread,
      orderkey: 10000 - index,
    );

void main() {
  test('20k conversations retain a contiguous bounded anchor window', () {
    final rows = List.generate(20000, (i) => _row(i, unread: 1));
    final result = ConversationSdkWindowPolicy.trimAroundAnchor(rows,
        type: 1, viewportAnchorId: 'c2c_10000');
    expect(result.rows, hasLength(600));
    expect(result.rows.map((r) => r.conversationID), contains('c2c_10000'));
    expect(
        [...result.droppedFromStart, ...result.rows, ...result.droppedFromEnd],
        rows);
  });
  test('small SDK window remains intact', () {
    expect(
      ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType,
      greaterThan(80),
    );
    final rows = List<V2TimConversation>.generate(
      80,
      (index) => _row(
        index,
        pinned: index == 1,
        unread: index == 70 ? 2 : 0,
      ),
    );

    final result = ConversationSdkWindowPolicy.trimAroundAnchor(
      rows,
      type: 1,
      viewportAnchorId: 'c2c_40',
    );

    expect(result.trimmed, isFalse);
    expect(result.rows, hasLength(80));
    expect(result.droppedFromStart, isEmpty);
    expect(result.droppedFromEnd, isEmpty);
    expect(
      result.rows.map((row) => row.conversationID),
      List<String>.generate(80, (index) => 'c2c_$index'),
    );
  });
}
