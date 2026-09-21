import 'package:flutter/foundation.dart';

/// 统一图片解码规格：显示多大，就尽量只解码多大。
///
/// 网络档位（SMALL/BIG/ORIGINAL）和 Flutter decoded cache / GPU texture
/// 不是一层。这里只约束解码像素，不负责清 ImageCache。
class ImageDecodeSpec {
  const ImageDecodeSpec({
    required this.kind,
    required this.targetDecodeWidth,
    required this.targetDecodeHeight,
    required this.sizeBucket,
    this.maxDecodedPixels = defaultMaxDecodedPixels,
  });

  static const int defaultMaxDecodedPixels = 10 * 1000 * 1000;
  static const List<int> sizeBuckets = <int>[
    128,
    256,
    480,
    720,
    1080,
    1440,
  ];

  static int imageDecodeRequestCount = 0;
  static int imageDecodeOversizeCount = 0;
  static int imageDecodeTargetPixels = 0;

  final ImageDecodeKind kind;
  final int targetDecodeWidth;
  final int targetDecodeHeight;
  final String sizeBucket;
  final int maxDecodedPixels;

  int get pixelCount => targetDecodeWidth * targetDecodeHeight;

  factory ImageDecodeSpec.avatar({
    double logical = 48,
    double devicePixelRatio = 3,
  }) {
    final px = _logicalPx(logical, devicePixelRatio, min: 64, max: 192);
    return ImageDecodeSpec(
      kind: ImageDecodeKind.avatar,
      targetDecodeWidth: px,
      targetDecodeHeight: px,
      sizeBucket: bucketFor(px),
    );
  }

  factory ImageDecodeSpec.chatThumbnail({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    bool deferHeavyDecode = false,
    double? sourceWidth,
    double? sourceHeight,
  }) {
    final maxSide = deferHeavyDecode ? 720 : 1440;
    final width = _logicalPx(logicalWidth, devicePixelRatio, max: maxSide);
    final height = _logicalPx(logicalHeight, devicePixelRatio, max: maxSide);
    return ImageDecodeSpec(
      kind: ImageDecodeKind.chatThumbnail,
      targetDecodeWidth: width,
      targetDecodeHeight: height,
      sizeBucket: bucketFor(width > height ? width : height),
    ).clampedToPixelBudget(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  factory ImageDecodeSpec.albumGrid({
    double logical = 120,
    double devicePixelRatio = 3,
  }) {
    final px = _logicalPx(logical, devicePixelRatio, max: 480);
    return ImageDecodeSpec(
      kind: ImageDecodeKind.albumGrid,
      targetDecodeWidth: px,
      targetDecodeHeight: px,
      sizeBucket: bucketFor(px),
    );
  }

  factory ImageDecodeSpec.fullscreenPreview({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    double? sourceWidth,
    double? sourceHeight,
  }) {
    final width = _logicalPx(logicalWidth, devicePixelRatio, max: 1440);
    final height = _logicalPx(logicalHeight, devicePixelRatio, max: 1440);
    return ImageDecodeSpec(
      kind: ImageDecodeKind.fullscreenPreview,
      targetDecodeWidth: width,
      targetDecodeHeight: height,
      sizeBucket: bucketFor(width > height ? width : height),
    ).clampedToPixelBudget(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  ImageDecodeSpec clampedToPixelBudget({
    double? sourceWidth,
    double? sourceHeight,
  }) {
    imageDecodeRequestCount++;
    var width = targetDecodeWidth < 1 ? 1 : targetDecodeWidth;
    var height = targetDecodeHeight < 1 ? 1 : targetDecodeHeight;
    if (sourceWidth != null &&
        sourceHeight != null &&
        sourceWidth > 0 &&
        sourceHeight > 0) {
      if (width >= height) {
        height = (width * (sourceHeight / sourceWidth)).round();
        if (height < 1) height = 1;
      } else {
        width = (height * (sourceWidth / sourceHeight)).round();
        if (width < 1) width = 1;
      }
    }
    var pixels = width * height;
    if (pixels > maxDecodedPixels) {
      imageDecodeOversizeCount++;
      final scale = maxDecodedPixels / pixels;
      width = (width * scale).floor();
      height = (height * scale).floor();
      if (width < 1) width = 1;
      if (height < 1) height = 1;
      pixels = width * height;
    }
    imageDecodeTargetPixels = pixels;
    return ImageDecodeSpec(
      kind: kind,
      targetDecodeWidth: width,
      targetDecodeHeight: height,
      sizeBucket: bucketFor(width > height ? width : height),
      maxDecodedPixels: maxDecodedPixels,
    );
  }

  static String bucketFor(int px) {
    for (final bucket in sizeBuckets) {
      if (px <= bucket) return '$bucket';
    }
    return '${sizeBuckets.last}';
  }

  static int _logicalPx(
    double logical,
    double dpr, {
    int min = 1,
    int max = 1440,
  }) {
    if (!logical.isFinite || logical <= 0 || !dpr.isFinite || dpr <= 0) {
      return min;
    }
    return (logical * dpr).round().clamp(min, max);
  }

  @visibleForTesting
  static void resetMetricsForTest() {
    imageDecodeRequestCount = 0;
    imageDecodeOversizeCount = 0;
    imageDecodeTargetPixels = 0;
  }
}

enum ImageDecodeKind {
  avatar,
  chatThumbnail,
  albumGrid,
  fullscreenPreview,
}
