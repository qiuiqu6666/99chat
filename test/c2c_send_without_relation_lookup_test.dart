import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tencent_cloud_chat_demo/src/utils/c2c_blocked_outgoing_message_sync.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/c2c_peer_rejected_tip_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_message_display.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_send_status.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _TestClockManager implements TIMManager {
  @override
  int getServerTime() => 1700000000;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native call: ${invocation.memberName}');
}

class _SendService implements MessageService {
  int sends = 0;
  int resultCode = 0;
  String? receiver;
  final Map<String, V2TimMessage> messages = {};

  @override
  Future<V2TimMsgCreateInfoResult?> createTextMessage({required String text}) async {
    final id = 'local-${messages.length}';
    final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = id
      ..elemType = 1
      ..sender = 'send-owner'
      ..isSelf = true
      ..status = MessageStatus.V2TIM_MSG_STATUS_SENDING
      ..textElem = V2TimTextElem(text: text);
    messages[id] = message;
    return V2TimMsgCreateInfoResult(id: id, messageInfo: message);
  }

  @override
  Future<V2TimValueCallback<V2TimMessage>> sendMessage({
    required String id,
    required String receiver,
    required String groupID,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool onlineUserOnly = false,
    bool isExcludedFromUnreadCount = false,
    bool needReadReceipt = false,
    OfflinePushInfo? offlinePushInfo,
    String? cloudCustomData,
    String? localCustomData,
    bool isExcludedFromContentModeration = false,
    void Function(String syncMsgID)? onSyncMsgID,
  }) async {
    sends++;
    this.receiver = receiver;
    final syncMsgID = 'server-$id';
    onSyncMsgID?.call(syncMsgID);
    final sent = V2TimMessage.fromJson(messages[id]!.toJson())
      ..id = id
      ..msgID = syncMsgID
      ..cloudCustomData = cloudCustomData
      ..status = resultCode == 0
          ? MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
          : MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    return V2TimValueCallback<V2TimMessage>(
      code: resultCode,
      desc: resultCode == 0 ? 'ok' : 'provider rejected',
      data: sent,
    );
  }

  @override
  Future<V2TimCallback> setLocalCustomData({
    required String msgID,
    required String localCustomData,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;
  late String originalDatabasePath;
  late TIMManager originalNativeManager;
  late _SendService sdk;
  late TUIChatSeparateViewModel page;
  late List<Interceptor> originalInterceptors;
  final pendingRequests = <(RequestOptions, RequestInterceptorHandler)>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalDatabasePath = await getDatabasesPath();
    databaseDirectory = await Directory.systemTemp.createTemp('c2c-send-test-');
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    setupServiceLocator();
    originalNativeManager = TIMManager.instance;
    TIMManager.instance = _TestClockManager();
    await ApiClient.instance.saveToken('fixture-token', userId: 'send-owner');
  });

  setUp(() async {
    C2cFriendMessageGuard.debugReset();
    sdk = _SendService();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(sdk);
    page = TUIChatSeparateViewModel()
      ..conversationID = 'send-peer'
      ..conversationType = ConvType.c2c
      ..suppressReadReporting = true;
    final dio = ApiClient.instance.dio;
    originalInterceptors = dio.interceptors.toList();
    dio.interceptors.clear();
    pendingRequests.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      pendingRequests.add((options, handler));
    }));
  });

  tearDown(() async {
    for (final (options, handler) in pendingRequests) {
      handler.reject(DioError(
        requestOptions: options,
        type: DioErrorType.receiveTimeout,
      ));
    }
    await Future<void>.delayed(Duration.zero);
    ApiClient.instance.dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
    page.dispose();
    serviceLocator<TUIChatGlobalModel>().removeMessageList('send-peer');
  });

  tearDownAll(() async {
    await ConversationSyncService.instance.detachRealtimeListeners();
    await MessageCoreStore.instance.closeIfOpen();
    await FriendLocalStore.instance.closeIfOpen();
    await ConversationLocalStore.instance.closeIfOpen();
    TIMManager.instance = originalNativeManager;
    await databaseFactory.setDatabasesPath(originalDatabasePath);
    // MessageCoreOwner deliberately holds its OS lock until process exit.
    // Delete the databases now; Windows cannot remove the lock file yet.
    for (final entry in databaseDirectory.listSync()) {
      if (entry.path.endsWith('.lock')) continue;
      await entry.delete(recursive: true);
    }
    if (databaseDirectory.listSync().isEmpty) {
      await databaseDirectory.delete();
    }
  });

  for (final code in [0, 20011, 20007]) {
    test('C2C text reaches SDK without relation HTTP and returns code $code',
        () async {
      sdk.resultCode = code;
      final result = await page.sendTextMessage(
        text: 'hello',
        convID: 'send-peer',
        convType: ConvType.c2c,
      ).timeout(const Duration(seconds: 5));
      expect(sdk.sends, 1);
      expect(sdk.receiver, 'send-peer');
      expect(result?.code, code);
      expect(pendingRequests, isEmpty);
    });
  }

  test('IM 20007 peer blacklist settles SEND_FAIL without delivery check',
      () async {
    sdk.resultCode = 20007;
    final result = await page.sendTextMessage(
      text: 'hello',
      convID: 'send-peer',
      convType: ConvType.c2c,
    ).timeout(const Duration(seconds: 5));
    expect(sdk.sends, 1);
    expect(result?.code, 20007);
    final origin = page.getOriginMessageList();
    final bubble = origin.firstWhere(
      (message) =>
          message.isSelf == true && !isC2cPeerRejectedTipMessage(message),
    );
    expect(bubble.status, MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
    final tip = origin.firstWhere(isC2cPeerRejectedTipMessage);
    expect(
      getC2cPeerRejectedTipDisplayText(tip.customElem),
      '消息已发出，但被对方拒收了。',
    );
    expect(
      OutgoingMessageDisplay.shouldShowDeliveryCheck(status: bubble.status!),
      isFalse,
    );
    expect(
      OutgoingSendStatus.mergeSelf(
        previous: bubble.status,
        incoming: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      ),
      MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
    );
  });

  test('IM code 0 still settles SEND_SUCC with delivery check', () async {
    final result = await page.sendTextMessage(
      text: 'hello',
      convID: 'send-peer',
      convType: ConvType.c2c,
    ).timeout(const Duration(seconds: 5));
    expect(sdk.sends, 1);
    expect(result?.code, 0);
    final bubble = page.getOriginMessageList().firstWhere(
      (message) => message.isSelf == true,
    );
    expect(bubble.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(
      OutgoingMessageDisplay.shouldShowDeliveryCheck(status: bubble.status!),
      isTrue,
    );
  });

  test('controller send reaches SDK without relation HTTP', () async {
    final created = await sdk.createTextMessage(text: 'forwarded text');
    final result = await page.sendMessageFromController(
      messageInfo: created!.messageInfo,
    )!.timeout(const Duration(seconds: 5));
    expect(sdk.sends, 1);
    expect(result?.code, 0);
    expect(pendingRequests, isEmpty);
  });

  test('pending UI relation refresh cannot block a C2C text send', () async {
    final refresh = C2cFriendMessageGuard.refreshUiSnapshot('send-peer');
    for (var turn = 0; turn < 100 && pendingRequests.isEmpty; turn++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(pendingRequests, hasLength(1));
    final result = await page.sendTextMessage(
      text: 'send while relation endpoint is slow',
      convID: 'send-peer',
      convType: ConvType.c2c,
    ).timeout(const Duration(seconds: 5));
    expect(sdk.sends, 1);
    expect(result?.code, 0);
    expect(pendingRequests, hasLength(1));
    final (options, handler) = pendingRequests.removeLast();
    handler.reject(DioError(
      requestOptions: options,
      type: DioErrorType.receiveTimeout,
    ));
    await refresh;
  });

  test('confirmed blocked C2C skips SDK and fails with 20011', () async {
    ApiClient.instance.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.path == '/me/friends/send-peer/relation') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'peerUserId': 'send-peer',
              'isFriend': false,
              'inMyFriendList': false,
              'canMessage': false,
              'peerDeletedMe': false,
            },
          ));
          return;
        }
        pendingRequests.add((options, handler));
      }));
    final snapshot =
        await C2cFriendMessageGuard.refreshUiSnapshot('send-peer');
    expect(snapshot.decision, C2cSendPermissionDecision.blocked);
    expect(snapshot.relationConfirmed, isTrue);
    expect(pendingRequests, isEmpty);

    final result = await page.sendTextMessage(
      text: 'blocked',
      convID: 'send-peer',
      convType: ConvType.c2c,
    ).timeout(const Duration(seconds: 5));
    expect(sdk.sends, 0);
    expect(result?.code, C2cBlockedOutgoingMessageSync.blockedCode);
    expect(result?.data?.status, MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
    expect(pendingRequests, isEmpty);
  });

  test('group send does not use the C2C relation gate', () async {
    C2cFriendMessageGuard.debugReset();
    ApiClient.instance.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.path.contains('/relation')) {
          pendingRequests.add((options, handler));
          return;
        }
        pendingRequests.add((options, handler));
      }));
    page
      ..conversationID = 'send-group'
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.work;
    final result = await page.sendTextMessage(
      text: 'hello group',
      convID: 'send-group',
      convType: ConvType.group,
    ).timeout(const Duration(seconds: 5));
    expect(sdk.sends, 1);
    expect(sdk.receiver, isEmpty);
    expect(result?.code, 0);
    expect(
      pendingRequests.where((item) => item.$1.path.contains('/relation')),
      isEmpty,
    );
  });
}
