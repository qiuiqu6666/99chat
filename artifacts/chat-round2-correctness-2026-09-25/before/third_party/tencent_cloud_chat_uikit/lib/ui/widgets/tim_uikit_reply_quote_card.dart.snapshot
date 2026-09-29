import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/common_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_bubble_text_color.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_cloud_custom_data.dart';

/// 消息气泡内引用区。
class TIMUIKitReplyQuoteCard extends StatelessWidget {
  final String senderLabel;
  final V2TimMessage? contentMessage;
  final MessageRepliedData? fallbackReplyData;
  final TUIChatSeparateViewModel chatModel;
  final TUITheme theme;
  final Color bubbleColor;

  const TIMUIKitReplyQuoteCard({
    super.key,
    required this.senderLabel,
    required this.contentMessage,
    required this.chatModel,
    required this.theme,
    required this.bubbleColor,
    this.fallbackReplyData,
  });

  @override
  Widget build(BuildContext context) {
    final quoteBgColor = MessageBubbleTextColor.quoteBackground(bubbleColor);
    final quoteBorderColor = MessageBubbleTextColor.quoteBorder(bubbleColor);
    final quoteSenderColor = MessageBubbleTextColor.quoteSenderText(
      theme: theme,
      backgroundColor: bubbleColor,
    );
    final quoteContentColor = MessageBubbleTextColor.quoteContentText(
      theme: theme,
      backgroundColor: bubbleColor,
    );
    final showThumb = _shouldShowReplyQuoteThumb(contentMessage);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: quoteBgColor,
        borderRadius: BorderRadius.circular(5),
        border: Border(
          left: BorderSide(color: quoteBorderColor, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showThumb) ...[
            _ReplyQuoteThumb(message: contentMessage!),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: quoteSenderColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                TIMUIKitReplyQuoteContent.build(
                  message: contentMessage,
                  fallbackReplyData: fallbackReplyData,
                  chatModel: chatModel,
                  quoteContentColor: quoteContentColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TIMUIKitReplyQuoteContent {
  TIMUIKitReplyQuoteContent._();

  static Widget buildText(String text, Color color, {int maxLines = 1}) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: color,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  static Widget build({
    required V2TimMessage? message,
    required MessageRepliedData? fallbackReplyData,
    required TUIChatSeparateViewModel chatModel,
    required Color quoteContentColor,
  }) {
    if (message != null &&
        message.elemType == MessageElemType.V2TIM_ELEM_TYPE_FACE) {
      final customPreview =
          chatModel.chatConfig.faceReplyPreviewBuilder?.call(message);
      if (customPreview != null) {
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: kReplyQuoteThumbSize,
          ),
          child: customPreview,
        );
      }
    }
    return buildText(
      replyQuoteSummaryText(
        message: message,
        fallbackReplyData: fallbackReplyData,
        chatModel: chatModel,
      ),
      quoteContentColor,
    );
  }
}

String replyQuoteSummaryText({
  required V2TimMessage? message,
  required MessageRepliedData? fallbackReplyData,
  required TUIChatSeparateViewModel chatModel,
}) {
  if (message == null) {
    return _fallbackSummary(fallbackReplyData);
  }
  if (_isRevoked(message)) {
    return _isAdminRevoke(message)
        ? TIM_t("[消息被管理员撤回]")
        : TIM_t("[消息被撤回]");
  }
  final customAbstractMessage = chatModel.abstractMessageBuilder?.call(message);
  if (customAbstractMessage != null) {
    return customAbstractMessage;
  }
  switch (message.elemType) {
    case MessageElemType.V2TIM_ELEM_TYPE_CUSTOM:
      return TIM_t("[自定义]");
    case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
      return TIM_t("[语音消息]");
    case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
      return message.textElem?.text ?? "";
    case MessageElemType.V2TIM_ELEM_TYPE_FACE:
      return TIM_t("表情");
    case MessageElemType.V2TIM_ELEM_TYPE_FILE:
      return TIM_t("[文件消息]");
    case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
      return TIM_t("图片");
    case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
      return TIM_t("视频");
    case MessageElemType.V2TIM_ELEM_TYPE_LOCATION:
      return TIM_t("[位置]");
    case MessageElemType.V2TIM_ELEM_TYPE_MERGER:
      return TIM_t("[合并消息]");
    default:
      return _fallbackSummary(fallbackReplyData);
  }
}

String _fallbackSummary(MessageRepliedData? fallbackReplyData) {
  try {
    final repliedMessageAbstract = RepliedMessageAbstract.fromJson(
      jsonDecode(fallbackReplyData?.messageAbstract ?? ""),
    );
    if (repliedMessageAbstract.elemType ==
        MessageElemType.V2TIM_ELEM_TYPE_FACE) {
      return repliedMessageAbstract.summary ?? TIM_t("[表情消息]");
    }
    if (repliedMessageAbstract.summary?.isNotEmpty == true) {
      return repliedMessageAbstract.summary!;
    }
  } catch (_) {}
  return fallbackReplyData?.messageAbstract ?? TIM_t("[未知消息]");
}

bool _shouldShowReplyQuoteThumb(V2TimMessage? message) {
  if (message == null || _isRevoked(message)) {
    return false;
  }
  final type = message.elemType;
  return type == MessageElemType.V2TIM_ELEM_TYPE_IMAGE ||
      type == MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
}

bool _isRevoked(V2TimMessage message) {
  if (message.status == MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED) {
    return true;
  }
  try {
    final customData = jsonDecode(message.cloudCustomData ?? "{}");
    return customData["isRevoke"] == true;
  } catch (_) {
    return false;
  }
}

bool _isAdminRevoke(V2TimMessage message) {
  try {
    final customData = jsonDecode(message.cloudCustomData ?? "{}");
    return customData["revokeByAdmin"] == true;
  } catch (_) {
    return false;
  }
}

class _ReplyQuoteThumb extends StatelessWidget {
  final V2TimMessage message;

  const _ReplyQuoteThumb({required this.message});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: kReplyQuoteThumbSize,
        height: kReplyQuoteThumbSize,
        child: _thumbImage() ??
            const ColoredBox(color: Color(0xFFE8E8E8)),
      ),
    );
  }

  Widget? _thumbImage() {
    final localPath = _localThumbPath();
    if (localPath != null) {
      return Image.file(
        File(localPath),
        width: kReplyQuoteThumbSize,
        height: kReplyQuoteThumbSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Color(0xFFE8E8E8)),
      );
    }
    final url = _remoteThumbUrl();
    if (url != null) {
      return Image.network(
        url,
        width: kReplyQuoteThumbSize,
        height: kReplyQuoteThumbSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Color(0xFFE8E8E8)),
      );
    }
    return null;
  }

  String? _localThumbPath() {
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
      final fromList = _imageLocalPathByType(1) ?? _imageLocalPathByType(2);
      return fromList ?? _existingLocalPath(message.imageElem?.path);
    }
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO) {
      final video = message.videoElem;
      return _existingLocalPath(video?.localSnapshotUrl) ??
          _existingLocalPath(video?.snapshotPath);
    }
    return null;
  }

  String? _remoteThumbUrl() {
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
      return _imageRemoteUrlByType(1) ?? _imageRemoteUrlByType(2);
    }
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO) {
      return TencentUtils.checkString(message.videoElem?.snapshotUrl);
    }
    return null;
  }

  String? _imageLocalPathByType(int type) {
    return _existingLocalPath(_imageOfType(type)?.localUrl);
  }

  String? _imageRemoteUrlByType(int type) {
    return TencentUtils.checkString(_imageOfType(type)?.url);
  }

  V2TimImage? _imageOfType(int type) {
    final list = message.imageElem?.imageList;
    if (list == null) {
      return null;
    }
    for (final item in list) {
      if (item?.type == type) {
        return item;
      }
    }
    return null;
  }
}

String? _existingLocalPath(String? path) {
  final trimmed = TencentUtils.checkString(path);
  if (trimmed == null || PlatformUtils().isWeb) {
    return null;
  }
  try {
    if (File(trimmed).existsSync()) {
      return trimmed;
    }
  } catch (_) {}
  return null;
}

/// 键盘上方 Telegram 风格引用预览。
class TIMUIKitInputReplyPreview extends StatelessWidget {
  final V2TimMessage repliedMessage;
  final TUIChatSeparateViewModel chatModel;
  final TUITheme theme;
  final Color? backgroundColor;
  final VoidCallback onClose;

  const TIMUIKitInputReplyPreview({
    super.key,
    required this.repliedMessage,
    required this.chatModel,
    required this.theme,
    required this.onClose,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final barColor =
        backgroundColor ?? theme.weakBackgroundColor ?? hexToColor("f5f5f6");
    final closeColor = theme.weakTextColor ?? hexToColor("8f959e");
    final name = MessageUtils.getDisplayName(repliedMessage);
    final titleColor = theme.primaryColor ?? hexToColor("147aff");
    final summaryColor = theme.weakTextColor ?? hexToColor("8f959e");
    final showThumb = _shouldShowReplyQuoteThumb(repliedMessage);

    return Container(
      color: barColor,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showThumb) ...[
            _ReplyQuoteThumb(message: repliedMessage),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${TIM_t("回复")} $name",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: titleColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyQuoteSummaryText(
                    message: repliedMessage,
                    fallbackReplyData: null,
                    chatModel: chatModel,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: summaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onClose,
            child: Icon(Icons.cancel, color: closeColor, size: 18),
          ),
        ],
      ),
    );
  }
}
