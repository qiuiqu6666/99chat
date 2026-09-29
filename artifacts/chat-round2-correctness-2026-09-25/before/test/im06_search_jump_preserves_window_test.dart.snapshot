import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search jump does not clear the shared message window', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'tim_uikit_chat.dart',
    ).readAsStringSync();
    const marker = 'if (isSearchJump && searchJumpAnchor != null) {';
    final start = source.indexOf(marker);
    final load = source.indexOf(
      'final loaded = await model!.loadListForSpecificMessage(',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(load, greaterThan(start));
    final jumpSetup = source.substring(start, load);
    expect(jumpSetup, isNot(contains('removeMessageList(')));
    expect(jumpSetup, contains('search_jump_preserve_window'));
  });
}
