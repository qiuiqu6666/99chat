import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sticker_preview_voice_scope.dart';

void main() {
  test('preview protection starts before navigation and ends after dismissal',
      () async {
    final dismissed = Completer<void>();
    final preview = StickerPreviewVoiceScope.run(() {
      expect(StickerPreviewVoiceScope.isOpen, isTrue);
      return dismissed.future;
    });
    expect(StickerPreviewVoiceScope.isOpen, isTrue);
    dismissed.complete();
    await preview;
    expect(StickerPreviewVoiceScope.isOpen, isFalse);
  });

  test('closing a nested preview preserves the outer preview', () async {
    await StickerPreviewVoiceScope.run(() async {
      await StickerPreviewVoiceScope.run(() async {});
      expect(StickerPreviewVoiceScope.isOpen, isTrue);
    });
    expect(StickerPreviewVoiceScope.isOpen, isFalse);
  });

  test('failed navigation cannot leave playback protection enabled', () async {
    await expectLater(
      StickerPreviewVoiceScope.run<void>(() => throw StateError('push failed')),
      throwsStateError,
    );
    expect(StickerPreviewVoiceScope.isOpen, isFalse);
  });
}
