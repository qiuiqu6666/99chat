import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opened group is retained without restoring a second list', () {
    final page = File('lib/src/conversation.dart').readAsStringSync();
    final sync = File('lib/src/services/conversation_local/conversation_sync_service.dart').readAsStringSync();
    expect(page, contains('retainOpenedGroupConversation('));
    expect(sync, contains('Future<void> retainOpenedGroupConversation('));
    expect(page, isNot(contains('waitUntilUpsertWriteIdle(')));
    expect(page, isNot(contains('prependNewerFromLocal(')));
    expect(page, isNot(contains('slideToHotPrefix(')));
  });
}
