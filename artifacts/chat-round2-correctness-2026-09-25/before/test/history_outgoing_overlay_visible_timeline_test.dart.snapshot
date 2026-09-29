import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

V2TimMessage _succ({
  required String conv,
  required int seq,
  required int timestamp,
  bool isSelf = true,
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': 'm$seq',
    'message_seq': '$seq',
    'message_conv_id': conv,
    'message_conv_type': 2,
    'message_server_time': timestamp,
    'message_is_from_self': isSelf,
    'message_status': MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    'message_risk_type_identified': 0,
  })
    ..groupID = conv
    ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
    ..elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT
    ..textElem = V2TimTextElem(text: 'succ $seq')
    ..isSelf = isSelf
    ..timestamp = timestamp;
  return message;
}

V2TimMessage _overlayImage({
  required String conv,
  required String clientId,
  required int timestamp,
  required int status,
  int? seq,
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': seq == null ? null : 'm$seq',
    'message_seq': seq == null ? null : '$seq',
    'message_conv_id': conv,
    'message_conv_type': 2,
    'message_server_time': timestamp,
    'message_is_from_self': true,
    'message_status': status,
    'message_risk_type_identified': 0,
  })
    ..groupID = conv
    ..id = clientId
    ..status = status
    ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
    ..imageElem = V2TimImageElem(path: '/tmp/$clientId.jpg')
    ..isSelf = true
    ..timestamp = timestamp;
  applyOutgoingStableIdToMessage(message, clientId);
  return message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  late TUIChatSeparateViewModel model;
  late TUIChatGlobalModel global;
  late String conv;

  setUp(() async {
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(TUIChatGlobalModel());
    conv = '@TGS#overlay-vis';
    model = TUIChatSeparateViewModel()
      ..conversationID = conv
      ..conversationType = ConvType.group
      ..chatConfig = TIMUIKitChatConfig(isShowReadingStatus: false)
      ..suppressReadReporting = true;
    global = model.globalModel;
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
  });

  tearDown(() {
    model.dispose();
  });

  List<V2TimMessage> sendingBatch() {
    final confirmed = _succ(conv: conv, seq: 102, timestamp: 1700000102);
    applyOutgoingStableIdToMessage(confirmed, 'prev-succ');
    return <V2TimMessage>[
      _overlayImage(
        conv: conv,
        clientId: 'L3',
        timestamp: 1700000105,
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING,
      ),
      _overlayImage(
        conv: conv,
        clientId: 'L2',
        timestamp: 1700000104,
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING,
      ),
      _overlayImage(
        conv: conv,
        clientId: 'L1',
        timestamp: 1700000103,
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING,
      ),
      confirmed,
      _succ(conv: conv, seq: 101, timestamp: 1700000101, isSelf: true),
      _succ(conv: conv, seq: 100, timestamp: 1700000100, isSelf: false),
    ];
  }

  void freezeLatestEdge(List<V2TimMessage> rows) {
    global.setMessageList(conv, rows, replace: true, applyMemoryWindow: false);
    model.freezeVisibleHistoryWindowIfNeeded();
    model.haveMoreLatestData = false;
  }

  test('freeze keeps SENDING on latest-edge visible timeline, not as cursor', () {
    final l1 = sendingBatch()[2];
    freezeLatestEdge(sendingBatch());

    expect(model.historyNewerPageCursor?.msgID, 'm102');
    expect(model.isMessageInHistoryReadingWindow(l1), isFalse);
    expect(model.isVisibleOnReadingTimeline(l1), isTrue);
    expect(model.isOutgoingLocalOverlayRow(l1), isTrue);
  });

  test('deep history does not attach outgoing overlay to the visible timeline',
      () {
    final rows = sendingBatch();
    final l1 = rows[2];
    freezeLatestEdge(rows);
    model.haveMoreLatestData = true;

    expect(model.shouldAttachOutgoingLocalOverlayToVisibleTimeline(), isFalse);
    expect(model.isVisibleOnReadingTimeline(l1), isFalse);
  });

  test('FAILED overlay stays visible and does not become cursor', () {
    final rows = sendingBatch();
    freezeLatestEdge(rows);
    final failed = _overlayImage(
      conv: conv,
      clientId: 'L1',
      timestamp: 1700000103,
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
    );
    global.setMessageList(
      conv,
      <V2TimMessage>[
        rows[0],
        rows[1],
        failed,
        ...rows.skip(3),
      ],
      replace: true,
      applyMemoryWindow: false,
    );

    expect(model.historyNewerPageCursor?.msgID, 'm102');
    expect(model.isOutgoingLocalOverlayRow(failed), isTrue);
    expect(model.isVisibleOnReadingTimeline(failed), isTrue);
  });

  test('own SENDING to SUCC admits cursor without dropping the row', () {
    freezeLatestEdge(sendingBatch());
    final succ = _overlayImage(
      conv: conv,
      clientId: 'L1',
      timestamp: 1700000103,
      status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      seq: 103,
    );
    expect(readOutgoingStableId(succ), 'L1');
    expect(model.isVisibleOnReadingTimeline(succ), isTrue);

    model.admitOwnConfirmedOutgoingToHistoryWindow(succ);

    expect(model.historyNewerPageCursor?.msgID, 'm103');
    expect(model.isMessageInHistoryReadingWindow(succ), isTrue);
    expect(model.isVisibleOnReadingTimeline(succ), isTrue);
    expect(
      model.isMessageInHistoryReadingWindow(
        _succ(conv: conv, seq: 102, timestamp: 1700000102),
      ),
      isTrue,
    );
  });

  test('frozen inbound stays off the reading timeline', () {
    freezeLatestEdge(sendingBatch());
    final inbound = _succ(
      conv: conv,
      seq: 200,
      timestamp: 1700000200,
      isSelf: false,
    );

    expect(model.isMessageInHistoryReadingWindow(inbound), isFalse);
    expect(model.isVisibleOnReadingTimeline(inbound), isFalse);
  });
}
