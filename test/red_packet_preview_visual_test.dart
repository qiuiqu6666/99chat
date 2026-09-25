import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_open_flow_page.dart';

void main() {
  testWidgets('red packet cover fits phone and compact screens',
      (tester) async {
    final font = FontLoader('PreviewChinese')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'));
    await font.load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'PreviewChinese'),
      home: RepaintBoundary(
        key: boundaryKey,
        child: const ColoredBox(
          color: Color(0xFFE8EDF4),
          child: RedPacketPreviewPage(
              data: RedPacketOpenPreviewData(
            orderId: '3525',
            packetType: 'LUCKY_GROUP',
            greeting: '恭喜发财，大吉大利',
          )),
        ),
      ),
    ));
    await tester.runAsync(() => precacheImage(
          const AssetImage('assets/img/red_packet_preview_cover_v2.png'),
          tester.element(find.byType(RedPacketPreviewPage)),
        ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('開'), findsOneWidget);
    if (Platform.environment['RED_PACKET_CAPTURE'] == '1') {
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('artifacts/red-packet-preview').create(recursive: true);
        await File('artifacts/red-packet-preview/preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('開')).bottom, lessThan(568));
  });
}
