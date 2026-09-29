// Host-side CPU microbenchmark. These timings are NOT Android frame timings.
// Run with dart run, or compile exe and run for an AOT host comparison.
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

Map<String, Object> measure(String name, Object? Function() action,
    {int warmups = 2, int samples = 7}) {
  for (var i = 0; i < warmups; i++) {
    action();
  }
  final times = <double>[];
  Object? value;
  for (var i = 0; i < samples; i++) {
    final watch = Stopwatch()..start();
    value = action();
    watch.stop();
    times.add(watch.elapsedMicroseconds / 1000);
  }
  times.sort();
  return {
    'name': name,
    'samples': samples,
    'medianMs': times[samples ~/ 2],
    'maxMs': times.last,
    'result': value ?? ''
  };
}

img.Image fixture(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return image;
}

void main() {
  final splash = img.encodeJpg(fixture(1080, 1920), quality: 85);
  final qr = img.encodeJpg(fixture(2048, 1536), quality: 90);
  final results = <Map<String, Object>>[
    measure('splash_decode_1080x1920', () {
      final decoded = img.decodeImage(splash)!;
      return decoded.width * decoded.height;
    }),
    measure('qr_decode_grayscale_contrast_encode_2048x1536', () {
      var decoded = img.decodeImage(qr)!;
      decoded = img.grayscale(decoded);
      decoded = img.adjustColor(decoded, contrast: 1.25);
      return img.encodeJpg(decoded, quality: 92).length;
    }),
    for (final n in [100, 6000])
      measure('presence_40_sequential_whole_map_merges_$n', () {
        var raw =
            jsonEncode({for (var i = 0; i < n; i++) 'user_$i': 'everyone'});
        for (var i = 0; i < 40; i++) {
          final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          map['user_$i'] = 'contacts';
          raw = jsonEncode(map);
        }
        return raw.length;
      }),
  ];
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'dartVersion': Platform.version,
    'scope':
        'Synthetic host CPU benchmark; no network, SQLite, rendering or Android timings. Presence measures 40 total merges, not one contiguous production frame.',
    'splashCompressedBytes': splash.length,
    'qrCompressedBytes': qr.length,
    'results': results,
  }));
}
