import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_region_grid.dart';

void main() {
  test('extreme dimensions and zoom never allocate a region over 512 squared',
      () {
    for (final source in [
      const Size(8000, 100000),
      const Size(30000, 1000),
      const Size(1, 100000),
      const Size(8000, 6000)
    ]) {
      for (final dpr in [1.0, 3.0, 4.0]) {
        for (final zoom in [1.0, 1.5, 4.0, 10.0]) {
          final display = Size(390, 390 * source.height / source.width);
          final grid = ImagePreviewRegionGrid(
              source: source, display: display, pixelRatio: dpr, zoom: zoom);
          final indices =
              grid.visible(Rect.fromLTWH(0, display.height / 2, 390, 844));
          expect(indices.length, lessThanOrEqualTo(48));
          for (final index in indices) {
            final src = grid.sourceRect(index), dst = grid.decodeSize(index);
            expect(src.left, greaterThanOrEqualTo(0));
            expect(src.right, lessThanOrEqualTo(source.width));
            expect(src.bottom, lessThanOrEqualTo(source.height));
            expect(dst.width * dst.height, lessThanOrEqualTo(512 * 512));
          }
        }
      }
    }
  });
  test(
      'wide images use columns and zoom changes sampling without distorting aspect',
      () {
    final a = ImagePreviewRegionGrid(
        source: const Size(30000, 1000),
        display: const Size(390, 13),
        pixelRatio: 3,
        zoom: 1);
    final b = ImagePreviewRegionGrid(
        source: const Size(30000, 1000),
        display: const Size(390, 13),
        pixelRatio: 3,
        zoom: 4);
    expect(b.columns, greaterThan(a.columns));
    expect(b.sourceSide, lessThan(a.sourceSide));
    expect(b.display, a.display);
    final rect = b.displayRect(b.columns - 1);
    expect(rect.right, closeTo(390, 0.001));
    expect(b.displayRect(0).width / b.sourceRect(0).width,
        closeTo(b.displayRect(0).height / b.sourceRect(0).height, 0.00001));
  });
}
