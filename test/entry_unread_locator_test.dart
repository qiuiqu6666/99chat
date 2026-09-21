import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/entry_unread_locator.dart';

V2TimMessage msg(int i, {bool self = false}) => V2TimMessage.fromJson({
      'message_risk_type_identified': 0,
    })
      ..msgID = 'message-$i'
      ..timestamp = i
      ..seq = '${9000 - i}'
      ..isSelf = self;

void main() {
  test(
      'walks full C2C cursors across more than 200 unread without a latest reload',
      () async {
    final cursors = <int>[];
    final target = await EntryUnreadLocator.find(
        unreadCount: 251,
        latestAtEntry: msg(300),
        isCurrent: () => true,
        older: (cursor) async {
          final end = cursor.timestamp!;
          cursors.add(end);
          final start = (end - 80).clamp(0, end);
          return V2TimMessageListResult(
              isFinished: start == 0,
              messageList: [for (var i = end; i >= start; i--) msg(i)]);
        });
    expect(target?.msgID, 'message-50');
    expect(cursors, [300, 220, 140, 60]);
  });
  test('own messages and inclusive page anchors do not count as unread',
      () async {
    final target = await EntryUnreadLocator.find(
        unreadCount: 3,
        latestAtEntry: msg(5),
        isCurrent: () => true,
        older: (cursor) async =>
            V2TimMessageListResult(isFinished: true, messageList: [
              msg(5),
              msg(4, self: true),
              msg(30)..isExcludedFromUnreadCount = true,
              msg(3),
              msg(2)
            ]));
    expect(target?.msgID, 'message-2');
  });
  test('no-progress SDK pages stop instead of looping', () async {
    var calls = 0;
    final target = await EntryUnreadLocator.find(
        unreadCount: 51,
        latestAtEntry: msg(5),
        isCurrent: () => true,
        older: (_) async {
          calls++;
          return V2TimMessageListResult(
              isFinished: false, messageList: [msg(5)]);
        });
    expect(target, isNull);
    expect(calls, 1);
  });
  test('leaving the page rejects the response', () async {
    var current = true;
    final target = await EntryUnreadLocator.find(
        unreadCount: 2,
        latestAtEntry: msg(5),
        isCurrent: () => current,
        older: (_) async {
          current = false;
          return V2TimMessageListResult(
              isFinished: true, messageList: [msg(4)]);
        });
    expect(target, isNull);
  });
}
