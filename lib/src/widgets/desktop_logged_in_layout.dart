import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/settings_widgets.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/utils/immersive_app_system_ui.dart';

const String kDesktopLoggedInArt = 'assets/jingyin.png';
const Color kDesktopSignOutButtonColor = Color(0xFF7A96B8);

class DesktopLoggedInLayout extends StatelessWidget {
  const DesktopLoggedInLayout({
    super.key,
    required this.title,
    required this.closeTooltip,
    required this.signOutText,
    required this.onClose,
    required this.onSignOut,
    this.loading = false,
    this.busy = false,
  });

  final String title;
  final String closeTooltip;
  final String signOutText;
  final VoidCallback? onClose;
  final VoidCallback? onSignOut;
  final bool loading;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final textColor = AppColors.text(dark: dark);
    final overlayStyle = immersiveOverlayForColors(
      statusBarBackground: AppColors.background(dark: dark),
      navigationBarBackground: AppColors.background(dark: dark),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: AppColors.background(dark: dark),
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: busy ? null : onClose,
                  icon: const Icon(Icons.close, size: 26),
                  color: AppTokens.accent,
                  tooltip: closeTooltip,
                ),
              ),
              Expanded(
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTokens.accent,
                        ),
                      )
                    : Column(
                        children: [
                          const SizedBox(height: 36),
                          Image.asset(
                            kDesktopLoggedInArt,
                            width: 280,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (!loading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                  child: Center(
                    child: SizedBox(
                      width: 188,
                      height: 44,
                      child: FilledButton(
                        onPressed: busy ? null : onSignOut,
                        style: FilledButton.styleFrom(
                          backgroundColor: kDesktopSignOutButtonColor,
                          disabledBackgroundColor: kDesktopSignOutButtonColor
                              .withValues(alpha: 0.55),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                signOutText,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
