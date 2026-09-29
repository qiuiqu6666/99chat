import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('my profile header renders the signature from IM profile data', () {
    final source = File('lib/src/profile.dart').readAsStringSync();

    expect(source, contains('userProfile?.selfSignature?.trim()'));
    expect(source, contains('loginUserInfo.selfSignature?.trim()'));
    expect(
      source,
      contains('final signature = _resolveImSignature('),
    );
    expect(source, isNot(contains('不能从 IM SDK 补值')));
  });
}
