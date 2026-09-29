/// Keeps sticker preview routes from ending chat voice playback.
/// Explicit stops, conversation changes and app suspension still apply.
class StickerPreviewVoiceScope {
  StickerPreviewVoiceScope._();

  static int _depth = 0;
  static bool get isOpen => _depth > 0;

  static Future<T> run<T>(Future<T> Function() openPreview) async {
    _depth++;
    try {
      return await openPreview();
    } finally {
      _depth--;
    }
  }
}
