import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/c2c_peer_rejected_tip_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/error_message_converter.dart';

class _TestClockManager implements TIMManager {
  @override
  int getServerTime() => 1700000000;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native call: ${invocation.memberName}');
}

class _ResendService implements MessageService {
  int creates = 0;
  int resultCode = 0;
  String? syncMsgID;
  final List<String> deletedLocalMsgIDs = <String>[];

  @override
  Future<V2TimMsgCreateInfoResult?> createTextMessage({required String text}) async {
    creates++;
    const id = 'resend-new';
    final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = id
      ..elemType = 1
      ..isSelf = true
      ..status = MessageStatus.V2TIM_MSG_STATUS_SENDING
      ..textElem = V2TimTextElem(text: text);
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
    final reused = syncMsgID?.trim() ?? '';
    if (reused.isNotEmpty) {
      onSyncMsgID?.call(reused);
    }
    final sent = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = id
      ..elemType = 1
      ..isSelf = true
      ..status = resultCode == 0
          ? MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
          : MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL
      ..textElem = V2TimTextElem(text: 'retry');
    if (reused.isNotEmpty) {
      sent.msgID = reused;
    }
    return V2TimValueCallback<V2TimMessage>(
      code: resultCode,
      desc: resultCode == 0 ? 'ok' : 'provider rejected',
      data: sent,
    );
  }

  @override
  Future<V2TimCallback> deleteMessageFromLocalStorage({
    required String msgID,
    Object? webMessageInstance,
  }) async {
    deletedLocalMsgIDs.add(msgID);
    return V2TimCallback(code: 0, desc: 'ok');
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

V2TimMessage _text({
  required String id,
  String? msgID,
  required int timestamp,
  required int status,
  required String text,
}) {
  final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
    ..id = id
    ..msgID = msgID
    ..elemType = 1
    ..isSelf = true
    ..timestamp = timestamp
    ..status = status
    ..textElem = V2TimTextElem(text: text);
  return message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;
  late String originalDatabasePath;
  late TIMManager originalNativeManager;
  late _ResendService sdk;
  late TUIChatSeparateViewModel page;
  late TUIChatGlobalModel global;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalDatabasePath = await getDatabasesPath();
    databaseDirectory =
        await Directory.systemTemp.createTemp('failed-resend-reposition-');
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    setupServiceLocator();
    originalNativeManager = TIMManager.instance;
    TIMManager.instance = _TestClockManager();
    await ApiClient.instance.saveToken('fixture-token', userId: 'resend-owner');
  });

  setUp(() async {
    sdk = _ResendService();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(sdk);
    global = serviceLocator<TUIChatGlobalModel>();
    page = TUIChatSeparateViewModel()
      ..conversationID = 'peer'
      ..conversationType = ConvType.c2c
      ..suppressReadReporting = true;
  });

  tearDown(() {
    page.dispose();
    global.removeMessageList('peer');
  });

  tearDownAll(() async {
    await ConversationSyncService.instance.detachRealtimeListeners();
    await MessageCoreStore.instance.closeIfOpen();
    await FriendLocalStore.instance.closeIfOpen();
    await ConversationLocalStore.instance.closeIfOpen();
    TIMManager.instance = originalNativeManager;
    await databaseFactory.setDatabasesPath(originalDatabasePath);
    for (final entry in databaseDirectory.listSync()) {
      if (entry.path.endsWith('.lock')) continue;
      await entry.delete(recursive: true);
    }
    if (databaseDirectory.listSync().isEmpty) {
      await databaseDirectory.delete();
    }
  });

  test('resend removes server-bound fail and inserts newest', () async {
    final older = _text(
      id: 'older-succ',
      msgID: 'server-older-succ',
      timestamp: 1000,
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      text: 'old',
    );
    final failed = _text(
      id: 'failed-original',
      msgID: 'server-failed-original',
      timestamp: 2000,
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      text: 'retry',
    );
    applyOutgoingStableIdToMessage(failed, 'failed-original');
    global.setMessageList('peer', <V2TimMessage>[failed, older], replace: true);

    final result = await page.reSendFailMessage(
      message: failed,
      convID: 'peer',
      convType: ConvType.c2c,
    );
    expect(result?.code, 0);
    expect(sdk.creates, 1);
    expect(sdk.deletedLocalMsgIDs, <String>['server-failed-original']);

    final list = global.rawMessageList('peer') ?? const <V2TimMessage>[];
    expect(
      list.map((item) => item.id),
      isNot(contains('failed-original')),
    );
    expect(
      list.map((item) => item.msgID),
      isNot(contains('server-failed-original')),
    );
    expect(
      list.map(readOutgoingStableId),
      isNot(contains('failed-original')),
    );
    final resent = list.singleWhere((item) => item.id == 'resend-new');
    for (final other in list.where((item) => item.id != 'resend-new')) {
      expect(
        TUIChatGlobalModel.compareMessagesChronological(resent, other),
        greaterThan(0),
      );
    }
  });

  test('resend removes local-only fail and inserts newest', () async {
    final older = _text(
      id: 'older-succ',
      timestamp: 1000,
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      text: 'old',
    );
    final failed = _text(
      id: 'failed-local',
      timestamp: 2000,
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      text: 'retry',
    );
    global.setMessageList('peer', <V2TimMessage>[failed, older], replace: true);

    final result = await page.reSendFailMessage(
      message: failed,
      convID: 'peer',
      convType: ConvType.c2c,
    );
    expect(result?.code, 0);
    expect(sdk.deletedLocalMsgIDs, isEmpty);

    final list = global.rawMessageList('peer') ?? const <V2TimMessage>[];
    expect(list.map((item) => item.id), isNot(contains('failed-local')));
    final resent = list.singleWhere((item) => item.id == 'resend-new');
    for (final other in list.where((item) => item.id != 'resend-new')) {
      expect(
        TUIChatGlobalModel.compareMessagesChronological(resent, other),
        greaterThan(0),
      );
    }
  });

  test('resend 20007 reuses msgID, drops old tip, keeps one new fail bubble',
      () async {
    sdk.resultCode = 20007;
    sdk.syncMsgID = 'server-failed-original';
    final older = _text(
      id: 'older-succ',
      msgID: 'server-older-succ',
      timestamp: 1000,
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      text: 'old',
    );
    final failed = _text(
      id: 'failed-original',
      msgID: 'server-failed-original',
      timestamp: 2000,
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      text: 'retry',
    );
    applyOutgoingStableIdToMessage(failed, 'failed-original');
    global.setMessageList('peer', <V2TimMessage>[failed, older], replace: true);
    global.insertPeerRejectedLocalTip(
      'peer',
      20007,
      clientId: 'failed-original',
    );

    final result = await page.reSendFailMessage(
      message: failed,
      convID: 'peer',
      convType: ConvType.c2c,
    );
    expect(result?.code, 20007);

    final list = global.rawMessageList('peer') ?? const <V2TimMessage>[];
    expect(list.map((item) => item.id), isNot(contains('failed-original')));
    expect(
      list.map((item) => item.id),
      isNot(contains(c2cPeerRejectedTipLocalId('failed-original'))),
    );
    final resent = list.singleWhere((item) => item.id == 'resend-new');
    expect(resent.status, MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
    final tips = list.where(isC2cPeerRejectedTipMessage).toList();
    expect(tips, hasLength(1));
    expect(tips.single.id, c2cPeerRejectedTipLocalId('resend-new'));
    expect(
      getC2cPeerRejectedTipDisplayText(tips.single.customElem),
      ErrorMessageConverter.getErrorMessage(20007),
    );
  });
}
