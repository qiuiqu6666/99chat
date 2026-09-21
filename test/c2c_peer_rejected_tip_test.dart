import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/c2c_peer_rejected_tip_message.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/custom_last_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/error_message_converter.dart';

class _TestClockManager implements TIMManager {
  @override
  int getServerTime() => 1700000000;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TIMManager originalNativeManager;

  setUpAll(() {
    originalNativeManager = TIMManager.instance;
    TIMManager.instance = _TestClockManager();
  });

  tearDownAll(() {
    TIMManager.instance = originalNativeManager;
  });

  test('buildC2cPeerRejectedTipMessage is in-memory CUSTOM with 20007 copy',
      () {
    final tip = buildC2cPeerRejectedTipMessage(clientId: 'local-abc');
    expect(isC2cPeerRejectedTipMessage(tip), isTrue);
    expect(tip.elemType, MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
    expect(tip.isSelf, isTrue);
    expect(tip.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(tip.id, 'peer-rejected:local-abc');
    expect(tip.msgID, isNull);
    expect(
      getC2cPeerRejectedTipDisplayText(tip.customElem),
      '消息已发出，但被对方拒收了。',
    );
    expect(
      getC2cPeerRejectedTipDisplayText(tip.customElem),
      ErrorMessageConverter.getErrorMessage(20007),
    );
  });

  test('plain text messages are not peer-rejected tips', () {
    final text = buildC2cPeerRejectedTipMessage(clientId: 'x');
    text.elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
    expect(isC2cPeerRejectedTipMessage(text), isFalse);
    expect(getC2cPeerRejectedTipDisplayText(text.customElem), isNotEmpty);
  });

  test('conversation preview uses 20007 copy and omits sender', () {
    final tip = buildC2cPeerRejectedTipMessage(clientId: 'preview');
    expect(omitsConversationPreviewSender(tip), isTrue);
    expect(
      lightCustomConversationPreview(tip),
      '消息已发出，但被对方拒收了。',
    );
  });
}
