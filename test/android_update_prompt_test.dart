import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/android_update_download.dart';
import 'package:tencent_cloud_chat_demo/src/services/android_update_prompt_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';

import 'android_update_download_test.dart'
    show FakeUpdateGateway, updateRequest;

void main() {
  late FakeUpdateGateway gateway;
  late AndroidUpdatePromptService service;

  Future<void> start(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    gateway = FakeUpdateGateway();
    service = AndroidUpdatePromptService.forTesting(
        AndroidUpdateDownloadController(gateway));
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppNavigator.key,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Scaffold(body: Text('home')),
    ));
  }

  Future<void> finish(WidgetTester tester) async {
    service.dispose();
    if (AppDialog.isShowing) AppDialog.dismiss();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'download is silent until verified and dismissed optional release stays dismissed',
      (tester) async {
    await start(tester);
    gateway.current =
        const AndroidUpdateSnapshot('running', request: updateRequest);
    await service.prepare(updateRequest, manual: false);
    await tester.pumpAndSettle();
    expect(find.text('新版本已准备好'), findsNothing);
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await service.download.refresh();
    await tester.pumpAndSettle();
    expect(find.text('新版本已准备好'), findsOneWidget);
    expect(find.text('立即安装'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await service.download.refresh();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('新版本已准备好'), findsNothing);
    expect(gateway.installCalls, 0);
    await finish(tester);
  });

  testWidgets(
      'ready download waits for foreground and restores without page context',
      (tester) async {
    await start(tester);
    await service.restore();
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await service.download.refresh();
    await tester.pumpAndSettle();
    expect(find.text('新版本已准备好'), findsNothing);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('新版本已准备好'), findsOneWidget);
    expect(gateway.ensureCalls, 0);
    expect(gateway.cancelCalls, 0);
    await finish(tester);
  });

  testWidgets('ready update waits for an existing app dialog', (tester) async {
    await start(tester);
    unawaited(AppDialog.showUpdateDialog(
        title: 'existing',
        message: 'busy',
        showCloseButton: true,
        onConfirm: () {}));
    await tester.pumpAndSettle();
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await service.restore();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('新版本已准备好'), findsNothing);
    expect(find.text('existing'), findsOneWidget);
    AppDialog.dismiss();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('新版本已准备好'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('force update stays actionable after failed installation',
      (tester) async {
    await start(tester);
    const forced = AndroidUpdateRequest(
        url: 'https://example.com/app.apk',
        version: '3.0.2',
        build: 21,
        mandatory: true);
    gateway.current = const AndroidUpdateSnapshot('ready', request: forced);
    gateway.onInstall = () async => 'unavailable';
    await service.restore();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await tester.tap(find.text('立即安装'));
    await tester.pumpAndSettle();
    expect(find.text('立即安装'), findsOneWidget);
    gateway.onInstall = null;
    await tester.tap(find.text('立即安装'));
    await tester.pumpAndSettle();
    expect(gateway.installCalls, 2);
    await finish(tester);
  });

  testWidgets(
      'permission return continues once without reopening settings on denial',
      (tester) async {
    await start(tester);
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    gateway.onInstall = () async => 'permission_required';
    await service.restore();
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即安装'));
    await tester.pumpAndSettle();
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    gateway.onInstall = () async => 'permission_denied';
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(gateway.permissions, [true, false]);
    await tester.pump(const Duration(seconds: 5));
    expect(gateway.installCalls, 2);
    expect(find.text('立即安装'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('withdrawn forced release closes its own blocking dialog',
      (tester) async {
    await start(tester);
    const forced = AndroidUpdateRequest(
        url: 'https://example.com/app.apk',
        version: '3.0.2',
        build: 21,
        mandatory: true);
    gateway.current = const AndroidUpdateSnapshot('ready', request: forced);
    await service.restore();
    await tester.pumpAndSettle();
    expect(find.text('立即安装'), findsOneWidget);
    await service.cancel();
    await tester.pumpAndSettle();
    expect(find.text('立即安装'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(AppDialog.isShowing, isFalse);
    await finish(tester);
  });

  testWidgets('cancel does not dismiss an unrelated app dialog',
      (tester) async {
    await start(tester);
    await service.restore();
    unawaited(AppDialog.showUpdateDialog(
        title: 'existing',
        message: 'busy',
        showCloseButton: true,
        onConfirm: () {}));
    await tester.pumpAndSettle();
    await service.cancel();
    await tester.pumpAndSettle();
    expect(find.text('existing'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('withdrawal before first layout cannot strand a blocking route',
      (tester) async {
    await start(tester);
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await service.restore();
    await service.cancel();
    await tester.pumpAndSettle();
    expect(find.text('立即安装'), findsNothing);
    expect(AppDialog.isShowing, isFalse);
    await finish(tester);
  });
}
