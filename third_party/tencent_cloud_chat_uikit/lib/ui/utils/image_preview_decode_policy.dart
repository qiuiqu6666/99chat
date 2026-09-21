import 'dart:math' as math;

import 'package:tencent_cloud_chat_uikit/ui/utils/progressive_image_decode_budget.dart';

/// 列表 / 气泡 / 进会话预热 / 图集左右预热：禁止 BIG/ORIGINAL 的 decoded-pixel 门槛。
const int kImageDecodedPixelsListPrefetchBan = 10 * 1000 * 1000;

/// 预览受控降采样上限，与 [ProgressiveImageDecodeBudget.maxDecodePx] 同一口径。
const int kImageDecodedPixelsControlledMax =
    ProgressiveImageDecodeBudget.maxDecodePx;

/// 任一边超过此值强制走 Tile Renderer。
const int kImageForceTileLongestSidePx = 16384;

enum ImagePreviewDecodeRoute {
  normal,
  controlledDownsample,
  tiled,
}

int imageDecodedPixelCount(int width, int height) {
  if (width <= 0 || height <= 0) {
    return 0;
  }
  return width * height;
}

bool imageExceedsListPrefetchBan({
  required int width,
  required int height,
}) {
  return imageDecodedPixelCount(width, height) >
      kImageDecodedPixelsListPrefetchBan;
}

bool imagePreviewRequiresTileRenderer({
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) {
    return false;
  }
  return math.max(width, height) > kImageForceTileLongestSidePx ||
      imageDecodedPixelCount(width, height) > kImageDecodedPixelsControlledMax;
}

bool shouldSkipGalleryAdjacentPrecache({
  required int width,
  required int height,
}) {
  return imageExceedsListPrefetchBan(width: width, height: height) ||
      imagePreviewRequiresTileRenderer(width: width, height: height);
}

ImagePreviewDecodeRoute imagePreviewDecodeRoute({
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) {
    return ImagePreviewDecodeRoute.normal;
  }
  if (imagePreviewRequiresTileRenderer(width: width, height: height)) {
    return ImagePreviewDecodeRoute.tiled;
  }
  if (imageExceedsListPrefetchBan(width: width, height: height)) {
    return ImagePreviewDecodeRoute.controlledDownsample;
  }
  return ImagePreviewDecodeRoute.normal;
}

/// 气泡网络图 SDK type 优先级。超 10MP 且已有 THUMB 时只用 type=1；
/// 没有 THUMB 时回退 ORIGINAL/BIG，由气泡 ResizeImage 限制解码像素。
List<int> imageBubbleNetworkSdkTypePriority({
  required bool exceedsListPrefetchBan,
  required bool hasThumbHttp,
}) {
  if (exceedsListPrefetchBan && hasThumbHttp) {
    return const [1];
  }
  return const [1, 2, 0];
}
