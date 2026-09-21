import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/indexed_message_windows.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';

class _Row extends V2TimMessage {
  _Row(String id)
      : super.fromJson({
          'message_msg_id': id,
          'message_server_time': 1,
          'message_risk_type_identified': 0
        });
  static int reads = 0;
  @override
  String? get msgID {
    reads++;
    return super.msgID;
  }

  @override
  set msgID(String? value) => super.msgID = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  test('unrelated identity changes do not scan retained windows', () {
    final windows = IndexedMessageWindows(
        onRetained: (_) {},
        onReleased: (_) {},
        onWindowRemoved: (_) {},
        onCleared: () {});
    for (var c = 0; c < 4; c++) {
      windows['c$c'] = List.generate(220, (i) => _Row('$c-$i'));
    }
    final unrelated = _Row('outside');
    _Row.reads = 0;
    for (var i = 0; i < 100; i++) {
      unrelated.seq = '$i';
      expect(windows.find('0-0'), hasLength(1));
    }
    expect(_Row.reads, 0);
    final retained = windows['c0']!.first;
    retained.msgID = 'adopted';
    expect(windows.find('adopted').single.value, same(retained));
    expect(_Row.reads, 220, reason: 'only the affected window rebuilds');
    _Row.reads = 0;
    retained.msgID = 'after-overflow';
    for (var i = 0; i < 300; i++) {
      unrelated.seq = '$i';
    }
    expect(windows.find('after-overflow').single.value, same(retained));
    expect(windows.find('adopted'), isEmpty);
  });

  test('real window replacement prunes old metadata and preserves selection',
      () {
    final global = serviceLocator<TUIChatGlobalModel>();
    final ui = serviceLocator<ChatUiStateStore>();
    global.clearData();
    const conv = 'c2c_metadata';
    global.setMessageList(
        conv, [_Row('old'), _Row('selected'), _Row('pending')..id = 'client'],
        replace: true);
    for (var i = 0; i < 10000; i++) {
      ui.markMessageChanged(conv, 'old$i');
    }
    ui.markMessageChanged(conv, 'old');
    ui.setMessageSelected(conv, 'selected', true);
    ui.bindMessageAlias(conv, 'client', 'pending');
    global.setMessageList(conv, [_Row('pending')..id = 'client'],
        replace: true, preserveInFlightOutgoing: false);
    expect(ui.rowRevision(conv, 'old'), 0);
    expect(ui.rowRevision(conv, 'old0'), 0);
    expect(ui.rowRevision(conv, 'old9999'), 0);
    expect(ui.isMessageSelected(conv, 'selected'), isTrue);
    ui.markMessageChanged(conv, 'client');
    expect(ui.rowRevision(conv, 'client'), ui.rowRevision(conv, 'pending'));
    global.clearData();
    expect(ui.isMessageSelected(conv, 'selected'), isFalse);
  });

  test('capacity backpressure preserves realtime FIFO and all results',
      () async {
    final coordinator = MessagePersistCoordinator(foregroundQueueLimit: 8);
    final hold = Completer<void>();
    final first = coordinator.enqueue<void>(
        priority: MessagePersistPriority.realtime,
        source: MessagePersistSource.realtime,
        run: () => hold.future);
    final seen = <int>[];
    final pending = List.generate(
        2000,
        (i) => coordinator.enqueue<int>(
            priority: MessagePersistPriority.realtime,
            source: MessagePersistSource.realtime,
            run: () async {
              seen.add(i);
              return i;
            }));
    expect(coordinator.realtimeQueueDepth, 8);
    expect(coordinator.waitingAdmissions, 1992);
    hold.complete();
    await first;
    expect(await Future.wait(pending), List.generate(2000, (i) => i));
    expect(seen, List.generate(2000, (i) => i));
    expect(coordinator.waitingAdmissions, 0);
  });

  test('continuous immediate jobs yield to event-loop work', () async {
    final coordinator = MessagePersistCoordinator(realtimeCoalesceLimit: 8);
    var done = 0;
    final timer = Future<void>.delayed(Duration.zero);
    final jobs = List.generate(
        100,
        (_) => coordinator.enqueue<void>(
            priority: MessagePersistPriority.realtime,
            source: MessagePersistSource.realtime,
            run: () async {
              done++;
            }));
    await timer;
    expect(done, lessThan(100));
    await Future.wait(jobs);
    expect(done, 100);
  });

  test('authority hot cache stays bounded across 10000 unique mutations', () {
    final coordinator = MessagePersistCoordinator(authorityCacheLimit: 128);
    for (var i = 0; i < 10000; i++) {
      coordinator.rememberAuthority(
          conversationId: 'chat',
          messageId: 'm$i',
          kind: MessagePersistAuthorityKind.revoke);
    }
    expect(coordinator.authorityCacheSize, 128);
    expect(coordinator.authorityFor(conversationId: 'chat', messageId: 'm9999'),
        MessagePersistAuthorityKind.revoke);
  });

  test('waiting admissions cannot cross account generations', () async {
    final coordinator = MessagePersistCoordinator(foregroundQueueLimit: 2);
    coordinator.bindAccountGeneration(1);
    final hold = Completer<void>();
    final first = coordinator.enqueue<void>(
        priority: MessagePersistPriority.realtime,
        source: MessagePersistSource.realtime,
        run: () => hold.future);
    var ran = 0;
    final pending = List.generate(
        20,
        (_) => coordinator
            .enqueue<void>(
                priority: MessagePersistPriority.realtime,
                source: MessagePersistSource.realtime,
                run: () async {
                  ran++;
                })
            .then((_) => false,
                onError: (Object error) => error is MessagePersistRejected));
    coordinator.bindAccountGeneration(2);
    hold.complete();
    await first;
    expect(await Future.wait(pending), everyElement(isTrue));
    expect(ran, 0);
    expect(coordinator.waitingAdmissions, 0);
  });

  test('history chunk producer queues progressively rather than all at once',
      () async {
    final coordinator = MessagePersistCoordinator();
    final started = Completer<void>();
    final hold = Completer<void>();
    var completed = 0;
    final work = coordinator.enqueueHistoryChunks(
        priority: MessagePersistPriority.userHistory,
        source: MessagePersistSource.userHistory,
        chunks: [
          () async {
            started.complete();
            await hold.future;
          },
          for (var i = 0; i < 1000; i++)
            () async {
              completed++;
            }
        ]);
    await started.future;
    expect(coordinator.userHistoryQueueDepth, 0);
    expect(coordinator.waitingAdmissions, 0);
    hold.complete();
    await work;
    expect(completed, 1000);
  });

  test('progressive history keeps its original account generation', () async {
    final coordinator = MessagePersistCoordinator()..bindAccountGeneration(1);
    final hold = Completer<void>();
    final started = Completer<void>();
    var lateRan = false;
    final work = coordinator.enqueueHistoryChunks(
      priority: MessagePersistPriority.userHistory,
      source: MessagePersistSource.userHistory,
      chunks: [() async { started.complete(); await hold.future; },
        () async { lateRan = true; }]);
    final rejected = expectLater(work, throwsA(isA<MessagePersistRejected>()));
    await started.future;
    coordinator.bindAccountGeneration(2);
    hold.complete();
    await rejected;
    expect(lateRan, isFalse);
  });
}
