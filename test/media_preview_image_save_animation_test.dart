import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/app_hud_indicator.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_chrome.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_save_notice.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tuikit_info_toast.dart';

Widget _host(Future<void> Function() save, {bool downloadOnly = false}) =>
    MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          MediaPreviewBottomBar(onDownload: save, downloadOnly: downloadOnly),
        ]),
      ),
    );

void main() {
  final saveButton = find.byKey(const ValueKey('image-inline-save'));
  final loading = find.byKey(const ValueKey('image-save-loading'));
  late List<String> notices;

  setUp(() {
    notices = [];
    TUIKitInfoToast.presenter = notices.add;
  });
  tearDown(() => TUIKitInfoToast.presenter = null);

  for (final downloadOnly in [false, true]) {
    testWidgets('fast save paints animation before notice (only=$downloadOnly)',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(() async {
        calls++;
        MediaPreviewSaveNotice.show(tester.element(find.byType(Scaffold)),
            success: true);
      }, downloadOnly: downloadOnly));
      await tester.tap(saveButton);
      await tester.pump();
      expect(loading, findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(tester.widget(loading), isA<AppHudIndicator>());
      expect(tester.getSize(loading), const Size(84, 84));
      expect(tester.getCenter(loading),
          tester.getCenter(find.byType(Scaffold)));
      expect(tester.getSize(saveButton), const Size(40, 40));
      expect(notices, isEmpty);
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(loading, findsOneWidget);
      expect(notices, isEmpty);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(calls, 1);
      expect(notices, ['图片已保存']);
      expect(loading, findsNothing);
      expect(saveButton, findsOneWidget);
    });
  }

  testWidgets('pending save ignores repeated taps and keeps original callback',
      (tester) async {
    final done = Completer<void>();
    var firstCalls = 0;
    var nextCalls = 0;
    await tester.pumpWidget(_host(() {
      firstCalls++;
      return done.future;
    }));
    final position = tester.getCenter(saveButton);
    await tester.tapAt(position);
    await tester.tapAt(position);
    await tester.pump();
    await tester.pumpWidget(_host(() async => nextCalls++));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(position);
    await tester.pump(const Duration(seconds: 2));
    expect(firstCalls, 1);
    expect(nextCalls, 0);
    expect(loading, findsOneWidget);
    done.complete();
    await tester.pump();
    expect(loading, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save stops animation and can retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(() async {
      calls++;
      throw StateError('save failed');
    }));
    for (var i = 0; i < 2; i++) {
      await tester.tap(saveButton);
      await tester.pump();
      expect(loading, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(loading, findsNothing);
      expect(saveButton, findsOneWidget);
    }
    expect(calls, 2);
    expect(notices, ['保存失败', '保存失败']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during save does not update a disposed widget',
      (tester) async {
    final done = Completer<void>();
    await tester.pumpWidget(_host(() => done.future));
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    expect(loading, findsNothing);
    done.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
