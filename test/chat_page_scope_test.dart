import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/chat_page_scope.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

V2TimMessage _msg(int id) => V2TimMessage.fromJson({
      'message_msg_id': 'm$id',
      'message_seq': '$id',
      'message_server_time': id,
      'message_risk_type_identified': 0,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ChatPageScope.instance.resetForTest();
  });

  test('enter then leave does not accumulate active ChatPageScope', () {
    for (var i = 0; i < 20; i++) {
      final token = ChatPageScope.instance.attach(
        conversationId: 'group_room',
        accountGeneration: 1,
      );
      expect(ChatPageScope.instance.activeCount, 1);
      expect(ChatPageScope.instance.isCurrent(token), isTrue);
      ChatImageMessagePrefetch.bindPageScope(token);
      ChatImageMessagePrefetch.cancelForPageDispose();
      ChatPageScope.instance.invalidate(token);
      expect(ChatPageScope.instance.activeCount, 0);
      expect(ChatPageScope.instance.isCurrent(token), isFalse);
    }
    expect(ChatPageScope.instance.disposeCount, 20);
    expect(ChatPageScope.instance.prefetchCancelCount, 20);
  });

  test('disposed page does not allow projection or image tasks', () {
    final token = ChatPageScope.instance.attach(
      conversationId: 'group_a',
      accountGeneration: 1,
    );
    ChatPageScope.instance.invalidate(token);
    expect(
      ChatPageScope.instance.allowsProjection(
        token: token,
        conversationId: 'group_a',
      ),
      isFalse,
    );
    expect(
      ChatPageScope.instance.allowsProjection(
        conversationId: 'group_a',
        accountGeneration: 1,
      ),
      isFalse,
    );
  });

  test('stale accountGeneration cannot write the new page scope', () {
    ChatPageScope.instance.attach(
      conversationId: 'group_a',
      accountGeneration: 2,
    );
    expect(
      ChatPageScope.instance.allowsProjection(
        conversationId: 'group_a',
        accountGeneration: 1,
      ),
      isFalse,
    );
  });

  test('mounted message window stays around the reading anchor', () {
    final list = List<V2TimMessage>.generate(1200, (i) => _msg(1200 - i));
    final trimmed = ChatMessageWindow.trimToWindow(
      list: list,
      anchorMsgID: 'm400',
      softMax: ChatMessageWindowPolicy.softMax,
      targetSize: ChatMessageWindowPolicy.targetSize,
    );
    expect(trimmed.didTrim, isTrue);
    expect(trimmed.list.length, lessThanOrEqualTo(ChatMessageWindowPolicy.targetSize));
    expect(trimmed.list.map((m) => m.msgID), contains('m400'));
    expect(trimmed.list.length, lessThan(400));
  });

  test('window policy starting budget is 120-300 not thousands', () {
    expect(ChatMessageWindowPolicy.targetSize, inInclusiveRange(120, 300));
    expect(ChatMessageWindowPolicy.softMax, inInclusiveRange(120, 320));
    expect(ChatMessageWindowPolicy.historyReadSoftMax, lessThanOrEqualTo(320));
  });
}
