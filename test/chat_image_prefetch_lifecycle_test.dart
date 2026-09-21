import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';

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
  testWidgets('resized prefetch eviction removes the resolved cache entry',
      (tester) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff112233), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(8, 8);
    picture.dispose();
    final stream = _Completer();
    stream.deliver(ImageInfo(image: image));
    final provider = ResizeImage(_Provider(stream), width: 4);
    final key = await provider.obtainKey(const ImageConfiguration());
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent(key, () => stream);
    expect(cache.containsKey(key), isTrue);
    await ChatImageMessagePrefetch.debugEvictProvider(provider);
    expect(cache.containsKey(key), isFalse);
  });

  testWidgets('prefetch releases every delivered image clone and its listener',
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
    for (var i = 0; i < 30; i++) {
      await ChatImageMessagePrefetch.debugWarmProvider(_Provider(stream));
      expect(image.debugGetOpenHandleStackTraces()!.length, baseline);
      expect(stream.hasListeners, isFalse);
    }
    keepAlive.dispose();
    image.dispose();
  });

  testWidgets('timeout removes the listener without a decoded frame',
      (tester) async {
    final stream = _Completer();
    final future =
        ChatImageMessagePrefetch.debugWarmProvider(_Provider(stream));
    expect(stream.hasListeners, isTrue);
    await tester.pump(const Duration(seconds: 9));
    await future;
    expect(stream.hasListeners, isFalse);
  });
}
