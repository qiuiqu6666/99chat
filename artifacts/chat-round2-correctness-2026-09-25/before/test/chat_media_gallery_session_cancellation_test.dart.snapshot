import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_expand.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_session.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

V2TimMessage _image(int seq) => V2TimMessage.fromJson({
      'message_msg_id': 'image-$seq',
      'message_server_time': seq,
      'message_seq': '$seq',
      'message_risk_type_identified': 0,
      'message_sender_group_member_info': <String, dynamic>{},
    })
      ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
      ..imageElem = V2TimImageElem(imageList: [
        V2TimImage(type: 0, url: 'https://example.invalid/image-$seq.jpg'),
      ]);

class _GalleryGlobal extends TUIChatGlobalModel {
  final rows = [_image(300)];
  final started = Completer<void>();
  final release = Completer<void>();
  final types = <HistoryMsgGetTypeEnum>[];

  @override
  List<V2TimMessage>? getMessageList(String conversationID) => rows;

  @override
  List<V2TimMessage>? rawMessageList(String conversationID) => rows;

  @override
  Future<V2TimMessageListResult?> getHistoryMessageListThroughIm06({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    types.add(getType);
    if (types.length == 1) {
      started.complete();
      await release.future;
      return V2TimMessageListResult(
        isFinished: false,
        messageList: [for (var seq = 299; seq >= 260; seq--) _image(seq)],
      );
    }
    return V2TimMessageListResult(
      isFinished: true,
      messageList: getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG
          ? [_image(400)]
          : [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  late TUIChatSeparateViewModel model;
  late _GalleryGlobal global;
  late ChatMediaGalleryLiveSession session;
  late int updates;
  late bool mounted;
  var sequence = 0;

  ChatMediaPreviewBuildResult buildPreview(List<V2TimMessage> rows) =>
      buildChatMediaPreviewItems(
        originList: rows,
        tappedMessage: global.rows.first,
        types: const {ChatMediaPreviewType.image},
        heroTagBuilder: (message) => message.msgID!,
      );

  ChatMediaGalleryLiveSession newSession() => ChatMediaGalleryLiveSession(
        chatModel: model,
        tappedMessage: global.rows.first,
        types: const {ChatMediaPreviewType.image},
        initialPreview: buildPreview(global.rows),
        rebuildPreview: buildPreview,
        isMounted: () => mounted,
      );

  setUp(() async {
    ChatMediaGalleryExpandCache.clear();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = _GalleryGlobal();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    model = TUIChatSeparateViewModel()
      ..conversationID = 'gallery-${++sequence}'
      ..conversationType = ConvType.c2c
      ..chatConfig = TIMUIKitChatConfig(isShowReadingStatus: false)
      ..suppressReadReporting = true;
    global.configureMessageWriterScope(
        ownerUserID: 'gallery-owner',
        accountGeneration: sequence,
        domainGeneration: 1);
    updates = 0;
    mounted = true;
    session = newSession();
  });

  tearDown(() {
    session.dispose();
    model.dispose();
    ChatMediaGalleryExpandCache.clear();
  });

  for (final cancel in [
    'dispose',
    'unmount',
    'conversation',
    'account',
    'sdkSession'
  ]) {
    test('$cancel cancels gallery continuation and late cache write', () async {
      final cacheKey = ChatMediaGalleryExpandCache.keyFor(
        conversationID: model.conversationID,
        types: {ChatMediaPreviewType.image},
      );
      session.ensureStarted(() => updates++);
      await Future<void>.delayed(Duration.zero);
      expect(global.started.isCompleted, isTrue);
      switch (cancel) {
        case 'dispose':
          session.dispose();
        case 'unmount':
          mounted = false;
        case 'conversation':
          model.conversationID = 'another-room';
        case 'account':
          global.configureMessageWriterScope(
              ownerUserID: 'another-owner',
              accountGeneration: sequence + 1,
              domainGeneration: 1);
        case 'sdkSession':
          global.configureMessageWriterScope(
              ownerUserID: 'gallery-owner',
              accountGeneration: sequence,
              domainGeneration: 2);
      }
      global.release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(global.types, [HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG]);
      expect(updates, 0);
      expect(session.preview.sortedMessages.map((message) => message.msgID),
          ['image-300']);
      expect(ChatMediaGalleryExpandCache.get(cacheKey), isNull);

      if (cancel == 'dispose') {
        session = newSession();
        session.ensureStarted(() => updates++);
        await Future<void>.delayed(Duration.zero);
        expect(global.types, hasLength(3));
        expect(session.preview.sortedMessages.map((message) => message.msgID),
            ['image-300', 'image-400']);
      }
    });
  }

  test('open gallery completes both sides and caches completed preview',
      () async {
    session.ensureStarted(() => updates++);
    await Future<void>.delayed(Duration.zero);
    expect(global.started.isCompleted, isTrue);
    global.release.complete();
    await Future<void>.delayed(Duration.zero);
    expect(global.types, [
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG,
    ]);
    expect(updates, 1);
    expect(session.preview.sortedMessages, hasLength(42));
    expect(session.preview.sortedMessages.first.msgID, 'image-260');
    expect(session.preview.sortedMessages.last.msgID, 'image-400');
    expect(
        ChatMediaGalleryExpandCache.get(ChatMediaGalleryExpandCache.keyFor(
          conversationID: model.conversationID,
          types: {ChatMediaPreviewType.image},
        )),
        hasLength(42));
  });
}
