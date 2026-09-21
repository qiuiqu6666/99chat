import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_writer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';

V2TimMessage row(int n, {String? text}) => V2TimMessage.fromJson({
      'message_msg_id': 'm$n',
      'message_server_time': 1700000000 + n,
      'message_risk_type_identified': 0,
    })
      ..userID = 'single-window-peer'
      ..seq = '$n'
      ..elemType = 1
      ..isSelf = false
      ..status = 2
      ..textElem = V2TimTextElem(text: text ?? 'message $n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const conv = 'c2c_single-window-peer';
  late TUIChatGlobalModel global;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    ChatMessageWindowPolicy.enabled = true;
    global = TUIChatGlobalModel();
    global.configureMessageWriterScope(
        ownerUserID: 'window-owner', accountGeneration: 1, domainGeneration: 1);
    ChatMainThreadPerf.debugForceEnabled = true;
    ChatMainThreadPerf.resetCounters();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 70));
    global.dispose();
    ChatMainThreadPerf.debugForceEnabled = false;
  });

  test('Writer publishes one stable immutable record-backed value view', () {
    final writer = MessageReconciliationWriter<String>(
        comparator: (a, b) => (b.numericSeq ?? 0).compareTo(a.numericSeq ?? 0));
    writer.seedAuthoritative(conversationID: conv, records: [
      const MessageReconciliationRecord(value: 'one', msgID: 'one', seq: '1')
    ]);
    final first = writer.valuesFor(conv);
    expect(writer.valuesFor(conv), same(first));
    expect(() => first.add('bypass'), throwsUnsupportedError);
    writer.applyDelta(MessageDelta(
        conversationKey: conv,
        eventID: 'new',
        kind: MessageDeltaKind.realtimeUpsert,
        source: MessageDeltaSource.sdkRealtime,
        generation: 0,
        clearEpoch: 0,
        upserts: [
          const MessageReconciliationRecord(
              value: 'two', msgID: 'two', seq: '2')
        ]));
    expect(writer.valuesFor(conv), ['two', 'one']);
    expect(first, ['one']);
    writer.clearConversation(conversationID: conv, clearEpoch: 1);
    expect(writer.valuesFor(conv), isEmpty);
    expect(first, ['one']);
  });

  test(
      'newest append reuses the canonical window and leaves prior snapshots stable',
      () {
    global.setMessageList(conv, [row(2), row(1)], replace: true);
    final before = global.rawMessageList(conv)!;
    expect(before, same(global.canonicalMessageWindow(conv)));
    final displayed = global.getMessageList(conv)!;
    expect(global.getMessageList('single-window-peer'), same(displayed));
    ChatMainThreadPerf.resetCounters();
    global.appendRealtimeMessages(conv, [row(3)]);
    expect(
        global.rawMessageList(conv)!.map((m) => m.msgID), ['m3', 'm2', 'm1']);
    expect(before.map((m) => m.msgID), ['m2', 'm1']);
    expect(displayed.where((m) => m.elemType != 11).map((m) => m.msgID),
        ['m2', 'm1']);
    expect(
        ChatMainThreadPerf.countersSnapshot()['message_realtime_writer_append'],
        1);
    expect(global.messageWriterRetainedCountForTesting(conv), 3);
    expect(
        global.rawMessageList(conv), same(global.canonicalMessageWindow(conv)));
    expect(() => global.rawMessageList(conv)!.clear(), throwsUnsupportedError);
    expect(() => global.messageListMap.remove(conv), throwsUnsupportedError);
  });

  test('edit and deletion invalidate one shared projection through the Writer',
      () {
    global.setMessageList(conv, [row(2), row(1)], replace: true);
    final first = global.getMessageList(conv);
    final edited = row(2, text: 'edited');
    global.commitMessageDelta(MessageDelta(
        conversationKey: conv,
        eventID: 'edit',
        kind: MessageDeltaKind.edit,
        source: MessageDeltaSource.sdkRealtime,
        generation: global.messageDeltaGenerationFor(conv),
        clearEpoch: 0,
        upserts: [
          MessageReconciliationRecord(
              value: edited, msgID: edited.msgID, seq: edited.seq)
        ]));
    final next = global.getMessageList(conv)!;
    expect(next, isNot(same(first)));
    expect(next.first.textElem!.text, 'edited');
    expect(global.rawMessageList(conv)!.first, same(next.first));
    global.commitMessageDelta(MessageDelta<V2TimMessage>(
        conversationKey: conv,
        eventID: 'delete',
        kind: MessageDeltaKind.delete,
        source: MessageDeltaSource.sdkRealtime,
        generation: global.messageDeltaGenerationFor(conv),
        clearEpoch: 0,
        explicitDeletes: ['m2']));
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), ['m1']);
    expect(
        global
            .getMessageList(conv)!
            .where((m) => m.elemType != 11)
            .map((m) => m.msgID),
        ['m1']);
    expect(global.messageWriterRetainedCountForTesting(conv), 1);
  });

  test(
      'normal latest window trims both Writer and projection at the same boundary',
      () {
    global.setMessageList(conv, List.generate(601, (i) => row(601 - i)),
        replace: true);
    expect(global.rawMessageList(conv)!.length,
        ChatMessageWindowPolicy.targetSize);
    expect(global.messageWriterRetainedCountForTesting(conv),
        ChatMessageWindowPolicy.targetSize);
    expect(global.rawMessageList(conv)!.first.msgID, 'm601');
    expect(global.getMessageList(conv)!.where((m) => m.elemType != 11).length,
        ChatMessageWindowPolicy.targetSize);
  });

  testWidgets(
      'actual message selector shares the model display without a per-notify copy',
      (tester) async {
    global.setMessageList(conv, [row(2), row(1)], replace: true);
    List<V2TimMessage?>? selected;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: global,
        child: MaterialApp(
            home: TIMUIKitHistoryMessageListSelector(
                conversationID: conv,
                builder: (_, list, __) {
                  selected = list;
                  return Text('rows ${list.length}');
                }))));
    expect(selected, same(global.getMessageList(conv)));
    expect(() => selected!.clear(), throwsUnsupportedError);
    global.appendRealtimeMessages(conv, [row(3)]);
    await tester.pump(const Duration(milliseconds: 80));
    expect(selected, same(global.getMessageList(conv)));
    expect(selected!.first!.msgID, 'm3');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
