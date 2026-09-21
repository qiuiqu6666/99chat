import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/favorite_message_from_im.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';

void main() {
  bool Function(String path) existsIn(Set<String> paths) {
    return (path) => paths.contains(path);
  }

  test('only thumb local returns null', () {
    final file = firstExistingFavoriteImageFile(
      imageList: [
        V2TimImage(type: 1, localUrl: '/thumb.jpg'),
      ],
      exists: existsIn({'/thumb.jpg'}),
    );
    expect(file, isNull);
  });

  test('origin and thumb both local returns origin', () {
    final file = firstExistingFavoriteImageFile(
      imageList: [
        V2TimImage(type: 1, localUrl: '/thumb.jpg'),
        V2TimImage(type: 0, localUrl: '/origin.jpg'),
      ],
      exists: existsIn({'/thumb.jpg', '/origin.jpg'}),
    );
    expect(file?.path, File('/origin.jpg').path);
  });

  test('only big local returns big', () {
    final file = firstExistingFavoriteImageFile(
      imageList: [
        V2TimImage(type: 1, localUrl: '/thumb.jpg'),
        V2TimImage(type: 2, localUrl: '/big.jpg'),
      ],
      exists: existsIn({'/thumb.jpg', '/big.jpg'}),
    );
    expect(file?.path, File('/big.jpg').path);
  });

  test('elemPath exists returns elemPath', () {
    final file = firstExistingFavoriteImageFile(
      elemPath: '/elem.jpg',
      imageList: [
        V2TimImage(type: 0, localUrl: '/origin.jpg'),
      ],
      exists: existsIn({'/elem.jpg', '/origin.jpg'}),
    );
    expect(file?.path, File('/elem.jpg').path);
  });
}
