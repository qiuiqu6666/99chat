import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_peek/conversation_peek_media_bubble.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_online_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class DelayedMediaService implements MessageService {
  final requests =
      <String, Completer<V2TimValueCallback<V2TimMessageOnlineUrl>>>{};
  final downloads = <String>[];
  @override
  Future<V2TimValueCallback<V2TimMessageOnlineUrl>> getMessageOnlineUrl(
      {required String msgID, bool reportError = true}) {
    return (requests[msgID] =
            Completer<V2TimValueCallback<V2TimMessageOnlineUrl>>())
        .future;
  }

  @override
  Future<V2TimCallback> downloadMessage(
      {required String msgID,
      required int messageType,
      required int imageType,
      required bool isSnapshot,
      V2TimMessage? message,
      void Function(V2TimMessage)? onDownloadFinished,
      bool reportError = true}) async {
    downloads.add(msgID);
    return V2TimCallback(code: 0, desc: '');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  test('peek rendering never performs synchronous file metadata calls', () {
    final source = File(
            'lib/src/widgets/conversation_peek/conversation_peek_media_bubble.dart')
        .readAsStringSync();
    expect(source, isNot(contains('existsSync(')));
    expect(source, isNot(contains('statSync(')));
  });
  testWidgets(
      'switching messages starts a new request and discards old completion',
      (tester) async {
    final original = serviceLocator<MessageService>();
    final service = DelayedMediaService();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(service);
    addTearDown(() async {
      await serviceLocator.unregister<MessageService>();
      serviceLocator.registerSingleton<MessageService>(original);
    });
    final a = V2TimMessage.fromJson(
        {'message_server_time': 0, 'message_risk_type_identified': 0})
      ..msgID = 'a'
      ..elemType = 3
      ..imageElem = V2TimImageElem();
    final b = V2TimMessage.fromJson(
        {'message_server_time': 0, 'message_risk_type_identified': 0})
      ..msgID = 'b'
      ..elemType = 3
      ..imageElem = V2TimImageElem();
    final oldBImage = b.imageElem;
    Future<void> show(V2TimMessage message) async {
      await tester.pumpWidget(
          MaterialApp(home: ConversationPeekMediaBubble(message: message)));
      await tester.pump();
    }

    await show(a);
    await show(b);
    expect(service.requests.keys, containsAll(['a', 'b']));
    service.requests['a']!.complete(V2TimValueCallback(
        code: 0,
        desc: '',
        data: V2TimMessageOnlineUrl(
            imageElem: V2TimImageElem(path: 'obsolete'))));
    await tester.pump();
    expect(identical(b.imageElem, oldBImage), isTrue);
    expect(service.downloads, isEmpty);
    await tester.pumpWidget(const SizedBox());
    service.requests['b']!
        .complete(V2TimValueCallback(code: 1, desc: 'offline'));
    await tester.pump();
    expect(service.downloads, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
