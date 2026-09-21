import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/utils/revoked_message_preview.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_change_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

V2TimMessage _copy(V2TimMessage message) =>
    V2TimMessage.fromJson(Map<String, dynamic>.from(message.toJson()));

class _RecordingMessageService implements MessageService {
  final modified = <V2TimMessage>[];
  final revoked = <String>[];
  final revokedMessages = <V2TimMessage?>[];
  final response = Completer<int>();

  @override
  Future<V2TimValueCallback<V2TimMessageChangeInfo>> modifyMessage({
    required V2TimMessage message,
  }) async {
    modified.add(_copy(message)..messageFromWeb = message.messageFromWeb);
    return V2TimValueCallback<V2TimMessageChangeInfo>(
      code: await response.future,
      desc: 'test response',
    );
  }

  @override
  Future<V2TimCallback> revokeMessage({
    required String msgID,
    Object? webMessageInstance,
    V2TimMessage? message,
  }) async {
    revoked.add(msgID);
    revokedMessages.add(message);
    return V2TimCallback(code: await response.future, desc: 'test response');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  var sequence = 0;
  late _RecordingMessageService sdk;
  late TUIChatSeparateViewModel model;
  late TUIChatGlobalModel global;
  late String peerId;
  late String storageKey;
  late V2TimMessage original;

  setUp(() async {
    await serviceLocator.unregister<MessageService>();
    sdk = _RecordingMessageService();
    serviceLocator.registerSingleton<MessageService>(sdk);
    peerId = 'peer_user_${++sequence}';
    storageKey = 'c2c_$peerId';
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    model = TUIChatSeparateViewModel()
      ..conversationID = peerId
      ..conversationType = ConvType.c2c
      ..suppressReadReporting = true
      ..chatConfig = const TIMUIKitChatConfig(isGroupAdminRecallEnabled: true);
    global = model.globalModel;
    global.configureMessageWriterScope(
      ownerUserID: 'c2c_self_revoke_test',
      accountGeneration: 1,
      domainGeneration: 1,
    );
    original = V2TimMessage.fromJson({
      'message_msg_id': 'c2c-revoke-message-$sequence',
      'id': 'c2c-local-id-$sequence',
      'message_conv_id': peerId,
      'message_conv_type': 1,
      'message_server_time': nowSeconds,
      'message_status': MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      'message_risk_type_identified': 0,
    })
      ..elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
      ..userID = peerId
      ..isSelf = true
      ..id = 'c2c-local-id-$sequence'
      ..cloudCustomData = jsonEncode({'existing': 'preserve me'})
      ..messageFromWeb = jsonEncode({
        'ID': 'c2c-revoke-message-$sequence',
        'cloudCustomData': jsonEncode({'existing': 'preserve me'}),
      })
      ..textElem = V2TimTextElem(text: 'c2c message content');
    original.elemList.add(original.textElem!);
    global.setMessageList(storageKey, [original]);
  });

  Future<void> finish(int code) async {
    sdk.response.complete(code);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  tearDown(() async {
    if (!sdk.response.isCompleted) await finish(1);
    model.dispose();
  });

  test('c2c self revoke finds the c2c_ bucket and passes message to SDK',
      () async {
    await model.revokeMsg(
      original.msgID!,
      false,
      original.messageFromWeb,
      original,
    );
    expect(
      isRevokedMessage(global.messageListMap[storageKey]!.single),
      isTrue,
    );
    expect(sdk.modified, isEmpty);
    expect(sdk.revoked, [original.msgID]);
    expect(sdk.revokedMessages, hasLength(1));
    expect(sdk.revokedMessages.single, isNotNull);
    await finish(0);
    expect(
      isRevokedMessage(global.messageListMap[storageKey]!.single),
      isTrue,
    );
  });

  test('c2c self revoke matches local id against the server row', () async {
    await model.revokeMsg(original.id!, false);
    expect(
      isRevokedMessage(global.messageListMap[storageKey]!.single),
      isTrue,
    );
    expect(sdk.revoked, isNotEmpty);
    expect(sdk.revokedMessages.single, isNotNull);
    expect(sdk.revokedMessages.single!.msgID, original.msgID);
    await finish(0);
  });

  test('rejected c2c self revoke restores the original message', () async {
    await model.revokeMsg(
      original.msgID!,
      false,
      original.messageFromWeb,
      original,
    );
    await finish(1);
    final restored = global.messageListMap[storageKey]!.single;
    expect(isRevokedMessage(restored), isFalse);
    expect(restored.cloudCustomData, original.cloudCustomData);
    expect(restored.textElem?.text, 'c2c message content');
  });
}
