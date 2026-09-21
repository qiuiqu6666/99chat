import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_bubble_insert_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

V2TimMessage _message(String id, int elemType) => V2TimMessage.fromJson(
      <String, dynamic>{
        'message_msg_id': id,
        'message_server_time': 1,
        'message_risk_type_identified': 0,
        'message_sender_group_member_info': <String, dynamic>{},
        'message_group_at_user_array': <String>[],
      },
    )
      ..msgID = id
      ..elemType = elemType;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
  });

  for (final chatIsNewer in <bool>[false, true]) {
    for (final sameSecond in <bool>[false, true]) {
      test(
          'preview reconciles chat window: newer=$chatIsNewer sameSecond=$sameSecond',
          () {
        final model = serviceLocator<TUIChatGlobalModel>();
        const key = 'c2c_preview_source_peer';
        addTearDown(() => model.removeMessageList(key));
        final older = _message('older', MessageElemType.V2TIM_ELEM_TYPE_TEXT)
          ..timestamp = 100
          ..seq = '10';
        final newer = _message('newer', MessageElemType.V2TIM_ELEM_TYPE_TEXT)
          ..timestamp = sameSecond ? 100 : 200
          ..seq = '11';
        model.setMessageList(
          key,
          <V2TimMessage>[chatIsNewer ? newer : older],
          needResetNewMessageCount: false,
          replace: true,
        );
        final conversation = V2TimConversation(
          conversationID: key,
          userID: 'preview_source_peer',
          type: 1,
          lastMessage: chatIsNewer ? older : newer,
        );
        expect(
          ConversationPreviewHistorySync.resolveFromChatVisibleProjection(
            globalModel: model,
            conversation: conversation,
          )?.msgID,
          'newer',
        );
      });
    }
  }

  test('visible projection prefers overlay call bubble over older lastMessage',
      () {
    final model = serviceLocator<TUIChatGlobalModel>();
    const key = 'c2c_overlay_preview_peer';
    addTearDown(() => model.removeMessageList(key));
    final older = _message('older_text', MessageElemType.V2TIM_ELEM_TYPE_TEXT)
      ..timestamp = 100
      ..seq = '10';
    model.setMessageList(
      key,
      <V2TimMessage>[older],
      needResetNewMessageCount: false,
      replace: true,
    );
    final overlay = CallBubbleInsertService.buildTerminalBubbleMessage(
      CallResultRecord(
        callId: 'ov',
        conversationId: key,
        callerUserId: 'self',
        operatorUserId: 'self',
        peerUserId: 'overlay_preview_peer',
        protocolType: CallProtocolType.cancel,
        durationSec: 0,
        endedAtMs: 200000,
        isOutgoing: true,
      ),
    )!;
    final store = LocalMessageOverlayStore.instance;
    store.resetForTesting();
    addTearDown(store.resetForTesting);
    expect(store.upsert(key, overlay), isTrue);
    final conversation = V2TimConversation(
      conversationID: key,
      userID: 'overlay_preview_peer',
      type: 1,
      lastMessage: older,
    );
    expect(
      ConversationPreviewHistorySync.resolveFromChatVisibleProjection(
        globalModel: model,
        conversation: conversation,
      )?.msgID,
      'local_call_bubble_ov',
    );
  });

  test('conversation preview selects newest real chat-visible message', () {
    final loading = _message('loading', 101);
    final divider = _message('divider', MessageElemType.V2TIM_ELEM_TYPE_NONE);
    final newest = _message('newest', MessageElemType.V2TIM_ELEM_TYPE_TEXT);
    final older = _message('older', MessageElemType.V2TIM_ELEM_TYPE_TEXT);

    final selected = ConversationPreviewHistorySync.latestVisibleChatMessage(
      <V2TimMessage>[loading, divider, newest, older],
    );
    expect(selected?.msgID, 'newest');
  });

  test('conversation preview returns null when chat projection has no message',
      () {
    expect(
      ConversationPreviewHistorySync.latestVisibleChatMessage(
        <V2TimMessage>[_message('divider', 11), _message('loading', 101)],
      ),
      isNull,
    );
  });
}
