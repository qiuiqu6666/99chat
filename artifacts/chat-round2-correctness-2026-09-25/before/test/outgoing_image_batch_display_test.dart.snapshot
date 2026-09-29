import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_image_batch_display.dart';

V2TimMessage image(String id, {String batch = 'gallery', bool self = true}) {
  final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
    ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
    ..isSelf = self
    ..status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
  applyOutgoingStableIdToMessage(message, id);
  applyChatMediaBatchToMessage(message, batchId: batch, batchIndex: 0);
  return message;
}

void main() {
  test('two or more pending local gallery images display immediately', () {
    expect(isNewOutgoingImageBatch([image('1'), image('2')]), isTrue);
    expect(
      isNewOutgoingImageBatch(List.generate(9, (i) => image('$i'))),
      isTrue,
    );
  });

  test('single sends and different batches keep normal viewport behavior', () {
    expect(isNewOutgoingImageBatch([]), isFalse);
    expect(isNewOutgoingImageBatch([image('1')]), isFalse);
    expect(
      isNewOutgoingImageBatch([image('1'), image('2', batch: 'other')]),
      isFalse,
    );
    expect(isNewOutgoingImageBatch([image('same'), image('same')]), isFalse);
  });

  test('received media, history and upload completion never trigger a jump', () {
    expect(
      isNewOutgoingImageBatch([image('1', self: false), image('2', self: false)]),
      isFalse,
    );
    for (final status in [
      MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
    ]) {
      expect(
        isNewOutgoingImageBatch([
          image('1')..status = status,
          image('2')..status = status,
        ]),
        isFalse,
      );
    }
  });

  test('video, missing metadata and corrupt metadata are not image batches', () {
    expect(
      isNewOutgoingImageBatch([
        image('1'),
        image('2')..elemType = MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
      ]),
      isFalse,
    );
    for (final metadata in [null, '', '{broken', '{}']) {
      expect(
        isNewOutgoingImageBatch([
          image('1'),
          image('2')..localCustomData = metadata,
        ]),
        isFalse,
      );
    }
  });
}
