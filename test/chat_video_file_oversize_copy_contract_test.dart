import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String panel;
  late String wide;

  setUpAll(() {
    panel = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_more_panel.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    wide = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_text_field_layout/wide.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
  });

  test('image oversize copy stays generic and appears four times', () {
    expect(
      'TIM_t("文件大小超出了限制")'.allMatches(panel).length,
      4,
    );
  });

  test('video and file oversize copy names the 100MB limit six times', () {
    expect(
      'TIM_t("文件大小超过上限100MB")'.allMatches(panel).length,
      6,
    );
  });

  test('wide video oversize uses the 100MB limit copy', () {
    expect(wide.contains('TIM_t("文件大小超过上限100MB")'), isTrue);
    expect(wide.contains('发送失败，视频不能大于100MB'), isFalse);
  });

  test('video and file max size remain 100 MiB', () {
    expect(panel.contains('static final int FILE_MAX_SIZE = 100 * 1024 * 1024;'),
        isTrue);
    expect(panel.contains('static final int VIDEO_MAX_SIZE = 100 * 1024 * 1024;'),
        isTrue);
  });
}
