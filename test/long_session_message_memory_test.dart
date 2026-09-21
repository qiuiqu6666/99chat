import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimMessage _row(int id) => V2TimMessage.fromJson({
      'message_msg_id': 'long_$id',
      'message_server_time': id,
      'message_risk_type_identified': 0,
    })
      ..seq = '$id'
      ..userID = 'long_session'
      ..isSelf = false
      ..status = 2
      ..elemType = 1;

V2TimMessageReceipt _receipt(String id, {int read = 1}) => V2TimMessageReceipt(
    userID: 'long_session',
    msgID: id,
    timestamp: 100,
    isPeerRead: false,
    readCount: read,
    unreadCount: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TUIChatGlobalModel global;
  const conv = 'c2c_long_session';
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    global = serviceLocator<TUIChatGlobalModel>();
  });
  setUp(() {
    global.clearData();
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
  });
  tearDown(() {
    global.clearCurrentConversation();
    global.clearData();
  });

  test('default memory budget also bounds the Writer after 10000 messages', () {
    expect(ChatMessageWindowPolicy.enabled, isTrue);
    global.setMessageList(conv, List.generate(10000, (i) => _row(10000 - i)),
        replace: true);
    expect(global.rawMessageCount(conv), ChatMessageWindowPolicy.targetSize);
    expect(global.messageWriterRetainedCountForTesting(conv),
        ChatMessageWindowPolicy.targetSize);
    expect(global.rawMessageList(conv)!.first.msgID, 'long_10000');
  });

  test('releasing and replacing windows releases their receipt objects', () {
    global.setMessageList(conv, [_row(3), _row(2), _row(1)], replace: true);
    global.applyAppMessageReadReceipts(
        [_receipt('long_3'), _receipt('long_2'), _receipt('long_1')]);
    expect(global.messageReadReceiptMap.length, 3);
    global.setMessageList(conv, [_row(3)],
        replace: true, preserveInFlightOutgoing: false);
    expect(global.messageReadReceiptMap.keys, ['long_3']);
    global.clearCurrentConversation();
    global.removeMessageList(conv);
    expect(global.messageReadReceiptMap, isEmpty);
  });

  test('unloaded receipt burst is bounded and promotes on later hydration', () {
    global.applyAppMessageReadReceipts(
        List.generate(1500, (i) => _receipt('long_$i')));
    expect(global.messageReadReceiptMap.length, lessThanOrEqualTo(512));
    global.setMessageList(conv, [_row(1499)], replace: true);
    global.applyAppMessageReadReceipts(
        List.generate(1500, (i) => _receipt('unloaded_$i')));
    expect(global.messageReadReceiptMap['long_1499']?.readCount, 1);
    expect(global.messageReadReceiptMap.length, lessThanOrEqualTo(513));
    global.clearCurrentConversation();
    global.removeMessageList(conv);
    expect(global.messageReadReceiptMap, isEmpty);
  });

  test('duplicate receipt batch updates a loaded row only once', () {
    global.setMessageList(conv, [_row(3)], replace: true);
    final ui = serviceLocator<ChatUiStateStore>();
    final before = ui.rowRevision(conv, 'long_3');
    global.applyAppMessageReadReceipts(
        List.generate(500, (_) => _receipt('long_3')));
    expect(ui.rowRevision(conv, 'long_3'), before + 1);
    expect(global.messageReadReceiptMap['long_3']?.readCount, 1);
    final after = ui.rowRevision(conv, 'long_3');
    global.applyAppMessageReadReceipts([_receipt('long_3')]);
    expect(ui.rowRevision(conv, 'long_3'), after);
  });
}
