import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

V2TimMessage imageMessage(int index, {bool sent = false}) {
  final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
    ..id = 'local-image-$index'
    ..msgID = sent ? 'server-image-$index' : null
    ..elemType = 3
    ..isSelf = true
    ..sender = 'sender'
    ..timestamp = 1700000000 + index
    ..status = sent ? 2 : 1
    ..imageElem = V2TimImageElem(path: '/tmp/image-$index.jpg');
  applyOutgoingStableIdToMessage(message, 'image-$index');
  return message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  test('every insertion is visible when reads interleave within one batch', () {
    final model = serviceLocator<TUIChatGlobalModel>();
    const conversation = 'c2c_image-batch-visibility';
    for (var i = 0; i < 20; i++) {
      final message = imageMessage(i);
      final commit = model.commitMessageDelta(MessageDelta<V2TimMessage>(
        conversationKey: conversation,
        eventID: 'batch-insert-$i',
        kind: MessageDeltaKind.optimisticInsert,
        source: MessageDeltaSource.sendPipeline,
        generation: model.messageDeltaGenerationFor(conversation),
        clearEpoch: model.messageDeltaClearEpochFor(conversation),
        upserts: [model.messageDeltaRecord(message)],
      ));
      expect(commit, isNotNull);
      expect(model.rawMessageList(conversation), hasLength(i + 1));
      expect(model.getMessageList(conversation)!.where((m) => m.elemType == 3),
          hasLength(i + 1),
          reason: 'visible batch after insertion $i');
    }
  });

  test('acknowledgement updates the image without changing list revision',
      () async {
    final model = serviceLocator<TUIChatGlobalModel>();
    const conversation = 'c2c_image-batch-ack';
    model.setMessageList(conversation, [imageMessage(1), imageMessage(0)],
        replace: true);
    await Future<void>.delayed(Duration.zero);
    model.getMessageList(conversation);
    final revision = model.messageListRevisionFor(conversation);
    final result = model.replaceMessageRowByStableIdentity(
      conversationID: conversation,
      stableIdentity: 'image-0',
      replacement: imageMessage(0, sent: true),
    );
    expect(result, RowLocalMessageReplacementResult.replaced);
    expect(model.messageListRevisionFor(conversation), revision);
    expect(model.rawMessageList(conversation)!.last.status, 2);
    expect(
        model
            .getMessageList(conversation)!
            .firstWhere((m) => m.id == 'local-image-0')
            .status,
        2);
  });

  for (final group in [false, true]) {
    test('out-of-order batch receipts preserve visible rows: group=$group',
        () async {
      final model = serviceLocator<TUIChatGlobalModel>();
      final conversation =
          group ? '@TGS#image-batch' : 'c2c_image-batch-receipts';
      final images = List.generate(20, (i) {
        final message = imageMessage(i);
        if (group) message.groupID = conversation;
        applyChatMediaBatchToMessage(message,
            batchId: conversation, batchIndex: i);
        model.assignOutgoingLocalSeq(conversation, message);
        return message;
      });
      model.setMessageList(conversation, images.reversed.toList(),
          replace: true);
      await Future<void>.delayed(Duration.zero);
      final revision = model.messageListRevisionFor(conversation);
      final ui = serviceLocator<ChatUiStateStore>();
      var listNotifications = 0;
      void onListChanged() => listNotifications++;
      model.addListener(onListChanged);
      addTearDown(() => model.removeListener(onListChanged));
      final expectedIds = images.reversed.map((m) => m.id).toList();
      for (final index in [
        9,
        0,
        19,
        3,
        15,
        1,
        18,
        8,
        17,
        2,
        16,
        4,
        14,
        5,
        13,
        6,
        12,
        7,
        11,
        10
      ]) {
        final before = ui.rowRevision(conversation, 'local-image-$index');
        final receipt = imageMessage(index, sent: true);
        if (group) {
          receipt.groupID = conversation;
          receipt.seq = '${200 + index}';
        }
        // Native receipts may omit our local metadata. updateMessage must
        // retain the batch identity/order and the already displayed preview.
        receipt.localCustomData = null;
        model.updateMessage(
          V2TimValueCallback<V2TimMessage>(code: 0, desc: '', data: receipt),
          conversation,
          'local-image-$index',
          group ? ConvType.group : ConvType.c2c,
          null,
          null,
        );
        await Future<void>.delayed(Duration.zero);
        expect(model.messageListRevisionFor(conversation), revision);
        expect(ui.rowRevision(conversation, 'local-image-$index'),
            greaterThan(before));
        final visible = model
            .getMessageList(conversation)!
            .where((m) => m.elemType == 3)
            .toList();
        expect(visible.map((m) => m.id), expectedIds);
        expect(
            visible.firstWhere((m) => m.id == 'local-image-$index').status, 2);
      }
      expect(listNotifications, 0);
    });
  }

  test('in-flight history cannot hide images or overwrite their receipts', () {
    final model = serviceLocator<TUIChatGlobalModel>();
    const conversation = 'c2c_image-batch-history';
    final request = model.beginHistoryReconciliation(
      conversationID: conversation,
      requestedSource: MessageReconciliationSource.cloud,
      networkState: MessageReconciliationNetworkState.online,
    );
    for (var i = 0; i < 6; i++) {
      for (final sent in [false, true]) {
        model.commitMessageDelta(MessageDelta<V2TimMessage>(
          conversationKey: conversation,
          eventID: 'history-send-$i-$sent',
          kind: sent
              ? MessageDeltaKind.optimisticAdoption
              : MessageDeltaKind.optimisticInsert,
          source: MessageDeltaSource.sendPipeline,
          generation: model.messageDeltaGenerationFor(conversation),
          clearEpoch: model.messageDeltaClearEpochFor(conversation),
          upserts: [model.messageDeltaRecord(imageMessage(i, sent: sent))],
        ));
        expect(
            model.getMessageList(conversation)!.where((m) => m.elemType == 3),
            hasLength(i + 1));
      }
    }
    final completed = model.completeHistoryReconciliation(
      request: request,
      history: [imageMessage(0)],
      actualSource: MessageReconciliationSource.cloud,
      networkState: MessageReconciliationNetworkState.online,
    );
    expect(completed, isNotNull);
    final visible =
        model.getMessageList(conversation)!.where((m) => m.elemType == 3);
    expect(visible, hasLength(6));
    expect(visible.every((m) => m.status == 2), isTrue);
  });
}
