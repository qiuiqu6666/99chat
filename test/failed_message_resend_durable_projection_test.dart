import 'dart:io';
import 'dart:async';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tencent_cloud_chat_sdk/models/common_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
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
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _TestClockManager implements TIMManager {
  @override
  int getServerTime() => 1700000000;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native call: ${invocation.memberName}');
}

class _ResendService implements MessageService {
  int creates = 0;
  int sends = 0;
  bool throwOnSend = false;
  bool emitSync = true;
  late V2TimMessage template;
  Completer<void>? entered;
  Completer<void>? release;
  int resultCode = 0;
  String? syncMsgID;
  final List<String> deletedLocalMsgIDs = <String>[];

  @override
  Future<V2TimMsgCreateInfoResult?> createTextMessage(
      {required String text}) async {
    return _create();
  }

  V2TimMessage _copyTemplate() => V2TimMessage.fromJson(template.toJson());

  V2TimMsgCreateInfoResult _create() {
    final id = '${template.id}-retry-${++creates}';
    final message = _copyTemplate()
      ..id = id
      ..msgID = null
      ..localCustomData = null
      ..cloudCustomData = null
      ..status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
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
    entered?.complete();
    if (release != null) await release!.future;
    if (throwOnSend) throw StateError('transport lost after dispatch');
    final reused = syncMsgID?.trim() ?? '';
    if (reused.isNotEmpty) {
      if (emitSync) onSyncMsgID?.call(reused);
    }
    final sent = _copyTemplate()
      ..id = id
      ..msgID = null
      ..status = resultCode == 0
          ? MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
          : MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
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
  dynamic noSuchMethod(Invocation invocation) {
    if ({
      #createImageMessage,
      #createVideoMessage,
      #createSoundMessage,
      #createFileMessage
    }.contains(invocation.memberName)) {
      return Future<V2TimMsgCreateInfoResult?>.value(_create());
    }
    throw StateError('Unexpected SDK call: ${invocation.memberName}');
  }
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
  late PathProviderPlatform originalPaths;
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
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(databaseDirectory.path);
    CommonUtils.applyIsolateSeed(CommonUtilsIsolateSeed(
        appFileDirPath: databaseDirectory.path,
        appCacheDirPath: databaseDirectory.path,
        externalCacheDirPath: null,
        sdkAppID: 1,
        loginUser: 'resend-owner'));
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
    PathProviderPlatform.instance = originalPaths;
    await databaseFactory.setDatabasesPath(originalDatabasePath);
    for (final entry in databaseDirectory.listSync()) {
      if (entry.path.endsWith('.lock')) continue;
      await entry.delete(recursive: true);
    }
    if (databaseDirectory.listSync().isEmpty) {
      await databaseDirectory.delete();
    }
  });

  var serial = 0;
  Future<V2TimMessage> seedFailure(int type) async {
    final number = ++serial;
    final path = '${databaseDirectory.path}/attachment-$number';
    await File(path)
        .writeAsBytes([0xff, 0xd8, 0xff, ...List.filled(300, 0), 0xff, 0xd9]);
    final failed = _text(
        id: 'failed-$number',
        msgID: 'failed-server-$number',
        timestamp: 2000,
        status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
        text: 'retry')
      ..elemType = type
      ..cloudCustomData = '{"messageReply":{"messageID":"quoted"}}'
      ..localCustomData = '{"imageWidth":320,"imageHeight":240}';
    if (type == 3) failed.imageElem = V2TimImageElem(path: path);
    if (type == 4) failed.soundElem = V2TimSoundElem(path: path, duration: 2);
    if (type == 5) {
      failed.videoElem =
          V2TimVideoElem(videoPath: path, snapshotPath: path, duration: 2);
    }
    if (type == 6) {
      failed.fileElem = V2TimFileElem(path: path, fileName: 'attachment');
    }
    failed.elemList = [
      if (type == 1) failed.textElem!,
      if (type == 3) failed.imageElem!,
      if (type == 4) failed.soundElem!,
      if (type == 5) failed.videoElem!,
      if (type == 6) failed.fileElem!,
    ];
    applyOutgoingStableIdToMessage(failed, 'original-bubble-$number');
    sdk.template = failed;
    sdk.resultCode = 20007;
    final initial = await ImOutgoingSendCoordinator.instance.send(
        messageService: sdk,
        sdkLocalId: failed.id!,
        conversationId: 'peer',
        conversationType: ImConversationType.c2c,
        receiver: 'peer',
        groupID: '',
        fallbackMessage: failed);
    expect(initial.outcomeUnknown, isFalse);
    expect(initial.sdkResult.code, 20007);
    expect(sdk.sends, 1);
    global.setMessageList('peer', [failed], replace: true);
    return failed;
  }

  for (final type in [1, 3, 4, 5, 6]) {
    test('original row receives pending and confirmed retry type=$type',
        () async {
      final failed = await seedFailure(type);
      final key = ChatUiStateStore.messageKeyOf(failed);
      expect(global.messageInConversationByKey('peer', key), isNotNull);
      sdk.resultCode = 0;
      sdk.emitSync = type != 1;
      sdk.syncMsgID = '${failed.id}-success';
      sdk.entered = Completer<void>();
      sdk.release = Completer<void>();
      final pending = page.reSendFailMessage(
          message: failed, convID: 'peer', convType: ConvType.c2c);
      await sdk.entered!.future.timeout(const Duration(seconds: 10));
      final during = global.messageInConversationByKey('peer', key);
      final revision = page.chatUiStateStore.rowRevision('peer', key);
      expect(
          await page.reSendFailMessage(
              message: failed, convID: 'peer', convType: ConvType.c2c),
          isNull);
      if (type == 1) {
        page.dispose();
        page = TUIChatSeparateViewModel()
          ..conversationID = 'peer'
          ..conversationType = ConvType.c2c
          ..suppressReadReporting = true;
      }
      sdk.release!.complete();
      await pending;
      expect(during, isNotNull,
          reason: 'retained bubble must resolve its original key');
      expect(during!.status, MessageStatus.V2TIM_MSG_STATUS_SENDING);
      expect(during.localCustomData, contains('imageWidth'));
      expect(during.cloudCustomData, contains('quoted'));
      final after = global.messageInConversationByKey('peer', key);
      expect(after?.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
      expect(page.chatUiStateStore.rowRevision('peer', key),
          greaterThan(revision));
      expect(after?.cloudCustomData, contains('quoted'));
      expect(global.rawMessageList('peer'), hasLength(1));
      expect(sdk.sends, 2, reason: 'initial failure and exactly one retry');
      final reopened = TUIChatSeparateViewModel()
        ..conversationID = 'peer'
        ..conversationType = ConvType.c2c
        ..suppressReadReporting = true;
      expect(
          reopened
              .getOriginMessageList()
              .where((m) => m.elemType == type)
              .single
              .status,
          MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
      reopened.dispose();
      if (type == 1) expect(after?.textElem?.text, 'retry');
      if (type == 3) expect(after?.imageElem?.path, failed.imageElem?.path);
      if (type == 4) expect(after?.soundElem?.path, failed.soundElem?.path);
      if (type == 5) {
        expect(after?.videoElem?.videoPath, failed.videoElem?.videoPath);
      }
      if (type == 6) expect(after?.fileElem?.fileName, 'attachment');
    });
  }

  test('failed retry can retry again from the original retained row', () async {
    final failed = await seedFailure(1);
    final key = ChatUiStateStore.messageKeyOf(failed);
    sdk.syncMsgID = '${failed.id}-second';
    expect(
        (await page.reSendFailMessage(
                message: failed, convID: 'peer', convType: ConvType.c2c))
            ?.code,
        20007);
    expect(global.messageInConversationByKey('peer', key)?.status,
        MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
    sdk.resultCode = 0;
    sdk.syncMsgID = '${failed.id}-third';
    expect(
        (await page.reSendFailMessage(
                message: failed, convID: 'peer', convType: ConvType.c2c))
            ?.code,
        0);
    expect(global.messageInConversationByKey('peer', key)?.status,
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(sdk.sends, 3);
  });
  test('unknown retry stays non-retryable through the original row', () async {
    final failed = await seedFailure(1);
    sdk.throwOnSend = true;
    await page.reSendFailMessage(
        message: failed, convID: 'peer', convType: ConvType.c2c);
    final row = global.messageInConversationByKey(
        'peer', ChatUiStateStore.messageKeyOf(failed));
    expect(row?.status, isNot(MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC));
    expect(
        await page.reSendFailMessage(
            message: failed, convID: 'peer', convType: ConvType.c2c),
        isNull);
    expect(sdk.sends, 2);
  });
}
