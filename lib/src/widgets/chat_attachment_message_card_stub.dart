import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';

class ChatAttachmentMessageCard extends StatelessWidget {
  const ChatAttachmentMessageCard(
      {super.key,
      required this.attachment,
      this.isSelf = false,
      this.message,
      this.conversationID,
      this.chatModel});
  final ChatAttachment attachment;
  final bool isSelf;
  final V2TimMessage? message;
  final String? conversationID;
  final TUIChatSeparateViewModel? chatModel;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(12),
      child: Text('${attachment.preview}\n请在新版 Android 或 iOS 客户端查看'));
}
