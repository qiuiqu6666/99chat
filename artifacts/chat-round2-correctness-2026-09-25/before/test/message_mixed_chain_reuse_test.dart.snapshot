import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_face_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_location_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_writer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';

class _CountedMessage extends V2TimMessage {
  _CountedMessage(int index)
      : super.fromJson({
          'message_msg_id': '123456-1700000000-$index',
          'message_server_time': 1700000000 + index,
          'message_risk_type_identified': 0,
        }) {
    id = 'local-$index';
    seq = '$index';
    userID = 'mixed-peer';
    isSelf = true;
    status = 2;
    elemType = index.isEven ? 3 : 1;
    if (index.isEven) {
      imageElem = V2TimImageElem(path: 'local-$index', imageList: [
        V2TimImage(type: 1, uuid: 'image-$index', width: 80, height: 80),
      ]);
    } else {
      textElem = V2TimTextElem(text: 'text-$index');
    }
  }
  static int identityReads = 0;
  @override
  String? get msgID {
    identityReads++;
    return super.msgID;
  }

  @override
  set msgID(String? value) => super.msgID = value;
  @override
  String? get id {
    identityReads++;
    return super.id;
  }

  @override
  set id(String? value) => super.id = value;
  @override
  String? get seq {
    identityReads++;
    return super.seq;
  }

  @override
  set seq(String? value) => super.seq = value;
}

class _NoJsonImage extends V2TimImageElem {
  _NoJsonImage()
      : super(path: 'image', imageList: [V2TimImage(type: 1, url: 'a')]);
  @override
  Map<String, dynamic> toJson() => throw StateError('image JSON allocated');
}

class _NoJsonCustom extends V2TimCustomElem {
  _NoJsonCustom() : super(data: 'card', desc: 'desc', extension: 'ext');
  @override
  Map<String, dynamic> toJson() => throw StateError('custom JSON allocated');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TUIChatGlobalModel model;
  const conv = 'c2c_mixed-peer';
  var event = 0;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    model = TUIChatGlobalModel();
    model.configureMessageWriterScope(
        ownerUserID: 'mixed', accountGeneration: 1, domainGeneration: 1);
    ChatMainThreadPerf.debugForceEnabled = true;
    ChatMainThreadPerf.resetCounters();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 70));
    model.dispose();
    ChatMainThreadPerf.debugForceEnabled = false;
  });
  void receive(V2TimMessage row,
      {MessageDeltaKind kind = MessageDeltaKind.realtimeUpsert}) {
    model.commitMessageDelta(MessageDelta<V2TimMessage>(
      conversationKey: conv,
      eventID: 'mixed-${++event}',
      kind: kind,
      source: MessageDeltaSource.sdkRealtime,
      generation: model.messageDeltaGenerationFor(conv),
      clearEpoch: model.messageDeltaClearEpochFor(conv),
      upserts: [model.messageDeltaRecord(row)],
    ));
  }

  test('realtime mixed windows reuse Writer authority without reseeding', () {
    model.setMessageList(
        conv, List.generate(100, (i) => _CountedMessage(100 - i)),
        replace: true);
    ChatMainThreadPerf.resetCounters();
    for (var i = 101; i <= 105; i++) receive(_CountedMessage(i));
    final counters = ChatMainThreadPerf.countersSnapshot();
    expect(counters['message_writer_seed_performed'] ?? 0, 0);
    expect(counters['message_writer_seed_reused'], 5);
    expect(model.rawMessageCount(conv), 105);
  });

  test('SDK identity/order edits and Writer reset invalidate seed authority',
      () {
    model.setMessageList(conv, [_CountedMessage(2), _CountedMessage(1)],
        replace: true);
    final row = model.rawMessageList(conv)!.last;
    row.msgID = '123456-1700000000-999';
    row.seq = '999';
    row.timestamp = 1700001000;
    ChatMainThreadPerf.resetCounters();
    receive(_CountedMessage(3));
    expect(model.rawMessageList(conv)!.first.msgID, row.msgID);
    expect(
        model
            .rawMessageList(conv)!
            .where((r) => r.msgID == '123456-1700000000-1'),
        isEmpty);
    expect(
        ChatMainThreadPerf.countersSnapshot()['message_writer_seed_performed'],
        1);
    model.cancelHistoryReconciliation(conv);
    receive(_CountedMessage(4));
    expect(model.rawMessageCount(conv), 4);
    expect(
        ChatMainThreadPerf.countersSnapshot()['message_writer_seed_performed'],
        2);
  });

  test('in-place nested media edits still publish after authority reuse',
      () async {
    model.setMessageList(conv, [_CountedMessage(2)], replace: true);
    await Future<void>.value();
    final before = model.messageListRevisionFor(conv);
    final row = model.rawMessageList(conv)!.single;
    row.imageElem!.imageList!.single!.localUrl = 'downloaded';
    receive(row, kind: MessageDeltaKind.edit);
    expect(model.messageListRevisionFor(conv), greaterThan(before));
    expect(
        model
            .rawMessageList(conv)!
            .single
            .imageElem!
            .imageList!
            .single!
            .localUrl,
        'downloaded');
  });

  test('bubble status, read and row-key lookup use one index per window', () {
    int? previousReads;
    for (final size in [500, 1000, 2000]) {
      model.setMessageList(
          conv, List.generate(size, (i) => _CountedMessage(size - i)),
          replace: true, applyMemoryWindow: false);
      final rows = model.rawMessageList(conv)!;
      final keys = rows.map((row) => row.msgID!).toList();
      ChatMainThreadPerf.resetCounters();
      _CountedMessage.identityReads = 0;
      for (var i = 0; i < rows.length; i++) {
        expect(model.messageStatusInConversation(conv, msgID: keys[i]), 2);
        expect(model.messageInConversationByKey(conv, keys[i]), same(rows[i]));
        expect(
            model.isOutgoingC2CMessagePeerRead(
                conversationID: conv, message: rows[i]),
            isFalse);
      }
      final reads = _CountedMessage.identityReads;
      print('MIXED_IDENTITY_LOOKUP n=$size reads=$reads');
      expect(
          ChatMainThreadPerf.countersSnapshot()['message_identity_index_built'],
          1);
      expect(reads, lessThan(size * 30));
      if (previousReads != null)
        expect(reads, lessThanOrEqualTo(previousReads * 2.1));
      previousReads = reads;
    }
  });

  test('identity changes stay live while structure changes use the Writer', () {
    final replacement = _CountedMessage(3);
    model.setMessageList(conv, [_CountedMessage(2), _CountedMessage(1)],
        replace: true);
    final rows = model.rawMessageList(conv)!;
    final olderKey = rows.last.msgID!;
    expect(model.messageInConversationByKey(conv, olderKey), same(rows.last));
    rows.first.msgID = olderKey;
    expect(model.messageInConversationByKey(conv, olderKey), same(rows.first));
    expect(() => rows[0] = replacement, throwsUnsupportedError);
    model.setMessageList(conv, [replacement, rows.last], replace: true);
    expect(model.messageInConversationByKey(conv, replacement.msgID!),
        same(replacement));
    expect(rows.length, 2,
        reason: 'a published snapshot never changes structure');
  });

  test('external list edits cannot bypass the authoritative message window',
      () {
    final first = _CountedMessage(2), second = _CountedMessage(1);
    final external = [first, second];
    model.setMessageList(conv, external, replace: true);
    expect(() => model.messageListMap[conv] = external, throwsUnsupportedError);
    external[0] = second;
    expect(model.rawMessageList(conv)!.first, same(first));
    expect(model.messageInConversationByKey(conv, second.msgID!), same(second));
  });

  test('published raw windows reject every structural mutation', () {
    final messages =
        List<V2TimMessage>.generate(4, (i) => _CountedMessage(i + 1));
    model.setMessageList(conv, messages, replace: true);
    final window = model.rawMessageList(conv)!;
    final before = List<V2TimMessage>.of(window);
    final actions = <void Function(List<V2TimMessage>)>[
      (list) => list.add(messages.first),
      (list) => list.addAll(messages),
      (list) => list.insert(0, messages.last),
      (list) => list.insertAll(1, messages),
      (list) => list.setAll(0, [messages.first]),
      (list) => list.setRange(0, 2, messages),
      (list) => list.replaceRange(0, 1, messages),
      (list) => list.fillRange(0, 2, messages.first),
      (list) => list.sort((a, b) => a.timestamp!.compareTo(b.timestamp!)),
      (list) => list.removeAt(1),
      (list) => list.removeWhere((_) => true),
      (list) => list.retainWhere((_) => false),
      (list) => list.removeLast(),
      (list) => list.clear(),
    ];
    for (final action in actions) {
      expect(() => action(window), throwsUnsupportedError);
      expect(window, orderedEquals(before));
    }
    expect(() => model.messageListMap.clear(), throwsUnsupportedError);
    expect(() => model.getMessageList(conv)!.clear(), throwsUnsupportedError);
  });

  test('anonymous timestamp keys stay live without a message identity mutation',
      () {
    final anonymous = _CountedMessage(1)
      ..msgID = null
      ..id = null
      ..seq = null;
    model.setMessageList(conv, [anonymous], replace: true);
    final row = model.rawMessageList(conv)!.single;
    expect(
        model.messageInConversationByKey(
            conv, 'ts_${row.timestamp}_mixed-peer'),
        same(row));
    row.timestamp = 123;
    row.sender = 'changed';
    expect(model.messageInConversationByKey(conv, 'ts_123_changed'), same(row));
  });

  test(
      '500 mixed group rows reuse protocol ordering, duplicate seq takes fallback',
      () {
    final group = List<V2TimMessage>.generate(
        500,
        (i) => _CountedMessage(i + 1)
          ..userID = null
          ..groupID = '@TGS#mixed');
    group[100].elemType = 2;
    group[100].customElem = V2TimCustomElem(data: '{"businessID":"card"}');
    expect(
        TUIChatGlobalModel.canonicalizeMessageProjection(group), same(group));
    group[100].seq = group[99].seq;
    expect(
        identical(
            TUIChatGlobalModel.canonicalizeMessageProjection(group), group),
        isFalse);
  });

  test(
      'complete mixed SDK projection skips dedupe/sort but guards incomplete identities',
      () {
    final mixed =
        List<V2TimMessage>.generate(500, (i) => _CountedMessage(i + 1));
    expect(
        TUIChatGlobalModel.canonicalizeMessageProjection(mixed), same(mixed));
    expect(
        ChatMainThreadPerf.countersSnapshot()[
            'message_mixed_projection_reused'],
        1);
    final reversed = mixed.reversed.toList();
    expect(
        TUIChatGlobalModel.canonicalizeMessageProjection(reversed)
            .map((m) => m.msgID),
        mixed.map((m) => m.msgID));
    final duplicate = [mixed[0], mixed[0]];
    expect(TUIChatGlobalModel.canonicalizeMessageProjection(duplicate),
        hasLength(1));
    mixed[10].msgID = null;
    expect(
        identical(
            TUIChatGlobalModel.canonicalizeMessageProjection(mixed), mixed),
        isFalse);
  });

  test('media/custom signatures avoid JSON and observe all direct mutations',
      () {
    final row = _CountedMessage(2)
      ..imageElem = _NoJsonImage()
      ..customElem = _NoJsonCustom()
      ..videoElem = V2TimVideoElem(videoPath: 'v')
      ..soundElem = V2TimSoundElem(path: 's')
      ..fileElem = V2TimFileElem(path: 'f')
      ..faceElem = V2TimFaceElem(data: 'face')
      ..locationElem = V2TimLocationElem(latitude: 1, longitude: 2);
    String signature() =>
        TUIChatGlobalModel.messageListProjectionSignature([row]);
    var before = signature();
    for (final mutate in <void Function()>[
      () => row.imageElem!.path = 'new path',
      () => row.imageElem!.imageList!.single!.localUrl = 'local',
      () => row.imageElem!.imageList!.single!.width = 99,
      () => row.customElem!.data = 'changed;:',
      () => row.customElem!.extension = 'changed',
      () => row.videoElem!.snapshotWidth = 99,
      () => row.videoElem!.localVideoUrl = 'downloaded',
      () => row.soundElem!.duration = 99,
      () => row.fileElem!.fileName = 'new file',
      () => row.faceElem!.index = 9,
      () => row.locationElem!.latitude = 99,
    ]) {
      mutate();
      final next = signature();
      expect(next, isNot(before));
      before = next;
    }
    expect(
        ChatMainThreadPerf.countersSnapshot()[
                'message_signature_nested_json'] ??
            0,
        0);
  });

  test(
      'opaque Writer authority rejects same revision after reset and changed record identity',
      () {
    final writer = MessageReconciliationWriter<V2TimMessage>(
        comparator: (a, b) => b.value.timestamp!.compareTo(a.value.timestamp!));
    final row = _CountedMessage(1);
    final records = [
      MessageReconciliationRecord<V2TimMessage>(value: row, msgID: row.msgID)
    ];
    writer.seedAuthoritative(conversationID: conv, records: records);
    final authority = writer.authorityFor(conv);
    bool owns() => writer.ownsAuthoritativeWindow(
        conversationID: conv,
        expectedAuthority: authority,
        values: [row],
        matchesRecord: (record, value) => record.msgID == value.msgID,
        trackSeqGaps: false,
        clearEpoch: 0);
    expect(owns(), isTrue);
    row.msgID = 'changed';
    expect(owns(), isFalse);
    row.msgID = records.single.msgID;
    expect(owns(), isTrue);
    writer.reset(conv);
    writer.seedAuthoritative(conversationID: conv, records: records);
    expect(writer.revisionFor(conv), 0);
    expect(owns(), isFalse);
  });
}
