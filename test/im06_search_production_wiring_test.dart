import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search ViewModel routes every SDK message search through IM-06', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/'
      'tui_search_view_model.dart',
    ).readAsStringSync();
    expect(source, contains('Im06MessageSearchCoordinator('));
    expect(source, contains('_searchMessagesThroughIm06('));
    expect(
      RegExp(r'_messageService\.search(?:Local|Cloud)Messages\(')
          .allMatches(source),
      hasLength(0),
    );
  });
}
