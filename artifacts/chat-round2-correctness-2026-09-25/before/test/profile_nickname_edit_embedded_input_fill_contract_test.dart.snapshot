import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded ProfileNicknameEditPage uses gray input fill', () {
    final source = File('lib/src/pages/profile_nickname_edit_page.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    expect(source, contains('inputFill: inputFill'));
    expect(
      source,
      isNot(contains('widget.embedded ? pageBackground : inputFill')),
    );
    expect(source, contains('AppUserAvatar'));
    expect(source, contains('_useAvatarHeaderLayout'));
    expect(source, contains('AppTokens.appBackground'));
    expect(source, contains('AppTokens.appSurface'));
    expect(source, contains('Colors.white'));
    expect(source, contains('minHeight: 52'));
    expect(source, contains('BorderRadius.circular(12)'));
    expect(source, contains('filled: true'));
  });
}
