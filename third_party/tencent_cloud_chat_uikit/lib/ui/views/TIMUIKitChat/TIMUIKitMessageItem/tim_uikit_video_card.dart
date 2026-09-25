import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';

/// Common video bubble; storage, download, gestures and preview stay with callers.
class TIMUIKitVideoCard extends StatelessWidget {
  const TIMUIKitVideoCard(
      {super.key,
      required this.aspectRatio,
      required this.cover,
      this.durationMs,
      this.showPlayButton = true,
      this.overlay,
      this.centerControl});

  static const borderRadius = BorderRadius.all(Radius.circular(16));
  final double aspectRatio;
  final Widget cover;
  final int? durationMs;
  final bool showPlayButton;
  final Widget? overlay, centerControl;

  static String durationLabel(int? milliseconds) {
    if (milliseconds == null || milliseconds <= 0) return '视频';
    final seconds = (milliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final scale = TUIKitScreenUtils.compactChatCardScale(context);
      final maxWidth = (kIsWeb
          ? kChatVideoBubbleMaxWidthWeb
          : constraints.hasBoundedWidth
              ? constraints.maxWidth * kChatVideoBubbleWidthFactor
              : kChatVideoBubbleMaxLogicalWidth) *
          scale;
      final maxHeight = (constraints.hasBoundedHeight
          ? math.min(constraints.maxHeight * .8, kChatVideoBubbleMaxHeight)
          : kChatVideoBubbleMaxHeight) *
          scale;
      final ratio =
          aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 9 / 16;
      final width = math.min(maxWidth, maxHeight * ratio);
      return ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
            width: width,
            height: width / ratio,
            child: Stack(fit: StackFit.expand, children: [
              AspectRatio(
                  aspectRatio: ratio,
                  child: const ColoredBox(color: Color(0xff30343b))),
              cover,
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 42 * scale,
                  child: const IgnorePointer(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                        Color(0x00000000),
                        Color(0x8C000000)
                      ]))))),
              if (centerControl != null)
                Center(child: centerControl!)
              else if (showPlayButton)
                Center(
                    child: Image.asset('images/play.png',
                        package: 'tencent_cloud_chat_uikit',
                        height: 46 * scale)),
              Positioned(
                  left: 8,
                  bottom: 6 * scale,
                  child: IgnorePointer(
                      child: Text(durationLabel(durationMs),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12 * scale)))),
              if (overlay != null) overlay!,
            ])),
      );
    });
  }
}
