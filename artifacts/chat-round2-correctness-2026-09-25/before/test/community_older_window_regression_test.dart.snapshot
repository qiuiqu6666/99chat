import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';

// Only identity fields are needed by the real window algorithm; no native SDK.
class _Message implements V2TimMessage {
  _Message(this.number);
  final int number;
  @override
  String get msgID => 'm$number';
  @override
  String get seq => '$number';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => ChatMessageWindowPolicy.enabled = true);
  tearDown(() => ChatMessageWindowPolicy.enabled = true);

  test('default policy retains short history and trims only above soft max',
      () {
    final short = List<V2TimMessage>.generate(180, (i) => _Message(200 - i));
    expect(ChatMessageWindow.trimToWindow(list: short).didTrim, isFalse);
    final count = ChatMessageWindowPolicy.softMax + 20;
    final long = List<V2TimMessage>.generate(count, (i) => _Message(count - i));
    final result = ChatMessageWindow.trimToWindow(
      list: long,
      anchorMsgID: 'm21',
      preferLatest: false,
    );
    expect(result.didTrim, isTrue);
    expect(result.list.length, ChatMessageWindowPolicy.targetSize);
    expect(result.list.last.msgID, 'm1');
    expect(result.list.map((message) => message.msgID), contains('m21'));
  });

  test('older pagination over 160 retains the page and reading seam', () {
    final messages = List<V2TimMessage>.generate(180, (i) => _Message(200 - i));
    final window = ChatMessageWindow.trimToWindow(
      softMax: 160,
      targetSize: 120,
      list: messages,
      preferLatest: false,
      anchorMsgID: 'm41',
      anchorSeq: '41',
    );
    expect(window.didTrim, isTrue);
    expect(window.list.length, lessThanOrEqualTo(120));
    expect(window.list.map((m) => m.msgID), contains('m41'));
    for (var seq = 21; seq <= 40; seq++) {
      expect(window.list.map((m) => m.msgID), contains('m$seq'));
    }
    expect(window.trimmedAwayOldestInMemory, isFalse);
    expect(window.trimmedAwayLatest, isTrue);
  });
  test('successive older pages preserve their tail across repeated trims', () {
    var window = List<V2TimMessage>.generate(160, (i) => _Message(1000 - i));
    var oldest = 841;
    for (var page = 0; page < 12; page++) {
      final incoming =
          List<V2TimMessage>.generate(20, (i) => _Message(oldest - i - 1));
      window = ChatMessageWindow.trimToWindow(
        softMax: 160,
        targetSize: 120,
        list: [...window, ...incoming],
        anchorMsgID: 'm$oldest',
        preferLatest: false,
      ).list;
      oldest -= 20;
      expect(window.last.msgID, 'm$oldest');
      expect(window.length, lessThanOrEqualTo(160));
    }
  });
}
