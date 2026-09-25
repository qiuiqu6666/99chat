import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_send_status.dart';

/// 图片/视频消息发送中的进度遮罩（读取 [TUIChatGlobalModel.getMessageProgress]）。
class TimUIKitMediaUploadOverlay {
  TimUIKitMediaUploadOverlay._();

  static int resolveUploadProgress(
    TUIChatGlobalModel model,
    V2TimMessage message,
  ) {
    final byMsgId = message.msgID != null && message.msgID!.isNotEmpty
        ? model.getMessageProgress(message.msgID)
        : 0;
    final byId = message.id != null && message.id!.isNotEmpty
        ? model.getMessageProgress(message.id)
        : 0;
    return max(byMsgId, byId);
  }

  static bool shouldShowUploadOverlay(
    V2TimMessage message,
    int progress, {
    int? statusOverride,
  }) {
    if (message.isSelf != true) {
      return false;
    }
    final status = statusOverride ??
        message.status ??
        OutgoingSendStatus.unconfirmed;
    if (status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      return false;
    }
    if (status == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
      return false;
    }
    if (progress >= 100) {
      return false;
    }
    return status == MessageStatus.V2TIM_MSG_STATUS_SENDING ||
        (progress > 0 && progress < 100);
  }

  static bool supportsInlineUploadOverlay(int? elemType) {
    return elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE ||
        elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
  }

  static int effectiveMessageStatus({
    required TUIChatGlobalModel model,
    required String conversationID,
    required V2TimMessage message,
  }) {
    final fallback = message.status ?? OutgoingSendStatus.unconfirmed;
    if (message.isSelf != true) {
      return fallback;
    }
    model.messageListRevisionFor(conversationID);
    return model.messageStatusInConversation(
      conversationID,
      clientId: message.id,
      msgID: message.msgID,
      fallback: fallback,
      elemType: message.elemType,
    );
  }

  static Widget build({
    required int progress,
    required bool visible,
    VoidCallback? onCancel,
  }) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    final hasMeasuredProgress = progress > 0 && progress < 100;
    return Positioned.fill(
      child: GestureDetector(
        onTap: onCancel,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: const Color(0x80000000),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: hasMeasuredProgress
                      ? TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: progress / 100),
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          builder: (context, displayProgress, _) => CustomPaint(
                            painter: _SegmentedUploadRingPainter(
                              progress: displayProgress,
                            ),
                          ),
                        )
                      : const _RotatingUploadRing(),
                ),
                const SizedBox(height: 5),
                Text(
                  TIM_t('发送中'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RotatingUploadRing extends StatefulWidget {
  const _RotatingUploadRing();

  @override
  State<_RotatingUploadRing> createState() => _RotatingUploadRingState();
}

class _RotatingUploadRingState extends State<_RotatingUploadRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _controller,
        child: const CustomPaint(painter: _SegmentedUploadRingPainter()),
      );
}

class _SegmentedUploadRingPainter extends CustomPainter {
  const _SegmentedUploadRingPainter({this.progress});

  static const _segmentCount = 10;
  static const _strokeWidth = 3.0;
  static const _gapAngle = 0.30;

  /// Null means the SDK has not reported a measurable upload percentage yet.
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (min(size.width, size.height) - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const step = 2 * pi / _segmentCount;
    const sweep = step - _gapAngle;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    final litSegments = (progress ?? 0) * _segmentCount;

    for (var index = 0; index < _segmentCount; index++) {
      final start = -pi / 2 + index * step + _gapAngle / 2;
      if (progress == null) {
        paint.color = Colors.white.withValues(
          alpha: 0.14 + 0.86 * index / (_segmentCount - 1),
        );
        canvas.drawArc(rect, start, sweep, false, paint);
        continue;
      }

      paint.color = Colors.white.withValues(alpha: 0.18);
      canvas.drawArc(rect, start, sweep, false, paint);
      final litFraction = (litSegments - index).clamp(0.0, 1.0);
      if (litFraction <= 0) continue;
      paint.color = Colors.white.withValues(
        alpha: 0.55 + 0.45 * (index + litFraction) / litSegments,
      );
      canvas.drawArc(rect, start, sweep * litFraction, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedUploadRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 仅重建上传遮罩，避免进度更新牵动整张图片气泡。
class TimUIKitMessageUploadOverlayLayer extends StatefulWidget {
  const TimUIKitMessageUploadOverlayLayer({
    super.key,
    required this.message,
    required this.conversationID,
    required this.globalModel,
  });

  final V2TimMessage message;
  final String conversationID;
  final TUIChatGlobalModel globalModel;

  @override
  State<TimUIKitMessageUploadOverlayLayer> createState() =>
      _TimUIKitMessageUploadOverlayLayerState();
}

class _TimUIKitMessageUploadOverlayLayerState
    extends State<TimUIKitMessageUploadOverlayLayer> {
  @override
  Widget build(BuildContext context) {
    final msgKey = ChatUiStateStore.messageKeyOf(widget.message);
    context.select<ChatUiStateStore, int>(
      (store) => store.rowRevision(widget.conversationID, msgKey),
    );
    final progress = TimUIKitMediaUploadOverlay.resolveUploadProgress(
      widget.globalModel,
      widget.message,
    );
    final status = TimUIKitMediaUploadOverlay.effectiveMessageStatus(
      model: widget.globalModel,
      conversationID: widget.conversationID,
      message: widget.message,
    );
    final visible = TimUIKitMediaUploadOverlay.shouldShowUploadOverlay(
      widget.message,
      progress,
      statusOverride: status,
    );
    return TimUIKitMediaUploadOverlay.build(
      progress: progress,
      visible: visible,
    );
  }
}
