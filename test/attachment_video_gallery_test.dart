import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/platform/attachment_video_gallery_io.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';

V2TimMessage message(String id, int time,
    {bool attachment = false, String kind = 'video'}) {
  final m = V2TimMessage.fromJson({
    'message_msg_id': id,
    'message_server_time': time,
    'message_risk_type_identified': 0
  });
  if (attachment) {
    m.elemType = 2;
    m.customElem = V2TimCustomElem(
        data: jsonEncode(ChatAttachment(
                attachmentId: id,
                referenceId: 'ref-$id',
                kind: kind,
                name: 'movie.mp4',
                sizeBytes: 200000000,
                mimeType: 'video/mp4')
            .toJson()));
  } else {
    m.elemType = 5;
    m.videoElem = V2TimVideoElem(videoUrl: 'https://native.example/$id');
  }
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installAttachmentVideoGallery);
  tearDown(() => externalChatMediaPreviewItem = null);
  test(
      'native and large videos share ordering and tapped index from either entry',
      () {
    final first = message('native', 1);
    final large = message('large', 2, attachment: true);
    final last = message('last', 3);
    final file = message('file', 4, attachment: true, kind: 'file');
    for (final tapped in [first, large, last]) {
      final result = buildChatMediaPreviewItems(
          originList: [last, file, large, first, large],
          tappedMessage: tapped,
          types: const {ChatMediaPreviewType.video},
          heroTagBuilder: (m) => m.msgID!);
      expect(result.items.map((i) => i.message.msgID),
          ['native', 'large', 'last']);
      expect(result.currentItem!.message.msgID, tapped.msgID);
      expect(result.items[1].resolveVideo, isNotNull);
      expect(result.items[0].resolveVideo, isNull);
      expect(result.items[1].heroTag, 'attachment-video:large:ref-large');
    }
    // Collection is synchronous and must never download or mutate IM messages.
    expect(large.elemType, 2);
    expect(large.videoElem, isNull);
  });
  test('attachment absent from loaded history can still be the tapped item',
      () {
    final tapped = message('large', 2, attachment: true);
    final result = buildChatMediaPreviewItems(
        originList: [message('native', 1)],
        tappedMessage: tapped,
        types: const {ChatMediaPreviewType.video},
        heroTagBuilder: (m) => m.msgID!);
    expect(result.items, hasLength(2));
    expect(result.currentItem!.message.msgID, 'large');
  });
  test('disabled host adapter leaves native collector behavior intact', () {
    externalChatMediaPreviewItem = null;
    final native = message('native', 1);
    final result = buildChatMediaPreviewItems(
        originList: [native, message('large', 2, attachment: true)],
        tappedMessage: native,
        types: const {ChatMediaPreviewType.video},
        heroTagBuilder: (m) => m.msgID!);
    expect(result.items, hasLength(1));
  });
}
