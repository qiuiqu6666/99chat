import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/bootstrap/startup_entry_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live_watch_float_prefs.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_watch_float.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_inline_watch_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async {
    StartupEntryPreferences.configure(() async {});
    await StartupEntryPreferences.ensureReady();
  });
  test('optional warmup joins one actual load and failed load can retry',
      () async {
    var calls = 0;
    final gate = Completer<void>();
    StartupEntryPreferences.configure(() {
      calls++;
      return calls == 1 ? gate.future : Future<void>.value();
    });
    final first = StartupEntryPreferences.ensureReady();
    final second = StartupEntryPreferences.ensureReady();
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    final failure = expectLater(first, throwsStateError);
    gate.completeError(StateError('disk unavailable'));
    await failure;
    expect(StartupEntryPreferences.isReady, isFalse);
    await StartupEntryPreferences.ensureReady();
    expect(calls, 2);
    expect(StartupEntryPreferences.isReady, isTrue);
  });
  for (final initiallyFails in [false, true]) {
    testWidgets(
        'live entry waits for preferences and recovers after failure=$initiallyFails',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'group_live_watch_float_v1:left': 30.0,
        'group_live_watch_float_v1:top': 70.0,
        'group_live_watch_float_v1:width': 400.0,
      });
      final gate = Completer<void>();
      var calls = 0;
      StartupEntryPreferences.configure(() async {
        if (++calls == 1) await gate.future;
        await GroupLiveWatchFloatPrefs.instance.preload();
      });
      final dio = ApiClient.instance.dio;
      final interceptors = dio.interceptors.toList();
      dio.interceptors
        ..clear()
        ..add(InterceptorsWrapper(onRequest: (options, handler) {
          handler.resolve(Response(
              requestOptions: options,
              data: {
                'code': 0,
                'data': {'liveSessionId': 'warmup', 'status': 'SCHEDULED'}
              },
              statusCode: 200));
        }));
      addTearDown(() {
        dio.interceptors
          ..clear()
          ..addAll(interceptors);
      });
      await tester.pumpWidget(MaterialApp(
          home: RouteVisibility(
              isVisible: true,
              child: Scaffold(
                  body: Stack(children: [
                const Text('usable app'),
                GroupLiveWatchFloat(
                    session: const GroupLiveSession(
                        liveSessionId: 'warmup',
                        groupId: 'group',
                        roomName: 'Room',
                        anchorUserId: 'host',
                        status: GroupLiveStatus.scheduled),
                    onClose: () {}),
              ])))));
      expect(find.text('usable app'), findsOneWidget);
      expect(find.byType(GroupLiveInlineWatchBanner), findsNothing);
      if (initiallyFails) {
        gate.completeError(StateError('temporary disk error'));
        await tester.pump();
        expect(find.byType(GroupLiveInlineWatchBanner), findsNothing);
        unawaited(StartupEntryPreferences.ensureReady());
      } else {
        gate.complete();
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(find.byType(GroupLiveInlineWatchBanner), findsOneWidget);
      expect(GroupLiveWatchFloatPrefs.instance.readWidthSync(), 400);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
