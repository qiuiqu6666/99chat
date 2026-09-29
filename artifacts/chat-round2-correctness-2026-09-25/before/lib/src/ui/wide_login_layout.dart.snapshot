import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/auth_localizations.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

/// 宽屏登录页视觉壳。仅登录页在宽度 ≥ 900 时使用；窄屏 / 移动端不走这里。
class WideLoginLayout extends StatelessWidget {
  const WideLoginLayout({
    super.key,
    required this.brandName,
    required this.form,
    required this.methodIndex,
    required this.showQrTab,
    required this.showRegisterForm,
    required this.onMethodSelected,
    required this.onRegisterTap,
    required this.onBackToLogin,
    this.headerTools,
    this.footer,
    this.showRegisterEntry = false,
  });

  final String brandName;
  final Widget form;
  final int methodIndex;
  final bool showQrTab;
  final bool showRegisterForm;
  final bool showRegisterEntry;
  final ValueChanged<int> onMethodSelected;
  final VoidCallback onRegisterTap;
  final VoidCallback onBackToLogin;
  final Widget? headerTools;
  final Widget? footer;

  static const Color pageTint = Color(0xFFE8F2FC);

  @override
  Widget build(BuildContext context) {
    final strings = AuthLocalizations.of(context);
    final page = ColoredBox(
      color: pageTint,
      child: Stack(
        children: [
          const Positioned.fill(child: _WideLoginBackdrop()),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1080,
                  maxHeight: 680,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B6FA8).withValues(alpha: 0.14),
                        blurRadius: 40,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 11,
                          child: _WideLoginBrandPanel(
                            brandName: brandName,
                            strings: strings,
                          ),
                        ),
                        Expanded(
                          flex: 12,
                          child: _WideLoginFormPanel(
                            strings: strings,
                            form: form,
                            methodIndex: methodIndex,
                            showQrTab: showQrTab,
                            showRegisterForm: showRegisterForm,
                            onMethodSelected: onMethodSelected,
                            onRegisterTap: onRegisterTap,
                            onBackToLogin: onBackToLogin,
                            headerTools: headerTools,
                            footer: footer,
                            showRegisterEntry: showRegisterEntry,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!PlatformUtils().isWindows) {
      return page;
    }
    return Column(
      children: [
        const _WideLoginWindowCaptionBar(),
        Expanded(child: page),
      ],
    );
  }
}

class _WideLoginBackdrop extends StatelessWidget {
  const _WideLoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFD4E6F8),
            Color(0xFFEAF3FC),
            Color(0xFFD7E8F7),
          ],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _WideLoginBrandPanel extends StatelessWidget {
  const _WideLoginBrandPanel({
    required this.brandName,
    required this.strings,
  });

  final String brandName;
  final AuthLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final family = AppTokens.fontFamilyOf(context);
    final fallback = AppTokens.fontFamilyFallbackOf(context);
    final drag = PlatformUtils().isWindows;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(44, 42, 36, 28),
      child: Column(
        children: [
          const SizedBox(height: 18),
          _BrandMark(brandName: brandName, family: family, fallback: fallback),
          const SizedBox(height: 10),
          Text(
            strings.wideLoginTagline,
            style: TextStyle(
              fontFamily: family,
              fontFamilyFallback: fallback,
              fontSize: 13,
              letterSpacing: 6,
              color: const Color(0xFF8A97A8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 28),
          Transform.rotate(
            angle: -0.08,
            child: Text(
              '${strings.wideLoginSloganLine1}\n${strings.wideLoginSloganLine2}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: family,
                fontFamilyFallback: fallback,
                fontSize: 20,
                height: 1.45,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(child: _WideLoginHeroArt()),
          Text(
            strings.wideLoginBrandFooter,
            style: TextStyle(
              fontFamily: family,
              fontFamilyFallback: fallback,
              fontSize: 12,
              color: const Color(0xFF9AA6B4),
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE7F3FC),
            Color(0xFFF4F9FE),
          ],
        ),
      ),
      child: drag ? MoveWindow(child: content) : content,
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({
    required this.brandName,
    required this.family,
    required this.fallback,
  });

  final String brandName;
  final String? family;
  final List<String>? fallback;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 46,
          height: 38,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7CBCFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 0,
                child: Container(
                  width: 32,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F8DFF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          brandName,
          style: TextStyle(
            fontFamily: family,
            fontFamilyFallback: fallback,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A2332),
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _WideLoginHeroArt extends StatelessWidget {
  const _WideLoginHeroArt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 280,
        height: 250,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 18,
              bottom: 36,
              child: Transform.rotate(
                angle: -0.38,
                child: _glassCard(
                  width: 118,
                  height: 148,
                  color: const Color(0xFFB9D8FB),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7EB6F5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 28,
              bottom: 28,
              child: Transform.rotate(
                angle: 0.22,
                child: _glassCard(
                  width: 128,
                  height: 158,
                  color: const Color(0xFFD6E8FB),
                ),
              ),
            ),
            Positioned(
              top: 18,
              child: Transform.rotate(
                angle: 0.08,
                child: _glassCard(
                  width: 148,
                  height: 168,
                  color: const Color(0xFFEAF4FF),
                  child: Center(
                    child: Container(
                      width: 72,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B8DFF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              right: 8,
              top: 36,
              child: Icon(
                Icons.send_rounded,
                size: 36,
                color: Color(0xFF5BA3F5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassCard({
    required double width,
    required double height,
    required Color color,
    Widget? child,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6EA4E0).withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WideLoginFormPanel extends StatelessWidget {
  const _WideLoginFormPanel({
    required this.strings,
    required this.form,
    required this.methodIndex,
    required this.showQrTab,
    required this.showRegisterForm,
    required this.showRegisterEntry,
    required this.onMethodSelected,
    required this.onRegisterTap,
    required this.onBackToLogin,
    this.headerTools,
    this.footer,
  });

  final AuthLocalizations strings;
  final Widget form;
  final int methodIndex;
  final bool showQrTab;
  final bool showRegisterForm;
  final bool showRegisterEntry;
  final ValueChanged<int> onMethodSelected;
  final VoidCallback onRegisterTap;
  final VoidCallback onBackToLogin;
  final Widget? headerTools;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final family = AppTokens.fontFamilyOf(context);
    final fallback = AppTokens.fontFamilyFallbackOf(context);
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                if (PlatformUtils().isWindows)
                  Expanded(child: MoveWindow())
                else
                  const Spacer(),
                if (headerTools != null) headerTools!,
                const SizedBox(width: 12),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 8, 48, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showRegisterForm
                        ? strings.registerTab
                        : strings.wideLoginWelcomeBack,
                    style: TextStyle(
                      fontFamily: family,
                      fontFamilyFallback: fallback,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A2332),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    showRegisterForm
                        ? strings.wideLoginRegisterSubtitle
                        : strings.wideLoginJourneySubtitle,
                    style: TextStyle(
                      fontFamily: family,
                      fontFamilyFallback: fallback,
                      fontSize: 14,
                      color: const Color(0xFF9AA6B4),
                    ),
                  ),
                  if (!showRegisterForm) ...[
                    const SizedBox(height: 28),
                    _WideLoginMethodTabs(
                      strings: strings,
                      methodIndex: methodIndex,
                      showQrTab: showQrTab,
                      onSelected: onMethodSelected,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Expanded(child: form),
                  const SizedBox(height: 8),
                  Center(
                    child: showRegisterForm
                        ? _WideLoginFooterLink(
                            prefix: strings.wideLoginAlreadyHaveAccount,
                            action: strings.wideLoginGoLogin,
                            onTap: onBackToLogin,
                          )
                        : (showRegisterEntry
                            ? _WideLoginFooterLink(
                                prefix: strings.wideLoginNoAccountYet,
                                action: strings.wideLoginRegisterNow,
                                onTap: onRegisterTap,
                              )
                            : (footer ?? const SizedBox.shrink())),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WideLoginMethodTabs extends StatelessWidget {
  const _WideLoginMethodTabs({
    required this.strings,
    required this.methodIndex,
    required this.showQrTab,
    required this.onSelected,
  });

  final AuthLocalizations strings;
  final int methodIndex;
  final bool showQrTab;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      strings.wideLoginPasswordTab,
      strings.wideLoginSmsTab,
      if (showQrTab) strings.switchToQrLogin,
    ];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 22),
          _WideLoginTab(
            label: labels[i],
            selected: methodIndex == i,
            onTap: () => onSelected(i),
          ),
        ],
      ],
    );
  }
}

class _WideLoginTab extends StatelessWidget {
  const _WideLoginTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final family = AppTokens.fontFamilyOf(context);
    final fallback = AppTokens.fontFamilyFallbackOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: family,
                fontFamilyFallback: fallback,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF2F7BFF)
                    : const Color(0xFF8B97A6),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2.5,
              width: selected ? 28 : 0,
              decoration: BoxDecoration(
                color: const Color(0xFF2F7BFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WideLoginFooterLink extends StatelessWidget {
  const _WideLoginFooterLink({
    required this.prefix,
    required this.action,
    required this.onTap,
  });

  final String prefix;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final family = AppTokens.fontFamilyOf(context);
    final fallback = AppTokens.fontFamilyFallbackOf(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 28, height: 1, color: const Color(0xFFE6EAF0)),
        const SizedBox(width: 10),
        Text(
          prefix,
          style: TextStyle(
            fontFamily: family,
            fontFamilyFallback: fallback,
            fontSize: 13,
            color: const Color(0xFF9AA6B4),
          ),
        ),
        GestureDetector(
          onTap: onTap,
          child: Text(
            action,
            style: TextStyle(
              fontFamily: family,
              fontFamilyFallback: fallback,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2F7BFF),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(width: 28, height: 1, color: const Color(0xFFE6EAF0)),
      ],
    );
  }
}

class _WideLoginWindowCaptionBar extends StatelessWidget {
  const _WideLoginWindowCaptionBar();

  @override
  Widget build(BuildContext context) {
    final titleBarColor = AppTokens.desktopTitleBar(false);
    final titleBarBorder = AppTokens.desktopTitleBarBorder(false);
    final titleBarIcon = AppTokens.desktopTitleBarIcon(false);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: titleBarColor,
        border: Border(
          bottom: BorderSide(
            color: titleBarBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: MoveWindow()),
          MinimizeWindowButton(
            colors: WindowButtonColors(
              iconNormal: titleBarIcon,
              iconMouseOver: AppTokens.ink900,
              mouseOver: titleBarBorder,
            ),
          ),
          MaximizeWindowButton(
            colors: WindowButtonColors(
              iconNormal: titleBarIcon,
              iconMouseOver: AppTokens.ink900,
              mouseOver: titleBarBorder,
            ),
          ),
          CloseWindowButton(
            colors: WindowButtonColors(
              iconNormal: titleBarIcon,
              iconMouseOver: const Color(0xFFFFFFFF),
              mouseOver: const Color(0xFFC42B1C),
            ),
          ),
        ],
      ),
    );
  }
}

class WideLoginPrimaryButton extends StatefulWidget {
  const WideLoginPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.loading = false,
    this.loadingText,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingText;

  @override
  State<WideLoginPrimaryButton> createState() => _WideLoginPrimaryButtonState();
}

class _WideLoginPrimaryButtonState extends State<WideLoginPrimaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!_enabled) return;
        FocusManager.instance.primaryFocus?.unfocus();
        widget.onPressed!();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        height: 48,
        transform: Matrix4.diagonal3Values(
          _pressed && _enabled ? 0.98 : 1.0,
          _pressed && _enabled ? 0.98 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: _enabled ? const Color(0xFF2F7BFF) : AppTokens.ink100,
          borderRadius: BorderRadius.circular(24),
          boxShadow: _enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF2F7BFF).withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        alignment: Alignment.center,
        child: widget.loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  if (widget.loadingText != null &&
                      widget.loadingText!.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text(
                      widget.loadingText!,
                      style: AppTokens.button,
                    ),
                  ],
                ],
              )
            : Text(widget.text, style: AppTokens.button),
      ),
    );
  }
}
