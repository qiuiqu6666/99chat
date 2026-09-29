import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_expand.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

V2TimMessage _image(
  String id, {
  int timestamp = 1700000000,
  String seq = '0',
  bool group = false,
  bool isSelf = true,
  Map<String, Object>? localData,
}) {
  return V2TimMessage.fromJson({
    'message_msg_id': id,
    'message_server_time': timestamp,
    'message_seq': seq,
    'message_is_from_self': isSelf,
    'message_status': MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
  })
    ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
    ..groupID = group ? '@TGS#gallery-order' : null
    ..userID = group ? null : 'peer'
    ..isSelf = isSelf
    ..localCustomData = localData == null ? null : jsonEncode(localData)
    ..imageElem = V2TimImageElem(imageList: [
      V2TimImage(type: 1, url: 'https://example.com/$id.jpg'),
    ]);
}

ChatMediaPreviewBuildResult _preview(
  List<V2TimMessage> messages,
  V2TimMessage tapped,
) {
  return buildChatMediaPreviewItems(
    originList: messages,
    tappedMessage: tapped,
    types: kChatMediaPreviewImageTypes,
    heroTagBuilder: (message) => 'image_${message.msgID}',
  );
}

List<String?> _ids(Iterable<V2TimMessage> messages) =>
    messages.map((message) => message.msgID).toList();

void _expectChatOrder(
  List<V2TimMessage> messages,
  List<String> expected,
) {
  final chatNewestFirst = TUIChatGlobalModel.sortMessagesNewestFirst(messages);
  expect(_ids(chatNewestFirst.reversed), expected);
  final tapped = messages.first;
  final preview = _preview(chatNewestFirst, tapped);
  expect(_ids(preview.items.map((item) => item.message)), expected);
  expect(preview.currentItem?.message.msgID, tapped.msgID);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gallery preserves batch selection order despite completion timestamps',
      () {
    final images = [
      for (var i = 0; i < 4; i++)
        _image(
          'image_$i',
          timestamp: 1700000004 - i,
          seq: '${104 - i}',
          group: true,
          localData: {
            kChatMediaBatchIdKey: 'selected_batch',
            kChatMediaBatchIndexKey: i,
          },
        ),
    ];
    _expectChatOrder(images, ['image_0', 'image_1', 'image_2', 'image_3']);
  });

  test('gallery honors group server sequence when timestamps go backwards', () {
    _expectChatOrder([
      _image('first', timestamp: 1700000002, seq: '1477', group: true),
      _image('second', timestamp: 1700000001, seq: '1478', group: true),
    ], [
      'first',
      'second'
    ]);
  });

  test('gallery rebuild honors string group sequence instead of input order',
      () {
    final first = _image('z-first', seq: '9', group: true);
    final second = _image('a-second', seq: '10', group: true);
    _expectChatOrder([second, first], ['z-first', 'a-second']);
    expect(_ids(_preview([first, second], second).sortedMessages),
        ['z-first', 'a-second']);
  });

  test('gallery follows C2C same-second self and reply order', () {
    final self = _image('z-self', seq: '900');
    final reply = _image('a-reply', seq: '1', isSelf: false);
    _expectChatOrder([reply, self], ['z-self', 'a-reply']);
    expect(_ids(_preview([self, reply], reply).sortedMessages),
        ['z-self', 'a-reply']);
  });

  test('gallery rebuild keeps local outgoing order on timestamp ties', () {
    final first = _image('z-first', localData: {'__outgoingLocalSeq': 1});
    final second = _image('a-second', localData: {'__outgoingLocalSeq': 2});
    _expectChatOrder([second, first], ['z-first', 'a-second']);
    expect(_ids(_preview([first, second], second).sortedMessages),
        ['z-first', 'a-second']);
  });

  test('gallery uses the chat timestamp normalization and local fallback', () {
    _expectChatOrder([
      _image('milliseconds', timestamp: 1700000000000),
      _image('seconds', timestamp: 1700000001),
      _image('local', timestamp: 0, localData: {
        '__outgoingLocalSentAt': 1700000002000,
        '__outgoingLocalSeq': 1,
      }),
    ], [
      'milliseconds',
      'seconds',
      'local'
    ]);
  });

  test('local history expansion and repeated rebuilds preserve image order',
      () async {
    final images = [
      for (var i = 0; i < 4; i++)
        _image('image_$i', seq: '${100 + i}', group: true),
    ];
    final tapped = images[2];
    final expanded = await expandChatMediaGalleryMessages(
      seedNewestFirst: [images[3], tapped],
      tappedMessage: tapped,
      types: kChatMediaPreviewImageTypes,
      isPreviewable: (message) =>
          isChatMediaPreviewable(message, kChatMediaPreviewImageTypes),
      loader: ({
        required getType,
        required count,
        lastMsgID,
        lastMsg,
        required messageTypeList,
      }) async =>
          ChatMediaGalleryExpandPage(
        messages: getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG
            ? [images[1], images[0]]
            : [],
        isFinished: true,
      ),
    );
    final expected = ['image_0', 'image_1', 'image_2', 'image_3'];
    expect(_ids(expanded.messagesOldestFirst), expected);
    var current = expanded.messagesOldestFirst;
    for (var i = 0; i < 3; i++) {
      final rebuilt = _preview(current, tapped);
      expect(_ids(rebuilt.items.map((item) => item.message)), expected);
      expect(rebuilt.initialIndex, 2);
      expect(rebuilt.currentItem?.message.msgID, tapped.msgID);
      current = rebuilt.sortedMessages;
    }
  });

  test('incoming image rebuild keeps existing same-second images in chat order',
      () {
    final first = _image('z-first', seq: '101', group: true);
    final second = _image('b-second', seq: '102', group: true);
    final incoming = _image('a-third', seq: '103', group: true);
    final current = _preview([second, first], second);
    final next = appendIncomingChatMediaGalleryMessage(
      currentOldestFirst: current.sortedMessages,
      incoming: incoming,
      isPreviewable: (message) =>
          isChatMediaPreviewable(message, kChatMediaPreviewImageTypes),
    );
    final rebuilt = _preview(next, second);
    expect(_ids(rebuilt.sortedMessages), ['z-first', 'b-second', 'a-third']);
    expect(rebuilt.initialIndex, 1);
  });
}
