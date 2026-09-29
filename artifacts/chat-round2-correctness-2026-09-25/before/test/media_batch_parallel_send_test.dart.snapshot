import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_service_implement.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_message_send_queue.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

typedef _Result = V2TimValueCallback<V2TimMessage>;

class _Messages implements V2TIMMessageManager {
  final starts = <String>[];
  final pending = <String, Completer<_Result>>{};

  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #sendMessage) {
      final id = call.namedArguments[#id] as String;
      starts.add(id);
      return pending.putIfAbsent(id, Completer<_Result>.new).future;
    }
    throw StateError('Unexpected SDK call: ${call.memberName}');
  }

  void complete(String id, {int code = 0, V2TimMessage? message}) =>
      pending[id]!.complete(_Result(code: code, desc: 'test', data: message));
}

class _Sdk implements V2TIMManager {
  _Sdk(this.messages);
  final _Messages messages;
  @override
  V2TIMMessageManager getMessageManager() => messages;
  @override
  dynamic noSuchMethod(Invocation call) =>
      throw StateError('Unexpected SDK call: ${call.memberName}');
}

String _batch(int index, [String id = 'selection']) => jsonEncode({
      kChatMediaBatchIdKey: id,
      kChatMediaBatchIndexKey: index,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late V2TIMManager original;
  late _Messages sdk;
  late MessageServiceImpl service;
  final queue = OutgoingMessageSendQueue.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    serviceLocator.registerSingleton<CoreServicesImpl>(CoreServicesImpl());
    await ApiClient.instance.saveToken('test-token', userId: 'media-owner');
    original = TencentImSDKPlugin.v2TIMManager;
  });
  setUp(() {
    SessionIdentityService.instance.invalidate(reason: 'media_batch_test');
    sdk = _Messages();
    TencentImSDKPlugin.v2TIMManager = _Sdk(sdk);
    service = MessageServiceImpl();
  });
  tearDown(queue.resetForTesting);
  tearDownAll(() async {
    TencentImSDKPlugin.v2TIMManager = original;
    await serviceLocator.reset();
  });

  Future<_Result> send(String id, {String? metadata}) => service.sendMessage(
      id: id, receiver: '', groupID: '@TGS#media', localCustomData: metadata);

  test(
      'SDK overlaps three uploads and each completion preserves selected UI order',
      () {
    fakeAsync((time) {
      final rows = List.generate(
          5,
          (i) => V2TimMessage.fromJson({'message_risk_type_identified': 0})
            ..id = 'image-$i'
            ..groupID = '@TGS#media'
            ..isSelf = true
            ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
            ..timestamp = 1700000000
            ..status = MessageStatus.V2TIM_MSG_STATUS_SENDING
            ..localCustomData = _batch(i));
      final completed = <int>[];
      for (var i = 0; i < rows.length; i++) {
        send('image-$i', metadata: rows[i].localCustomData).then((result) {
          final replacement = result.data!;
          TUIChatGlobalModel.preserveOutgoingLocalOrderDataForTesting(
              rows[i], replacement);
          rows[i] = replacement;
          completed.add(i);
        });
      }
      time.flushMicrotasks();
      expect(sdk.starts, ['image-0', 'image-1', 'image-2']);
      var sequence = 1;
      for (final i in [2, 1, 4, 3, 0]) {
        final receipt =
            V2TimMessage.fromJson({'message_risk_type_identified': 0})
              ..id = 'image-$i'
              ..msgID = 'server-$i'
              ..groupID = '@TGS#media'
              ..isSelf = true
              ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
              ..seq = '${sequence++}'
              ..timestamp = 1700000000 + sequence
              ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
        sdk.complete('image-$i', message: receipt);
        time.flushMicrotasks();
        final visible =
            TUIChatGlobalModel.sortMessagesNewestFirst(rows).reversed;
        expect(visible.map((m) => m.id), List.generate(5, (i) => 'image-$i'));
        expect(visible.map(readChatMediaBatchIndex), [0, 1, 2, 3, 4]);
      }
      expect(completed, [2, 1, 4, 3, 0]);
      expect(sdk.starts, List.generate(5, (i) => 'image-$i'));
    });
  });

  test(
      'typed media SDK lanes isolate slow video and fence queued account changes',
      () {
    fakeAsync((time) {
      send('video-1', metadata: '{"mediaSendKind":"video"}');
      final stale = <int>[];
      send('video-2', metadata: '{"mediaSendKind":"video"}')
          .then((r) => stale.add(r.code));
      for (var i = 0; i < 4; i++) {
        send('typed-image-$i', metadata: '{"mediaSendKind":"image"}');
      }
      time.flushMicrotasks();
      expect(sdk.starts,
          ['video-1', 'typed-image-0', 'typed-image-1', 'typed-image-2']);
      sdk.complete('typed-image-1');
      time.flushMicrotasks();
      expect(sdk.starts.last, 'typed-image-3');
      SessionIdentityService.instance.invalidate(reason: 'typed-lane-switch');
      sdk.complete('video-1');
      for (final i in [0, 2, 3]) {
        sdk.complete('typed-image-$i');
      }
      time.flushMicrotasks();
      expect(sdk.starts.contains('video-2'), isFalse);
      expect(stale, [-1]);
    });
  });

  test('text is a barrier and later batches do not overtake it', () {
    fakeAsync((time) {
      send('before');
      send('a', metadata: _batch(0));
      send('b', metadata: _batch(1));
      send('middle');
      send('c', metadata: _batch(0, 'next'));
      send('d', metadata: _batch(1, 'next'));
      time.flushMicrotasks();
      expect(sdk.starts, ['before']);
      sdk.complete('before');
      time.flushMicrotasks();
      expect(sdk.starts, ['before', 'a', 'b']);
      sdk.complete('b');
      time.flushMicrotasks();
      expect(sdk.starts, ['before', 'a', 'b']);
      sdk.complete('a');
      time.flushMicrotasks();
      expect(sdk.starts.last, 'middle');
      sdk.complete('middle');
      time.flushMicrotasks();
      expect(sdk.starts, ['before', 'a', 'b', 'middle', 'c', 'd']);
      sdk.complete('d');
      sdk.complete('c');
      time.flushMicrotasks();
    });
  });

  for (final metadata in [
    'not-json',
    '[]',
    '{}',
    jsonEncode(
        {kChatMediaBatchIdKey: 'selection', kChatMediaBatchIndexKey: -1}),
    jsonEncode({kChatMediaBatchIdKey: '', kChatMediaBatchIndexKey: 0})
  ]) {
    test('invalid order metadata stays serial: $metadata', () {
      fakeAsync((time) {
        send('a', metadata: metadata);
        send('b', metadata: metadata);
        time.flushMicrotasks();
        expect(sdk.starts, ['a']);
        sdk.complete('a');
        time.flushMicrotasks();
        expect(sdk.starts, ['a', 'b']);
        sdk.complete('b');
        time.flushMicrotasks();
      });
    });
  }

  test('a failed upload frees its slot without cancelling the batch', () {
    fakeAsync((time) {
      for (var i = 0; i < 4; i++) {
        send('$i', metadata: _batch(i));
      }
      time.flushMicrotasks();
      expect(sdk.starts, ['0', '1', '2']);
      sdk.complete('1', code: -1);
      time.flushMicrotasks();
      expect(sdk.starts, ['0', '1', '2', '3']);
      for (final id in ['3', '2', '0']) {
        sdk.complete(id);
      }
      time.flushMicrotasks();
    });
  });

  test('timeout releases media slot and late native completion never resends',
      () {
    fakeAsync((time) {
      final native = List.generate(4, (_) => Completer<int>());
      final starts = <int>[];
      final failures = <int>[];
      for (var i = 0; i < 4; i++) {
        queue.runMediaBatch('group:test', 'batch', () {
          starts.add(i);
          return native[i].future;
        }, dispatchTimeout: const Duration(seconds: 1)).then<void>((_) {},
            onError: (Object error) {
          expect(error, isA<TimeoutException>());
          failures.add(i);
        });
      }
      time.flushMicrotasks();
      expect(starts, [0, 1, 2]);
      time.elapse(const Duration(seconds: 1));
      time.flushMicrotasks();
      expect(starts, [0, 1, 2, 3]);
      expect(failures, [0, 1, 2]);
      for (var i = 0; i < 4; i++) {
        native[i].complete(i);
      }
      time.flushMicrotasks();
      expect(starts, [0, 1, 2, 3]);
      expect(queue.hasPending('group:test'), isFalse);
    });
  });

  test('account change prevents queued media from reaching the SDK', () {
    fakeAsync((time) {
      final results = <int>[];
      for (var i = 0; i < 4; i++) {
        send('$i', metadata: _batch(i)).then((r) => results.add(r.code));
      }
      time.flushMicrotasks();
      expect(sdk.starts, ['0', '1', '2']);
      SessionIdentityService.instance.invalidate(reason: 'account_changed');
      queue.clearSession();
      for (final id in ['0', '1', '2']) {
        sdk.complete(id);
      }
      time.flushMicrotasks();
      expect(sdk.starts, ['0', '1', '2']);
      expect(results, contains(-1));
    });
  });
}
