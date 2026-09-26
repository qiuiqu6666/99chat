import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Fake the installed platform boundary, including asynchronous native replies.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_gallery_pick_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/gallery_send_perf_trace.dart';

class _NativePicker extends ImagePickerPlatform {
  final reply = Completer<List<XFile>>();
  final requests = <MediaOptions>[];

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) {
    requests.add(options);
    return reply.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImagePickerPlatform original;
  late _NativePicker native;

  setUp(() {
    original = ImagePickerPlatform.instance;
    native = _NativePicker();
    ImagePickerPlatform.instance = native;
  });

  tearDown(() => ImagePickerPlatform.instance = original);

  test('successful native selection preserves files and selection order',
      () async {
    final selection = ChatGalleryPickUtils.pickSystemGalleryMedia();
    final files = [XFile('/selected/second.png'), XFile('/selected/first.mov')];
    native.reply.complete(files);
    expect(await selection, same(files));
    expect(native.requests, hasLength(1));
    final options = native.requests.single;
    expect(options.allowMultiple, isTrue);
    expect(options.limit, 9);
    expect(options.imageOptions.requestFullMetadata, isFalse);
  });

  test('native cancellation is empty, never a request for a second picker',
      () async {
    final selection = ChatGalleryPickUtils.pickSystemGalleryMedia();
    native.reply.complete([]);
    expect(await selection, isEmpty);
    expect(native.requests, hasLength(1));
  });

  for (final failure in <Object>[
    PlatformException(
      code: 'invalid_image',
      message: 'Cannot load representation of type public.jpeg',
      details: 'NSItemProviderErrorDomain',
    ),
    PlatformException(code: 'invalid_source'),
    PlatformException(code: 'invalid_result'),
    PlatformException(code: 'multiple_request'),
    PlatformException(code: 'photo_access_denied'),
    PlatformException(code: 'channel-error'),
    PlatformException(code: 'flutter_image_picker_copy_video_error'),
    StateError('invalid native path'),
    TypeError(),
  ]) {
    final label =
        failure is PlatformException ? failure.code : failure.runtimeType;
    test('$label after confirmation cannot trigger custom picker fallback',
        () async {
      final selection = ChatGalleryPickUtils.pickSystemGalleryMedia();
      final expectation = expectLater(selection, throwsA(same(failure)));
      // The OS sheet opened successfully and only its later completion failed.
      await Future<void>.delayed(Duration.zero);
      native.reply.completeError(failure);
      await expectation;
      expect(native.requests, hasLength(1),
          reason: 'Do not silently reselect.');
    });
  }

  for (final failure in <Object>[
    MissingPluginException('native picker not installed'),
    UnimplementedError('getMedia is not implemented'),
  ]) {
    test('${failure.runtimeType} still permits capability fallback', () async {
      final selection = ChatGalleryPickUtils.pickSystemGalleryMedia();
      native.reply.completeError(failure);
      expect(await selection, isNull);
    });
  }

  test('failure trace retains native error code, message and domain', () async {
    final lines = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    final trace = GallerySendPerfTrace(mode: 'picker_failure_test');
    try {
      final failure = PlatformException(
        code: 'invalid_image',
        message: 'Cannot load representation',
        details: 'NSItemProviderErrorDomain',
      );
      final selection =
          ChatGalleryPickUtils.pickSystemGalleryMedia(perf: trace);
      final expectation = expectLater(selection, throwsA(same(failure)));
      native.reply.completeError(failure);
      await expectation;
      final line = lines.singleWhere(
        (line) => line.contains('event=system_picker_failed'),
      );
      expect(line, contains('code=invalid_image'));
      expect(line, contains('message=Cannot load representation'));
      expect(line, contains('details=NSItemProviderErrorDomain'));
      expect(line, contains('os='));
      expect(lines.any((line) => line.contains('system_picker_unavailable')),
          isFalse);
    } finally {
      trace.markTaskReturned();
      debugPrint = previousPrint;
    }
  });

  test('mobile send entry uses checked picker without swallowing its failures',
      () {
    final panel = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_more_panel.dart',
    ).readAsStringSync();
    expect(panel,
        contains('ChatGalleryPickUtils.pickSystemGalleryMedia(perf: perf)'));
    expect(panel, isNot(contains('_pickSystemGalleryMedia(')));
    expect(panel,
        isNot(contains('system media picker unavailable, use fallback')));
    final send = panel.substring(
      panel.indexOf('  _sendImageMessage('),
      panel.indexOf('  _sendImageFromCamera('),
    );
    final catchPath = send.substring(send.lastIndexOf('} catch (err)'));
    expect(catchPath.indexOf('await dismissPicker();'), greaterThanOrEqualTo(0));
    expect(catchPath.indexOf('await dismissPicker();'),
        lessThan(catchPath.indexOf('_showPanelNotice(')));
    expect(catchPath, contains('图片或视频未能发送，请重试'));
    expect(catchPath, isNot(contains('EditableAssetPicker.pickAssets')));
  });
}
