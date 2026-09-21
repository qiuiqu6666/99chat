import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TUIChatGlobalModel global;
  var serial = 0;
  late String conv;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    conv = 'c2c_canonical_${++serial}';
    global = serviceLocator<TUIChatGlobalModel>();
    global.configureMessageWriterScope(
        ownerUserID: 'canonical_owner',
        accountGeneration: 1,
        domainGeneration: 1);
    ChatMainThreadPerf.resetCounters();
    ChatMainThreadPerf.debugForceEnabled = true;
  });
  tearDown(() => ChatMainThreadPerf.debugForceEnabled = false);

  V2TimMessage message(int id, {String? text}) => V2TimMessage.fromJson({
        'message_msg_id': '$conv-$id',
        'message_server_time': id,
        'message_risk_type_identified': 0,
      })
        ..isSelf = false
        ..elemType = 1
        ..textElem = V2TimTextElem(text: text ?? 'text$id');

  void receive(List<V2TimMessage> items,
      {MessageDeltaKind kind = MessageDeltaKind.realtimeUpsert}) {
    global.commitMessageDelta(MessageDelta<V2TimMessage>(
      conversationKey: conv,
      eventID: '$conv-${++serial}',
      kind: kind,
      source: MessageDeltaSource.sdkRealtime,
      generation: global.messageDeltaGenerationFor(conv),
      clearEpoch: global.messageDeltaClearEpochFor(conv),
      upserts: items.map(global.messageDeltaRecord),
    ));
  }

  test('budgeted window reuses writer ordering for a newer batch', () {
    const size = ChatMessageWindowPolicy.targetSize;
    global.setMessageList(conv, List.generate(size, (i) => message(size - i)),
        replace: true);
    receive([message(size + 1), message(size + 3), message(size + 2)]);
    expect(global.rawMessageList(conv)!.take(4).map((m) => m.timestamp),
        [size + 3, size + 2, size + 1, size]);
    expect(global.rawMessageCount(conv), size + 3);
    expect(
        ChatMainThreadPerf.countersSnapshot()[
            'message_realtime_canonical_reused'],
        1);
  });

  test('identical snapshot preserves the visible cache and list revision', () {
    global.setMessageList(conv, [message(2), message(1)], replace: true);
    final visible = global.getMessageList(conv);
    final revision = global.messageListRevisionFor(conv);
    global.setMessageList(conv, [message(2), message(1)], replace: true);
    expect(global.messageListRevisionFor(conv), revision);
    expect(identical(global.getMessageList(conv), visible), isTrue);
    expect(
        ChatMainThreadPerf.countersSnapshot()['message_noop_canonical_reused'],
        1);
  });

  test('same-count text edits and receipts still advance visible state',
      () async {
    global.setMessageList(conv, [message(1)], replace: true);
    await Future<void>.value();
    final before = global.messageListRevisionFor(conv);
    receive([message(1, text: 'edited')], kind: MessageDeltaKind.edit);
    expect(global.rawMessageList(conv)!.single.textElem!.text, 'edited');
    expect(global.messageListRevisionFor(conv), greaterThan(before));
    await Future<void>.value();
    final edited = global.messageListRevisionFor(conv);
    receive([message(1, text: 'edited')..isPeerRead = true],
        kind: MessageDeltaKind.readReceipt);
    expect(global.messageListRevisionFor(conv), greaterThan(edited));
  });

  test('append across the cap preserves older-pagination availability', () {
    const size = ChatMessageWindowPolicy.softMax;
    global.setMessageList(conv, List.generate(size, (i) => message(size - i)),
        replace: true);
    receive([message(size + 1)]);
    expect(global.rawMessageCount(conv), ChatMessageWindowPolicy.targetSize);
    expect(global.rawMessageList(conv)!.first.timestamp, size + 1);
    expect(global.memoryWindowMissingOlder(conv), isTrue);
  });

  test('older inserts fall back and remain correctly ordered', () {
    global.setMessageList(conv, [message(4), message(2)], replace: true);
    receive([message(3)]);
    expect(global.rawMessageList(conv)!.map((m) => m.timestamp), [4, 3, 2]);
    expect(
        ChatMainThreadPerf.countersSnapshot()[
                'message_realtime_canonical_reused'] ??
            0,
        0);
  });

  test('plain-text projection reuse requires ordered unique server identities',
      () {
    final first = message(1)
      ..msgID = '123456-1'
      ..userID = 'peer';
    final second = message(2)
      ..msgID = '123456-2'
      ..userID = 'peer';
    expect(TUIChatGlobalModel.isCanonicalPlainTextProjection([first, second]),
        isTrue);
    expect(TUIChatGlobalModel.isCanonicalPlainTextProjection([second, first]),
        isFalse);
    expect(TUIChatGlobalModel.isCanonicalPlainTextProjection([first, first]),
        isFalse);
    expect(
        TUIChatGlobalModel.isCanonicalPlainTextProjection(
            [message(1)..msgID = null]),
        isFalse);
    expect(
        TUIChatGlobalModel.isCanonicalPlainTextProjection(
            [message(1)..localCustomData = '{"localGroupTips":true}']),
        isFalse);
    expect(
        TUIChatGlobalModel.isCanonicalPlainTextProjection(
            [message(1)..elemType = 2]),
        isFalse);
  });

  test('own outgoing messages retain the full reconciliation path', () {
    global.setMessageList(conv, [message(1)], replace: true);
    receive([message(2)..isSelf = true]);
    expect(global.rawMessageList(conv)!.first.timestamp, 2);
    expect(
        ChatMainThreadPerf.countersSnapshot()[
                'message_realtime_canonical_reused'] ??
            0,
        0);
  });

  test('group text projection falls back for duplicate sequence identities',
      () {
    final first = message(1)
      ..groupID = '@TGS#plain'
      ..seq = '1';
    final second = message(2)
      ..groupID = '@TGS#plain'
      ..seq = '2';
    expect(TUIChatGlobalModel.isCanonicalPlainTextProjection([first, second]),
        isTrue);
    second.seq = '1';
    expect(TUIChatGlobalModel.isCanonicalPlainTextProjection([first, second]),
        isFalse);
    second.seq = '2';
    second.localCustomData = '{"localGroupTips":true}';
    expect(TUIChatGlobalModel.isCanonicalPlainTextProjection([first, second]),
        isFalse);
  });

  test('contiguous group messages reuse canonical ordering', () {
    conv = '@TGS#canonical_${++serial}';
    V2TimMessage groupMessage(int id) => message(id)
      ..groupID = conv
      ..seq = '$id';
    global.setMessageList(conv, [groupMessage(2), groupMessage(1)],
        replace: true);
    receive([groupMessage(3)]);
    expect(global.rawMessageList(conv)!.map((m) => m.seq), ['3', '2', '1']);
    expect(
        ChatMainThreadPerf.countersSnapshot()[
            'message_realtime_canonical_reused'],
        1);
  });
}

