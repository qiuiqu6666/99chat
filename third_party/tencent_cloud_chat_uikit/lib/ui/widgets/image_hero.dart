import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_image_flight.dart';

/// make hero better when slide out
class HeroWidget extends StatefulWidget {
  const HeroWidget(
      {required this.child,
      required this.tag,
      required this.slidePagekey,
      this.slideType = SlideType.onlyImage,
      this.animateCornerRadius = false,
      this.cornerRadius = 10,
      Key? key})
      : super(key: key);
  final Widget child;
  final SlideType slideType;
  final Object tag;
  final GlobalKey<ExtendedImageSlidePageState> slidePagekey;

  /// 飞行时圆角是否随进度从 [cornerRadius] 渐变到 0（打开）/ 0 到 [cornerRadius]（关闭）。
  /// 微信手感：气泡圆角进入全屏时逐渐消失。
  final bool animateCornerRadius;

  /// 源（气泡）圆角，单位 px。仅 [animateCornerRadius] 为 true 时生效。
  final double cornerRadius;
  @override
  _HeroWidgetState createState() => _HeroWidgetState();
}

class _HeroWidgetState extends TIMUIKitState<HeroWidget> {
  final _imageFrame = MediaPreviewImageFrameController();

  @override
  void dispose() {
    _imageFrame.dispose();
    super.dispose();
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    return MediaPreviewImageFrameScope(
      controller: _imageFrame,
      child: Hero(
        tag: widget.tag,
        placeholderBuilder: (context, size, child) {
          return SizedBox(width: size.width, height: size.height);
        },
        // 位移只跟路由 animation，不再套一层 easeInOut，避免出手慢半拍。
        createRectTween: (Rect? begin, Rect? end) {
          // Destination layout is ready before Flutter replaces either Hero
          // with a placeholder, even if the preview has not painted yet.
          _imageFrame.capture();
          return mediaPreviewHeroRectTween(
            begin: begin,
            end: end,
          );
        },
        flightShuttleBuilder: (BuildContext flightContext,
            Animation<double> animation,
            HeroFlightDirection flightDirection,
            BuildContext fromHeroContext,
            BuildContext toHeroContext) {
          if (widget.slideType == SlideType.onlyImage) {
            final imageFlight = buildMediaPreviewImageFlight(
              fromContext: fromHeroContext,
              toContext: toHeroContext,
              animation: animation,
              direction: flightDirection,
              cornerRadius:
                  widget.animateCornerRadius ? widget.cornerRadius : 0,
            );
            if (imageFlight != null) return imageFlight;
          }
          // Loading/error placeholders and video retain the widget fallback.
          // 气泡缩略图（contain）与预览页（contain/fitWidth）的 fit 不同。
          // 官方默认用 toHero 会把 contain 图塞进气泡框（先缩出黑边再放大）。
          // push 用 contain 等比铺满插值框：保持缩略图与预览页的内容裁剪
          // 一致，避免飞行结束瞬间从"cover 裁剪"跳到"contain 完整"产生闪一下。
          final Hero fromHero = fromHeroContext.widget as Hero;
          final Widget body = flightDirection == HeroFlightDirection.push
              ? SizedBox.expand(
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      clipBehavior: Clip.hardEdge,
                      child: fromHero.child,
                    ),
                  ),
                )
              : fromHero.child;

          final slideState = widget.slidePagekey.currentState;
          final bool fixTransform =
              flightDirection == HeroFlightDirection.pop &&
                  widget.slideType == SlideType.onlyImage &&
                  slideState != null &&
                  (slideState.offset != Offset.zero || slideState.scale != 1.0);

          // 微信手感：圆角随飞行进度从气泡圆角逐渐消失到 0。
          // 打开时 10px → 0；关闭时 0 → 10px。用 AnimatedBuilder 驱动，
          // 前段快后段慢（easeOut），无 bounce/overshoot。
          final bool needsCornerTween =
              widget.animateCornerRadius && (widget.cornerRadius > 0);
          Widget flight = body;
          if (needsCornerTween) {
            flight = AnimatedBuilder(
              animation: animation,
              builder: (BuildContext context, Widget? child) {
                final t = animation.value;
                final radius = widget.cornerRadius * (1.0 - t);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: child,
                );
              },
              child: body,
            );
          }

          if (fixTransform) {
            flight = AnimatedBuilder(
              animation: animation,
              builder: (BuildContext buildContext, Widget? child) {
                return Transform.translate(
                  offset: Tween<Offset>(
                    begin: Offset.zero,
                    end: slideState.offset,
                  ).evaluate(animation),
                  child: Transform.scale(
                    scale: Tween<double>(
                      begin: 1.0,
                      end: slideState.scale,
                    ).evaluate(animation),
                    child: child,
                  ),
                );
              },
              child: flight,
            );
          }

          // The Hero itself now spans the viewport so zoom can paint there.
          // Interpolate the visible image's insets inside that flight instead of
          // changing its endpoint (which Flutter would retarget to the top left).
          final fromInsets = _flightInsets(fromHeroContext);
          final toInsets = _flightInsets(toHeroContext);
          if (fromInsets == EdgeInsets.zero && toInsets == EdgeInsets.zero) {
            return flight;
          }
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final progress = flightDirection == HeroFlightDirection.push
                  ? animation.value
                  : 1.0 - animation.value;
              return Padding(
                padding: EdgeInsets.lerp(fromInsets, toInsets, progress)!,
                child: child,
              );
            },
            child: flight,
          );
        },
        child: MediaPreviewImageSurface(
          controller: _imageFrame,
          child: widget.child,
        ),
      ),
    );
  }

  EdgeInsets _flightInsets(BuildContext heroContext) {
    final layout = MediaPreviewHeroLayout.maybeOf(heroContext);
    if (layout == null) {
      return EdgeInsets.zero;
    }
    final box = heroContext.findRenderObject()! as RenderBox;
    final content = layout.inset(Offset.zero & box.size);
    return EdgeInsets.fromLTRB(
      content.left,
      content.top,
      box.size.width - content.right,
      box.size.height - content.bottom,
    );
  }
}
