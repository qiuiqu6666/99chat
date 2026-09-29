import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contact user avatars stay circular with presence on or off', () {
    final source = File('lib/src/widgets/contact_list_with_presence.dart')
        .readAsStringSync();

    expect(
      source,
      contains('BorderRadius.all(Radius.circular(999))'),
    );
    expect(
      RegExp(r'borderRadius:\s*[_A-Za-z][\w.]*contactAvatarBorderRadius')
          .allMatches(source)
          .length,
      2,
    );
  });
}
