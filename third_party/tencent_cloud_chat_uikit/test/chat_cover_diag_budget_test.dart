import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_cover_diag.dart';

void main() {
  test('disabled diagnostics retain nothing; opt-in respects lifetime budget',
      () {
    final originalPrint = debugPrint;
    var printed = 0;
    debugPrint = (String? message, {int? wrapWidth}) => printed++;
    ChatCoverDiag.debugReset();
    try {
      for (var i = 0; i < ChatCoverDiag.maxLines * 4; i++) {
        ChatCoverDiag.logOnce('row', '$i', 'details');
      }
      expect(ChatCoverDiag.debugRetainedKeyCount,
          ChatCoverDiag.enabled ? ChatCoverDiag.maxLines : 0);
      expect(printed, ChatCoverDiag.enabled ? ChatCoverDiag.maxLines : 0);
      expect(ChatCoverDiag.canLog, isFalse);
      expect(ChatCoverDiag.logOnce('row', 'extra', 'details'), isFalse);
    } finally {
      debugPrint = originalPrint;
      ChatCoverDiag.debugReset();
    }
  });

  test('a repeated key is accepted at most once', () {
    ChatCoverDiag.debugReset();
    final originalPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      expect(ChatCoverDiag.logOnce('builder', '1', 'details'),
          ChatCoverDiag.enabled);
      expect(ChatCoverDiag.logOnce('builder', '1', 'changed details'), isFalse);
      expect(
          ChatCoverDiag.debugRetainedKeyCount, ChatCoverDiag.enabled ? 1 : 0);
    } finally {
      debugPrint = originalPrint;
      ChatCoverDiag.debugReset();
    }
  });
}
