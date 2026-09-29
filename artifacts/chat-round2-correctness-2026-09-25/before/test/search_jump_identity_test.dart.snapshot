import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_list_stable_keys.dart';

void main() {
  V2TimMessage message(String id, String seq) => V2TimMessage.fromJson({
        'message_risk_type_identified': 0,
        'message_msg_id': id,
        'message_seq': int.parse(seq),
      })
        ..timestamp = 1000
        ..sender = 'bot'
        ..elemType = 1;

  test('same-second bot messages with zero seq are distinct', () {
    const anchor = MessageAnchor(
        conversationID: 'group_g',
        convType: 2,
        msgID: 'clicked',
        seq: '0',
        timestamp: 1000,
        sender: 'bot',
        elemType: 1);
    expect(anchor.matches(message('another', '0')), isFalse);
    expect(anchor.matches(message('clicked', '0')), isTrue);
  });

  test('loaded neighbours do not count as the clicked message', () {
    const anchor =
        MessageAnchor(conversationID: 'group_g', convType: 2, seq: '300');
    expect(
        anchor.isPresentIn([message('before', '299'), message('after', '301')]),
        isFalse);
    expect(anchor.isPresentIn([message('target', '0300')]), isTrue);
  });

  test('C2C sequence equality cannot substitute for SDK identity', () {
    const anchor = MessageAnchor(
        conversationID: 'c2c_u', convType: 1, msgID: 'clicked', seq: '20');
    expect(anchor.matches(message('another', '20')), isFalse);
  });

  testWidgets('stacked pages for one conversation have independent stable keys',
      (tester) async {
    final original = ChatListStableKeys();
    final search = ChatListStableKeys();
    Widget page(ChatListStableKeys keys) => KeyedSubtree(
          key: keys.containerFor('group_g'),
          child: Text('chat', key: keys.historyFor('group_g')),
        );
    Widget app() =>
        MaterialApp(home: Stack(children: [page(original), page(search)]));
    final firstKey = original.historyFor('group_g');
    await tester.pumpWidget(app());
    final originalElement = firstKey.currentContext;
    expect(tester.takeException(), isNull);
    expect(find.text('chat'), findsNWidgets(2));
    expect(identical(firstKey, search.historyFor('group_g')), isFalse);
    await tester.pumpWidget(app());
    expect(identical(firstKey.currentContext, originalElement), isTrue);
    expect(tester.takeException(), isNull);
  });
}
