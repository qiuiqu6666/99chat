import 'package:extended_text/extended_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/emoji_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/link_preview/common/utils.dart';
import 'package:tim_ui_kit_sticker_plugin/utils/tim_custom_face_data.dart';

class MentionWrapSpan {
  final int start;
  final int end;
  final String? memberUserId;

  const MentionWrapSpan({
    required this.start,
    required this.end,
    this.memberUserId,
  });
}

class ChatIdMentionText extends SpecialText {
  ChatIdMentionText(
    TextStyle? textStyle,
    SpecialTextGestureTapCallback? onTap, {
    this.start,
    this.isUseQQPackage = false,
    this.isUseTencentCloudChatPackage = false,
    this.isUseTencentCloudChatPackageOldKeys = false,
    this.customEmojiStickerList = const [],
  }) : super(flag, flag, textStyle, onTap: onTap);

  static const String flag = '!@99CHATID#*&\$';
  static const String payloadSep = '\u0001';
  static final RegExp _bracketTokenReg = RegExp(r'\[[^\[\]]+\]');

  final int? start;
  final bool isUseQQPackage;
  final bool isUseTencentCloudChatPackage;
  final bool isUseTencentCloudChatPackageOldKeys;
  final List<CustomEmojiFaceData> customEmojiStickerList;

  static String parseRawId(String mentionText) {
    final trimmed = mentionText.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    // 完整/公开群 ID（含中间 `@`）保留原样，供加群解析。
    if (trimmed.toUpperCase().contains('TGS#')) {
      return trimmed.startsWith('@') ? trimmed : '@$trimmed';
    }
    if (trimmed.startsWith('@')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  static String encodeSpan(String displayText, {String? memberUserId}) {
    final userId = memberUserId?.trim() ?? '';
    if (userId.isEmpty) {
      return displayText;
    }
    return '$displayText${payloadSep}m$payloadSep$userId';
  }

  static String visibleText(String content) {
    final sep = content.indexOf(payloadSep);
    if (sep < 0) {
      return content;
    }
    return content.substring(0, sep);
  }

  static String tapToken(String content) {
    final parts = content.split(payloadSep);
    if (parts.length >= 3 && parts[1] == 'm' && parts[2].trim().isNotEmpty) {
      return parts[2].trim();
    }
    return parseRawId(visibleText(content));
  }

  @override
  InlineSpan finishText() {
    final String raw = getContent();
    final String text = visibleText(raw);
    final linkColor = LinkUtils.hexToColor('015fff');
    final mentionStyle = TextStyle(color: linkColor);
    final children = _inlineChildren(text, mentionStyle);
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        if (onTap != null) {
          onTap!(tapToken(raw));
        }
      };

    if (children == null) {
      return SpecialTextSpan(
        text: text,
        actualText: toString(),
        start: start!,
        deleteAll: true,
        style: mentionStyle,
        recognizer: recognizer,
      );
    }
    return SpecialTextSpan(
      text: '',
      actualText: toString(),
      start: start!,
      deleteAll: true,
      style: mentionStyle,
      children: children,
      recognizer: recognizer,
    );
  }

  List<InlineSpan>? _inlineChildren(String text, TextStyle mentionStyle) {
    if (!text.contains('[')) {
      return null;
    }
    final children = <InlineSpan>[];
    var index = 0;
    var spanStart = start ?? 0;
    for (final match in _bracketTokenReg.allMatches(text)) {
      if (index < match.start) {
        final chunk = text.substring(index, match.start);
        children.add(TextSpan(text: chunk, style: mentionStyle));
        spanStart += chunk.length;
      }
      final token = match.group(0)!;
      children.add(
        EmojiText.spanForBracketToken(
              token: token,
              textStyle: mentionStyle,
              start: spanStart,
              isUseQQPackage: isUseQQPackage,
              isUseTencentCloudChatPackage: isUseTencentCloudChatPackage,
              isUseTencentCloudChatPackageOldKeys:
                  isUseTencentCloudChatPackageOldKeys,
              customEmojiStickerList: customEmojiStickerList,
            ) ??
            TextSpan(text: token, style: mentionStyle),
      );
      spanStart += token.length;
      index = match.end;
    }
    if (index < text.length) {
      children.add(
        TextSpan(text: text.substring(index), style: mentionStyle),
      );
    }
    return children;
  }
}
