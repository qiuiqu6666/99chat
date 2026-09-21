import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wide profile header avatar uses default circular clip', () {
    final source = File('lib/src/user_profile.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final start = source.indexOf('Widget _buildWideProfileHeader(');
    final end = source.indexOf('Widget _buildWideProfileSettings(');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final header = source.substring(start, end);

    expect(header, contains('_buildProfileAvatar('));
    expect(header, isNot(contains('borderRadius: BorderRadius.circular(10)')));
  });
}
