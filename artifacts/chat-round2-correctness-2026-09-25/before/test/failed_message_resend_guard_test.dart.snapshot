import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart';

class FakeCreateService implements MessageService {
  int calls = 0;
  Completer<V2TimMsgCreateInfoResult?> gate = Completer();
  @override
  Future<V2TimMsgCreateInfoResult?> createTextMessage({required String text}) {
    calls++;
    return gate.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('unexpected SDK call');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeCreateService sdk;
  late TUIChatSeparateViewModel page;
  late TUIChatGlobalModel global;
  late V2TimMessage original;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    await ApiClient.instance.saveToken('fixture-token', userId: 'resend-owner');
    sdk = FakeCreateService();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(sdk);
    global = serviceLocator<TUIChatGlobalModel>();
    page = TUIChatSeparateViewModel()..suppressReadReporting = true;
    original = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = 'failed-original'..elemType = 1..isSelf = true
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL
      ..textElem = V2TimTextElem(text: 'retry');
    global.setMessageList('peer', [original], replace: true);
  });
  tearDown(() { page.dispose(); global.removeMessageList('peer'); });
  for (final type in [ConvType.c2c, ConvType.group]) {
    test('concurrent resend shares creation for $type and releases on failure', () async {
      final first = page.reSendFailMessage(message: original, convID: 'peer', convType: type);
      final second = page.reSendFailMessage(message: original, convID: 'peer', convType: type);
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(sdk.calls, 1);
      sdk.gate.complete(null);
      await Future.wait([first, second]);
      sdk.gate = Completer();
      final retry = page.reSendFailMessage(message: original, convID: 'peer', convType: type);
      await Future<void>.delayed(Duration.zero);
      expect(sdk.calls, 2);
      sdk.gate.complete(null);
      await retry;
    });
  }
  for (final status in [MessageStatus.V2TIM_MSG_STATUS_SENDING, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC]) {
    test('live status $status overrides stale failed object', () async {
      final live = V2TimMessage.fromJson({'message_risk_type_identified': 0})
        ..id = original.id..elemType = 1..isSelf = true..status = status;
      global.setMessageList('peer', [live], replace: true);
      expect(await page.reSendFailMessage(message: original, convID: 'peer', convType: ConvType.c2c), isNull);
      expect(sdk.calls, 0);
    });
  }
  test('creation exception releases the task for another retry', () async {
    final first = page.reSendFailMessage(message: original, convID: 'peer', convType: ConvType.c2c);
    final error = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    sdk.gate.completeError(StateError('create failed'));
    await error;
    sdk.gate = Completer();
    final retry = page.reSendFailMessage(message: original, convID: 'peer', convType: ConvType.c2c);
    await Future<void>.delayed(Duration.zero);
    expect(sdk.calls, 2);
    sdk.gate.complete(null);
    await retry;
  });
  test('removed original cannot be resent from a stale dialog', () async {
    global.removeMessageList('peer');
    expect(await page.reSendFailMessage(message: original, convID: 'peer', convType: ConvType.c2c), isNull);
    expect(sdk.calls, 0);
  });
  test('success during asynchronous creation prevents send and replacement', () async {
    final task = page.reSendFailMessage(message: original, convID: 'peer', convType: ConvType.c2c);
    await Future<void>.delayed(Duration.zero);
    original.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    sdk.gate.complete(V2TimMsgCreateInfoResult(id: 'new-id', messageInfo:
        V2TimMessage.fromJson({'message_risk_type_identified': 0})..id = 'new-id'));
    expect(await task, isNull);
    expect(global.rawMessageList('peer')!.single.id, original.id);
  });
}
