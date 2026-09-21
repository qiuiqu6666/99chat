import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings exposes the test page entry', () {
    final settingsSource =
        File('lib/src/pages/settings/settings_page.dart').readAsStringSync();
    final testPageSource =
        File('lib/src/pages/settings/test_page.dart').readAsStringSync();

    expect(
        settingsSource,
        contains(
            "import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';"));
    expect(settingsSource, contains("zhHans: '测试页面'"));
    expect(settingsSource, contains('onTap: () => _open(const TestPage())'));
    expect(testPageSource, contains('class TestPage extends StatelessWidget'));
    expect(testPageSource, contains("zhHans: '这是一个测试页面。'"));
  });
}
