import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat body uses platform default font at 16px and weight 400', () {
    final textStyleSource = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/message_bubble_text_color.dart',
    ).readAsStringSync();
    expect(textStyleSource, contains('messageBodyFontSize = 16'));
    expect(
        textStyleSource, contains('messageBodyFontWeight = FontWeight.w400'));
    expect(
        textStyleSource, isNot(contains('fontFamily: variableCjkFontFamily')));
    expect(textStyleSource, isNot(contains('FontVariation(')));
  });
}
