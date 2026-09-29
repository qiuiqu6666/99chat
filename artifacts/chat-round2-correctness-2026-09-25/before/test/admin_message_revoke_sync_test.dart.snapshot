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
  late V2TimMessage original;

  setUp(() async {
    await serviceLocator.unregister<MessageService>();
    sdk = _RecordingMessageService();
    serviceLocator.registerSingleton<MessageService>(sdk);
    model = TUIChatSeparateViewModel()
      ..conversationID = '@TGS#admin_revoke_test_${++sequence}'
      ..suppressReadReporting = true
      ..chatConfig = const TIMUIKitChatConfig(isGroupAdminRecallEnabled: true);
    global = model.globalModel;
    global.configureMessageWriterScope(
      ownerUserID: 'admin_revoke_test',
      accountGeneration: 1,
      domainGeneration: 1,
    );
    original = V2TimMessage.fromJson({
      'message_msg_id': 'revoke-message-$sequence',
      'message_conv_id': model.conversationID,
      'message_conv_type': 2,
      'message_server_time': 100,
      'message_status': MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      'message_risk_type_identified': 0,
    })
      ..elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
      ..groupID = model.conversationID
      ..isSelf = false
      ..cloudCustomData = jsonEncode({'existing': 'preserve me'})
      ..messageFromWeb = jsonEncode({
        'ID': 'revoke-message-$sequence',
        'cloudCustomData': jsonEncode({'existing': 'preserve me'}),
      })
      ..textElem = V2TimTextElem(text: 'message content');
    original.elemList.add(original.textElem!);
    global.setMessageList(model.conversationID, [original]);
  });

  Future<void> finish(int code) async {
    sdk.response.complete(code);
    // Drain SDK completion and local projection callbacks, without network IO.
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  tearDown(() async {
    if (!sdk.response.isCompleted) await finish(1);
    model.dispose();
  });

  for (final ownMessage in [false, true]) {
    test(
        'admin revoke of ${ownMessage ? 'own old' : 'other member'} message sends a durable marker',
        () async {
      original.isSelf = ownMessage;
      await model.revokeMsg(original.msgID!, true, original.messageFromWeb);
      expect(
          isRevokedMessage(global.messageListMap[model.conversationID]!.single),
          isTrue);
      expect(sdk.modified, hasLength(1));
      expect(sdk.revoked, isEmpty);
      final submitted = sdk.modified.single;
      final cloud = jsonDecode(submitted.cloudCustomData!) as Map;
      expect(cloud['isRevoke'], isTrue);
      expect(cloud['revokeByAdmin'], isTrue);
      expect(cloud['existing'], 'preserve me');
      final web = jsonDecode(submitted.messageFromWeb!) as Map;
      expect(web['ID'], original.msgID);
      expect(jsonDecode(web['cloudCustomData'] as String), cloud);
      expect(submitted.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
      expect(isRevokedMessage(original), isFalse);

      await finish(0);
      // Simulate the server persisting only the submitted cloud data, then
      // delivering it to another member and returning it in fresh history.
      final serverMessage = _copy(original)
        ..cloudCustomData = submitted.cloudCustomData;
      final receiver = TUIChatGlobalModel();
      receiver.setMessageList(model.conversationID, [_copy(original)]);
      await receiver.onMessageModified(serverMessage, model.conversationID);
      expect(
          isRevokedMessage(
              receiver.messageListMap[model.conversationID]!.single),
          isTrue);
      final restarted = TUIChatGlobalModel();
      restarted.setMessageList(model.conversationID, [_copy(serverMessage)]);
      expect(
          isRevokedMessage(
              restarted.messageListMap[model.conversationID]!.single),
          isTrue);
    });
  }

  test('ordinary self revoke uses the SDK revoke API', () async {
    original.isSelf = true;
    await model.revokeMsg(original.msgID!, false, original.messageFromWeb);
    expect(sdk.modified, isEmpty);
    expect(sdk.revoked, [original.msgID]);
    await finish(0);
    expect(
        isRevokedMessage(global.messageListMap[model.conversationID]!.single),
        isTrue);
  });

  test('rejected admin revoke restores the original message', () async {
    await model.revokeMsg(original.msgID!, true, original.messageFromWeb);
    await finish(1);
    final restored = global.messageListMap[model.conversationID]!.single;
    expect(isRevokedMessage(restored), isFalse);
    expect(restored.cloudCustomData, original.cloudCustomData);
    expect(restored.textElem?.text, 'message content');
  });
}
