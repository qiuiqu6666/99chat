import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_history_around_loader.dart';

void main() {
  test('C2C SDK exception retries the same full message locally', () async {
    final target = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..msgID = 'c2c-target';
    final calls = <HistoryMsgGetTypeEnum>[];
    final result = await MessageHistoryAroundLoader.loadSide(
      read: (type, {required lastMsgSeq, lastMsgID, lastMsg}) async {
        calls.add(type);
        expect(lastMsgSeq, -1);
        expect(lastMsgID, target.msgID);
        expect(identical(lastMsg, target), isTrue);
        if (type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG) {
          throw StateError('native history callback failed');
        }
        return V2TimMessageListResult(messageList: [target], isFinished: false);
      },
      isGroup: false,
      newer: true,
      targetSeq: 500,
      targetMsgID: target.msgID,
      targetMessage: target,
    );
    expect(result!.messageList.single, target);
    expect(calls, [
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG
    ]);
  });

  testWidgets('C2C missing callbacks finish and ignore late cloud data',
      (tester) async {
    final cloud = Completer<V2TimMessageListResult?>();
    final local = Completer<V2TimMessageListResult?>();
    final calls = <HistoryMsgGetTypeEnum>[];
    var completed = false;
    V2TimMessageListResult? result;
    final task = MessageHistoryAroundLoader.loadSide(
      read: (type, {required lastMsgSeq, lastMsgID, lastMsg}) {
        calls.add(type);
        return type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG
            ? cloud.future
            : local.future;
      },
      isGroup: false,
      newer: false,
      targetSeq: 0,
      targetMsgID: 'target',
      targetMessage: null,
    ).then((value) {
      result = value;
      completed = true;
    });
    await tester.pump(const Duration(seconds: 4));
    expect(calls.length, 2);
    await tester.pump(const Duration(seconds: 2));
    await task;
    expect(completed, isTrue);
    expect(result, isNull);
    cloud.complete(V2TimMessageListResult(messageList: [], isFinished: true));
    local.complete(null);
    await tester.pump();
    expect(result, isNull);
  });

  test('far group jump requests both sides at the target sequence', () async {
    final calls = <HistoryMsgGetTypeEnum>[];
    for (final newer in [false, true]) {
      final result = await MessageHistoryAroundLoader.loadSide(
        read: (type, {required lastMsgSeq, lastMsgID, lastMsg}) async {
          calls.add(type);
          expect(lastMsgSeq, 850000);
          expect(lastMsgID, isNull);
          expect(lastMsg, isNull);
          return V2TimMessageListResult(messageList: [], isFinished: true);
        },
        isGroup: true,
        newer: newer,
        targetSeq: 850000,
        targetMsgID: 'target',
        targetMessage: null,
      );
      expect(result!.isFinished, isTrue);
    }
    expect(calls, [
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
    ]);
  });

  test('C2C keeps its message cursor even when search returns a seq', () async {
    // fromJson avoids constructing a native message handle in this unit test.
    final target = V2TimMessage.fromJson(<String, dynamic>{
      'message_risk_type_identified': 0,
      'message_msg_id': 'c2c-target',
      'message_seq': 1234,
    });
    for (final newer in [false, true]) {
      var count = 0;
      await MessageHistoryAroundLoader.loadSide(
        read: (type, {required lastMsgSeq, lastMsgID, lastMsg}) async {
          count++;
          expect(lastMsgSeq, -1);
          expect(lastMsgID, 'c2c-target');
          expect(lastMsg, same(target));
          return V2TimMessageListResult(messageList: [], isFinished: true);
        },
        isGroup: false,
        newer: newer,
        targetSeq: 1234,
        targetMsgID: 'c2c-target',
        targetMessage: target,
      );
      expect(count, 1);
    }
  });

  test('cloud failure retries only the same SDK-local anchor', () async {
    final calls = <HistoryMsgGetTypeEnum>[];
    final result = await MessageHistoryAroundLoader.loadSide(
      read: (type, {required lastMsgSeq, lastMsgID, lastMsg}) async {
        calls.add(type);
        expect(lastMsgSeq, 456);
        return null;
      },
      isGroup: true,
      newer: true,
      targetSeq: 456,
      targetMsgID: null,
      targetMessage: null,
    );
    expect(result, isNull);
    expect(calls, [
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG,
    ]);
  });

  test('invalid C2C cursor cannot silently read the latest page', () async {
    final result = await MessageHistoryAroundLoader.loadSide(
      read: (type, {required lastMsgSeq, lastMsgID, lastMsg}) async {
        fail('SDK must not receive an unanchored search request');
      },
      isGroup: false,
      newer: false,
      targetSeq: 456,
      targetMsgID: null,
      targetMessage: null,
    );
    expect(result, isNull);
  });

  test('nonempty SDK pages retain independent pagination boundaries', () async {
    final target = V2TimMessage.fromJson(<String, dynamic>{
      'message_risk_type_identified': 0,
      'message_msg_id': 'target',
    });
    for (final newer in [false, true]) {
      var calls = 0;
      final result = await MessageHistoryAroundLoader.loadSide(
        read: (type, {required lastMsgSeq, lastMsgID, lastMsg}) async {
          calls++;
          return V2TimMessageListResult(
            messageList: [target],
            isFinished: !newer,
          );
        },
        isGroup: true,
        newer: newer,
        targetSeq: 456,
        targetMsgID: 'target',
        targetMessage: target,
      );
      expect(calls, 1);
      expect(result!.messageList, [target]);
      expect(result.isFinished, !newer);
    }
  });

  test('list jump opens a target window and never chases older pages', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final start = source.indexOf('  _onScrollToIndex(V2TimMessage targetMsg)');
    final end = source.indexOf('  Future<bool> _onScrollToIndexBySeq', start);
    final jump = source.substring(start, end);
    expect(jump, contains('loadListForSpecificMessage('));
    expect(jump, isNot(contains('widget.onLoadMore(')));
    expect(source, contains('visible: !_initialSearchJumpPending &&'));
    final newerStart = source.indexOf('  Future<void> _loadLatest(');
    final newerEnd = source.indexOf(
      '  bool _renderObjectNeedsLayout',
      newerStart,
    );
    final newer = source.substring(newerStart, newerEnd);
    expect(newer, contains('lastMsg: anchor.message'));
    expect(newer, isNot(contains('minScrollExtent')));
    expect(newer, isNot(contains('drainRound')));
  });
}
