import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/customer_service/customer_service_static_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';

/// 在线客服：底部固定 80% 高度面板（非可拖拽 BottomSheet），顶部圆角。
class CustomerServiceSheet extends StatelessWidget {
  const CustomerServiceSheet({super.key, this.guest = false});

  /// 预留给后续身份层。
  // ignore: unused_field
  final bool guest;

  static const double sheetHeightFactor = 0.8;
  static const double sheetTopRadius = 16;
  static const BorderRadius sheetBorderRadius = BorderRadius.vertical(
    top: Radius.circular(sheetTopRadius),
  );

  static Future<void> show(BuildContext context, {bool guest = false}) {
    final i18n = AppI18n.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = screenHeight * sheetHeightFactor;

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: i18n.t(
        zhHans: '关闭在线客服',
        zhHant: '關閉線上客服',
        en: 'Dismiss customer service',
        ja: 'オンラインサポートを閉じる',
        ko: '고객센터 닫기',
      ),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: sheetHeight,
            width: double.infinity,
            child: CustomerServiceSheet(guest: guest),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final background =
        theme.weakBackgroundColor ?? theme.wideBackgroundColor ?? Colors.white;
    // 面板贴屏幕底边，高度固定 80%；键盘只压缩内部底边，不把整块上推。
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final bottomGap = keyboard > 0 ? keyboard : media.padding.bottom;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: CustomerServiceSheet.sheetBorderRadius,
        ),
        child: ClipRRect(
          borderRadius: CustomerServiceSheet.sheetBorderRadius,
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: bottomGap,
                child: const CustomerServiceStaticPage(),
              ),
              if (keyboard == 0 && media.padding.bottom > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: media.padding.bottom,
                  // 与底部输入条同色，避免安全区一条异色缝。
                  child: const ColoredBox(color: Colors.white),
                ),
              const Positioned(
                top: 0,
                right: 0,
                child: _SheetCloseButtonAnchor(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetCloseButtonAnchor extends StatelessWidget {
  const _SheetCloseButtonAnchor();

  @override
  Widget build(BuildContext context) {
    return _SheetCloseButton(
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}

class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);

    // 热区略大于圆钮；圆钮本身 top/right=0 贴弹窗最边缘，
    // 外侧被面板 ClipRRect 圆角裁切，形成角上圆标。
    return Tooltip(
      message: i18n.t(
        zhHans: '关闭',
        zhHant: '關閉',
        en: 'Close',
        ja: '閉じる',
        ko: '닫기',
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Align(
              alignment: Alignment.topRight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x8A000000),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: _size,
                  height: _size,
                  child: Center(
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
