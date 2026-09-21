import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_writer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _Value {
  _Value(this.id);
  final int id;
}

MessageReconciliationRecord<_Value> _record(_Value value) =>
    MessageReconciliationRecord(
        value: value, msgID: 'm${value.id}', seq: '${value.id}');

MessageReconciliationWriter<_Value> _writer() => MessageReconciliationWriter(
    comparator: (left, right) => right.value.id.compareTo(left.value.id));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  test('eviction is revision guarded and does not tombstone replayable rows',
      () {
    final writer = _writer();
    final values = List.generate(700, _Value.new);
    writer.seedAuthoritative(
        conversationID: 'c2c_peer', records: values.map(_record));
    expect(
        writer.retainCommittedWindow(
            conversationID: 'c2c_peer',
            expectedRevision: 1,
            expectedClearEpoch: 0,
            expectedScope: null,
            retainedValues: values.take(500)),
        isFalse);
    expect(writer.recordsFor('c2c_peer'), hasLength(700));
    expect(
        writer.retainCommittedWindow(
            conversationID: 'c2c_peer',
            expectedRevision: 0,
            expectedClearEpoch: 0,
            expectedScope: null,
            retainedValues: values.take(500)),
        isTrue);
    expect(writer.recordsFor('c2c_peer'), hasLength(500));
    expect(writer.revisionFor('c2c_peer'), 0);
    expect(writer.tombstonesFor('c2c_peer'), isEmpty);
    final request = writer.beginCloudCatchUp(
        conversationID: 'c2c_peer',
        networkState: MessageReconciliationNetworkState.online);
    expect(
        writer.retainCommittedWindow(
            conversationID: 'c2c_peer',
            expectedRevision: 0,
            expectedClearEpoch: 0,
            expectedScope: null,
            retainedValues: values.take(100)),
        isFalse);
    final replay = writer.completeHistory(
        request: request,
        history: values.skip(500).take(40).map(_record),
        actualSource: MessageReconciliationSource.cloud,
        networkState: MessageReconciliationNetworkState.online);
    expect(replay!.records, hasLength(540));
    expect(replay.records.map((r) => r.value.id), contains(539));
  });

  test('clear barrier and unknown objects cannot evict writer state', () {
    final writer = _writer();
    final value = _Value(1);
    writer.seedAuthoritative(
        conversationID: 'c2c_peer', records: [_record(value)]);
    expect(
        writer.retainCommittedWindow(
            conversationID: 'c2c_peer',
            expectedRevision: 0,
            expectedClearEpoch: 0,
            expectedScope: null,
            retainedValues: [_Value(1)]),
        isFalse);
    expect(writer.recordsFor('c2c_peer'), hasLength(1));
    writer.clearConversation(conversationID: 'c2c_peer', clearEpoch: 1);
    expect(
        writer.retainCommittedWindow(
            conversationID: 'c2c_peer',
            expectedRevision: writer.revisionFor('c2c_peer'),
            expectedClearEpoch: 0,
            expectedScope: null,
            retainedValues: const []),
        isFalse);
  });

  test('a late empty-window eviction cannot clear a different account', () {
    final writer = _writer();
    const oldScope = MessageReconciliationWriterScope(
        ownerUserID: 'old', accountGeneration: 1, domainGeneration: 1);
    const newScope = MessageReconciliationWriterScope(
        ownerUserID: 'new', accountGeneration: 2, domainGeneration: 1);
    writer.configureScope(oldScope);
    writer.configureScope(newScope);
    writer.seedAuthoritative(
        conversationID: 'c2c_peer', records: [_record(_Value(1))]);
    expect(
        writer.retainCommittedWindow(
            conversationID: 'c2c_peer',
            expectedRevision: 0,
            expectedClearEpoch: 0,
            expectedScope: oldScope,
            retainedValues: const []),
        isFalse);
    expect(writer.recordsFor('c2c_peer'), hasLength(1));
  });

  V2TimMessage message(int id) => V2TimMessage.fromJson({
        'message_msg_id': '1000-$id-1',
        'message_server_time': id,
        'message_risk_type_identified': 0,
      })
        ..seq = '$id'
        ..isSelf = false;

  test('stable message identity wins over an index shifted by pagination', () {
    final list = List.generate(1000, (i) => message(1000 - i));
    final trimmed = ChatMessageWindow.trimToWindow(
        list: list,
        anchorMsgID: '1000-50-1',
        anchorIndexHint: 30,
        softMax: 600,
        targetSize: 500);
    expect(trimmed.list.map((m) => m.msgID), contains('1000-50-1'));
    expect(trimmed.list.map((m) => m.msgID),
        containsAll(['1000-10-1', '1000-90-1']));
    final seqTrimmed = ChatMessageWindow.trimToWindow(
        list: list,
        anchorMsgID: 'missing',
        anchorSeq: '50',
        anchorIndexHint: 30,
        softMax: 600,
        targetSize: 500);
    expect(seqTrimmed.list.map((m) => m.seq), contains('50'));
  });

  test('production raw and writer remain bounded across 100 growing batches',
      () {
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = 'c2c_retained_working_set';
    global.configureMessageWriterScope(
        ownerUserID: 'retained_owner',
        accountGeneration: 1,
        domainGeneration: 1);
    global.setMessageList(conv, List.generate(600, (i) => message(600 - i)),
        replace: true);
    var newest = 600;
    for (var page = 0; page < 100; page++) {
      final next = List.generate(50, (i) => message(newest + 50 - i));
      newest += 50;
      global.commitMessageDelta(MessageDelta<V2TimMessage>(
        conversationKey: conv,
        eventID: 'batch$page',
        kind: MessageDeltaKind.realtimeUpsert,
        source: MessageDeltaSource.sdkRealtime,
        generation: global.messageDeltaGenerationFor(conv),
        clearEpoch: global.messageDeltaClearEpochFor(conv),
        upserts: next.map(global.messageDeltaRecord),
      ));
      expect(global.rawMessageCount(conv), lessThanOrEqualTo(600));
      expect(global.messageWriterRetainedCountForTesting(conv),
          global.rawMessageCount(conv));
      expect(global.rawMessageList(conv)!.first.timestamp, newest);
    }
    expect(global.memoryWindowMissingOlder(conv), isTrue);
  });
}
