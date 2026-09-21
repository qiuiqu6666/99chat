import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/services/sangong_admin_realtime_service.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_admin_realtime_state.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_game/group_game_status_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = SangongAdminRealtimeService.instance;
  final streams = <StreamController<Uint8List>>[];
  var snapshotCalls = 0;
  var total = 100;
  var version = 1;
  RequestInterceptorHandler? heldSnapshot;
  RequestOptions? heldOptions;
  var holdNextSnapshot = false;
  var failNextStream = false;
  Map<String, dynamic> state(int v, int amount) => {
        'version': v,
        'round': {'id': 1, 'betWindowOpenAt': '2026-09-16T01:00:00Z'},
        'pending': {
          'doorTotals': {'2': amount}
        },
      };
  void push(int v, int amount) {
    streams.last.add(Uint8List.fromList(utf8.encode(
      'event: state\ndata: ${jsonEncode(state(v, amount))}\n\n',
    )));
  }

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.saveToken('a' * 40, userId: 'realtime-test');
    SangongGameHttp.setTenantId('realtime-group', persist: false);
    total = 100;
    version = 1;
    snapshotCalls = 0;
    holdNextSnapshot = false;
    failNextStream = false;
    heldSnapshot = null;
    heldOptions = null;
    SangongGameHttp.adminClient.interceptors.clear();
    SangongGameHttp.adminClient.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) {
        if (options.path.endsWith('/snapshot')) {
          snapshotCalls++;
          if (holdNextSnapshot) {
            holdNextSnapshot = false;
            heldSnapshot = handler;
            heldOptions = options;
            return;
          }
          handler.resolve(
              Response(requestOptions: options, data: state(version, total)));
        } else if (options.path.endsWith('/stream')) {
          if (failNextStream) {
            failNextStream = false;
            handler.reject(DioError(requestOptions: options, error: 'Offline'));
            return;
          }
          final stream = StreamController<Uint8List>();
          streams.add(stream);
          handler.resolve(Response(
            requestOptions: options,
            data: ResponseBody(stream.stream, 200, headers: {
              Headers.contentTypeHeader: ['text/event-stream'],
            }),
          ));
        } else {
          handler.reject(
              DioError(requestOptions: options, error: 'Unexpected request'));
        }
      }),
    );
  });

  tearDown(() async {
    while (service.isActive) {
      service.release();
    }
    for (final stream in streams) {
      unawaited(stream.close());
    }
    streams.clear();
    SangongGameHttp.adminClient.interceptors.clear();
  });

  testWidgets('a closed stream recovers missed totals without leaving chat',
      (tester) async {
    service.acquire();
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 100);
    total = 250;
    version = 2;
    unawaited(streams.last.close());
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 250);
    service.release();
    await flush(tester);
  });

  testWidgets('silent stream gets a bounded snapshot fallback', (tester) async {
    service.acquire();
    await flush(tester);
    total = 350;
    version = 3;
    await tester.pump(const Duration(seconds: 16));
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 350);
    service.release();
    await flush(tester);
  });

  testWidgets('late snapshot cannot roll back a newer pushed total',
      (tester) async {
    service.acquire();
    await flush(tester);
    holdNextSnapshot = true;
    final refresh = service.refreshSnapshot();
    await flush(tester);
    push(5, 500);
    await flush(tester);
    heldSnapshot!
        .resolve(Response(requestOptions: heldOptions!, data: state(2, 200)));
    await flush(tester);
    await refresh;
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 500);
    service.release();
    await flush(tester);
  });

  testWidgets('returning from background refreshes totals immediately',
      (tester) async {
    service.acquire();
    await flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final before = snapshotCalls;
    total = 450;
    version = 4;
    await tester.pump(const Duration(seconds: 31));
    await flush(tester);
    expect(snapshotCalls, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 450);
    service.release();
    await flush(tester);
  });

  testWidgets('healthy pushes update the mounted banner and defer fallback',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: StreamBuilder<SangongAdminRealtimeState>(
        stream: service.states,
        builder: (context, snapshot) => snapshot.hasData
            ? GroupGameStatusBanner(
                doorCount: snapshot.data!.doorCount,
                roundStatus: snapshot.data!.toGroupGameRoundStatus(),
              )
            : const SizedBox(),
      ),
    ));
    service.acquire();
    await flush(tester);
    expect(find.textContaining('共100注'), findsOneWidget);
    final initialCalls = snapshotCalls;
    for (var i = 2; i <= 4; i++) {
      await tester.pump(const Duration(seconds: 10));
      push(i, i * 100);
      await flush(tester);
      expect(find.textContaining('共${i * 100}注'), findsOneWidget);
    }
    expect(snapshotCalls, initialCalls);
    service.release();
    await flush(tester);
  });

  testWidgets('concurrent refreshes share one HTTP snapshot', (tester) async {
    service.acquire();
    await flush(tester);
    final before = snapshotCalls;
    holdNextSnapshot = true;
    final first = service.refreshSnapshot();
    final second = service.refreshSnapshot();
    await flush(tester);
    expect(snapshotCalls, before + 1);
    heldSnapshot!
        .resolve(Response(requestOptions: heldOptions!, data: state(5, 500)));
    await flush(tester);
    await Future.wait([first, second]);
    service.release();
    await flush(tester);
  });

  testWidgets(
      'tenant switch during startup ignores the old snapshot and reconnects',
      (tester) async {
    holdNextSnapshot = true;
    service.acquire();
    await flush(tester);
    expect(heldSnapshot, isNotNull);
    total = 700;
    version = 7;
    SangongGameHttp.setTenantId('second-group', persist: false);
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 700);
    heldSnapshot!
        .resolve(Response(requestOptions: heldOptions!, data: state(99, 9900)));
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 700);
    push(8, 800);
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 800);
    service.release();
    await flush(tester);
  });

  testWidgets('releasing one of two subscribers keeps the other live',
      (tester) async {
    service.acquire();
    service.acquire();
    await flush(tester);
    expect(streams.length, 1);
    service.release();
    push(2, 200);
    await flush(tester);
    expect(service.isActive, isTrue);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 200);
    service.release();
    final before = snapshotCalls;
    await tester.pump(const Duration(seconds: 60));
    await flush(tester);
    expect(service.isActive, isFalse);
    expect(snapshotCalls, before);
  });

  testWidgets('released startup cannot repopulate or block a new subscriber',
      (tester) async {
    holdNextSnapshot = true;
    service.acquire();
    await flush(tester);
    service.release();
    total = 300;
    version = 3;
    service.acquire();
    await flush(tester);
    heldSnapshot!
        .resolve(Response(requestOptions: heldOptions!, data: state(99, 9900)));
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 300);
    service.release();
    await flush(tester);
  });

  testWidgets('a failed connection still retries after a slow initial snapshot',
      (tester) async {
    holdNextSnapshot = true;
    failNextStream = true;
    service.acquire();
    await flush(tester);
    await tester.pump(const Duration(seconds: 2));
    await flush(tester);
    heldSnapshot!
        .resolve(Response(requestOptions: heldOptions!, data: state(1, 100)));
    await flush(tester);
    await tester.pump(const Duration(seconds: 3));
    await flush(tester);
    expect(streams, isNotEmpty);
    push(3, 300);
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 300);
    service.release();
    await flush(tester);
  });

  testWidgets(
      'partial SSE from a closed connection cannot corrupt its replacement',
      (tester) async {
    service.acquire();
    await flush(tester);
    streams.last.add(
        Uint8List.fromList(utf8.encode('event: state\ndata: {"version":')));
    await flush(tester);
    unawaited(streams.last.close());
    await flush(tester);
    await tester.pump(const Duration(seconds: 3));
    await flush(tester);
    push(3, 300);
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 300);
    service.release();
    await flush(tester);
  });

  testWidgets('a connection with no bytes is replaced after the idle deadline',
      (tester) async {
    service.acquire();
    await flush(tester);
    final before = streams.length;
    await tester.pump(const Duration(seconds: 46));
    await flush(tester);
    expect(streams.length, greaterThan(before));
    push(3, 300);
    await flush(tester);
    expect(service.latestState?.toGroupGameRoundStatus().totalBetCount, 300);
    service.release();
    await flush(tester);
  });
}
