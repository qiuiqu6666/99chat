import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';

void main() {
  testWidgets('update close button dismisses route without starting download',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppNavigator.key,
      home: const Scaffold(body: Text('home')),
    ));
    var confirmed = false;
    var completed = false;
    final dialog = AppDialog.showUpdateDialog(
      title: '发现新版本',
      message: '体验全面升级',
      showCloseButton: true,
      onConfirm: () => confirmed = true,
    ).then((_) => completed = true);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(confirmed, isFalse);
    expect(completed, isTrue);
    expect(AppDialog.isShowing, isFalse);
    await dialog;
  });

  testWidgets('force update confirm launches download without dismissing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppNavigator.key,
      home: const Scaffold(body: Text('home')),
    ));
    var confirmed = false;
    unawaited(AppDialog.showUpdateDialog(
      title: '发现新版本',
      message: '体验全面升级',
      showCloseButton: false,
      onConfirm: () => confirmed = true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(AppDialog.isShowing, isTrue);
    AppDialog.dismiss();
    await tester.pumpAndSettle();
  });

  testWidgets('force update system back does not dismiss', (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppNavigator.key,
      home: const Scaffold(body: Text('home')),
    ));
    unawaited(AppDialog.showUpdateDialog(
      title: '发现新版本',
      message: '体验全面升级',
      showCloseButton: false,
      onConfirm: () {},
    ));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(AppDialog.isShowing, isTrue);
    AppDialog.dismiss();
    await tester.pumpAndSettle();
  });

  testWidgets('optional update confirm dismisses and starts download',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppNavigator.key,
      home: const Scaffold(body: Text('home')),
    ));
    var confirmed = false;
    var completed = false;
    final dialog = AppDialog.showUpdateDialog(
      title: '发现新版本',
      message: '体验全面升级',
      showCloseButton: true,
      onConfirm: () => confirmed = true,
    ).then((_) => completed = true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(find.text('发现新版本'), findsNothing);
    expect(completed, isTrue);
    expect(AppDialog.isShowing, isFalse);
    await dialog;
  });

  testWidgets('update dialog follows dark theme text colors', (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppNavigator.key,
      theme: ThemeData.dark(),
      home: const Scaffold(body: Text('home')),
    ));
    unawaited(AppDialog.showUpdateDialog(
      title: '发现新版本',
      message: '体验全面升级',
      showCloseButton: true,
      onConfirm: () {},
    ));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    final title = tester.widget<Text>(find.text('发现新版本'));
    expect(title.style?.color, AppColors.darkText);
    final body = tester.widget<Text>(find.text('体验全面升级'));
    expect(body.style?.color, AppColors.darkSubText);
    AppDialog.dismiss();
    await tester.pumpAndSettle();
  });
}
