import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_tile_geometry.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_decode_policy.dart';

void main() {
  test('record real layout policy across screen and image sizes', () {
    for (final screen in [(320.0, 568.0, 2.0), (390.0, 844.0, 3.0),
        (844.0, 390.0, 3.0), (1024.0, 1366.0, 2.0), (1920.0, 1080.0, 1.0)]) {
      for (final img in [(64,64), (120,2400), (1080,2340), (1080,2400),
          (1080,12000), (1080,100000), (30000,1000), (8000,6000), (1,100000)]) {
        final c = imagePreviewDisplayConfig(imageWidth: img.$1, imageHeight: img.$2,
            screenWidth: screen.$1, screenHeight: screen.$2);
        final size = imagePreviewInitialDisplaySize(imageWidth: img.$1,
            imageHeight: img.$2, screenWidth: screen.$1, screenHeight: screen.$2, fit: c.fit);
        print(jsonEncode({'screen': '${screen.$1}x${screen.$2}@${screen.$3}',
          'image': '${img.$1}x${img.$2}', 'mode': c.mode.name, 'fit': c.fit.name,
          'display': '${size.width}x${size.height}', 'tile': imagePreviewRequiresTileRenderer(width: img.$1,height:img.$2)}));
        expect(size.width.isFinite && size.height.isFinite, isTrue);
      }
    }
  });
  test('record tile zoom geometry and decode footprint', () {
    ImagePreviewTileGeometry geometry(double scale) => ImagePreviewTileGeometry.from(
        imageWidth:8000, imageHeight:100000, screenWidth:390, screenHeight:844,
        devicePixelRatio:3, scale:scale);
    final a=geometry(1), b=geometry(4);
    print(jsonEncode({'zoom1Width':a.screenWidth, 'zoom4Width':b.screenWidth,
      'zoom1ContentHeight':a.contentHeight, 'zoom4ContentHeight':b.contentHeight,
      'zoom4SingleTileBytes':b.dstWidth*b.dstHeightFor(0)*4}));
    expect(a.contentHeight, b.contentHeight);
    expect(b.dstWidth, greaterThan(a.dstWidth));
  });
}
