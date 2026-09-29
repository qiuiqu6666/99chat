import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/complaint_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/complaint/complaint_form_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/feedback_success_view.dart';

void main() {
  for (final group in [false, true]) {
    testWidgets(
        'complaint preserves ${group ? 'group' : 'private'} payload and returns true after acknowledgement',
        (tester) async {
      PackageInfo.setMockInitialValues(
          appName: 'Test',
          packageName: 'test',
          version: '1',
          buildNumber: '1',
          buildSignature: '');
      final dio = ApiClient.instance.dio;
      final original = dio.interceptors.toList();
      final pending = Completer<void>();
      RequestOptions? request;
      dio.interceptors.clear();
      dio.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) async {
        request = options;
        await pending.future;
        handler.resolve(Response(
            requestOptions: options, statusCode: 200, data: {'id': 1}));
      }));
      addTearDown(() {
        dio.interceptors.clear();
        dio.interceptors.addAll(original);
      });
      bool? result;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                                builder: (_) => ComplaintFormPage(
                                    reportedUserId: 'reported-user',
                                    reportedUserName: 'Test user',
                                    reason: ComplaintReason.spam,
                                    groupId: group ? 'group-1' : null,
                                    msgKey: 'message-key',
                                    msgSeq: 42)));
                      },
                      child: const Text('Previous page'))))));
      await tester.tap(find.text('Previous page'));
      await tester.pumpAndSettle();
      // Additional details stay optional, unlike the feedback page.
      await tester
          .ensureVisible(find.byKey(const ValueKey('complaint-submit')));
      await tester.tap(find.byKey(const ValueKey('complaint-submit')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(FeedbackSuccessView), findsNothing);
      expect(request, isNotNull);
      expect(request!.data['reportedUserId'], 'reported-user');
      expect(request!.data['reason'], 'spam');
      expect(request!.data['msgKey'], 'message-key');
      expect(request!.data['msgSeq'], 42);
      expect(request!.data.containsKey('content'), isFalse);
      expect(request!.data['groupId'], group ? 'group-1' : null);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackSuccessView), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.byKey(const ValueKey('feedback-success-done')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.text('Previous page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('complaint handles long names and large text in dark mode',
      (tester) async {
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: ComplaintFormPage(
            reportedUserId: 'test',
            reportedUserName: 'A very long name ' * 10,
            reason: ComplaintReason.spam)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('complaint-submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
