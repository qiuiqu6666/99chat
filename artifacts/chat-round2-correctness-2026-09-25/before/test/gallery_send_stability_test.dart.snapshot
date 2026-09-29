import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  test('six picker pins coalesce and survive a slow nested picker dismissal',
      () async {
    final model = serviceLocator<TUIChatGlobalModel>();
    const conversation = 'c2c_picker-pin';
    model.setCurrentConversation(
        CurrentConversation(conversation, ConvType.c2c),
        notify: false);
    addTearDown(() => model.clearCurrentConversation());
    final before = model.pinToBottomRequestSeq;
    model.beginMediaPickerOverlay();
    model.beginMediaPickerOverlay();
    model.setChatListUserScrolling(true);
    for (var i = 0; i < 6; i++) {
      model.requestPinToBottom(conversation, force: i == 0);
    }
    // Longer than the old bounded force-pin retry window.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(model.pinToBottomRequestSeq, before);
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before);
    expect(model.isMediaPickerOverlayOpen, isTrue);
    model.endMediaPickerOverlay();
    expect(model.isChatListUserScrolling, isFalse);
    expect(model.pinToBottomRequestSeq, before + 1);
    expect(model.pinToBottomRequestConvId, conversation);
    expect(model.pinToBottomForce, isTrue);
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before + 1);
  });

  test('picker cancellation without sends does not scroll', () {
    final model = serviceLocator<TUIChatGlobalModel>();
    final before = model.pinToBottomRequestSeq;
    model.beginMediaPickerOverlay();
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before);
  });

  test('picker pins use the active chat alias and preserve a forced request',
      () {
    final model = serviceLocator<TUIChatGlobalModel>();
    model.setCurrentConversation(
        CurrentConversation('picker-alias', ConvType.c2c),
        notify: false);
    addTearDown(() => model.clearCurrentConversation());
    final before = model.pinToBottomRequestSeq;
    model.beginMediaPickerOverlay();
    model.requestPinToBottom('c2c_picker-alias', force: true);
    model.requestPinToBottom('picker-alias');
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before + 1);
    expect(model.pinToBottomRequestConvId, 'picker-alias');
    expect(model.pinToBottomForce, isTrue);
  });

  test('old conversation deferred pin cannot move a newly opened chat', () {
    final model = serviceLocator<TUIChatGlobalModel>();
    model.setCurrentConversation(
        CurrentConversation('c2c_picker-old', ConvType.c2c),
        notify: false);
    addTearDown(() => model.clearCurrentConversation());
    final before = model.pinToBottomRequestSeq;
    model.beginMediaPickerOverlay();
    model.requestPinToBottom('c2c_picker-old', force: true);
    model.setCurrentConversation(
        CurrentConversation('c2c_picker-new', ConvType.c2c),
        notify: false);
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before);
    model.clearCurrentConversation();
    model.beginMediaPickerOverlay();
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before);
  });

  test('preview remains stable through upload path and receipt changes', () {
    final preview = ChatOutgoingImagePreviewLatch();
    final files = {'/picker/original.jpg', '/stage/source.jpg', '/upload.jpg'};
    String? resolve(String identity, String path) => preview.resolve(
          identity: identity,
          candidates: [path],
          fileExists: files.contains,
        );
    expect(resolve('chat|stable-1', '/picker/original.jpg'),
        '/picker/original.jpg');
    expect(
        resolve('chat|stable-1', '/stage/source.jpg'), '/picker/original.jpg');
    expect(resolve('chat|stable-1', '/upload.jpg'), '/picker/original.jpg');
    files.remove('/picker/original.jpg');
    expect(resolve('chat|stable-1', '/upload.jpg'), '/upload.jpg');
    expect(resolve('chat|stable-2', '/stage/source.jpg'), '/stage/source.jpg');
    expect(resolve('chat|stable-3', '/missing.jpg'), isNull);
  });

  test('async header batch preserves order and sniffs picker file contents',
      () async {
    final directory = await Directory.systemTemp.createTemp('gallery-header-');
    addTearDown(() => directory.delete(recursive: true));
    final paths = <String>[];
    for (var i = 0; i < 6; i++) {
      final bytes = Uint8List(24);
      bytes.setRange(0, 8, [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);
      final data = ByteData.sublistView(bytes);
      data.setUint32(16, 100 + i);
      data.setUint32(20, 200 + i);
      final file = File('${directory.path}/$i.jpg');
      await file.writeAsBytes(bytes);
      paths.add(file.path);
    }
    final sizes = await Future.wait(paths.map(readLocalImageSizeFromHeader));
    expect(sizes.map((size) => size?.width), [100, 101, 102, 103, 104, 105]);
    expect(sizes.map((size) => size?.height), [200, 201, 202, 203, 204, 205]);
    expect(await readLocalImageSizeFromHeader('${directory.path}/missing'),
        isNull);
    final invalid = File('${directory.path}/invalid');
    await invalid.writeAsBytes([1, 2, 3]);
    expect(await readLocalImageSizeFromHeader(invalid.path), isNull);
    final gif = File('${directory.path}/animation.gif');
    await gif.writeAsBytes(base64Decode(
        'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'));
    expect(await readLocalImageSizeFromHeader(gif.path), isNull);
    final gifSize = await probeLocalImageSize(gif.path);
    expect(gifSize?.width, 1);
    expect(gifSize?.height, 1);
  });

  test('gallery production path avoids sync probes and releases picker early',
      () {
    const root = 'third_party/tencent_cloud_chat_uikit/lib/';
    final panel = File('${root}ui/views/TIMUIKitChat/TIMUIKitTextField/'
            'tim_uikit_more_panel.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final start = panel.indexOf('Future<void> _dispatchSystemPickedMedia(');
    final end = panel.indexOf('void _enqueueGalleryImage(', start);
    final dispatch = panel.substring(start, end);
    expect(dispatch, contains('readLocalImageSizeFromHeader(file.path)'));
    expect(dispatch, contains('probeSizeSynchronously: false'));
    expect(dispatch, isNot(contains('probeSizeSynchronously: true')));
    expect(dispatch, contains('imageWidth: imageSizes[i]?.width.round()'));
    expect(
        panel,
        contains('await dismissPicker();\n'
            '            await _dispatchSystemPickedMedia('));
    final model = File('${root}business_logic/separate_models/'
            'tui_chat_separate_view_model.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final send = model.substring(
        model.indexOf(
            '  Future<V2TimValueCallback<V2TimMessage>?> sendImageMessage('),
        model.indexOf('  Size? _resolveImageSizeForSend('));
    expect(send, isNot(contains('readLocalImageSizeSync')));
    expect(send, contains('knownSourceSize: knownLayoutSize'));
    expect(model,
        contains('setImageDecodeStagger(optimistic, inputs.length > 1)'));
    expect(send.indexOf('enqueueSelectedPhoto'),
        greaterThan(send.indexOf('await _sendMessage(')));
    final bubble = File('${root}ui/views/TIMUIKitChat/TIMUIKitMessageItem/'
            'tim_uikit_chat_image_elem.dart')
        .readAsStringSync();
    expect(bubble, contains('_outgoingPreview.resolve('));
    expect(bubble, contains('previousPreviewPath != nextPreviewPath'));
  });
}
