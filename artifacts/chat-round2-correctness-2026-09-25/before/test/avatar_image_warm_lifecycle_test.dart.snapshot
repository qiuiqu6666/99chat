import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';

class _Provider extends ImageProvider<_Provider> {
  _Provider(this.completer);
  final ImageStreamCompleter completer;

  @override
  Future<_Provider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(ImageConfiguration configuration, ImageStream stream,
      _Provider key, ImageErrorListener handleError) {
    stream.setCompleter(completer);
  }
}

class _Completer extends ImageStreamCompleter {
  void deliver(ImageInfo info) => setImage(info);
}

void main() {
  tearDown(AvatarImageWarm.clearRetainedDecoded);

  testWidgets('avatar warm releases every delivered frame clone',
      (tester) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff112233), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(8, 8);
    picture.dispose();
    final stream = _Completer();
    final keepAlive = stream.keepAlive();
    stream.deliver(ImageInfo(image: image.clone()));
    final baseline = image.debugGetOpenHandleStackTraces()!.length;
    await AvatarImageWarm.debugWarmProvider(_Provider(stream));
    expect(stream.hasListeners, isTrue);
    expect(image.debugGetOpenHandleStackTraces()!.length, baseline);
    for (var i = 0; i < 30; i++) {
      stream.deliver(ImageInfo(image: image.clone()));
      expect(image.debugGetOpenHandleStackTraces()!.length, baseline);
    }
    AvatarImageWarm.clearRetainedDecoded();
    expect(stream.hasListeners, isFalse);
    keepAlive.dispose();
    image.dispose();
  });

  testWidgets('avatar warm timeout removes its listener', (tester) async {
    final stream = _Completer();
    final future = AvatarImageWarm.debugWarmProvider(_Provider(stream));
    expect(stream.hasListeners, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await future;
    expect(stream.hasListeners, isFalse);
  });
}
