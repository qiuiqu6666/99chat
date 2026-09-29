import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded QR dialog hides save and scan bottom actions', () {
    final source = File('lib/src/qr_code_page.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    expect(source, contains('if (showQrCode && !widget.embedded)'));
    expect(source, contains('_buildBottomActions(palette)'));
  });
}
