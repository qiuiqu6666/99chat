import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_save_notice.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tuikit_info_toast.dart';

Widget _host({required Widget child}) => MaterialApp(
      navigatorKey: AppNavigator.key,
      home: Scaffold(body: child),
    );

void main() {
  setUp(() {
    TUIKitInfoToast.presenter = (message) => ToastUtils.toast(message);
  });

  tearDown(() {
    TUIKitInfoToast.presenter = null;
    AppDialog.hideNotice();
  });

  testWidgets('save result is visible above the active route', (tester) async {
    await tester.pumpWidget(
      _host(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaPreviewSaveNotice.show(
              context,
              success: true,
            ),
            child: const Text('save'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('save'));
    await tester.pump();
    expect(find.text('图片已保存'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('图片已保存'), findsNothing);
  });

  testWidgets('failed save has explicit feedback', (tester) async {
    await tester.pumpWidget(
      _host(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaPreviewSaveNotice.show(
              context,
              success: false,
            ),
            child: const Text('save'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('save'));
    await tester.pump();
    expect(find.text('保存失败'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('video success shows 视频已保存', (tester) async {
    await tester.pumpWidget(
      _host(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaPreviewSaveNotice.show(
              context,
              success: true,
              kind: MediaPreviewSaveKind.video,
            ),
            child: const Text('save'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('save'));
    await tester.pump();
    expect(find.text('视频已保存'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('视频已保存'), findsNothing);
  });

  testWidgets('video failure shows 保存失败', (tester) async {
    await tester.pumpWidget(
      _host(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaPreviewSaveNotice.show(
              context,
              success: false,
              kind: MediaPreviewSaveKind.video,
            ),
            child: const Text('save'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('save'));
    await tester.pump();
    expect(find.text('保存失败'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 200));
  });
}
