import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_writer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

// Developer-machine microbenchmarks. These are reproducible work measurements,
// not frame-time or device-memory assertions. Run this file by itself.
final class _Samples {
  final values = <int>[];
  var _seen = 0;

  void record(void Function() action) {
    final watch = Stopwatch()..start();
    action();
    watch.stop();
    // Exclude the first few VM warm-up runs from the reported distribution.
    if (_seen++ >= 5) values.add(watch.elapsedMicroseconds);
  }

  String summary() {
    final sorted = [...values]..sort();
    final average = values.reduce((a, b) => a + b) / values.length;
    final p95 =
        sorted[((sorted.length * 0.95).ceil() - 1).clamp(0, sorted.length - 1)];
    return 'mean=${average.toStringAsFixed(1)}us p95=${p95}us max=${sorted.last}us';
  }
}

V2TimConversation _conversation(int index, {int unread = 0, String? face}) =>
    V2TimConversation(
      conversationID: 'c2c_stage2_$index',
      type: 1,
      userID: 'stage2_$index',
      showName: 'stage2 $index',
      faceUrl: face,
      unreadCount: unread,
      orderkey: 1700000000000 - index,
    );

V2TimMessage _message(int index, {int version = 0}) => V2TimMessage.fromJson({
      'message_msg_id': 'stage2-$index',
      'message_server_time': 1700000000 + index,
      'message_risk_type_identified': 0,
    })
      ..userID = 'stage2-peer'
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'message $index / $version');

MessageReconciliationRecord<String> _record(int index, {int version = 0}) =>
    MessageReconciliationRecord<String>(
      value: 'row-$index-$version',
      msgID: 'stage2-$index',
      seq: '$index',
    );

MessageReconciliationWriter<String> _writer(int count) {
  final writer = MessageReconciliationWriter<String>(
    comparator: (left, right) =>
        (left.numericSeq ?? 0).compareTo(right.numericSeq ?? 0),
  );
  writer.seedAuthoritative(
    conversationID: 'c2c_stage2',
    trackSeqGaps: false,
    records: [for (var i = 0; i < count; i++) _record(i + 100)],
  );
  return writer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
  });

  testWidgets('736 row bridges notify only their changed ID and release',
      (tester) async {
    final session = ChatSessionController.instance;
    final store = ConversationTabStore.instance;
    session.clearSessionProjection(notify: false);
    session.ensureTabStoreBridgeAttached();
    store.notifyColdStartEnded();
    store.setItemsForTest(
      convType: 1,
      items: [for (var i = 0; i < 761; i++) _conversation(i)],
    );

    final first = session.rowRevisionOf('c2c_stage2_0');
    final firstRow = store.rowViewListenable('c2c_stage2_0');
    await tester.pumpWidget(MaterialApp(
      home: AnimatedBuilder(
        animation: Listenable.merge([first, firstRow]),
        builder: (_, __) => const SizedBox(height: 72),
      ),
    ));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(store.workActiveRowSubscriptionCount, 1);

    for (var i = 1; i < 736; i++) {
      session.rowRevisionOf('c2c_stage2_$i');
    }
    expect(store.workActiveRowSubscriptionCount, 736);
    expect(identical(first, session.rowRevisionOf('c2c_stage2_0')), isTrue);

    var firstCallbacks = 0;
    var targetCallbacks = 0;
    final target = session.rowRevisionOf('c2c_stage2_500');
    void onFirst() => firstCallbacks++;
    void onTarget() => targetCallbacks++;
    first.addListener(onFirst);
    target.addListener(onTarget);
    store.resetWorkCounters();
    store.applyPatches(
        [_conversation(500, face: 'https://stage2.test/new.png')]);
    expect(store.workRowProjectedCount, 1);
    expect(store.workRowNotifyCount, 1);
    expect(firstCallbacks, 0);
    expect(targetCallbacks, greaterThan(0));
    first.removeListener(onFirst);
    target.removeListener(onTarget);

    session.applyPendingRealtimeDeletion(['c2c_stage2_500']);
    expect(store.workActiveRowSubscriptionCount, lessThan(736));
    // Simulate paging to a disjoint feed window after visiting many rows.
    store.setItemsForTest(
      convType: 1,
      items: [for (var i = 1000; i < 1761; i++) _conversation(i)],
    );
    session.notifyListeners();
    expect(store.workActiveRowSubscriptionCount, 0);
    session.clearSessionProjection(notify: false);
    expect(store.workActiveRowSubscriptionCount, 0);
  });

  test('developer-machine row patch and listener fan-out', () {
    final session = ChatSessionController.instance;
    final store = ConversationTabStore.instance;
    session.clearSessionProjection(notify: false);
    session.ensureTabStoreBridgeAttached();
    store.notifyColdStartEnded();
    store.setItemsForTest(
      convType: 1,
      items: [for (var i = 0; i < 761; i++) _conversation(i)],
    );
    for (var i = 0; i < 736; i++) {
      session.rowRevisionOf('c2c_stage2_$i');
    }
    var changedIdCallbacks = 0;
    var unrelatedCallbacks = 0;
    void changed() => changedIdCallbacks++;
    void unrelated() => unrelatedCallbacks++;
    session.rowRevisionOf('c2c_stage2_500').addListener(changed);
    session.rowRevisionOf('c2c_stage2_0').addListener(unrelated);
    final samples = _Samples();
    for (var i = 0; i < 35; i++) {
      samples.record(() => store.applyPatches([
            _conversation(500, face: 'https://stage2.test/$i.png'),
          ]));
    }
    expect(unrelatedCallbacks, 0);
    expect(changedIdCallbacks, greaterThan(0));
    expect(store.workActiveRowSubscriptionCount, 736);
    // ignore: avoid_print
    print('[stage2] row_patch_761_rows_736_bridges ${samples.summary()} '
        'changedCallbacks=$changedIdCallbacks unrelatedCallbacks=$unrelatedCallbacks');
    session.rowRevisionOf('c2c_stage2_500').removeListener(changed);
    session.rowRevisionOf('c2c_stage2_0').removeListener(unrelated);
    session.clearSessionProjection(notify: false);
  });

  test('developer-machine message window scaling', () async {
    const sizes = [20, 50, 100, 300, 500];
    for (final size in sizes) {
      final model = TUIChatGlobalModel();
      model.configureMessageWriterScope(
        ownerUserID: 'stage2-owner',
        accountGeneration: 1,
        domainGeneration: 1,
      );
      const conversationID = 'c2c_stage2-peer';
      final projection = _Samples();
      final cachedProjection = _Samples();
      final groupIndices = _Samples();
      final liveRowKeys = _Samples();
      var sink = 0;
      for (var trial = 0; trial < 35; trial++) {
        model.setMessageList(
          conversationID,
          [for (var i = size - 1; i >= 0; i--) _message(i, version: trial)],
          replace: true,
          applyMemoryWindow: false,
        );
        List<V2TimMessage> displayed = const [];
        projection.record(() {
          displayed = model.getMessageList(conversationID)!;
          sink += displayed.length;
        });
        cachedProjection.record(() {
          sink += model.getMessageList(conversationID)!.length;
        });
        // These two isolated kernels match the all-msgID branch in the list
        // container. They exclude Widget build/layout and row-cache work.
        groupIndices.record(() {
          final indices = <Object, int>{
            for (var i = 0; i < displayed.length; i++) displayed[i].msgID!: i,
          };
          sink += indices.length;
        });
        liveRowKeys.record(() {
          final keys = <String>{
            for (final message in displayed) 'msg:${message.msgID}',
          };
          sink += keys.length;
        });
        expect(displayed.any((message) => message.msgID == 'stage2-0'), isTrue);
      }
      expect(sink, greaterThan(0));

      final append = _Samples();
      final update = _Samples();
      final prepend = _Samples();
      for (var trial = 0; trial < 35; trial++) {
        final appendWriter = _writer(size);
        MessageReconciliationWriterCommit<String>? appendCommit;
        append.record(() {
          appendCommit = appendWriter.applyDelta(MessageDelta<String>(
            conversationKey: 'c2c_stage2',
            eventID: 'append-$trial',
            kind: MessageDeltaKind.realtimeUpsert,
            source: MessageDeltaSource.sdkRealtime,
            generation: 0,
            clearEpoch: 0,
            upserts: [_record(size + 100)],
          ));
        });
        expect(appendCommit?.records.last.msgID, 'stage2-${size + 100}');

        final updateWriter = _writer(size);
        MessageReconciliationWriterCommit<String>? updateCommit;
        update.record(() {
          updateCommit = updateWriter.applyDelta(MessageDelta<String>(
            conversationKey: 'c2c_stage2',
            eventID: 'update-$trial',
            kind: MessageDeltaKind.edit,
            source: MessageDeltaSource.sdkRealtime,
            generation: 0,
            clearEpoch: 0,
            upserts: [_record(size ~/ 2 + 100, version: trial + 1)],
          ));
        });
        expect(
          updateCommit?.records
              .singleWhere(
                  (record) => record.msgID == 'stage2-${size ~/ 2 + 100}')
              .value,
          'row-${size ~/ 2 + 100}-${trial + 1}',
        );

        final prependWriter = _writer(size);
        final request = prependWriter.beginInitialHistory(
          conversationID: 'c2c_stage2',
          requestedSource: MessageReconciliationSource.cloud,
          networkState: MessageReconciliationNetworkState.online,
        );
        MessageReconciliationWriterCommit<String>? prependCommit;
        prepend.record(() {
          prependCommit = prependWriter.completeHistory(
            request: request,
            history: [for (var i = 60; i < 100; i++) _record(i)],
            actualSource: MessageReconciliationSource.cloud,
            networkState: MessageReconciliationNetworkState.online,
          );
        });
        expect(prependCommit?.records.first.msgID, 'stage2-60');
      }
      // ignore: avoid_print
      print('[stage2] messages=$size display=${projection.summary()} '
          'cache_hit=${cachedProjection.summary()} '
          'group_indices_kernel=${groupIndices.summary()} '
          'live_keys_kernel=${liveRowKeys.summary()} '
          'writer_append=${append.summary()} '
          'writer_update=${update.summary()} '
          'writer_prepend40=${prepend.summary()}');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      model.dispose();
    }
  });
}
