import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_region_grid.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';

void main() {
  for (final size in [const Size(1182, 45234), const Size(2496, 30492)]) {
    test(
        'visible regions of ${size.width}x${size.height} stay bounded at native hook',
        () async {
      final grid = ImagePreviewRegionGrid(
          source: size,
          display: Size(390, 390 * size.height / size.width),
          pixelRatio: 3,
          zoom: 4);
      final requests = <ImageRegionDecodeRequest>[];
      ImageRegionDecodeHook.decode = (request) async {
        requests.add(request);
        return null;
      };
      addTearDown(ImageRegionDecodeHook.resetForTest);
      for (final index in grid
          .visible(Rect.fromLTWH(0, grid.display.height / 2, 390, 844))) {
        final src = grid.sourceRect(index), dst = grid.decodeSize(index);
        await ImageRegionDecodeHook.decode!(ImageRegionDecodeRequest(
            path: 'mem',
            srcLeft: src.left.toInt(),
            srcTop: src.top.toInt(),
            srcWidth: src.width.toInt(),
            srcHeight: src.height.toInt(),
            dstWidth: dst.width.toInt(),
            dstHeight: dst.height.toInt()));
      }
      expect(requests, isNotEmpty);
      expect(requests.length, lessThanOrEqualTo(48));
      for (final request in requests) {
        expect(request.srcHeight, lessThan(size.height));
        expect(
            request.dstWidth * request.dstHeight, lessThanOrEqualTo(512 * 512));
        expect(request.srcTop, greaterThan(0));
      }
    });
  }
}
