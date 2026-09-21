import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history preview hydration cannot reorder the conversation feed', () {
    final scheduler = File(
      'lib/src/services/conversation_history_warm_scheduler.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/src/chat_session/chat_session_controller.dart',
    ).readAsStringSync();

    expect(scheduler, contains('allowReorder: false'));
    expect(controller, contains('bool allowReorder = true'));
    expect(controller, contains('final needsReorder = allowReorder &&'));
    expect(
      controller,
      contains('orderkey: allowReorder && (preferred.timestamp ?? 0) > 0'),
    );
  });

  test('conversation peek pagination does not change list extent', () {
    final overlay = File(
      'lib/src/widgets/conversation_peek/conversation_peek_overlay.dart',
    ).readAsStringSync();

    expect(overlay, isNot(contains('_PeekListItem.loadingOlder')));
    expect(overlay, contains('if (_loadingOlder)'));
    expect(overlay, contains('Positioned('));
    expect(overlay, contains('_userHasInteractedWithList'));
    expect(overlay, contains('notification.dragDetails != null'));
    expect(overlay, contains('_mediaRefreshPending = true'));
    expect(overlay, contains('_flushPendingMediaRefresh()'));
    expect(overlay, contains(r"'conversation-peek-message-$messageId'"));
    expect(overlay, contains('ObjectKey(message)'));
  });
}
