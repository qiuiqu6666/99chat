import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';

/// Replaces the form within its existing route after the server accepts it.
class FeedbackSuccessView extends StatelessWidget {
  const FeedbackSuccessView({super.key, this.message, this.onDone});

  final String? message;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final i18n = AppI18n.of(context);
    final background = AppColors.card(dark: dark);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarDividerColor: background,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight:
                        (constraints.maxHeight - 64).clamp(0, double.infinity)),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset('assets/images/feedback_success.png',
                            height: 210,
                            width: 210,
                            cacheWidth: 630,
                            excludeFromSemantics: true),
                        const SizedBox(height: 28),
                        Semantics(
                          liveRegion: true,
                          header: true,
                          child: Text(
                              i18n.t(
                                  zhHans: '提交成功',
                                  zhHant: '提交成功',
                                  en: 'Submitted successfully',
                                  ja: '送信完了',
                                  ko: '제출 완료'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.text(dark: dark),
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 18),
                        Text(
                            message ??
                                i18n.t(
                                    zhHans: '感谢您的反馈！\n我们会尽快处理，并持续优化产品体验。',
                                    zhHant: '感謝您的回饋！\n我們會盡快處理，並持續優化產品體驗。',
                                    en:
                                        'Thank you for your feedback!\nWe will review it as soon as possible and keep improving your experience.',
                                    ja:
                                        'フィードバックありがとうございます！\n速やかに確認し、サービスの改善に努めます。',
                                    ko:
                                        '의견을 보내 주셔서 감사합니다!\n신속히 검토하고 서비스 경험을 지속적으로 개선하겠습니다.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.subText(dark: dark),
                                fontSize: 15,
                                height: 1.6)),
                        const SizedBox(height: 60),
                        ElevatedButton(
                          key: const ValueKey('feedback-success-done'),
                          onPressed:
                              onDone ?? () => Navigator.of(context).maybePop(),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: dark
                                  ? const Color(0xFF176DD9)
                                  : AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              surfaceTintColor: Colors.transparent,
                              elevation: 0,
                              minimumSize: const Size.fromHeight(50),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          child: Text(
                              i18n.t(
                                  zhHans: '我知道了',
                                  zhHant: '我知道了',
                                  en: 'Got it',
                                  ja: '確認しました',
                                  ko: '확인'),
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
