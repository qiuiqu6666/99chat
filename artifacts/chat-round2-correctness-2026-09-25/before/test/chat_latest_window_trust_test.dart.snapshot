import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_trust.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

V2TimMessage _msg(
  int seq, {
  String? msgID,
  bool isSelf = false,
  int status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
  String? localCustomData,
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': msgID ?? 'm$seq',
    'message_server_time': 1700000000 + seq,
    'message_risk_type_identified': 0,
  })
    ..groupID = 'g1'
    ..seq = '$seq'
    ..isSelf = isSelf
    ..elemType = 1
    ..localCustomData = localCustomData;
  message.status = status;
  return message;
}

List<V2TimMessage> _window(int newestSeq, int count) => List.generate(
      count,
      (index) => _msg(newestSeq - index),
    );

void main() {
  group('latestEdgeMatchesPreview validates the RAW window', () {
    test('preview inside raw window matches', () {
      final raw = _window(1500, 20);
      final result = latestEdgeMatchesPreview(
        preview: _msg(1500),
        rawWindow: raw,
      );
      expect(result.matched, isTrue);
      expect(result.previewUnverifiable, isFalse);
    });

    test('stale local page behind the preview is rejected', () {
      // The blocking scenario: SDK degraded to local 1001..1020, preview 1500.
      final raw = _window(1020, 20);
      final result = latestEdgeMatchesPreview(
        preview: _msg(1500),
        rawWindow: raw,
      );
      expect(result.matched, isFalse);
    });

    test('splicing the preview into the window must not be how it passes', () {
      // Even if a caller wrongly appended the preview, the RAW list handed to
      // the validator is what decides; this documents the contract.
      final raw = _window(1020, 20);
      final spliced = <V2TimMessage>[_msg(1500), ...raw];
      expect(latestEdgeMatchesPreview(preview: _msg(1500), rawWindow: raw)
          .matched, isFalse);
      // A spliced list would pass, which is why validation runs before splice.
      expect(latestEdgeMatchesPreview(preview: _msg(1500), rawWindow: spliced)
          .matched, isTrue);
    });

    test('raw newer than preview (preview lagging) matches', () {
      final raw = _window(1600, 20);
      final result = latestEdgeMatchesPreview(
        preview: _msg(1500),
        rawWindow: raw,
      );
      expect(result.matched, isTrue);
    });

    test('SENDING self rows cannot be the confirmed latest edge', () {
      final raw = <V2TimMessage>[
        _msg(1500, isSelf: true, status: MessageStatus.V2TIM_MSG_STATUS_SENDING),
        ..._window(1020, 20),
      ];
      final result = latestEdgeMatchesPreview(
        preview: _msg(1500),
        rawWindow: raw,
      );
      // Preview 1500 is confirmed; the raw confirmed edge is 1020 → mismatch.
      expect(result.matched, isFalse);
    });

    test('synthetic local rows and local group tips are ignored as edge', () {
      final raw = <V2TimMessage>[
        _msg(9999, msgID: 'local_gt_1'),
        _msg(9998, localCustomData: '{"localGroupTips":true}'),
        ..._window(1020, 20),
      ];
      expect(rawConfirmedLatest(raw)?.seq, '1020');
      expect(
        latestEdgeMatchesPreview(preview: _msg(1500), rawWindow: raw).matched,
        isFalse,
      );
    });

    test('unconfirmed self preview is previewUnverifiable, not a match proof',
        () {
      final raw = _window(1020, 20);
      final result = latestEdgeMatchesPreview(
        preview: _msg(1500,
            isSelf: true, status: MessageStatus.V2TIM_MSG_STATUS_SENDING),
        rawWindow: raw,
      );
      expect(result.matched, isTrue);
      expect(result.previewUnverifiable, isTrue);
    });

    test('empty raw window or missing preview never matches', () {
      expect(
        latestEdgeMatchesPreview(preview: _msg(1), rawWindow: const [])
            .matched,
        isFalse,
      );
      expect(
        latestEdgeMatchesPreview(preview: null, rawWindow: _window(10, 5))
            .matched,
        isFalse,
      );
    });
  });

  group('windowIsSelfContiguous', () {
    test('group page with a seq hole is not contiguous', () {
      final raw = <V2TimMessage>[..._window(1500, 5), ..._window(1400, 5)];
      expect(windowIsSelfContiguous(rawWindow: raw, isGroup: true), isFalse);
    });

    test('group page without holes is contiguous regardless of order', () {
      final raw = _window(1500, 20)..shuffle();
      expect(windowIsSelfContiguous(rawWindow: raw, isGroup: true), isTrue);
    });

    test('single C2C page is contiguous by construction, empty is not', () {
      expect(windowIsSelfContiguous(rawWindow: _window(50, 3), isGroup: false),
          isTrue);
      expect(windowIsSelfContiguous(rawWindow: const [], isGroup: false),
          isFalse);
    });
  });

  group('freshnessProven', () {
    test('requires transport proof, online, ready and no sync pending', () {
      expect(
        freshnessProven(
          cloudTransportConfirmed: true,
          networkOnline: true,
          transportReady: true,
          serverSyncPendingBefore: false,
          serverSyncPendingAfter: false,
        ),
        isTrue,
      );
      for (final broken in [
        () => freshnessProven(
              cloudTransportConfirmed: false,
              networkOnline: true,
              transportReady: true,
              serverSyncPendingBefore: false,
              serverSyncPendingAfter: false,
            ),
        () => freshnessProven(
              cloudTransportConfirmed: true,
              networkOnline: false,
              transportReady: true,
              serverSyncPendingBefore: false,
              serverSyncPendingAfter: false,
            ),
        () => freshnessProven(
              cloudTransportConfirmed: true,
              networkOnline: true,
              transportReady: false,
              serverSyncPendingBefore: false,
              serverSyncPendingAfter: false,
            ),
        () => freshnessProven(
              cloudTransportConfirmed: true,
              networkOnline: true,
              transportReady: true,
              serverSyncPendingBefore: true,
              serverSyncPendingAfter: false,
            ),
        () => freshnessProven(
              cloudTransportConfirmed: true,
              networkOnline: true,
              transportReady: true,
              serverSyncPendingBefore: false,
              serverSyncPendingAfter: true,
            ),
      ]) {
        expect(broken(), isFalse);
      }
    });
  });

  group('ChatLatestWindowTrust.needsLatestWindowReset', () {
    setUp(ChatLatestWindowTrust.instance.clear);

    test('epoch 0 (never reconnected) needs no reset', () {
      expect(
        ChatLatestWindowTrust.instance.needsLatestWindowReset(
          conversationKey: 'group_g1',
          currentEpoch: 0,
        ),
        isFalse,
      );
    });

    test('untrusted or stale-epoch trust needs a reset', () {
      final trust = ChatLatestWindowTrust.instance;
      expect(
        trust.needsLatestWindowReset(conversationKey: 'c2c_u', currentEpoch: 1),
        isTrue,
      );
      trust.markTrusted('c2c_u', 1);
      expect(
        trust.needsLatestWindowReset(conversationKey: 'c2c_u', currentEpoch: 1),
        isFalse,
      );
      // A real reconnect happened: epoch 2 invalidates the epoch-1 proof.
      expect(
        trust.needsLatestWindowReset(conversationKey: 'c2c_u', currentEpoch: 2),
        isTrue,
      );
    });

    test('a provisional install always keeps the reset armed', () {
      final trust = ChatLatestWindowTrust.instance;
      trust.markTrusted('c2c_u', 3);
      expect(
        trust.needsLatestWindowReset(
          conversationKey: 'c2c_u',
          currentEpoch: 3,
          provisionalRegistered: true,
        ),
        isTrue,
      );
    });

    test('clear drops every trusted epoch', () {
      final trust = ChatLatestWindowTrust.instance;
      trust.markTrusted('c2c_u', 1);
      trust.clear();
      expect(trust.trustedEpochFor('c2c_u'), isNull);
    });
  });
}
