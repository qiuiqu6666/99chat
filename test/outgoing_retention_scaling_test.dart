import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

class _CountedOutgoing extends V2TimMessage {
  _CountedOutgoing(int index, {required bool group})
      : super.fromJson({
          'message_msg_id': '123456-1700001000-$index',
          'message_server_time': 1700001000,
          'message_risk_type_identified': 0,
        }) {
    sender = 'self';
    userID = group ? null : 'peer';
    groupID = group ? '@TGS#retention' : null;
    seq = '$index';
    id = 'local-$index';
    isSelf = true;
    status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
    textElem = V2TimTextElem(text: 'same-second send');
    // Every row qualifies as a recent ack, so the test exercises coverage
    // lookup rather than passing only through the old-message eligibility gate.
    localCustomData = jsonEncode({'__outgoingLocalSeq': index});
  }

  static int reads = 0;
  @override
  String? get msgID {
    reads++;
    return super.msgID;
  }

  @override
  set msgID(String? value) => super.msgID = value;
  @override
  String? get userID {
    reads++;
    return super.userID;
  }

  @override
  set userID(String? value) => super.userID = value;
  @override
  String? get groupID {
    reads++;
    return super.groupID;
  }

  @override
  set groupID(String? value) => super.groupID = value;
  @override
  String? get seq {
    reads++;
    return super.seq;
  }

  @override
  set seq(String? value) => super.seq = value;
}

V2TimMessage _row({
  String? id,
  String? msgID,
  String? peer = 'peer',
  String? group,
  int timestamp = 1700001000,
  int status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
  bool self = true,
  int? localSeq,
  String? stable,
  String? seq,
  bool archive = false,
}) {
  final row = V2TimMessage.fromJson({
    'message_msg_id': msgID,
    'message_server_time': timestamp,
    'message_risk_type_identified': 0,
  });
  row.id = id;
  row.userID = group == null ? peer : null;
  row.groupID = group;
  row.isSelf = self;
  row.status = status;
  row.seq = seq;
  row.elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
  row.localCustomData = jsonEncode({
    if (localSeq != null) '__outgoingLocalSeq': localSeq,
    if (stable != null) kChatOutgoingStableIdKey: stable,
    if (archive) 'archiveHistory': true,
  });
  return row;
}

List<V2TimMessage> _extras(
        List<V2TimMessage> previous, List<V2TimMessage> incoming) =>
    TUIChatGlobalModel.collectUncorrelatedInFlightOutgoing(
        previous: previous, incoming: incoming);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final group in [false, true]) {
    for (final fresh in [false, true]) {
      test('recent outgoing coverage scales linearly group=$group fresh=$fresh',
          () {
        int? previousReads;
        for (final size in [500, 1000, 2000]) {
          final previous = List<V2TimMessage>.generate(
              size, (i) => _CountedOutgoing(i + 1, group: group));
          final incoming = fresh
              ? List<V2TimMessage>.generate(
                  size, (i) => _CountedOutgoing(i + 1, group: group))
              : List<V2TimMessage>.of(previous);
          _CountedOutgoing.reads = 0;
          expect(_extras(previous, incoming), isEmpty);
          final reads = _CountedOutgoing.reads;
          // Counts measure the actual production getters, not elapsed time.
          // ignore: avoid_print
          print('OUTGOING_RETENTION_SCALE group=$group fresh=$fresh '
              'n=$size reads=$reads');
          expect(reads, lessThan(size * 200));
          if (previousReads != null) {
            expect(reads, lessThanOrEqualTo(previousReads * 2.1));
          }
          previousReads = reads;
        }
      });
    }
  }

  test('retention eligibility keeps original order, objects and 120s boundary',
      () {
    final newest = _row(msgID: '123456-1700001000-99');
    final newer = _row(msgID: '123456-1700001001-1', timestamp: 1700001001);
    final oldSuccess =
        _row(msgID: '123456-1700000999-2', timestamp: 1700000999);
    final pendingA = _row(
        id: 'pending-a',
        timestamp: 1700000500,
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING);
    final recentAck =
        _row(msgID: '123456-1700000880-3', timestamp: 1700000880, localSeq: 3);
    final pendingB = _row(
        id: 'pending-b',
        timestamp: 1700000501,
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING);
    final oldAck =
        _row(msgID: '123456-1700000879-4', timestamp: 1700000879, localSeq: 4);
    final failed = _row(
        id: 'failed',
        timestamp: 1700001002,
        status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
    final peer =
        _row(msgID: '123456-1700001002-5', self: false, timestamp: 1700001002);
    final actual = _extras([
      newer,
      oldSuccess,
      pendingA,
      recentAck,
      pendingB,
      oldAck,
      failed,
      peer,
    ], [
      newest
    ]);
    final expected = [newer, pendingA, recentAck, pendingB];
    expect(actual.length, expected.length);
    for (var i = 0; i < actual.length; i++) {
      expect(identical(actual[i], expected[i]), isTrue);
    }
  });

  test('different IDs retain existing local-sequence correlation', () {
    final pending = _row(
        id: 'client-a',
        localSeq: 7,
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING);
    final ack =
        _row(id: 'sdk-client-b', msgID: '123456-1700001000-7', localSeq: 7);
    expect(TUIChatGlobalModel.messagesCorrelateForDedup(pending, ack), isTrue);
    expect(_extras([pending], [ack]), isEmpty);
  });

  test('archive SDK group copies remain correlated across different IDs', () {
    final sdk = _row(
        msgID: '123456-1700001000-7',
        group: '@TGS#group',
        seq: '7',
        localSeq: 7);
    final archive = _row(
        msgID: '@TGS#group:7', group: '@TGS#group', seq: '7', archive: true);
    expect(TUIChatGlobalModel.messagesCorrelateForDedup(sdk, archive), isTrue);
    expect(_extras([sdk], [archive]), isEmpty);
  });

  test('same-field IDs and stable IDs keep their original coverage semantics',
      () {
    final candidates = [
      _row(id: 'same-local', msgID: '123456-1700001000-1', localSeq: 1),
      _row(msgID: 'same-server', localSeq: 2),
      _row(msgID: '123456-1700001000-3', stable: 'same-stable', localSeq: 3),
    ];
    final incoming = [
      _row(id: 'same-local', msgID: '123456-1700001000-11'),
      _row(msgID: 'same-server'),
      _row(msgID: '123456-1700001000-13', stable: 'same-stable'),
    ];
    expect(_extras(candidates, incoming), isEmpty);
  });

  test('cross-field aliases cannot bypass distinct SDK identity guards', () {
    final candidate = _row(
        id: '123456-1700001000-2',
        msgID: '123456-1700001000-1',
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING);
    final incoming = _row(id: 'other-local', msgID: '123456-1700001000-2');
    expect(TUIChatGlobalModel.messagesCorrelateForDedup(candidate, incoming),
        isFalse);
    expect(_extras([candidate], [incoming]).single, same(candidate));
  });

  test('cross-field aliases cannot bypass distinct group sequences', () {
    final candidate = _row(
        id: '123456-1700001000-2',
        msgID: '123456-1700001000-1',
        group: '@TGS#group',
        seq: '1',
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING);
    final incoming = _row(
        id: 'other-local',
        msgID: '123456-1700001000-2',
        group: '@TGS#group',
        seq: '2');
    expect(TUIChatGlobalModel.messagesCorrelateForDedup(candidate, incoming),
        isFalse);
    expect(_extras([candidate], [incoming]).single, same(candidate));
  });

  test('same anonymous instance does not gain an invented correlation', () {
    final anonymous = _row(
        peer: null,
        timestamp: 0,
        status: MessageStatus.V2TIM_MSG_STATUS_SENDING);
    expect(TUIChatGlobalModel.messagesCorrelateForDedup(anonymous, anonymous),
        isFalse);
    expect(_extras([anonymous], [anonymous]).single, same(anonymous));
  });

  test('restore leaves the incoming list instance intact when fully covered',
      () {
    final previous = [_row(msgID: '123456-1700001000-7', localSeq: 7)];
    final incoming = [_row(msgID: '123456-1700001000-7', localSeq: 7)];
    final restored = TUIChatGlobalModel.restoreUncorrelatedInFlightOutgoing(
        previous: previous, incoming: incoming);
    expect(identical(restored, incoming), isTrue);
  });
}
