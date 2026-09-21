import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded ProfileSignatureEditPage uses gray input fill', () {
    final source = File('lib/src/pages/profile_signature_edit_page.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    expect(source, contains('inputFill: inputFill'));
    expect(
      source,
      isNot(contains('widget.embedded ? pageBackground : inputFill')),
    );
  });
}
