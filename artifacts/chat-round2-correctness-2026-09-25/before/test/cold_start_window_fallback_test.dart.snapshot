import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = ConversationTabStore.instance;

  setUp(store.clear);
  tearDown(store.clear);

  test('a fresh session opens the cold start window', () {
    expect(store.isColdStartWindowActive, isTrue);
  });

  test('post-home completion closes the window', () {
    store.notifyColdStartEnded();

    expect(store.isColdStartWindowActive, isFalse);
  });

  test('reopening the window restarts the fallback clock', () {
    store.notifyColdStartEnded();
    store.reopenColdStartWindow();

    expect(store.isColdStartWindowActive, isTrue);
  });

  test('clear reopens the window for the next session', () {
    store.notifyColdStartEnded();
    store.clear();

    expect(store.isColdStartWindowActive, isTrue);
  });

  test('repeated reads before the fallback delay stay stable', () {
    for (var i = 0; i < 5; i++) {
      expect(store.isColdStartWindowActive, isTrue);
    }
  });

  test('cold start admission reads the self-healing getter, not the field', () {
    final source = File(
      'lib/src/services/conversation_local/conversation_tab_store.dart',
    ).readAsStringSync();
    final fieldReferences =
        RegExp(r'_coldStartWindowActive').allMatches(source).length;

    // Declaration + getter guard + the three write sites. Any extra reference
    // would bypass the fallback and keep preserveOrder pinned to true.
    expect(fieldReferences, lessThanOrEqualTo(5));
  });
}
