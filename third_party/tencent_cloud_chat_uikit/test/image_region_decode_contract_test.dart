import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_tile_geometry.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';

void main() {
  test('middle scroll never requests the full 45234-tall source', () {
    final geometry = ImagePreviewTileGeometry.from(
      imageWidth: 1182,
      imageHeight: 45234,
      screenWidth: 390,
      screenHeight: 844,
      devicePixelRatio: 3,
    );
    final requests = <ImageRegionDecodeRequest>[];
    final center = geometry.visibleTileIndex(geometry.contentHeight / 2);
    final radius = geometry.prefetchRadius(desktop: false);
    for (var i = center - radius; i <= center + radius; i++) {
      if (i < 0 || i >= geometry.tileCount) {
        continue;
      }
      final src = geometry.srcRectFor(i);
      requests.add(
        ImageRegionDecodeRequest(
          path: 'mem',
          srcLeft: src.left.round(),
          srcTop: src.top.round(),
          srcWidth: src.width.round(),
          srcHeight: src.height.round(),
          dstWidth: geometry.dstWidth,
          dstHeight: geometry.dstHeightFor(i),
        ),
      );
    }
    expect(requests, isNotEmpty);
    expect(
      requests.any(
        (request) => request.srcTop == 0 && request.srcHeight == 45234,
      ),
      isFalse,
    );
    final oneScreen = 1182 * geometry.srcTileHeight;
    for (final request in requests) {
      expect(request.srcPixels, lessThanOrEqualTo((oneScreen * 1.5).round()));
    }
    expect(requests.length, lessThanOrEqualTo(geometry.maxCachedTiles(desktop: false)));
  });

  test('hook can record decode requests without decoding the full bitmap',
      () async {
    final recorded = <ImageRegionDecodeRequest>[];
    ImageRegionDecodeHook.decode = (request) async {
      recorded.add(request);
      return null;
    };
    addTearDown(ImageRegionDecodeHook.resetForTest);
    final geometry = ImagePreviewTileGeometry.from(
      imageWidth: 2496,
      imageHeight: 30492,
      screenWidth: 390,
      screenHeight: 844,
      devicePixelRatio: 3,
    );
    final src = geometry.srcRectFor(0);
    await ImageRegionDecodeHook.decode!(
      ImageRegionDecodeRequest(
        path: 'mem',
        srcLeft: src.left.round(),
        srcTop: src.top.round(),
        srcWidth: src.width.round(),
        srcHeight: src.height.round(),
        dstWidth: geometry.dstWidth,
        dstHeight: geometry.dstHeightFor(0),
      ),
    );
    expect(recorded, hasLength(1));
    expect(recorded.single.srcHeight, isNot(30492));
    expect(recorded.single.srcTop, 0);
  });
}
