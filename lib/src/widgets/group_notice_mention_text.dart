import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/utils/group_mention_resolver.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/chat_id_mention_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/link_preview/common/utils.dart';

class GroupNoticeMentionText extends StatelessWidget {
  const GroupNoticeMentionText({
    super.key,
    required this.text,
    required this.style,
    required this.onTapMention,
    required this.onTapUrl,
  });

  final String text;
  final TextStyle style;
  final ValueChanged<String> onTapMention;
  final ValueChanged<String> onTapUrl;

  static const Color _urlColor = Color(0xFF1E90FF);

  @override
  Widget build(BuildContext context) {
    final mentionStyle = style.copyWith(
      color: LinkUtils.hexToColor('015fff'),
    );
    final urlStyle = style.copyWith(
      color: _urlColor,
      decoration: TextDecoration.underline,
      decorationColor: _urlColor,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(style: style, children: _buildSpans(mentionStyle, urlStyle)),
    );
  }

  List<InlineSpan> _buildSpans(TextStyle mentionStyle, TextStyle urlStyle) {
    final segments = _collectSegments(text);
    if (segments.isEmpty) {
      return <InlineSpan>[TextSpan(text: text, style: style)];
    }
    final spans = <InlineSpan>[];
    var index = 0;
    for (final segment in segments) {
      if (index < segment.start) {
        spans.add(TextSpan(text: text.substring(index, segment.start)));
      }
      final raw = text.substring(segment.start, segment.end);
      if (segment.isUrl) {
        spans.add(
          TextSpan(
            text: raw,
            style: urlStyle,
            recognizer: TapGestureRecognizer()..onTap = () => onTapUrl(raw),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: raw,
            style: mentionStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => onTapMention(
                    segment.userId ?? ChatIdMentionText.parseRawId(raw),
                  ),
          ),
        );
      }
      index = segment.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return spans;
  }

  static List<_GroupNoticeLinkSegment> _collectSegments(String text) {
    final segments = <_GroupNoticeLinkSegment>[];
    for (final match in LinkUtils.urlReg.allMatches(text)) {
      segments.add(
        _GroupNoticeLinkSegment(
          start: match.start,
          end: match.end,
          isUrl: true,
        ),
      );
    }
    if (text.contains('@')) {
      final mentions = GroupMentionResolver.resolve(text: text);
      for (final item in mentions) {
        final overlaps = segments.any(
          (segment) => item.start < segment.end && item.end > segment.start,
        );
        if (!overlaps) {
          segments.add(
            _GroupNoticeLinkSegment(
              start: item.start,
              end: item.end,
              isUrl: false,
              userId: item.isMemberWithUserId ? item.userId : null,
            ),
          );
        }
      }
    }
    segments.sort((a, b) => a.start.compareTo(b.start));
    return segments;
  }
}

class _GroupNoticeLinkSegment {
  const _GroupNoticeLinkSegment({
    required this.start,
    required this.end,
    required this.isUrl,
    this.userId,
  });

  final int start;
  final int end;
  final bool isUrl;
  final String? userId;
}
