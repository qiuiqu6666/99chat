import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/feedback_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/feedback_success_view.dart';

void main() {
  testWidgets(
      'waits for server success then acknowledges back to previous page',
      (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'test',
        version: '1.0',
        buildNumber: '1',
        buildSignature: '');
    final dio = ApiClient.instance.dio;
    final original = dio.interceptors.toList();
    final pending = Completer<void>();
    var requests = 0;
    dio.interceptors.clear();
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      requests++;
      await pending.future;
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{'id': 1, 'content': 'My feedback'}));
    }));
    addTearDown(() {
      dio.interceptors.clear();
      dio.interceptors.addAll(original);
    });
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const FeedbackPage())),
                      child: const Text('Previous page')),
                ))));
    await tester.tap(find.text('Previous page'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My feedback');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('feedback-submit')));
    await tester.tap(find.byKey(const ValueKey('feedback-submit')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FeedbackSuccessView), findsNothing);
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const ValueKey('feedback-submit')))
            .onPressed,
        isNull);
    pending.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FeedbackSuccessView), findsNothing);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 100));
    final fade = tester.widget<FadeTransition>(find
        .ancestor(
          of: find.byType(FeedbackSuccessView),
          matching: find.byType(FadeTransition),
        )
        .first);
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byType(FeedbackSuccessView), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const ValueKey('feedback-success-done')));
    await tester.pumpAndSettle();
    expect(find.text('Previous page'), findsOneWidget);
    expect(find.byType(FeedbackPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('success view scrolls with large text on a small dark screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: const FeedbackSuccessView()));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('feedback-success-done')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
