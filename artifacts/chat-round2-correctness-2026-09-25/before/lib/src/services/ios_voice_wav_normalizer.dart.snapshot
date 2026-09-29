import 'dart:io';

import 'package:flutter/foundation.dart';

/// Legacy compatibility reader. The native recorder now produces the final WAV;
/// Dart must not strip the first 4100 bytes a second time.
class IosVoiceWavNormalizer {
  IosVoiceWavNormalizer._();

  static Uint8List normalizeIfNeeded(Uint8List bytes) => bytes;

  static Future<Uint8List?> readNormalizedFile(String path) async {
    if (kIsWeb) {
      return null;
    }
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }
}
