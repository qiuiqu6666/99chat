import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contact list visible rows soft-refresh presence with ttl bucket', () {
    final source = File('lib/src/widgets/contact_list_with_presence.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    expect(source, contains('presence.refresh(userIds)'));
    expect(source, isNot(contains('presence.ensure(userIds)')));
    expect(source, contains('PresenceProvider.softFetchTtl'));
    expect(source, contains('_lastPresenceEnsureKey'));
  });
}
