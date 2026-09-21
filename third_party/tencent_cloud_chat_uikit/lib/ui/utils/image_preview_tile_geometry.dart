import 'dart:math' as math;
import 'dart:ui';

class ImagePreviewTileGeometry {
  const ImagePreviewTileGeometry({
    required this.imageWidth,
    required this.imageHeight,
    required this.screenWidth,
    required this.screenHeight,
    required this.devicePixelRatio,
    required this.scale,
    required this.dstWidth,
    required this.srcTileHeight,
    required this.tileCount,
    required this.contentHeight,
  });

  final int imageWidth;
  final int imageHeight;
  final double screenWidth;
  final double screenHeight;
  final double devicePixelRatio;
  final double scale;
  final int dstWidth;
  final int srcTileHeight;
  final int tileCount;
  final double contentHeight;

  factory ImagePreviewTileGeometry.from({
    required int imageWidth,
    required int imageHeight,
    required double screenWidth,
    required double screenHeight,
    required double devicePixelRatio,
    double scale = 1.0,
  }) {
    final safeScale = scale < 1.0 ? 1.0 : scale;
    final dstWidth = math.max(
      1,
      math.min(
        imageWidth,
        (screenWidth * devicePixelRatio * safeScale).round(),
      ),
    );
    final srcTileHeight = math.max(
      1,
      (imageWidth * screenHeight / screenWidth).ceil(),
    );
    final tileCount = math.max(1, (imageHeight / srcTileHeight).ceil());
    final contentHeight = screenWidth * imageHeight / imageWidth;
    return ImagePreviewTileGeometry(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      devicePixelRatio: devicePixelRatio,
      scale: safeScale,
      dstWidth: dstWidth,
      srcTileHeight: srcTileHeight,
      tileCount: tileCount,
      contentHeight: contentHeight,
    );
  }

  int srcTopFor(int index) => index * srcTileHeight;

  int srcHeightFor(int index) {
    final top = srcTopFor(index);
    return math.max(1, math.min(srcTileHeight, imageHeight - top));
  }

  Rect srcRectFor(int index) {
    return Rect.fromLTWH(
      0,
      srcTopFor(index).toDouble(),
      imageWidth.toDouble(),
      srcHeightFor(index).toDouble(),
    );
  }

  int dstHeightFor(int index) {
    return math.max(
      1,
      (srcHeightFor(index) * dstWidth / imageWidth).round(),
    );
  }

  double tileLogicalHeight(int index) {
    return screenWidth * srcHeightFor(index) / imageWidth;
  }

  int visibleTileIndex(double scrollOffset) {
    if (contentHeight <= 0 || tileCount <= 0) {
      return 0;
    }
    final firstHeight = tileLogicalHeight(0);
    if (firstHeight <= 0) {
      return 0;
    }
    return (scrollOffset / firstHeight).floor().clamp(0, tileCount - 1);
  }

  int maxCachedTiles({required bool desktop}) => desktop ? 6 : 3;

  int prefetchRadius({required bool desktop}) => desktop ? 2 : 1;
}
