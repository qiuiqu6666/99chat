import 'package:flutter/material.dart';
import 'lottery_theme.dart';
import 'test_page.dart';
import '../../ui/app_tokens.dart';

Future<void> showLotteryDrawer(BuildContext context,
    {required String groupUid, String? gameId, double? anchorY}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final cardKey = GlobalKey();
  var expanding = false;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭开奖预览',
    barrierColor: Colors.black12,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => SafeArea(
      right: false,
      child: CustomSingleChildLayout(
        delegate: _LotteryPreviewPosition(
          anchorY == null ? null : anchorY - MediaQuery.paddingOf(context).top,
          MediaQuery.devicePixelRatioOf(context),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: SizedBox(
            key: const ValueKey('lottery-latest-preview'),
            width: (MediaQuery.sizeOf(context).width * .88).clamp(0.0, 520.0),
            child: Material(
              color: Colors.transparent,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Semantics(
                  key: cardKey,
                  button: true,
                  label: '全屏查看开奖记录',
                  child: InkWell(
                    key: const ValueKey('lottery-preview-open'),
                    onTap: () {
                      if (expanding) return;
                      final box = cardKey.currentContext?.findRenderObject()
                          as RenderBox?;
                      if (box == null) return;
                      expanding = true;
                      final origin = box.localToGlobal(Offset.zero) & box.size;
                      navigator
                          .pushReplacement<void, void>(PageRouteBuilder<void>(
                        transitionDuration: const Duration(milliseconds: 380),
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (_, __, ___) =>
                            TestPage(groupUid: groupUid, gameId: gameId),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          final size = MediaQuery.sizeOf(context);
                          final t =
                              Curves.easeInOutCubic.transform(animation.value);
                          final rect =
                              Rect.lerp(origin, Offset.zero & size, t)!;
                          return Stack(children: [
                            Positioned.fromRect(
                              rect: rect,
                              child: ClipRRect(
                                key: const ValueKey('lottery-card-expansion'),
                                borderRadius:
                                    BorderRadius.circular(16 * (1 - t)),
                                child: Material(
                                    color: lotteryThemeColor(context,
                                        Colors.white, AppTokens.surfaceDark),
                                    child: Stack(children: [
                                      OverflowBox(
                                        alignment: Alignment.topLeft,
                                        minWidth: size.width,
                                        maxWidth: size.width,
                                        minHeight: size.height,
                                        maxHeight: size.height,
                                        child:
                                            Opacity(opacity: t, child: child),
                                      ),
                                      if (t < 1)
                                        IgnorePointer(
                                            child: Opacity(
                                          opacity: (1 - t * 2).clamp(0.0, 1.0),
                                          child: SizedBox(
                                              width: double.infinity,
                                              child: LotteryLatestPreview(
                                                  gameId: gameId)),
                                        )),
                                    ])),
                              ),
                            ),
                          ]);
                        },
                      ));
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      key: const ValueKey('lottery-preview-card-shell'),
                      height: 160,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            lotteryThemeColor(context, const Color(0xFFFAFCFF),
                                AppTokens.surfaceDark),
                            lotteryThemeColor(context, const Color(0xFFF0F6FF),
                                AppTokens.surfaceDark),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: lotteryThemeColor(context,
                                const Color(0xFFD8E6FC), AppTokens.borderDark)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F17243D),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          )
                        ],
                      ),
                      child: Stack(children: [
                        Positioned(
                          right: 6,
                          bottom: 8,
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Opacity(
                                opacity: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? 0.14
                                    : 0.20,
                                child: Image.asset(
                                  'assets/lhc/latest_card_watermark.png',
                                  key: const ValueKey(
                                      'lottery-latest-watermark'),
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Column(children: [
                          Expanded(
                              child: LayoutBuilder(
                            builder: (context, constraints) =>
                                SingleChildScrollView(
                                    child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight),
                              child: Center(
                                  child: LotteryLatestPreview(gameId: gameId)),
                            )),
                          )),
                          Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text('点击卡片 · 全屏查看开奖记录',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: lotteryThemeColor(
                                        context,
                                        const Color(0xFF4B586D),
                                        AppTokens.textSecondaryDark),
                                    fontWeight: FontWeight.w500)),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _LotteryPreviewPosition extends SingleChildLayoutDelegate {
  const _LotteryPreviewPosition(this.anchorY, this.pixelRatio);
  final double? anchorY;
  final double pixelRatio;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxY = (size.height - childSize.height).clamp(0.0, double.infinity);
    final y =
        ((anchorY ?? size.height * .3) - childSize.height / 2).clamp(0.0, maxY);
    final snappedY = (y * pixelRatio).round() / pixelRatio;
    return Offset(size.width - childSize.width,
        snappedY.clamp(0.0, (maxY * pixelRatio).floor() / pixelRatio));
  }

  @override
  bool shouldRelayout(_LotteryPreviewPosition oldDelegate) =>
      anchorY != oldDelegate.anchorY || pixelRatio != oldDelegate.pixelRatio;
}
