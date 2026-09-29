import 'dart:ui';

import 'package:flutter/foundation.dart';

class ImageRegionDecodeRequest {
  const ImageRegionDecodeRequest({
    required this.path,
    required this.srcLeft,
    required this.srcTop,
    required this.srcWidth,
    required this.srcHeight,
    required this.dstWidth,
    required this.dstHeight,
  });

  final String path;
  final int srcLeft;
  final int srcTop;
  final int srcWidth;
  final int srcHeight;
  final int dstWidth;
  final int dstHeight;

  int get srcPixels => srcWidth * srcHeight;
}

typedef ImageRegionDecodeFn = Future<Image?> Function(
  ImageRegionDecodeRequest request,
);

/// UIKit 只依赖 hook；App 在启动时注册原生区域解码。
class ImageRegionDecodeHook {
  ImageRegionDecodeHook._();

  static ImageRegionDecodeFn? decode;

  @visibleForTesting
  static void resetForTest() {
    decode = null;
  }
}
