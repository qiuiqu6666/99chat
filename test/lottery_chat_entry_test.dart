import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_query_endpoint.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/lottery_chat_entry.dart';

void main() {
  testWidgets(
      'entry cache is account/group scoped and revokes before other lookup finishes',
      (tester) async {
    Widget page(
            String account,
            String group,
            Future<String?> Function(String) game,
            Future<bool> Function(String) enabled) =>
        MaterialApp(
            home: Scaffold(
                body: Stack(children: [
          LotteryChatEntry(
              groupUid: group,
              accountId: () => account,
              loadGameId: game,
              loadEnabled: enabled),
        ])));
    final handle = find.byKey(const ValueKey('lottery-edge-handle'));
    await tester.pumpWidget(page('cache-user-A', 'cache-group',
        (_) async => 'machine', (_) async => true));
    await tester.pumpAndSettle();
    expect(handle, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final game = Completer<String?>();
    final enabled = Completer<bool>();
    await tester.pumpWidget(page('cache-user-A', 'cache-group',
        (_) => game.future, (_) => enabled.future));
    expect(handle, findsOneWidget);
    enabled.complete(false);
    await tester.pump();
    expect(handle, findsNothing);
    game.complete('machine');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    // A separate account must not inherit A's positive entry cache.
    await tester.pumpWidget(page('cache-user-A', 'other-group',
        (_) async => 'machine', (_) async => true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    final pending = Completer<bool>();
    await tester.pumpWidget(page('cache-user-B', 'other-group',
        (_) async => 'machine', (_) => pending.future));
    expect(handle, findsNothing);
    pending.complete(false);
    await tester.pumpAndSettle();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hint fades after three seconds and appears at most three times',
      (tester) async {
    for (var visit = 0; visit < 4; visit++) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Stack(children: [
        LotteryChatEntry(
            loadGameId: (_) async => 'machine',
            loadEnabled: (_) async => true,
            groupUid: 'group'),
      ]))));
      await tester.pumpAndSettle();
      expect(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
          visit < 3 ? 1 : 0);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
          0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(
        (await SharedPreferences.getInstance())
            .getInt('lottery_history_hint_count_v1'),
        3);
  });

  testWidgets('opening entry persists dismissal and still opens drawer',
      (tester) async {
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: {'code': 1}));
    });
    GroupQueryEndpoint.client.interceptors.insert(0, interceptor);
    addTearDown(
        () => GroupQueryEndpoint.client.interceptors.remove(interceptor));
    Widget page() => MaterialApp(
            home: Scaffold(
                body: Stack(children: [
          LotteryChatEntry(
              groupUid: 'group',
              loadGameId: (_) async => 'machine',
              loadEnabled: (_) async => true),
        ])));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lottery-edge-handle')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('lottery-latest-preview')), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance())
            .getBool('lottery_history_hint_opened_v1'),
        true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0);
  });
  test('backend gate reads App group gameEnabled, not robot or admin fields',
      () async {
    final client = ApiClient.instance.dio;
    var payload = <String, dynamic>{'gameEnabled': true, 'enabled': false};
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.uri.query, isEmpty);
      expect(options.path, '/group/%40group%231');
      expect(options.uri.fragment, isEmpty);
      handler
          .resolve(Response(requestOptions: options, data: {'data': payload}));
    });
    client.interceptors.insert(0, interceptor);
    addTearDown(() => client.interceptors.remove(interceptor));
    expect(await loadLotteryBackendEnabled('@group#1'), isTrue);
    payload = {'gameEnabled': false, 'enabled': true, 'game_enabled': true};
    expect(await loadLotteryBackendEnabled('@group#1'), isFalse);
    payload = {'enabled': true, 'game_enabled': true};
    expect(await loadLotteryBackendEnabled('@group#1'), isFalse);
    payload = {'gameEnabled': 'true'};
    expect(await loadLotteryBackendEnabled('@group#1'), isFalse);
  });
  testWidgets('SDK fields show entry even when chat model has no group info',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      LotteryChatEntry(
          groupUid: '@group#1',
          loadGameId: (_) async => 'machine1',
          loadEnabled: (_) async => true),
    ]))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.text('六合彩开奖'), findsNothing);
    final handle = find.byKey(const ValueKey('lottery-edge-handle'));
    expect(tester.getRect(handle).right, 800);
    expect(tester.getCenter(handle).dy, 180);
    expect(find.byType(ElevatedButton), findsNothing);
    await tester.drag(handle, const Offset(0, 120));
    await tester.pump();
    expect(tester.getCenter(handle).dy, greaterThan(180));
    await tester.drag(handle, const Offset(0, -1000));
    await tester.pump();
    expect(tester.getRect(handle).top, 0);
    await tester.drag(handle, const Offset(0, 1000));
    await tester.pump();
    expect(tester.getRect(handle).bottom, 600);
  });

  testWidgets('late previous group result cannot show entry in disabled group',
      (tester) async {
    final oldGame = Completer<String?>();
    Future<String?> game(String id) =>
        id == 'A' ? oldGame.future : Future.value('machineB');
    Future<bool> enabled(String id) async => id == 'A';
    Widget page(String id) => MaterialApp(
            home: Scaffold(
                body: Stack(children: [
          LotteryChatEntry(
              groupUid: id, loadGameId: game, loadEnabled: enabled),
        ])));
    await tester.pumpWidget(page('A'));
    await tester.pumpWidget(page('B'));
    await tester.pumpAndSettle();
    oldGame.complete('machineA');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
  });

  testWidgets('failed SDK request keeps entry hidden', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      LotteryChatEntry(
          groupUid: 'A',
          loadGameId: (_) async => throw StateError('SDK failed'),
          loadEnabled: (_) async => true),
    ]))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
  });
  test('lottery requires nonempty gameid and enabled true', () {
    expect(canShowLotteryEntry(null), isFalse);
    expect(canShowLotteryEntry({'gameid': 'abc'}), isFalse);
    expect(canShowLotteryEntry({'gameid': ' ', 'enabled': 'true'}), isFalse);
    expect(canShowLotteryEntry({'gameid': 'abc', 'enabled': 'false'}), isFalse);
    expect(canShowLotteryEntry({'gameid': 'abc', 'enabled': '1'}), isFalse);
    expect(canShowLotteryEntry({'gameid': 'abc', 'enabled': 'true'}), isFalse);
    expect(
        canShowLotteryEntry({'gameid': ' ', 'enabled': 'true'},
            backendEnabled: true),
        isFalse);
    expect(
        canShowLotteryEntry({'gameid': '@abc#123', 'enabled': 'false'},
            backendEnabled: true),
        isTrue);
    expect(canShowLotteryEntry({'gameid': '@abc#123'}, backendEnabled: true),
        isTrue);
  });
}
