import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String chatSource;

  setUpAll(() {
    chatSource = File('lib/src/chat.dart').readAsStringSync();
  });

  test('route return gates media overlay before recovering history', () {
    final recoveryAt = chatSource.indexOf(
      'void _recoverAfterRouteBecameCurrent()',
    );
    expect(recoveryAt, greaterThanOrEqualTo(0));
    final recoveryBody = chatSource.substring(recoveryAt, recoveryAt + 1900);

    expect(recoveryBody.contains('isMediaPreviewOverlayOpen'), isTrue);
    expect(
      recoveryBody.contains('isRestoringScrollAfterMediaPreview'),
      isTrue,
    );
    expect(recoveryBody.contains('isMediaPickerOverlayOpen'), isTrue);
    expect(recoveryBody.contains('isWalletOverlayOpen'), isTrue);

    final mediaGate = recoveryBody.indexOf('isMediaPreviewOverlayOpen');
    final recoverCall =
        recoveryBody.indexOf("_recoverChatHistoryAfterOverlayReturn");
    expect(mediaGate, greaterThanOrEqualTo(0));
    expect(recoverCall, greaterThan(mediaGate));
    expect(recoveryBody.contains("reason: 'route_reactivated'"), isTrue);
  });

  test('recover skips aggressive jumpTo for media route_reactivated', () {
    final recoverAt = chatSource.indexOf(
      'Future<void> _performChatHistoryAfterOverlayReturn',
    );
    expect(recoverAt, greaterThanOrEqualTo(0));
    final recoverBody = chatSource.substring(recoverAt, recoverAt + 2800);

    expect(recoverBody.contains('overlay_return_skip_aggressive'), isTrue);
    expect(recoverBody.contains("reason == 'route_reactivated'"), isTrue);
    expect(recoverBody.contains('isMediaPreviewOverlayOpen'), isTrue);
    expect(
      recoverBody.contains('isRestoringScrollAfterMediaPreview'),
      isTrue,
    );
    // A maintained conversation owns its viewport on every ordinary return.
    // Forcing bottom here would also undo a preview's restored history offset.
    expect(
      recoverBody.contains('jumpTo(scroll.position.minScrollExtent)'),
      isFalse,
    );
    expect(recoverBody.contains('if (_hasVisibleHistoryMessages()) return;'),
        isTrue);
  });

  test('explicit profile recover reasons remain in chat.dart', () {
    expect(chatSource.contains("reason: 'return_from_profile'"), isTrue);
    expect(chatSource.contains("reason: 'return_from_settings'"), isTrue);
  });
}
