// P0-2: aggregate 滑动窗口去重测试。
//
// 真实场景：tab_store 与 chat_session_controller 可能对同一条 commit
// 各自发出一份 (oldNotifiable, newNotifiable) 的 delta。若不去重，
// 聚合值会被双倍累加（observed: store=1357, ui=2714）。
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_unread_utils.dart';

void main() {
  tearDown(() {
    ConversationUnreadAggregate.instance.resetForTest();
  });

  group('applyNotifiableDeltas idempotency (P0-2)', () {
    test('same delta applied twice does not double-count', () {
      final agg = ConversationUnreadAggregate.instance;
      const delta = ConversationUnreadDelta(
        isGroup: true,
        oldNotifiable: 0,
        newNotifiable: 5,
        conversationKey: 'g1',
      );
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[delta]);
      final afterFirst = agg.groupNotifiableUnreadSum;
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[delta]);
      final afterSecond = agg.groupNotifiableUnreadSum;
      expect(afterFirst, 5);
      expect(afterSecond, 5, reason: 'duplicate delta must not double-count');
    });

    test('different conversations with same old/new still both apply', () {
      final agg = ConversationUnreadAggregate.instance;
      const deltaA = ConversationUnreadDelta(
        isGroup: true,
        oldNotifiable: 0,
        newNotifiable: 3,
        conversationKey: 'gA',
      );
      const deltaB = ConversationUnreadDelta(
        isGroup: true,
        oldNotifiable: 0,
        newNotifiable: 3,
        conversationKey: 'gB',
      );
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[deltaA]);
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[deltaB]);
      expect(agg.groupNotifiableUnreadSum, 6);
    });

    test('different old/new range is a different key — applies again', () {
      final agg = ConversationUnreadAggregate.instance;
      const first = ConversationUnreadDelta(
        isGroup: true,
        oldNotifiable: 0,
        newNotifiable: 5,
        conversationKey: 'g1',
      );
      const second = ConversationUnreadDelta(
        isGroup: true,
        oldNotifiable: 5,
        newNotifiable: 8,
        conversationKey: 'g1',
      );
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[first]);
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[second]);
      expect(agg.groupNotifiableUnreadSum, 8);
    });

    test('same transition applies again after the conversation was read', () {
      final agg = ConversationUnreadAggregate.instance;
      void apply(int oldValue, int newValue) {
        agg.applyNotifiableDeltas(<ConversationUnreadDelta>[
          ConversationUnreadDelta(
            isGroup: false,
            oldNotifiable: oldValue,
            newNotifiable: newValue,
            conversationKey: 'c2c_repeat',
          ),
        ]);
      }

      apply(0, 1);
      apply(1, 0);
      apply(0, 1);

      expect(agg.c2cNotifiableUnreadSum, 1,
          reason: 'a later 0 -> 1 is a new unread event, not a duplicate');
    });

    test('c2c deltas do not collide with group deltas', () {
      final agg = ConversationUnreadAggregate.instance;
      const c2cDelta = ConversationUnreadDelta(
        isGroup: false,
        oldNotifiable: 0,
        newNotifiable: 2,
        conversationKey: 'c1',
      );
      const groupDelta = ConversationUnreadDelta(
        isGroup: true,
        oldNotifiable: 0,
        newNotifiable: 2,
        conversationKey: 'g1',
      );
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[c2cDelta]);
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[groupDelta]);
      expect(agg.c2cNotifiableUnreadSum, 2);
      expect(agg.groupNotifiableUnreadSum, 2);
    });

    test(
        'sliding window evicts old keys — after 33rd new delta, the 1st '
        'becomes applicable again', () {
      final agg = ConversationUnreadAggregate.instance;
      // Window size is 32; submit 33 unique deltas then re-submit a key
      // matching the first delta — the first has been evicted from the
      // window, so the re-submit should now apply (delta=+1 → +1 to sum).
      final baseline = agg.groupNotifiableUnreadSum;
      final all = <ConversationUnreadDelta>[];
      for (var i = 0; i < 33; i++) {
        all.add(
          ConversationUnreadDelta(
            isGroup: true,
            oldNotifiable: 0,
            newNotifiable: i + 1,
            conversationKey: 'g$i',
          ),
        );
      }
      agg.applyNotifiableDeltas(all);
      final sumAfter33 = agg.groupNotifiableUnreadSum;
      // All 33 are unique keys so all apply; the sum increased by 1+2+...+33.
      expect(sumAfter33 - baseline, 561);

      // Re-submitting the first delta (g0: 0→1) — its key has been evicted
      // from the 32-slot window — should apply and add delta=+1 to sum.
      final first = ConversationUnreadDelta(
        isGroup: true,
        oldNotifiable: 0,
        newNotifiable: 1,
        conversationKey: 'g0_repeat',
      );
      agg.applyNotifiableDeltas(<ConversationUnreadDelta>[first]);
      expect(agg.groupNotifiableUnreadSum - sumAfter33, 1,
          reason: 'evicted key re-applies');
    });
  });
}
