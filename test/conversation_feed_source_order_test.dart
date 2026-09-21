import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

V2TimConversation _row(String id, int order) => V2TimConversation(
      conversationID: id,
      type: id.startsWith('group_') ? 2 : 1,
      orderkey: order,
    );

int _newestFirst(V2TimConversation a, V2TimConversation b) =>
    (b.orderkey ?? 0).compareTo(a.orderkey ?? 0);

void main() {
  test('ordinary feed reuses the Store view without sorting or copying', () {
    final source = List<V2TimConversation>.unmodifiable([
      _row('c2c_older', 10),
      _row('c2c_newer', 30),
    ]);
    final result = mergeConversationFeedSupplementsInSourceOrder(
      source: source,
      supplements: const [],
      compare: _newestFirst,
    );
    expect(identical(result, source), isTrue);
    expect(result.map((row) => row.conversationID), ['c2c_older', 'c2c_newer']);
  });

  test('folder supplements retain frozen source order and current SDK rows',
      () {
    final first = _row('c2c_same', 10);
    final second = _row('c2c_newer', 30);
    final source = [first, second];
    final result = mergeConversationFeedSupplementsInSourceOrder(
      source: source,
      supplements: [
        _row('c2c_same', 99),
        _row('c2c_tail', 1),
        _row('group_same', 20),
        _row('group_same', 50),
      ],
      compare: _newestFirst,
    );
    expect(result.map((row) => row.conversationID),
        ['group_same', 'c2c_same', 'c2c_newer', 'c2c_tail']);
    expect(identical(result[1], first), isTrue);
    expect(identical(result[2], second), isTrue);
    expect(source, [first, second]);
  });

  test('loaded SDK identities suppress stale folder copies without allocation',
      () {
    final source = [_row('group_chat', 10)];
    final result = mergeConversationFeedSupplementsInSourceOrder(
      source: source,
      supplements: [_row('group_chat', 99)],
      compare: _newestFirst,
    );
    expect(identical(result, source), isTrue);
  });
}
