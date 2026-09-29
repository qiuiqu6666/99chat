import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/wav_pcm_extractor.dart';

void main() {
  test('resamples Android 22050 Hz PCM to Xfyun 8000 Hz PCM', () {
    final source = Uint8List(22050 * 2);

    final converted = WavPcmExtractor.resampleLinear16Mono(
      source,
      22050,
      8000,
    );

    expect(converted.length, 8000 * 2);
  });
}
