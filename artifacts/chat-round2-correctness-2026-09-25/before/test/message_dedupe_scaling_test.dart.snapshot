import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_writer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

// Count actual production field reads, not a branch counter or wall-clock time.
class _CountedMessage extends V2TimMessage {
  _CountedMessage(int index, {required bool c2c, required bool burst})
      : super.fromJson({
          'message_msg_id': '123456-${1700000000 + index}-$index',
          'message_server_time': burst ? 1700000000 : 1700000000 + index,
          'message_risk_type_identified': 0,
        }) {
    sender = 'peer';
    groupID = c2c ? null : '@TGS#scaling';
    userID = c2c ? 'peer' : null;
    seq = '$index';
    random = index;
    isSelf = index.isEven;
    elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
    textElem = V2TimTextElem(text: burst ? 'same text' : 'message $index');
  }

  static int reads = 0;
  @override
  String? get groupID {
    reads++;
    return super.groupID;
  }

  @override
  set groupID(String? value) => super.groupID = value;
  @override
  String? get userID {
    reads++;
    return super.userID;
  }

  @override
  set userID(String? value) => super.userID = value;
  @override
  String? get msgID {
    reads++;
    return super.msgID;
  }

  @override
  set msgID(String? value) => super.msgID = value;
}

V2TimMessage _message({
  String? msgID,
  String? id,
  String? peer,
  String? group,
  String? sender,
  int timestamp = 0,
  int seq = 0,
  int? random,
  bool self = false,
  bool sending = false,
  int? localSeq,
  String? text,
  String? path,
  bool archive = false,
}) {
  final message = V2TimMessage.fromJson({
    'message_msg_id': msgID,
    'message_server_time': timestamp,
    'message_risk_type_identified': 0,
  });
  message.id = id;
  message.userID = peer;
  message.groupID = group;
  message.sender = sender;
  message.seq = '$seq';
  message.random = random;
  message.isSelf = self;
  message.status = sending
      ? MessageStatus.V2TIM_MSG_STATUS_SENDING
      : MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
  message.elemType = path == null
      ? MessageElemType.V2TIM_ELEM_TYPE_TEXT
      : MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
  if (text != null) message.textElem = V2TimTextElem(text: text);
  if (path != null) message.imageElem = V2TimImageElem(path: path);
  message.localCustomData = jsonEncode({
    if (localSeq != null) '__outgoingLocalSeq': localSeq,
    if (archive) 'archiveHistory': true,
  });
  return message;
}

void _expectPair(V2TimMessage Function() a, V2TimMessage Function() b) {
  for (final reversed in [false, true]) {
    final left = reversed ? b() : a();
    final right = reversed ? a() : b();
    expect(TUIChatGlobalModel.messagesCorrelateForDedup(left, right), isTrue);
    expect(TUIChatGlobalModel.dedupeMessages([left, right]), hasLength(1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final c2c in [false, true]) {
    for (final burst in [false, true]) {
      test(
          '${c2c ? 'C2C' : 'group'} unique SDK rows scale linearly '
          '(same-second identical text: $burst)', () {
        int? previousReads;
        for (final size in [500, 1000, 2000]) {
          final input = List<V2TimMessage>.generate(
              size, (i) => _CountedMessage(i + 1, c2c: c2c, burst: burst));
          _CountedMessage.reads = 0;
          final result = TUIChatGlobalModel.dedupeMessages(input);
          final reads = _CountedMessage.reads;
          expect(result.length, size);
          for (var i = 0; i < size; i++) {
            expect(identical(result[i], input[i]), isTrue);
          }
          expect(reads, lessThan(size * 80));
          if (previousReads != null) {
            expect(reads, lessThanOrEqualTo(previousReads * 2.2));
          }
          previousReads = reads;
          // ignore: avoid_print
          print('DEDUPE_SCALE c2c=$c2c burst=$burst n=$size reads=$reads');
        }
      });
    }
  }

  test('aliases bridge rows with no timestamp, sender or matching elemType',
      () {
    _expectPair(
      () => _message(msgID: 'alias'),
      () => _message(id: 'alias', path: '/tmp/photo.jpg'),
    );
  });

  test('outgoing local sequence bridges changed ID and timestamp', () {
    _expectPair(
      () => _message(id: 'client', self: true, sending: true, localSeq: 17),
      () => _message(
          msgID: '123456-1700000020-5',
          self: true,
          timestamp: 1700000020,
          localSeq: 17),
    );
  });

  test('image path bridges placeholder and ack without metadata', () {
    _expectPair(
      () => _message(
          id: 'client', self: true, sending: true, path: '/tmp/same.jpg'),
      () => _message(
          msgID: '123456-1700000020-5',
          self: true,
          timestamp: 1700000020,
          path: '/tmp/same.jpg'),
    );
  });

  test('new server alias remains indexed after a placeholder wins/adopts', () {
    final placeholder = _message(
        id: 'client',
        self: true,
        sending: true,
        localSeq: 7,
        path: '/tmp/photo.jpg');
    final ack = _message(
        msgID: '123456-1700000020-5',
        id: 'sdk-local',
        self: true,
        timestamp: 1700000020,
        localSeq: 7,
        path: '/tmp/photo.jpg');
    final laterAlias = _message(
        id: '123456-1700000020-5',
        self: true,
        timestamp: 1700000050,
        path: '/tmp/photo.jpg');
    expect(TUIChatGlobalModel.dedupeMessages([placeholder, ack, laterAlias]),
        hasLength(1));
  });

  test(
      'group seq bridges archive and SDK with missing group and different type',
      () {
    _expectPair(
      () => _message(
          msgID: '@TGS#group:9',
          group: '@TGS#group',
          seq: 9,
          archive: true,
          timestamp: 1700000000,
          text: 'archive'),
      () => _message(
          msgID: '123456-1700000200-5',
          seq: 9,
          timestamp: 1700000200,
          path: '/tmp/photo.jpg'),
    );
  });

  test('missing seq preview still correlates to complete SDK in both orders',
      () {
    _expectPair(
      () => _message(id: 'preview', group: '@TGS#group', timestamp: 1700000000),
      () => _message(
          msgID: '123456-1700000000-5',
          group: '@TGS#group',
          seq: 9,
          timestamp: 1700000000,
          text: 'SDK body'),
    );
  });

  test('C2C preview tolerates mismatched peer and sender', () {
    _expectPair(
      () => _message(
          id: 'preview',
          peer: 'self',
          self: true,
          timestamp: 1700000000,
          text: 'same'),
      () => _message(
          msgID: '123456-1700000000-5',
          peer: 'peer',
          sender: 'peer',
          timestamp: 1700000000,
          text: 'same'),
    );
  });

  test('same-second C2C cloud IDs remain distinct with a legacy preview nearby',
      () {
    final input = [
      _message(
          id: 'preview', peer: 'peer', timestamp: 1700000000, text: 'same'),
      _message(
          msgID: '123456-1700000000-5',
          peer: 'peer',
          timestamp: 1700000000,
          text: 'same'),
      _message(
          msgID: '123456-1700000000-6',
          peer: 'peer',
          timestamp: 1700000000,
          text: 'same'),
    ];
    final result = TUIChatGlobalModel.dedupeMessages(input);
    expect(result.map((m) => m.msgID),
        containsAll(['123456-1700000000-5', '123456-1700000000-6']));
    expect(result, hasLength(2));
  });

  test('Writer checks already ordered rows once and reorders changed keys', () {
    var comparisons = 0;
    final writer = MessageReconciliationWriter<int>(comparator: (a, b) {
      comparisons++;
      return a.value.compareTo(b.value);
    });
    MessageReconciliationRecord<int> record(int value, {String? id}) =>
        MessageReconciliationRecord(value: value, msgID: id ?? '$value');
    writer.seedAuthoritative(
        conversationID: 'c2c_peer', records: List.generate(1000, record));
    expect(comparisons, 999);
    comparisons = 0;
    final receipt = writer.applyDelta(MessageDelta<int>(
      conversationKey: 'c2c_peer',
      eventID: 'receipt',
      kind: MessageDeltaKind.readReceipt,
      source: MessageDeltaSource.sdkRealtime,
      generation: 0,
      clearEpoch: 0,
      upserts: [record(500)],
    ));
    expect(receipt!.records.map((r) => r.value),
        orderedEquals(List.generate(1000, (i) => i)));
    expect(comparisons, 999);
    final edit = writer.applyDelta(MessageDelta<int>(
      conversationKey: 'c2c_peer',
      eventID: 'edit',
      kind: MessageDeltaKind.edit,
      source: MessageDeltaSource.sdkRealtime,
      generation: 0,
      clearEpoch: 0,
      upserts: [record(-1, id: '500')],
    ));
    expect(edit!.records.first.value, -1);
    expect(edit.records, hasLength(1000));
    expect(
        edit.records.map((r) => r.value),
        orderedEquals(
            [-1, ...List.generate(1000, (i) => i).where((i) => i != 500)]));
  });
}
