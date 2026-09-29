import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_media_metadata_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_online_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _DelayedMediaService extends MessageService {
  final started = Completer<void>();
  final requests =
      <String, Completer<V2TimValueCallback<V2TimMessageOnlineUrl>>>{};

  @override
  Future<V2TimValueCallback<V2TimMessageOnlineUrl>> getMessageOnlineUrl({
    required String msgID,
    bool reportError = true,
  }) {
    final request = Completer<V2TimValueCallback<V2TimMessageOnlineUrl>>();
    requests[msgID] = request;
    if (!started.isCompleted) started.complete();
    return request.future;
  }

  @override
  Future<V2TimCallback> downloadMessage({
    required String msgID,
    required int messageType,
    required int imageType,
    required bool isSnapshot,
    V2TimMessage? message,
    void Function(V2TimMessage)? onDownloadFinished,
    bool reportError = true,
  }) async =>
      V2TimCallback(code: 0, desc: '');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

V2TimMessage _imageMessage(String id) =>
    V2TimMessage.fromJson(<String, dynamic>{
      'message_msg_id': id,
      'message_server_time': 1,
      'message_status': 2,
      'message_risk_type_identified': 0,
    })
      ..msgID = id
      ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
      ..imageElem = V2TimImageElem();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MessageService originalService;
  late _DelayedMediaService delayedService;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setupServiceLocator();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SessionIdentityService.instance.invalidate(reason: 'test_setup');
    await ApiClient.instance
        .saveToken('media-owner-a-token', userId: 'media_owner_a');
    originalService = serviceLocator<MessageService>();
    delayedService = _DelayedMediaService();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(delayedService);
  });

  tearDown(() async {
    final store = MessageMediaMetadataStore.instance;
    await store.clearForOwner('media_owner_a');
    await store.clearForOwner('media_owner_b');
    store.debugClearMemoryForOwner('media_owner_a');
    store.debugClearMemoryForOwner('media_owner_b');
    store.debugOwnerUserId = null;
    await store.closeDatabaseForTest();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(originalService);
    SessionIdentityService.instance.invalidate(reason: 'test_teardown');
    await ApiClient.instance.clearToken();
  });

  test('late online URL is discarded after the account changes', () async {
    final message = _imageMessage('late-media-url-after-switch');
    final originalElem = message.imageElem;
    var callbackCount = 0;

    final resolving = ChatImageMessagePrefetch.resolveOnlineUrlsForMessages(
      <V2TimMessage>[message],
      onMessageResolved: (_) => callbackCount++,
    );
    await delayedService.started.future.timeout(const Duration(seconds: 3));
    expect(
        delayedService.requests.keys, contains('late-media-url-after-switch'));

    await ApiClient.instance
        .saveToken('media-owner-b-token', userId: 'media_owner_b');
    SessionIdentityService.instance.invalidate(reason: 'test_account_switch');
    delayedService.requests['late-media-url-after-switch']!.complete(
      V2TimValueCallback(
        code: 0,
        desc: '',
        data: V2TimMessageOnlineUrl(
          imageElem: V2TimImageElem(
            imageList: <V2TimImage?>[
              V2TimImage(
                type: 1,
                uuid: 'late-thumb',
                url: 'https://cdn.example.test/late-thumb.jpg',
              ),
            ],
          ),
        ),
      ),
    );

    await resolving;
    expect(identical(message.imageElem, originalElem), isTrue);
    expect(callbackCount, 0);

    final currentAccountMessage = _imageMessage('late-media-url-after-switch');
    await MessageMediaMetadataStore.instance.hydrateMessages(
      <V2TimMessage>[currentAccountMessage],
      ownerUserId: 'media_owner_b',
    );
    expect(currentAccountMessage.imageElem?.imageList, anyOf(isNull, isEmpty));
  });
}
