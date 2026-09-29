import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_continuity.dart';

void main() {
  group('HistoryPaginationContinuity.canPrependNewerBatch', () {
    test('empty incoming → true', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 100, timestamp: 1)],
          incomingNewerNewestFirst: const [],
        ),
        isTrue,
      );
    });

    test('empty existing → true', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: const [],
          incomingNewerNewestFirst: [(seq: 101, timestamp: 2)],
        ),
        isTrue,
      );
    });

    test('contiguous group seqs (newest 100, incoming 102..101) → true', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 100, timestamp: 10)],
          incomingNewerNewestFirst: [
            (seq: 102, timestamp: 12),
            (seq: 101, timestamp: 11),
          ],
        ),
        isTrue,
      );
    });

    test(
        'group seq gap (existing 100, incoming starts at 150) → true '
        '(trust SDK lastMsg cursor, dedupe handles overlap)', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 100, timestamp: 10)],
          incomingNewerNewestFirst: [
            (seq: 152, timestamp: 50),
            (seq: 150, timestamp: 40),
          ],
        ),
        isTrue,
      );
    });

    test('overlap at edge seq → true', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 100, timestamp: 10)],
          incomingNewerNewestFirst: [
            (seq: 101, timestamp: 11),
            (seq: 100, timestamp: 10),
          ],
        ),
        isTrue,
      );
    });

    test(
        'C2C per-sender seq not contiguous but time direction correct → true '
        '(C2C seq has no global continuity)', () {
      // C2C: existing newest is from sender B (seq=3), incoming oldest is
      // from sender A (seq=50). Seq is per-sender, not comparable. But
      // incoming timestamp >= existing timestamp, so direction is correct.
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 3, timestamp: 1000)],
          incomingNewerNewestFirst: [
            (seq: 52, timestamp: 1050),
            (seq: 50, timestamp: 1030),
          ],
        ),
        isTrue,
      );
    });

    test(
        'C2C large time gap but direction correct → true '
        '(no 120s time window check, trust SDK lastMsg)', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: null, timestamp: 1000)],
          incomingNewerNewestFirst: [
            (seq: null, timestamp: 5000),
            (seq: null, timestamp: 4000),
          ],
        ),
        isTrue,
      );
    });

    test('incoming older than existing (direction error) → false', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 100, timestamp: 1000)],
          incomingNewerNewestFirst: [
            (seq: 50, timestamp: 500),
            (seq: 49, timestamp: 400),
          ],
        ),
        isFalse,
      );
    });

    test('C2C incoming older → false (direction error)', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: null, timestamp: 1000)],
          incomingNewerNewestFirst: [
            (seq: null, timestamp: 900),
            (seq: null, timestamp: 800),
          ],
        ),
        isFalse,
      );
    });

    test('zero timestamps → true (no direction info, trust SDK)', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 100, timestamp: 0)],
          incomingNewerNewestFirst: [
            (seq: 200, timestamp: 0),
            (seq: 150, timestamp: 0),
          ],
        ),
        isTrue,
      );
    });

    test('equal timestamps → true (same second, allow merge)', () {
      expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 100, timestamp: 500)],
          incomingNewerNewestFirst: [
            (seq: 102, timestamp: 500),
            (seq: 101, timestamp: 500),
          ],
        ),
        isTrue,
      );
    });
  });

  group('HistoryPaginationContinuity.canAppendOlderBatch', () {
    List<({int? seq, String? msgID})> rows(List<int> seqs) => [
          for (final seq in seqs) (seq: seq, msgID: 'm$seq'),
        ];

    test('abut: incomingMaxSeq == existingMinSeq - 1 → merge', () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: rows([1002, 1001, 1000]),
        incomingOlderNewestFirst: rows([999, 998, 997]),
        isGroup: true,
        olderCloudBacked: false,
      );
      expect(decision.canMerge, isTrue);
      expect(decision.reason, 'abut_seq');
    });

    test('msgID overlap → merge', () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: [
          (seq: 1000, msgID: 'shared'),
          (seq: 999, msgID: 'm999'),
        ],
        incomingOlderNewestFirst: [
          (seq: 850, msgID: 'shared'),
          (seq: 849, msgID: 'm849'),
        ],
        isGroup: true,
        olderCloudBacked: false,
      );
      expect(decision.canMerge, isTrue);
      expect(decision.overlapByMsgId, isTrue);
    });

    test('seq intersection → merge', () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: rows([1000, 999]),
        incomingOlderNewestFirst: rows([1001, 1000, 990]),
        isGroup: true,
        olderCloudBacked: false,
      );
      expect(decision.canMerge, isTrue);
      expect(decision.overlapBySeq, isTrue);
    });

    test('incomingMaxSeq=850 existingMinSeq=1000 → reject closed gap [851,999]',
        () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: rows([1002, 1001, 1000]),
        incomingOlderNewestFirst: rows([850, 849, 848]),
        isGroup: true,
        olderCloudBacked: false,
      );
      expect(decision.canMerge, isFalse);
      expect(decision.missingLowerSeq, 851);
      expect(decision.missingUpperSeq, 999);
      expect(decision.olderAnchorSeq, 850);
      expect(decision.newerAnchorSeq, 1000);
      expect(decision.hasClosedGap, isTrue);
    });

    test('cloud deleted-seq gap <= 5 → merge', () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: rows([1000]),
        incomingOlderNewestFirst: rows([994]),
        isGroup: true,
        olderCloudBacked: true,
      );
      expect(decision.canMerge, isTrue);
      expect(decision.reason, 'cloud_deleted_seq_relax');
    });

    test('cloud deleted-seq gap > 5 → reject', () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: rows([1000]),
        incomingOlderNewestFirst: rows([993]),
        isGroup: true,
        olderCloudBacked: true,
      );
      expect(decision.canMerge, isFalse);
      expect(decision.missingLowerSeq, 994);
      expect(decision.missingUpperSeq, 999);
    });

    test('LOCAL any jump → reject even gap=1 would need abut', () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: rows([1000]),
        incomingOlderNewestFirst: rows([998]),
        isGroup: true,
        olderCloudBacked: false,
      );
      expect(decision.canMerge, isFalse);
      expect(decision.missingLowerSeq, 999);
      expect(decision.missingUpperSeq, 999);
    });

    test('long quiet time with contiguous seq still merges', () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: [(seq: 1000, msgID: 'm1000')],
        incomingOlderNewestFirst: [(seq: 999, msgID: 'm999')],
        isGroup: true,
        olderCloudBacked: false,
      );
      expect(decision.canMerge, isTrue);
      expect(decision.reason, 'abut_seq');
    });

    test('incomingMaxSeq >= existingMinSeq alone without intersection → reject',
        () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: rows([1000, 999]),
        incomingOlderNewestFirst: rows([1005, 1004, 1003]),
        isGroup: true,
        olderCloudBacked: true,
      );
      expect(decision.canMerge, isFalse);
      expect(decision.reason, 'seq_no_intersection');
      expect(decision.hasClosedGap, isFalse);
    });

    test('C2C → merge without group seq gate', () {
      final decision = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: rows([3]),
        incomingOlderNewestFirst: rows([50]),
        isGroup: false,
        olderCloudBacked: false,
      );
      expect(decision.canMerge, isTrue);
      expect(decision.reason, 'c2c_trust_sdk');
    });
  });
}
