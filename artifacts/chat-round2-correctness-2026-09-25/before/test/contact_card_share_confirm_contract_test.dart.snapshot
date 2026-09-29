import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile contact sharing confirms before creating the message', () {
    final source = File('lib/src/user_profile.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _handleShareContact');
    final end = source.indexOf('Future<void> _handleMoreAction', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = source.substring(start, end);
    final confirmIndex = body.indexOf('showContactCardSendConfirm(');
    final createIndex = body.indexOf('createCustomMessage(');
    expect(confirmIndex, greaterThanOrEqualTo(0));
    expect(createIndex, greaterThan(confirmIndex));
    expect(body.contains('if (!confirmed || !context.mounted)'), isTrue);
  });

  test('chat and profile sharing use the shared confirmation card', () {
    final chatSource = File('lib/src/chat.dart').readAsStringSync();
    final profileSource = File('lib/src/user_profile.dart').readAsStringSync();
    expect(chatSource.contains('showContactCardSendConfirm('), isTrue);
    expect(profileSource.contains('showContactCardSendConfirm('), isTrue);
  });
}
