import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_entry_read_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/conversation_read_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_conversation_read_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';

const _owner = 'entry_read_owner';
const _group = 'group_@TGS#entry_read';
const _c2c = 'c2c_entry_peer';
const _time = 1800000010;

V2TimConversation _row(
        {bool group = true, int? sequence = 10, int unread = 40}) =>
    V2TimConversation(
      conversationID: group ? _group : _c2c,
      groupID: group ? '@TGS#entry_read' : null,
      userID: group ? null : 'entry_peer',
      type: group ? 2 : 1,
      recvOpt: 0,
      unreadCount: unread,
      lastMessage: V2TimMessage.fromJson({
        'message_msg_id': 'm10',
        'message_server_time': _time,
        'message_risk_type_identified': 0,
      })
        ..seq = sequence?.toString(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final outbox = ConversationReadOutboxStore.instance;
  final store = ConversationLocalStore.instance;
  final aggregate = ConversationUnreadAggregate.instance;
  final tabs = ConversationTabStore.instance;
  final calls = <(String, int, int)>[];
  late bool visible;
  late int sdkCode;
  late Completer<void> nativeCalled;

  void sdk(V2TimConversation row) {
    ChatSessionController.instance
        .applyPendingRealtimeProjection([row], reason: 'sdk_realtime');
    tabs.flushRealtimePatches();
  }

  Future<ConversationReadOutboxRecord?> pending([String id = _group]) =>
      outbox.find(ownerUserId: _owner, conversationId: id);

  Future<bool> enter(V2TimConversation row) =>
      ChatEntryReadService.clearOnEntry(
          conversation: row, isCurrent: () => visible);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    store.debugOwnerUserId = _owner;
    await outbox.clearOwner(_owner);
    aggregate.resetForTest();
    tabs.clear();
    tabs.notifyColdStartEnded();
    aggregate.sdkPageForTest = (_) async => throw StateError('offline');
    calls.clear();
    visible = true;
    sdkCode = 0;
    nativeCalled = Completer<void>();
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) async {
      calls.add((conversationID, cleanTimestamp, cleanSequence));
      if (!nativeCalled.isCompleted) nativeCalled.complete();
      return V2TimCallback(code: sdkCode, desc: 'fixture');
    };
  });
  tearDown(() async {
    ConversationUnreadClearService.resetCoordinatorStateForTesting();
    TencentConversationReadService.cleanUnreadForTesting = null;
    ChatSessionController.instance.clearSessionProjection();
    aggregate.resetForTest();
    await store.flushReadBarrierWritesForTest();
    store.resetAnchorStateForTest();
    await outbox.clearOwner(_owner);
    store.debugOwnerUserId = null;
  });

  test('only explicit single-conversation entry permits zero boundaries', () {
    for (final id in [_group, _c2c]) {
      expect(ConversationReadPolicy.validTarget(id, 0, 0), isFalse);
      expect(
          ConversationReadPolicy.validTarget(id, 0, 0,
              explicitConversationClear: true),
          isTrue);
    }
    for (final id in ['', 'group', 'c2c', 'group_', 'c2c_']) {
      expect(
          ConversationReadPolicy.validTarget(id, 0, 0,
              explicitConversationClear: true),
          isFalse);
    }
    expect(
        ConversationReadPolicy.validTarget(_group, 100, 0,
            explicitConversationClear: true),
        isFalse);
  });

  for (final group in [true, false]) {
    test('entry clears SDK unread and waits for callback: group=$group',
        () async {
      final row = _row(group: group);
      sdk(row);
      expect(await enter(row), isTrue);
      expect(calls, [(row.conversationID, 0, 0)]);
      expect(await pending(row.conversationID), isNull);
      // A successful request is not an invented count. A delayed callback
      // must still drive the actual list and badge together.
      expect(tabs.conversationForId(row.conversationID)?.unreadCount, 40);
      sdk(_row(group: group, unread: 0));
      expect(tabs.conversationForId(row.conversationID)?.unreadCount, 0);
      expect(
          group
              ? aggregate.groupNotifiableUnreadSum
              : aggregate.c2cNotifiableUnreadSum,
          0);
      sdk(_row(group: group, unread: 1, sequence: 11));
      expect(tabs.conversationForId(row.conversationID)?.unreadCount, 1);
    });
  }

  test('group entry does not need a preview or native message sequence',
      () async {
    final row = _row(sequence: null)..lastMessage = null;
    expect(await enter(row), isTrue);
    expect(calls, [(_group, 0, 0)]);
    expect(await pending(), isNull);
  });

  test('raw SDK group ID receives exactly one group prefix', () async {
    final row = _row()..conversationID = '@TGS#entry_read';
    expect(await enter(row), isTrue);
    expect(calls.single.$1, _group);
  });

  test('a hidden or disposed entry cannot dispatch full clear', () async {
    visible = false;
    expect(await enter(_row()), isFalse);
    expect(calls, isEmpty);
    visible = true;
    final request = enter(_row());
    visible = false;
    expect(await request, isFalse);
    expect(calls, isEmpty);
  });

  test('concurrent entry requests share one native call', () async {
    final started = Completer<void>();
    final result = Completer<V2TimCallback>();
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) {
      calls.add((conversationID, cleanTimestamp, cleanSequence));
      started.complete();
      return result.future;
    };
    final first = enter(_row());
    await started.future;
    final second = enter(_row());
    result.complete(V2TimCallback(code: 0, desc: 'ok'));
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(calls, hasLength(1));
  });

  for (final newerMessage in [false, true]) {
    test('fresh entry waits for an older request: newerMessage=$newerMessage',
        () async {
      final started = Completer<void>();
      final firstResult = Completer<V2TimCallback>();
      TencentConversationReadService.cleanUnreadForTesting = ({
        required conversationID,
        required cleanTimestamp,
        required cleanSequence,
      }) async {
        calls.add((conversationID, cleanTimestamp, cleanSequence));
        if (calls.length == 1) {
          started.complete();
          return firstResult.future;
        }
        return V2TimCallback(code: 6014, desc: 'new entry offline');
      };
      final first = enter(_row());
      await started.future;
      if (!newerMessage) visible = false;
      final newRow = _row(sequence: newerMessage ? 20 : 10);
      final second = ChatEntryReadService.clearOnEntry(
          conversation: newRow, isCurrent: () => true);
      // A later preview must not expand the queued entry's retry boundary.
      newRow.lastMessage!.seq = '99';
      firstResult.complete(V2TimCallback(code: 0, desc: 'older request'));
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(calls, [(_group, 0, 0), (_group, 0, 0)]);
      expect((await pending())?.cleanSequence, newerMessage ? 20 : 10);
    });
  }

  test('failed C2C retry preserves later messages in the same second',
      () async {
    final row = _row(group: false);
    sdk(row);
    sdkCode = 6014;
    expect(await enter(row), isFalse);
    expect((await pending(_c2c))?.cleanTimestamp, _time - 1);
    expect(tabs.conversationForId(_c2c)?.unreadCount, 40);
    visible = false;
    // The SDK only accepts a whole second, not this message's ID. Retrying
    // _time would also read an unseen new message carrying that timestamp.
    sdk(_row(group: false, unread: 41));
    row.lastMessage!.timestamp = _time + 10;
    sdkCode = 0;
    await outbox.resumeAfterReconnect(_owner);
    await ConversationUnreadClearService.scheduleSdkUnreadClean(
        conversationID: _c2c, trigger: SdkUnreadCleanTrigger.recovery);
    expect(calls, [(_c2c, 0, 0), (_c2c, _time - 1, 0)]);
    expect(await pending(_c2c), isNull);
  });

  test('group retry uses the captured sequence, never a later preview',
      () async {
    final row = _row();
    sdkCode = 6014;
    final request = enter(row);
    row.lastMessage!.seq = '99';
    expect(await request, isFalse);
    expect((await pending())?.cleanSequence, 10);
    visible = false;
    sdkCode = 0;
    await outbox.resumeAfterReconnect(_owner);
    await ConversationUnreadClearService.scheduleSdkUnreadClean(
        conversationID: _group, trigger: SdkUnreadCleanTrigger.recovery);
    expect(calls, [(_group, 0, 0), (_group, 0, 10)]);
  });

  test('missing boundary cannot replay zero clear, but a new entry can clear',
      () async {
    sdkCode = 6014;
    expect(await enter(_row(sequence: null)), isFalse);
    expect((await pending())?.retryReason, 'blocked:watermark_unavailable');
    visible = false;
    await ConversationUnreadClearService.scheduleSdkUnreadClean(
        conversationID: _group, trigger: SdkUnreadCleanTrigger.recovery);
    expect(calls, hasLength(1));
    visible = true;
    sdkCode = 0;
    expect(await enter(_row(sequence: null)), isTrue);
    expect(calls, [(_group, 0, 0), (_group, 0, 0)]);
    expect(await pending(), isNull);
  });

  test('late success cannot acknowledge a newer read intent', () async {
    final started = Completer<void>();
    final result = Completer<V2TimCallback>();
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) {
      started.complete();
      return result.future;
    };
    final request = enter(_row());
    await started.future;
    await outbox.enqueue(
        ownerUserId: _owner,
        conversationId: _group,
        lastReadMessageId: 'm20',
        cleanSequence: 20);
    result.complete(V2TimCallback(code: 0, desc: 'ok'));
    expect(await request, isTrue);
    expect((await pending())?.cleanSequence, 20);
  });

  test('late SDK success after account switch has no completion side effects',
      () async {
    final started = Completer<void>();
    final result = Completer<V2TimCallback>();
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) {
      started.complete();
      return result.future;
    };
    final request = enter(_row());
    await started.future;
    SessionIdentityService.instance.invalidate(reason: 'entry_read_test');
    result.complete(V2TimCallback(code: 0, desc: 'late'));
    expect(await request, isFalse);
    expect((await pending())?.cleanSequence, 10);
  });

  test('list prework persists retry state without a duplicate native clean',
      () async {
    await ConversationUnreadClearService.clearLocalForOpenFast(
        conversation: _row(), dispatchSdk: false);
    for (var i = 0; i < 100 && await pending() == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect((await pending())?.cleanSequence, 10);
    expect(calls, isEmpty);
    expect(await enter(_row()), isTrue);
    expect(calls, [(_group, 0, 0)]);
  });

  test('explicit entry respects a persisted SDK frequency cooldown', () async {
    await outbox.enqueue(
        ownerUserId: _owner, conversationId: _group, cleanSequence: 9);
    final cooldown = DateTime.now().millisecondsSinceEpoch + 60000;
    await outbox.markRetry((await pending())!,
        sdkCode: -10113, notBeforeAtMs: cooldown);
    expect(await enter(_row()), isFalse);
    expect(calls, isEmpty);
    expect((await pending())?.nextRetryAtMs, greaterThanOrEqualTo(cooldown));
    expect((await pending())?.cleanSequence, 10);
  });

  test('a missing boundary does not discard SDK frequency cooldown', () async {
    sdkCode = -10113;
    expect(await enter(_row(sequence: null)), isFalse);
    expect((await pending())?.nextRetryAtMs,
        greaterThan(DateTime.now().millisecondsSinceEpoch));
    expect(await enter(_row(sequence: null)), isFalse);
    expect(calls, [(_group, 0, 0)]);
  });

  for (final source in ['app_banner', 'system_notification', 'search']) {
    testWidgets('reused chat entry reads only normal navigation: $source',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      late BuildContext root;
      final registry = AppChatRouteRegistry.instance;
      registry.prepareForTest = () async {};
      registry.chatBuilderForTest =
          (_, __) => const Scaffold(body: Text('existing chat'));
      final handler = FlutterError.onError;
      try {
        await tester.pumpWidget(MaterialApp(
          navigatorKey: nav,
          home: Builder(builder: (context) {
            root = context;
            return const Scaffold(body: Text('list'));
          }),
        ));
        final conversation = _row();
        final first = openOrReuseAppChat<void>(root, conversation);
        await tester.pumpAndSettle();
        nav.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('details'))));
        await tester.pumpAndSettle();
        late Future<void> reused;
        await tester.runAsync(() async {
          reused = openOrReuseAppChat<void>(root, conversation,
              openSource: source,
              searchJumpAnchor: source == 'search'
                  ? MessageAnchor.fromConversationMessage(
                      conversation, conversation.lastMessage!)
                  : null);
          if (source != 'search') {
            await nativeCalled.future.timeout(const Duration(seconds: 5));
          }
        });
        await tester.pumpAndSettle();
        FlutterError.onError = handler;
        expect(find.text('existing chat'), findsOneWidget);
        expect(calls, source == 'search' ? isEmpty : [(_group, 0, 0)]);
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future.wait([first, reused]));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        registry.reset();
        ChatOpenPerfLog.resetForTest();
        await tester.pump(const Duration(seconds: 3));
        FlutterError.onError = handler;
      }
    });
  }
}
