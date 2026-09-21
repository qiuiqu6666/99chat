import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_file_card.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_file_card.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_file_icon.dart';

import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_video_card.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_video_card.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  test('native file entry delegates presentation without replacing transport',
      () {
    final source = File('third_party/tencent_cloud_chat_uikit/lib/ui/views/'
            'TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_file_elem.dart')
        .readAsStringSync();
    expect(source, contains('child: TIMUIKitFileCard('));
    expect(source, contains('_downloadFromRemoteUrl(remoteUrl, theme)'));
    expect(source, contains('await addUrlToWaitingPath(theme)'));
    expect(source, contains('TIMUIKitMessageReactionWrapper('));
    expect(source, isNot(contains('child: LinearProgressIndicator(')));
  });

  for (final isSelf in [true, false]) {
    testWidgets('large file shares native surface, direction=$isSelf',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        TIMUIKitFileCard(
            name: 'report.zip',
            isSelf: isSelf,
            isLocal: true,
            subtitle: TIMUIKitFileCard.formatSize(1024)),
        ChatAttachmentFileCard(
            name: 'report.zip',
            sizeBytes: 128 * 1024 * 1024,
            isSelf: isSelf,
            isLocal: true,
            busy: false,
            progress: 0,
            error: '',
            onOpen: () => opened++,
            onPause: () {}),
      ]))));
      final cards = find.byType(TIMUIKitFileCard);
      expect(cards, findsNWidgets(2));
      expect(tester.getSize(cards.first),
          Size(240, 72 * TUIKitScreenUtils.compactChatCardScale()));
      expect(tester.getSize(cards.last), tester.getSize(cards.first));
      expect(find.byType(TIMUIKitFileIcon), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(TIMUIKitFileIcon),
          matching: find.byWidgetPredicate((w) {
            if (w is! Image) return false;
            final image = w.image;
            return image is AssetImage && image.assetName == 'assets/wenjian.png';
          }),
        ),
        findsNWidgets(2),
      );
      expect(find.text('1.00 KB'), findsOneWidget);
      expect(find.text('128.00 MB · ZIP'), findsOneWidget);
      final decorations = tester
          .widgetList<Container>(
              find.descendant(of: cards, matching: find.byType(Container)))
          .where((w) => w.decoration is BoxDecoration)
          .map((w) => w.decoration)
          .toList();
      expect(decorations, hasLength(2));
      expect(decorations.first, decorations.last);
      await tester.tap(cards.last);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('downloading file keeps pause and blocks open', (tester) async {
    var opened = 0, paused = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatAttachmentFileCard(
                name: 'report.zip',
                sizeBytes: 128 * 1024 * 1024,
                isSelf: false,
                isLocal: false,
                busy: true,
                progress: .4,
                error: '',
                onOpen: () => opened++,
                onPause: () => paused++))));
    await tester.tap(find.text('下载中 40%'));
    expect(opened, 0);
    await tester.tap(find.byTooltip('暂停下载'));
    expect(paused, 1);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .4);
    expect(tester.takeException(), isNull);
  });

  test('formatSizeWithExtension keeps units and extension', () {
    expect(TIMUIKitFileCard.formatSize(950), '950 B');
    expect(TIMUIKitFileCard.formatSizeWithExtension('a.txt', 3942),
        '3.85 KB · TXT');
    expect(TIMUIKitFileCard.formatSizeWithExtension('noext', 950), '950 B');
    expect(TIMUIKitFileCard.formatSizeWithExtension('file.', 1024), '1.00 KB');
  });

  testWidgets('idle remote file shows download icon, local file does not',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      ChatAttachmentFileCard(
          name: 'report.zip',
          sizeBytes: 1024,
          isSelf: false,
          isLocal: false,
          busy: false,
          progress: 0,
          error: '',
          onOpen: () {},
          onPause: () {}),
      ChatAttachmentFileCard(
          name: 'report.zip',
          sizeBytes: 1024,
          isSelf: false,
          isLocal: true,
          busy: false,
          progress: 0,
          error: '',
          onOpen: () {},
          onPause: () {}),
    ]))));
    tester.takeException();
    expect(
      find.byWidgetPredicate((w) {
        if (w is! Image) return false;
        final image = w.image;
        return image is AssetImage && image.assetName == 'assets/xia.png';
      }),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('long filename ellipsis keeps card width', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TIMUIKitFileCard(
                name: '用户下注明细_349_extra_long_filename.txt',
                isSelf: false,
                isLocal: true,
                subtitle: '3.85 KB · TXT'))));
    expect(tester.getSize(find.byType(TIMUIKitFileCard)),
        Size(240, 72 * TUIKitScreenUtils.compactChatCardScale()));
    expect(find.text('用户下注明细_349_extra_long_filename.txt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('native video retains preview and delegates its surface', () {
    final source = File('third_party/tencent_cloud_chat_uikit/lib/ui/views/'
            'TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_video_elem.dart')
        .readAsStringSync();
    expect(source, contains('child: TIMUIKitVideoCard('));
    expect(source, contains('_openMobileMediaPreview(heroTag)'));
    expect(source, contains('child: PreviewHero('));
    expect(source, contains('TIMUIKitMessageReactionWrapper('));
    expect(source, contains('overlay: TimUIKitMessageUploadOverlayLayer('));
  });

  for (final ratio in [9 / 16, 16 / 9]) {
    testWidgets('large video shares native dimensions and play asset $ratio',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        TIMUIKitVideoCard(
            aspectRatio: ratio,
            durationMs: 65000,
            cover: const SizedBox.expand()),
        ChatAttachmentVideoCard(
            sizeBytes: 128 * 1024 * 1024,
            videoWidth: ratio < 1 ? 9 : 16,
            videoHeight: ratio < 1 ? 16 : 9,
            durationMs: 65000,
            onOpen: () {}),
      ]))));
      final surfaces = find.byType(TIMUIKitVideoCard);
      expect(surfaces, findsNWidgets(2));
      expect(tester.getSize(surfaces.first), tester.getSize(surfaces.last));
      expect(tester.getSize(surfaces.first).height,
          lessThanOrEqualTo(250 * TUIKitScreenUtils.compactChatCardScale()));
      expect(find.text('1:05'), findsNWidgets(2));
      final clips = tester.widgetList<ClipRRect>(
          find.descendant(of: surfaces, matching: find.byType(ClipRRect)));
      expect(
          clips.every((c) => c.borderRadius == TIMUIKitVideoCard.borderRadius),
          isTrue);
      expect(
          find.byWidgetPredicate((w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == 'images/play.png'),
          findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}
