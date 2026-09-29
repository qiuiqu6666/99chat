import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';

class ImageRegionDecoder {
  ImageRegionDecoder._();

  static const MethodChannel _channel =
      MethodChannel('ninechat/image_region_decoder');

  static Future<ui.Image?> decode(ImageRegionDecodeRequest request) async {
    if (kIsWeb) {
      return null;
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'decodeRegion',
        <String, dynamic>{
          'path': request.path,
          'srcLeft': request.srcLeft,
          'srcTop': request.srcTop,
          'srcWidth': request.srcWidth,
          'srcHeight': request.srcHeight,
          'dstWidth': request.dstWidth,
          'dstHeight': request.dstHeight,
        },
      );
      if (raw is! Map) {
        return null;
      }
      final bytes = raw['bytes'];
      final width = raw['width'];
      final height = raw['height'];
      if (bytes is! Uint8List || width is! int || height is! int) {
        return null;
      }
      if (bytes.length < width * height * 4) {
        return null;
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return completer.future;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
