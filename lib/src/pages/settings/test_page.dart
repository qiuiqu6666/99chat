import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/settings_widgets.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';

class TestPage extends StatelessWidget {
  const TestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final i18n = AppI18n.of(context);

    return SettingsScaffold(
      title: i18n.t(
        zhHans: '测试页面',
        zhHant: '測試頁面',
        en: 'Test Page',
        ja: 'テストページ',
        ko: '테스트 페이지',
      ),
      children: [
        SettingsGroup(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Text(
                i18n.t(
                  zhHans: '这是一个测试页面。',
                  zhHant: '這是一個測試頁面。',
                  en: 'This is a test page.',
                  ja: 'これはテストページです。',
                  ko: '테스트 페이지입니다.',
                ),
                style: TextStyle(
                  color: AppColors.text(dark: dark),
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
