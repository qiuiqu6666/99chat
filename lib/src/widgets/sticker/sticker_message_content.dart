import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_face_bubble.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// The message list owns the timestamp; the sticker only renders its image.
class StickerMessageContent extends StatelessWidget {
  const StickerMessageContent({
    super.key,
    required this.data,
    required this.message,
  });

  final String data;
  final V2TimMessage message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: StickerFaceBubble(data: data),
      );
}
