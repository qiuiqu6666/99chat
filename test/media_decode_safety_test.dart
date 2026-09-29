import 'dart:io';
import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_media_work_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('predecode sample preserves current target for 12MP, 48MP and tall text',
      () {
    expect(chatImageDecodeAdmission(const Size(4000, 3000)).sampleSize, 1);
    expect(chatImageDecodeAdmission(const Size(8000, 6000)).sampleSize, 2);
    expect(chatImageDecodeAdmission(const Size(6000, 8000)).sampleSize, 2);
    expect(chatImageDecodeAdmission(const Size(1080, 12000)).sampleSize, 1);
    expect(chatImageDecodeAdmission(const Size(1, 1)).sampleSize, 1);
    expect(chatImageDecodeAdmission(const Size(1, 65535)).sampleSize,
        greaterThan(1));
    expect(() => chatImageDecodeAdmission(const Size(double.infinity, 1)),
        throwsArgumentError);
    for (final size in [
      const Size(4000, 3000),
      const Size(8000, 6000),
      const Size(1080, 12000)
    ]) {
      final target = resolveChatImageSendTargetSize(
          sourceWidth: size.width, sourceHeight: size.height);
      final sample = chatImageDecodeAdmission(size).sampleSize;
      expect(size.width / sample, greaterThanOrEqualTo(target.width));
      expect(size.height / sample, greaterThanOrEqualTo(target.height));
    }
  });
  test(
      'weighted decode queue serializes large jobs, admits small jobs and releases failures',
      () async {
    final queue = OutgoingMediaWorkQueue(maxConcurrent: 2, maxWeight: 100);
    final gate = Completer<void>();
    final started = <String>[];
    final big = queue.run(() async {
      started.add('big');
      await gate.future;
      throw StateError('encoder');
    }, weight: 150);
    final failed = expectLater(big, throwsStateError);
    final first = queue.run(() async {
      started.add('a');
    }, weight: 40);
    final second = queue.run(() async {
      started.add('b');
    }, weight: 40);
    expect(started, ['big']);
    gate.complete();
    await failed;
    await Future.wait([first, second]);
    expect(started, ['big', 'a', 'b']);
  });
  test('small encoded JPEG still needs preparation when pixels are large',
      () async {
    final dir = await Directory.systemTemp.createTemp('pixel_budget_');
    try {
      final image = File('${dir.path}/large.jpg');
      await image.writeAsBytes([
        0xff,
        0xd8,
        0xff,
        0xc0,
        0,
        17,
        8,
        0x17,
        0x70,
        0x1f,
        0x40,
        3,
        1,
        0x11,
        0,
        2,
        0x11,
        0,
        3,
        0x11,
        0,
        0xff,
        0xd9
      ]);
      expect(await readLocalImageSizeFromHeader(image.path),
          const Size(8000, 6000));
      expect(await needsChatImageBackgroundCompression(image.path), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
      'unknown metadata gives a bounded aspect-preserving decode even for original',
      () {
    for (final full in [false, true]) {
      final target = imagePreviewDecodeTarget(
          screenWidth: 390,
          screenHeight: 844,
          devicePixelRatio: 3,
          imageWidth: 0,
          imageHeight: 0,
          preferFullResolution: full);
      expect(target.width, isNotNull);
      expect(target.height, isNotNull);
      final provider = imagePreviewDecodedProvider(
          const NetworkImage('https://example.test/a'),
          target: target);
      expect(provider, isA<ResizeImage>());
      final resized = provider as ResizeImage;
      expect(resized.policy, ResizeImagePolicy.fit);
      expect(resized.allowUpscaling, isFalse);
    }
  });

  test('iOS picker bounds still-image decode and parallel native exports',
      () async {
    final root = Directory.current.path;
    final nativeRoot =
        '$root/third_party/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios';
    final imageUtil =
        await File('$nativeRoot/FLTImagePickerImageUtil.m').readAsString();
    final assetUtil =
        await File('$nativeRoot/FLTImagePickerPhotoAssetUtil.m').readAsString();
    final picker =
        await File('$nativeRoot/FLTImagePickerPlugin.m').readAsString();
    final operation =
        await File('$nativeRoot/FLTPHPickerSaveImageToPathOperation.m')
            .readAsString();

    expect(imageUtil, contains('CGImageSourceCreateThumbnailAtIndex'));
    expect(assetUtil, contains('downsampledImageFromData:originalImageData'));
    final downsample =
        assetUtil.indexOf('downsampledImageFromData:originalImageData');
    expect(downsample, greaterThanOrEqualTo(0));
    expect(assetUtil.substring(downsample), contains('image:image'));
    expect(assetUtil, contains('if (data == nil) return nil;'));
    expect(picker, contains('saveQueue.maxConcurrentOperationCount = 2'));
    expect(picker, contains('Could not export the selected image.'));
    expect(operation, contains('FLTPHPickerGIFDecodeSemaphore'));
    expect(operation, contains('CGImageSourceCreateThumbnailAtIndex'));
  });
}
