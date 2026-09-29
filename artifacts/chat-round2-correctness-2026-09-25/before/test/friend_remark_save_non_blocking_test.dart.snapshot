import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remark save has a bounded wait', () {
    final source = File('lib/src/user_profile.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final start = source.indexOf('Future<void> _openFriendRemarkEdit');
    final end = source.indexOf('\n  Future<void> _handleAddFriend', start);

    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start, end);
    expect(body, contains('.timeout('));
    expect(body, contains('Duration(seconds: 12)'));
  });

  test('remark lifecycle does not await conversation refresh', () {
    final source = File('lib/src/user_profile.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
        RegExp(r'await\s+conversationModel\s*\.\s*refreshConversationItem')
            .hasMatch(source),
        isFalse);
    expect(
        RegExp(r'unawaited\(\s*conversationModel\s*\.\s*refreshConversationItem')
            .hasMatch(source),
        isTrue);
  });
}
