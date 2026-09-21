import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_service_implement.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_message_send_queue.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

typedef _SendResult = V2TimValueCallback<V2TimMessage>;
typedef _CreateResult = V2TimValueCallback<V2TimMsgCreateInfoResult>;

_SendResult _success() => _SendResult(code: 0, desc: 'ok');
_CreateResult _created(String id) => _CreateResult(
      code: 0,
      desc: 'ok',
      data: V2TimMsgCreateInfoResult(id: id),
    );

class _SdkMessages implements V2TIMMessageManager {
  final creates = <Map<String, dynamic>>[];
  final sends = <Map<Symbol, dynamic>>[];
  Future<_CreateResult> Function(String id)? create;
  Future<_SendResult> Function(Map<Symbol, dynamic> args)? send;

  @override
  Future<_CreateResult> createCustomMessage({
    required String data,
    String desc = '',
    String extension = '',
  }) {
    creates.add(jsonDecode(data) as Map<String, dynamic>);
    final id = 'typing-${creates.length}';
    return create?.call(id) ?? Future.value(_created(id));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendMessage) {
      final args = invocation.namedArguments;
      sends.add(args);
      return send?.call(args) ?? Future.value(_success());
    }
    throw StateError('Unexpected SDK call: ${invocation.memberName}');
  }
}

class _Sdk implements V2TIMManager {
  _Sdk(this.messages);
  final _SdkMessages messages;

  @override
  V2TIMMessageManager getMessageManager() => messages;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late V2TIMManager originalSdk;
  late MessageServiceImpl service;
  late _SdkMessages sdk;
  final errors = <TIMCallback>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    serviceLocator.registerSingleton<CoreServicesImpl>(
      CoreServicesImpl()..onCallback = errors.add,
    );
    await ApiClient.instance.saveToken('fixture-token', userId: 'typing-owner');
    originalSdk = TencentImSDKPlugin.v2TIMManager;
  });

  setUp(() {
    SessionIdentityService.instance.invalidate(reason: 'typing_test');
    sdk = _SdkMessages();
    TencentImSDKPlugin.v2TIMManager = _Sdk(sdk);
    service = MessageServiceImpl();
    errors.clear();
  });

  tearDown(OutgoingMessageSendQueue.instance.resetForTesting);
  tearDownAll(() async {
    TencentImSDKPlugin.v2TIMManager = originalSdk;
    await serviceLocator.reset();
  });

  test('stuck typing cannot block text; text still preserves send order', () {
    fakeAsync((time) {
      final typing = Completer<_SendResult>();
      final text = Completer<_SendResult>();
      sdk.send = (args) {
        if (args[#onlineUserOnly] == true) return typing.future;
        if (args[#id] == 'text-1') return text.future;
        return Future.value(_success());
      };
      service.sendTypingStatus(receiver: 'c2c_peer', isTyping: true);
      time.flushMicrotasks();
      service.sendMessage(id: 'text-1', receiver: 'peer', groupID: '');
      service.sendMessage(id: 'text-2', receiver: 'peer', groupID: '');
      time.flushMicrotasks();
      expect(sdk.sends.map((args) => args[#id]), ['typing-1', 'text-1']);
      expect(typing.isCompleted, isFalse);
      text.complete(_success());
      time.flushMicrotasks();
      expect(
          sdk.sends.map((args) => args[#id]), ['typing-1', 'text-1', 'text-2']);
      expect(typing.isCompleted, isFalse);
      expect(sdk.sends.first[#receiver], 'peer');
      expect(sdk.sends.first[#onlineUserOnly], isTrue);
      expect(sdk.sends.first[#needReadReceipt], isFalse);
      expect(sdk.sends.first[#isExcludedFromUnreadCount], isTrue);
      typing.complete(_success());
      time.flushMicrotasks();
    });
  });

  test('slow create is superseded by stop and never blocks text', () {
    fakeAsync((time) {
      final creation = Completer<_CreateResult>();
      sdk.create = (id) =>
          id == 'typing-1' ? creation.future : Future.value(_created(id));
      service.sendTypingStatus(receiver: 'peer', isTyping: true);
      service.sendTypingStatus(receiver: 'peer', isTyping: false);
      service.sendMessage(id: 'text', receiver: 'peer', groupID: '');
      time.flushMicrotasks();
      expect(sdk.sends.single[#id], 'text');
      creation.complete(_created('typing-1'));
      time.flushMicrotasks();
      expect(sdk.sends.map((args) => args[#id]), ['text', 'typing-2']);
      expect(sdk.creates.last, {
        'businessID': 'user_typing_status',
        'typingStatus': 0,
        'userAction': 14,
        'version': 0,
        'actionParam': 'EIMAMSG_InputStatus_End',
      });
    });
  });

  test('typing can be dispatched while the body send is pending', () {
    fakeAsync((time) {
      final text = Completer<_SendResult>();
      sdk.send = (args) =>
          args[#id] == 'text' ? text.future : Future.value(_success());
      service.sendMessage(id: 'text', receiver: 'peer', groupID: '');
      time.flushMicrotasks();
      service.sendTypingStatus(receiver: 'peer', isTyping: true);
      time.flushMicrotasks();
      expect(sdk.sends.map((args) => args[#id]), ['text', 'typing-1']);
      text.complete(_success());
      time.flushMicrotasks();
    });
  });

  test('typing SDK rejection and exceptions do not raise message error UI', () {
    fakeAsync((time) {
      sdk.send = (_) async => _SendResult(code: 6015, desc: 'rate limited');
      service.sendTypingStatus(receiver: 'peer', isTyping: true);
      time.flushMicrotasks();
      sdk.send = (_) async => throw StateError('offline');
      service.sendTypingStatus(receiver: 'peer', isTyping: false);
      time.flushMicrotasks();
      sdk.send = (_) async => _success();
      service.sendTypingStatus(receiver: 'peer', isTyping: true);
      time.flushMicrotasks();
      expect(sdk.sends, hasLength(3));
      expect(errors, isEmpty);
    });
  });

  test('session change during creation discards old and pending signals', () {
    fakeAsync((time) {
      final creation = Completer<_CreateResult>();
      sdk.create = (id) =>
          id == 'typing-1' ? creation.future : Future.value(_created(id));
      service.sendTypingStatus(receiver: 'peer', isTyping: true);
      service.sendTypingStatus(receiver: 'peer', isTyping: false);
      SessionIdentityService.instance.invalidate(reason: 'logout');
      creation.complete(_created('typing-1'));
      time.flushMicrotasks();
      expect(sdk.sends, isEmpty);
      expect(sdk.creates, hasLength(1));
      service.sendTypingStatus(receiver: 'peer', isTyping: true);
      time.flushMicrotasks();
      expect(sdk.sends.single[#id], 'typing-2');
    });
  });

  test('failed custom creation is dropped without affecting the next update',
      () {
    fakeAsync((time) {
      sdk.create = (_) async => _CreateResult(code: -1, desc: 'offline');
      service.sendTypingStatus(receiver: 'peer', isTyping: true);
      time.flushMicrotasks();
      expect(sdk.sends, isEmpty);
      sdk.create = null;
      service.sendTypingStatus(receiver: 'peer', isTyping: false);
      time.flushMicrotasks();
      expect(sdk.sends, hasLength(1));
      expect(errors, isEmpty);
    });
  });
}
