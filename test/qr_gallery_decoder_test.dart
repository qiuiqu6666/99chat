import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tencent_cloud_chat_demo/src/utils/qr_gallery_decoder.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_app_payload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const savedCard =
      'test/fixtures/qr_gallery/IMAGE_2026-06-20_21_22_37-56b1a881-05d3-45e7-b6b2-8ee6d77e0cf7.png';
  const screenshot =
      'test/fixtures/qr_gallery/IMAGE_2026-06-20_21_22_39-e3caf051-8631-41c6-bc49-fb42868d0d79.png';

  Future<void> expectDecoded(String path, Pattern idFragment) async {
    final sw = Stopwatch()..start();
    final value = await QrGalleryDecoder.decodeFromPath(path);
    sw.stop();
    expect(value, isNotNull, reason: 'failed to decode $path');
    expect(value!, contains(idFragment));
    expect(
      sw.elapsedMilliseconds,
      lessThan(10000),
      reason: 'decode took ${sw.elapsedMilliseconds}ms',
    );
  }

  test('decodes saved QR card image quickly', () async {
    await expectDecoded(savedCard, 'acnj6oxey9');
  });

  test('decodes full-page QR screenshot', () async {
    await expectDecoded(screenshot, 'jc1kbqdxvf');
  });

  test('pickPreferred favors app business payload', () {
    final preferred = QrGalleryDecoder.pickPreferred([
      'https://example.com',
      '{"type":"user","id":"u_abc","name":"n"}',
    ]);
    expect(preferred, contains('u_abc'));
  });

  test('returns null quickly for image without QR code', () async {
    final plain = img.Image(width: 640, height: 960);
    img.fill(plain, color: img.ColorRgb8(120, 180, 220));
    final tempDir = await Directory.systemTemp.createTemp('qr_gallery_test_');
    final path = '${tempDir.path}/plain.png';
    await File(path).writeAsBytes(img.encodePng(plain));

    final sw = Stopwatch()..start();
    final value = await QrGalleryDecoder.decodeFromPath(path);
    sw.stop();

    expect(value, isNull);
    expect(
      sw.elapsedMilliseconds,
      lessThan(10000),
      reason: 'no-QR decode took ${sw.elapsedMilliseconds}ms',
    );
    await tempDir.delete(recursive: true);
  });

  test('sync zxing2 helper decodes fixture', () {
    final value = QrGalleryDecoder.decodeZxingFromPathForTest(savedCard);
    expect(value, contains('acnj6oxey9'));
  });

  String appCode(String id, {QrAppPayloadType type = QrAppPayloadType.user}) =>
      QrAppPayload.encode(baseUrl: 'https://99chat.vip/', type: type, id: id);

  test('current URL codes take priority over unrelated links', () {
    for (final type in QrAppPayloadType.values) {
      final value = appCode('@TGS#_@TGS#cLFXJRIM62C5', type: type);
      expect(QrGalleryDecoder.pickPreferred(['https://example.com', value]),
          value);
    }
  });

  test('legacy JSON and URL for same target require no duplicate choice', () {
    final url = appCode('user-a');
    expect(
        QrGalleryDecoder.preferredCandidates([
          '  $url  ',
          '{"type":"user","id":"user-a","name":"Old name"}',
          url,
        ]),
        [url]);
  });

  test('different targets require choice even with the same display name', () {
    final values = [appCode('user-a'), appCode('user-b')];
    expect(QrGalleryDecoder.pickPreferred(values), isNull);
    expect(QrGalleryDecoder.preferredCandidates(values), values);
    // Group and user IDs occupy different namespaces.
    expect(
        QrGalleryDecoder.preferredCandidates([
          appCode('same'),
          appCode('same', type: QrAppPayloadType.group),
        ]),
        hasLength(2));
  });

  test('web login is prioritized but not chosen over another app target', () {
    const login = '{"type":"web_login","sessionId":"secret","v":1}';
    expect(QrGalleryDecoder.pickPreferred(['other text', login]), login);
    expect(QrGalleryDecoder.pickPreferred([appCode('a'), login]), isNull);
  });

  test('wallet mode retains non-app codes for address filtering', () {
    final url = appCode('a');
    expect(
        QrGalleryDecoder.preferredCandidates(
          ['  address  ', '', 'address', url],
          preferAppCodes: false,
        ),
        ['address', url]);
  });

  test('worker decodes bitmap once and diagnostics do not contain payloads',
      () async {
    final result =
        await QrGalleryDecoder.scan(savedCard, collectDiagnostics: true);
    expect(result.status, 'ok');
    expect(result.diagnostics['imageDecodes'], 1);
    expect(result.diagnostics['elapsedMs'], isA<int>());
    expect(result.diagnostics.toString(), isNot(contains(savedCard)));
    expect(result.diagnostics.toString(), isNot(contains('acnj6oxey9')));
  });

  test('pre-cancelled and zero-budget tasks do not decode', () async {
    final cancel = QrGalleryCancellation()..cancel();
    expect(
        (await QrGalleryDecoder.scan(savedCard, cancellation: cancel)).status,
        'cancelled');
    expect(
        (await QrGalleryDecoder.scan(savedCard, timeout: Duration.zero)).status,
        'timeout');
  });

  test('large bitmap work remains cancellable and event loop stays responsive',
      () async {
    final directory = await Directory.systemTemp.createTemp('qr_cancel_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/large.bmp';
    // Uncompressed data ensures a real worker has meaningful bitmap work.
    await File(path)
        .writeAsBytes(img.encodeBmp(img.Image(width: 3000, height: 3000)));
    final cancellation = QrGalleryCancellation();
    var heartbeatTicks = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 5), (_) {
      heartbeatTicks++;
      if (heartbeatTicks == 4) cancellation.cancel();
    });
    addTearDown(heartbeat.cancel);
    final result =
        await QrGalleryDecoder.scan(path, cancellation: cancellation);
    heartbeat.cancel();
    expect(heartbeatTicks, greaterThanOrEqualTo(4));
    expect(result.status, 'cancelled');
    expect(result.values, isEmpty);
    final timedOut = await QrGalleryDecoder.scan(path,
        timeout: const Duration(milliseconds: 5));
    expect(timedOut.status, 'timeout');
    expect(timedOut.values, isEmpty);
    // No stale cancellation/deadline state contaminates the next request.
    expect((await QrGalleryDecoder.scan(screenshot)).status, 'ok');
  });

  test('invalid image and oversized file return explicit statuses', () async {
    expect((await QrGalleryDecoder.scan('')).status, 'invalid_image');
    final directory = await Directory.systemTemp.createTemp('qr_invalid_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/invalid.png');
    await file.writeAsString('not an image');
    expect((await QrGalleryDecoder.scan(file.path)).status, 'invalid_image');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(32 * 1024 * 1024 + 1);
    await handle.close();
    expect((await QrGalleryDecoder.scan(file.path)).status, 'too_large');
  });
}
