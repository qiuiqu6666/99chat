import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as img;
import 'package:tencent_cloud_chat_demo/src/utils/qr_zxing2_decode.dart';

typedef QrGalleryWorkerInput = (SendPort, String, int, bool);

/// No platform channels or UI objects in this isolate. Decode the file once
/// and reuse the bitmap for native passes and the Dart fallback.
void decodeQrGalleryWorker(QrGalleryWorkerInput input) {
  final clock = Stopwatch()..start();
  var passes = 0;
  var width = 0;
  var height = 0;
  var imageDecodes = 0;
  var engine = 'none';
  bool hasTime([int reserveMs = 0]) =>
      clock.elapsedMilliseconds < input.$3 - reserveMs;
  Map<String, Object?> finish(List<String> values, String status) => {
        'values': values,
        'status': status,
        'engine': engine,
        'workerMs': clock.elapsedMilliseconds,
        'passes': passes,
        'width': width,
        'height': height,
        'imageDecodes': imageDecodes,
      };
  Map<String, Object?> decode() {
    final file = File(input.$2);
    if (file.lengthSync() > 32 * 1024 * 1024) return finish([], 'too_large');
    final bytes = file.readAsBytesSync();
    final decoder = img.findDecoderForData(bytes);
    final header = decoder?.startDecode(bytes);
    if (header == null) return finish([], 'invalid_image');
    width = header.width;
    height = header.height;
    // The mobile normalizer downsamples first. If it failed or timed out, do
    // not allocate an unbounded original bitmap in the fallback.
    if (width <= 0 || height <= 0 || width * height > 4096 * 4096) {
      return finish([], 'too_large');
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) return finish([], 'invalid_image');
    imageDecodes++;
    final source = img.bakeOrientation(decoded);
    img.Image limit(int maxSide) {
      final longest = math.max(source.width, source.height);
      if (longest <= maxSide) return source;
      return img.copyResize(source,
          width: math.max(1, (source.width * maxSide / longest).round()),
          height: math.max(1, (source.height * maxSide / longest).round()),
          interpolation: img.Interpolation.linear);
    }

    var nativeReady = false;
    if (input.$4) {
      try {
        zx.version();
        nativeReady = true;
      } catch (_) {}
    }
    List<String> native(img.Image image, {required bool harder}) {
      passes++;
      engine = 'zxing-native';
      try {
        return zx
            .readBarcodes(
              image.getBytes(),
              width: image.width,
              height: image.height,
              params: DecodeParams(
                  format: Format.qrCode,
                  tryRotate: true,
                  tryHarder: harder,
                  tryInverted: harder),
            )
            .codes
            .where((c) => c.isValid && (c.text?.trim().isNotEmpty ?? false))
            .map((c) => c.text!.trim())
            .toSet()
            .toList();
      } catch (_) {
        return [];
      }
    }

    img.Image gray(img.Image image) =>
        img.grayscale(image.convert(format: img.Format.uint8, numChannels: 1));

    if (nativeReady && hasTime(1500)) {
      final normal = gray(limit(2048));
      for (final harder in [false, true]) {
        if (!hasTime(1500)) break;
        final values = native(normal, harder: harder);
        if (values.isNotEmpty) return finish(values, 'ok');
      }
      if (math.max(source.width, source.height) > 2048 && hasTime(1500)) {
        final values = native(gray(limit(3072)), harder: true);
        if (values.isNotEmpty) return finish(values, 'ok');
      }
      if (hasTime(1500)) {
        final enhanced =
            img.adjustColor(img.grayscale(normal.clone()), contrast: 1.25);
        final values = native(enhanced, harder: true);
        if (values.isNotEmpty) return finish(values, 'ok');
      }
    }
    if (!hasTime()) return finish([], 'timeout');
    engine = 'zxing-dart';
    final values = decodeQrWithZxing2FromImage(source,
        shouldContinue: hasTime, onPass: () => passes++);
    return finish(
        values,
        values.isNotEmpty
            ? 'ok'
            : hasTime()
                ? 'no_code'
                : 'timeout');
  }

  Map<String, Object?> response;
  try {
    response = decode();
  } catch (_) {
    response = finish([], 'error');
  }
  Isolate.exit(input.$1, response);
}
