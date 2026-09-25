import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/conversation_read_policy.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    AppChatRouteRegistry.instance.reset();
    ChatOpenPerfLog.resetForTest();
  });
  for (final warmup in ['success', 'failure', 'timeout']) {
    testWidgets(
        'concurrent initial opens share one route through $warmup and wait for pop',
        (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
          navigatorKey: navKey,
          home: Builder(builder: (c) {
            context = c;
            return const SizedBox();
          })));
      final prepare = Completer<void>();
      var prepares = 0, pushes = 0;
      final registry = AppChatRouteRegistry.instance;
      registry.prepareForTest = () {
        prepares++;
        return prepare.future;
      };
      registry.routeForTest = () {
        pushes++;
        return MaterialPageRoute<String>(builder: (_) => const Text('chat'));
      };
      final conversation =
          V2TimConversation(conversationID: 'c2c_bob', userID: 'bob', type: 1);
      var completions = 0;
      final a = openOrReuseAppChat<String>(context, conversation)
          .whenComplete(() => completions++);
      final b = openOrReuseAppChat<String>(context, conversation)
          .whenComplete(() => completions++);
      expect(prepares, 1);
      if (warmup == 'success') prepare.complete();
      if (warmup == 'failure') prepare.completeError(StateError('warmup'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(pushes, 1);
      expect(completions, 0);
      navKey.currentState!.pop('popped');
      await tester.pumpAndSettle();
      expect(await a, 'popped');
      expect(await b, 'popped');
      if (warmup == 'timeout') prepare.complete();
    });
  }

  testWidgets(
      'account generation change cancels pending push and releases reservation',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final prepare = Completer<void>();
    var pushes = 0;
    AppChatRouteRegistry.instance.prepareForTest = () => prepare.future;
    AppChatRouteRegistry.instance.routeForTest = () {
      pushes++;
      return MaterialPageRoute<void>(builder: (_) => const SizedBox());
    };
    final pending = openOrReuseAppChat<void>(context,
        V2TimConversation(conversationID: 'c2c_bob', userID: 'bob', type: 1));
    SessionIdentityService.instance.invalidate(reason: 'test-account-switch');
    prepare.complete();
    await tester.pumpAndSettle();
    await pending;
    expect(pushes, 0);
    ChatOpenPerfLog.resetForTest();
    await tester.pump(const Duration(seconds: 3));
  });

  for (final keepSecondCaller in [true, false]) {
    testWidgets('disposed caller preserves other waiters=$keepSecondCaller',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      late BuildContext aContext, bContext, survivingContext;
      late StateSetter rebuild;
      var showCallers = true;
      await tester.pumpWidget(MaterialApp(
          navigatorKey: nav,
          home: StatefulBuilder(builder: (context, setState) {
            survivingContext = context;
            rebuild = setState;
            return Column(children: [
              if (showCallers)
                Builder(
                    key: const ValueKey('a'),
                    builder: (c) {
                      aContext = c;
                      return const SizedBox();
                    }),
              if (showCallers || keepSecondCaller)
                Builder(
                    key: const ValueKey('b'),
                    builder: (c) {
                      bContext = c;
                      return const SizedBox();
                    }),
            ]);
          })));
      final ready = Completer<void>();
      var pushes = 0;
      final registry = AppChatRouteRegistry.instance;
      registry.prepareForTest = () => ready.future;
      registry.routeForTest = () {
        pushes++;
        return MaterialPageRoute<void>(builder: (_) => const Text('chat'));
      };
      final conversation =
          V2TimConversation(conversationID: 'c2c_bob', userID: 'bob', type: 1);
      final a = openOrReuseAppChat(aContext, conversation);
      final b = openOrReuseAppChat(bContext, conversation);
      rebuild(() => showCallers = false);
      await tester.pump();
      ready.complete();
      await tester.pumpAndSettle();
      expect(pushes, keepSecondCaller ? 1 : 0);
      if (keepSecondCaller) {
        nav.currentState!.pop();
        await tester.pumpAndSettle();
      }
      await Future.wait([a, b]);
      // The completed reservation must release even if every original caller left.
      final reopened = openOrReuseAppChat(survivingContext, conversation);
      await tester.pumpAndSettle();
      expect(pushes, keepSecondCaller ? 2 : 1);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      await reopened;
      ChatOpenPerfLog.resetForTest();
      await tester.pump(const Duration(seconds: 3));
    });
  }

  test('inclusive seconds cannot clear the unseen message sharing timestamp T',
      () {
    expect(
        ConversationReadPolicy.conservativeTimestamp(1700000000), 1699999999);
    expect(ConversationReadPolicy.conservativeTimestamp(1700000000000),
        1699999999);
    expect(ConversationReadPolicy.validTarget('c2c_bob', 0, 0), isFalse);
    expect(ConversationReadPolicy.validTarget('c2c', 100, 0), isFalse);
    expect(
        ConversationReadPolicy.validTarget('', 100, 0, explicitTypeClear: true),
        isFalse);
    expect(ConversationReadPolicy.validTarget('group_room', 100, 0), isFalse);
    expect(ConversationReadPolicy.validTarget('group_room', 0, 20), isTrue);
    expect(
        ConversationReadPolicy.validTarget('c2c', 0, 0,
            explicitTypeClear: true),
        isTrue);
  });

  test(
      'read W1 acknowledgement preserves same-millisecond W2; retries classify and resume',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final directory = await Directory.systemTemp.createTemp('round2-read-');
    await MessageCoreStore.instance.closeIfOpen();
    await databaseFactory.setDatabasesPath(directory.path);
    final store = ConversationReadOutboxStore.instance;
    try {
      await store.enqueue(
          ownerUserId: 'alice',
          conversationId: 'c2c_bob',
          lastReadMessageId: 'W1',
          cleanTimestamp: 10,
          lastReadAtMs: 100);
      final w1 =
          (await store.find(ownerUserId: 'alice', conversationId: 'c2c_bob'))!;
      await store.enqueue(
          ownerUserId: 'alice',
          conversationId: 'c2c_bob',
          lastReadMessageId: 'W2',
          cleanTimestamp: 11,
          lastReadAtMs: 100);
      await store.acknowledge(
          ownerUserId: 'alice',
          conversationId: 'c2c_bob',
          lastReadAtMs: w1.lastReadAtMs);
      final w2 =
          (await store.find(ownerUserId: 'alice', conversationId: 'c2c_bob'))!;
      expect(w2.lastReadMessageId, 'W2');
      expect(w2.lastReadAtMs, greaterThan(w1.lastReadAtMs));
      await store.markRetry(w1, sdkCode: 6017);
      expect(
          (await store.find(ownerUserId: 'alice', conversationId: 'c2c_bob'))!
              .attemptCount,
          0);
      await store.markRetry(w2, sdkCode: 6014);
      expect(await store.listDue(ownerUserId: 'alice'), isEmpty);
      expect(await store.earliestNextRetryAt(ownerUserId: 'alice'), isNull);
      await store.resumeAfterReconnect('bob');
      expect(await store.listDue(ownerUserId: 'alice'), isEmpty);
      await store.resumeAfterReconnect('alice');
      expect(await store.listDue(ownerUserId: 'alice'), hasLength(1));
      final resumed =
          (await store.find(ownerUserId: 'alice', conversationId: 'c2c_bob'))!;
      await store.markRetry(resumed, sdkCode: 6017);
      await store.resumeAfterReconnect('alice');
      expect(await store.listDue(ownerUserId: 'alice'), isEmpty);
      expect(
          (await store.find(ownerUserId: 'alice', conversationId: 'c2c_bob'))!
              .retryReason,
          'blocked:sdk_6017');
      await store.enqueue(
          ownerUserId: 'alice',
          conversationId: 'c2c_bob',
          lastReadMessageId: 'W2',
          cleanTimestamp: 11,
          lastReadAtMs: 100);
      expect(await store.listDue(ownerUserId: 'alice'), isEmpty,
          reason: 'same target must retain blocked state');
      await store.enqueue(
          ownerUserId: 'alice',
          conversationId: 'c2c_bob',
          lastReadMessageId: 'W3',
          cleanTimestamp: 12,
          lastReadAtMs: 100);
      final w3 =
          (await store.find(ownerUserId: 'alice', conversationId: 'c2c_bob'))!;
      expect(w3.lastReadMessageId, 'W3');
      expect(w3.lastReadAtMs, greaterThan(w2.lastReadAtMs));
      expect(w3.attemptCount, resumed.attemptCount + 1);
      expect(w3.retryReason, 'blocked:sdk_6017');
      expect(w3.nextRetryAtMs, -1);
      await store.acknowledge(
          ownerUserId: 'alice',
          conversationId: 'c2c_bob',
          lastReadAtMs: w2.lastReadAtMs);
      expect(
          (await store.find(ownerUserId: 'alice', conversationId: 'c2c_bob'))!
              .lastReadMessageId,
          'W3');
    } finally {
      await MessageCoreStore.instance.closeIfOpen();
      await databaseFactory
          .deleteDatabase('${directory.path}/${MessageCoreStore.dbName}');
      await databaseFactory.setDatabasesPath(original);
      await directory.delete();
    }
  });
}
