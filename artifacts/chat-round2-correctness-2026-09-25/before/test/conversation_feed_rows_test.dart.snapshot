import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_rows.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart'
    show GroupSystemNoticeItem, GroupSystemNoticeType;

void main() {
  group('patchVisibleConversationsInSourceOrder', () {
    test('refreshes row references in committed source order', () {
      final oldA = V2TimConversation(conversationID: 'c2c_a');
      final oldB = V2TimConversation(conversationID: 'c2c_b');
      final nextA = V2TimConversation(conversationID: 'c2c_a');
      final nextB = V2TimConversation(conversationID: 'c2c_b');

      final result = patchVisibleConversationsInSourceOrder(
        current: <V2TimConversation>[nextB, nextA],
        cachedVisibleIds: <String>{oldA.conversationID, oldB.conversationID},
        cachedVisibleCount: 2,
        cachedSourceLength: 2,
        cachedSourceIds: {'c2c_a', 'c2c_b'},
      );

      expect(result, isNotNull);
      expect(result, <V2TimConversation>[nextB, nextA]);
    });

    test('falls back when source membership length changes', () {
      final result = patchVisibleConversationsInSourceOrder(
        current: <V2TimConversation>[
          V2TimConversation(conversationID: 'c2c_a'),
          V2TimConversation(conversationID: 'c2c_b'),
        ],
        cachedVisibleIds: <String>{'c2c_a'},
        cachedVisibleCount: 1,
        cachedSourceLength: 1,
        cachedSourceIds: {'c2c_a'},
      );

      expect(result, isNull);
    });

    test('falls back when a cached visible id disappeared', () {
      final result = patchVisibleConversationsInSourceOrder(
        current: <V2TimConversation>[
          V2TimConversation(conversationID: 'c2c_a'),
          V2TimConversation(conversationID: 'group_x'),
        ],
        cachedVisibleIds: <String>{'c2c_a', 'c2c_b'},
        cachedVisibleCount: 2,
        cachedSourceLength: 2,
        cachedSourceIds: {'c2c_a', 'c2c_b'},
      );

      expect(result, isNull);
    });

    test('equal-length replacement cannot preserve a stale empty group view',
        () {
      expect(
        patchVisibleConversationsInSourceOrder(
          current: [V2TimConversation(conversationID: 'group_joined')],
          cachedVisibleIds: {},
          cachedVisibleCount: 0,
          cachedSourceLength: 1,
          cachedSourceIds: {'c2c_old'},
        ),
        isNull,
      );
    });

    test('replacement of a hidden row must rerun membership filters', () {
      expect(
        patchVisibleConversationsInSourceOrder(
          current: [
            V2TimConversation(conversationID: 'group_kept'),
            V2TimConversation(conversationID: 'group_new'),
          ],
          cachedVisibleIds: {'group_kept'},
          cachedVisibleCount: 1,
          cachedSourceLength: 2,
          cachedSourceIds: {'group_kept', 'c2c_old'},
        ),
        isNull,
      );
    });
  });

  group('appendVisibleConversationsIfSourceGrewAtTail', () {
    test('appends predicate-visible suffix when prefix ids are unchanged', () {
      final nextA = V2TimConversation(conversationID: 'c2c_a');
      final nextB = V2TimConversation(conversationID: 'c2c_b');
      final nextC = V2TimConversation(conversationID: 'c2c_c');
      final nextD = V2TimConversation(conversationID: 'c2c_d');
      final result = appendVisibleConversationsIfSourceGrewAtTail(
        current: <V2TimConversation>[nextA, nextB, nextC, nextD],
        cachedVisibleIds: <String>{'c2c_a', 'c2c_b'},
        cachedVisibleCount: 2,
        cachedSourceLength: 2,
        cachedSourceIds: <String>{'c2c_a', 'c2c_b'},
        suffixVisiblePredicate: (row) => row.conversationID != 'c2c_d',
      );

      expect(result, isNotNull);
      expect(
        result!.map((row) => row.conversationID).toList(),
        ['c2c_a', 'c2c_b', 'c2c_c'],
      );
    });

    test('falls back when prefix membership is broken', () {
      expect(
        appendVisibleConversationsIfSourceGrewAtTail(
          current: <V2TimConversation>[
            V2TimConversation(conversationID: 'c2c_x'),
            V2TimConversation(conversationID: 'c2c_b'),
            V2TimConversation(conversationID: 'c2c_c'),
          ],
          cachedVisibleIds: <String>{'c2c_a'},
          cachedVisibleCount: 1,
          cachedSourceLength: 2,
          cachedSourceIds: <String>{'c2c_a', 'c2c_b'},
          suffixVisiblePredicate: (_) => true,
        ),
        isNull,
      );
    });

    test('falls back when a row is inserted into the prefix', () {
      expect(
        appendVisibleConversationsIfSourceGrewAtTail(
          current: <V2TimConversation>[
            V2TimConversation(conversationID: 'c2c_a'),
            V2TimConversation(conversationID: 'c2c_mid'),
            V2TimConversation(conversationID: 'c2c_b'),
          ],
          cachedVisibleIds: <String>{'c2c_a', 'c2c_b'},
          cachedVisibleCount: 2,
          cachedSourceLength: 2,
          cachedSourceIds: <String>{'c2c_a', 'c2c_b'},
          suffixVisiblePredicate: (_) => true,
        ),
        isNull,
      );
    });
  });

  test('buildConversationFeedRows inserts archived entry at top', () {
    final rows = buildConversationFeedRows(
      conversations: [
        V2TimConversation(
          conversationID: 'c2c_a',
          type: 1,
          userID: 'a',
          unreadCount: 1,
        ),
      ],
      includeArchivedEntry: true,
      includeGroupNoticeEntry: false,
      applications: const [],
      notices: const [],
      conversationTimestampMs: (_) => 100,
    );

    expect(rows.first.kind, ConversationFeedRowKind.archived);
    expect(rows.length, 2);
  });

  test(
    'buildConversationFeedRows includes archived entry when only group notice visible',
    () {
      final rows = buildConversationFeedRows(
        conversations: const [],
        includeArchivedEntry: true,
        includeGroupNoticeEntry: true,
        applications: const [],
        notices: [
          GroupSystemNoticeItem(
            id: 'n1',
            groupID: 'g1',
            groupName: 'Group',
            groupFaceUrl: '',
            type: GroupSystemNoticeType.grantAdministrator,
            operatorUserID: 'u1',
            operatorName: 'User',
            targetUserID: 'u2',
            targetName: 'Target',
            timestamp: 200,
          ),
        ],
        conversationTimestampMs: (_) => 0,
      );

      expect(rows.length, 2);
      expect(rows.first.kind, ConversationFeedRowKind.archived);
      expect(rows[1].kind, ConversationFeedRowKind.groupNotice);
    },
  );

  test('buildConversationFeedRows hides dismissed group notice entry', () {
    final rows = buildConversationFeedRows(
      conversations: const [],
      includeArchivedEntry: false,
      includeGroupNoticeEntry: true,
      applications: const [],
      notices: [
        GroupSystemNoticeItem(
          id: 'n1',
          groupID: 'g1',
          groupName: 'Group',
          groupFaceUrl: '',
          type: GroupSystemNoticeType.grantAdministrator,
          operatorUserID: 'u1',
          operatorName: 'User',
          targetUserID: 'u2',
          targetName: 'Target',
          timestamp: 200,
        ),
      ],
      conversationTimestampMs: (_) => 0,
      groupNoticeDismissWatermarkMs: 200000,
    );

    expect(rows, isEmpty);
  });

  test('buildConversationFeedRows pins group notice before non-pinned chats',
      () {
    final rows = buildConversationFeedRows(
      conversations: [
        V2TimConversation(
          conversationID: 'group_b',
          type: 2,
          groupID: 'b',
          isPinned: true,
        ),
        V2TimConversation(
          conversationID: 'group_a',
          type: 2,
          groupID: 'a',
          isPinned: false,
        ),
      ],
      includeArchivedEntry: false,
      includeGroupNoticeEntry: true,
      applications: const [],
      notices: [
        GroupSystemNoticeItem(
          id: 'n1',
          groupID: 'g1',
          groupName: 'Group',
          groupFaceUrl: '',
          type: GroupSystemNoticeType.grantAdministrator,
          operatorUserID: 'u1',
          operatorName: 'User',
          targetUserID: 'u2',
          targetName: 'Target',
          timestamp: 100,
        ),
      ],
      conversationTimestampMs: (_) => 300,
      groupNoticePinned: true,
    );

    expect(rows[0].kind, ConversationFeedRowKind.groupNotice);
    expect(rows[1].conversation?.conversationID, 'group_b');
    expect(rows[2].conversation?.conversationID, 'group_a');
  });

  test('buildConversationFeedRows keeps archived above pinned group notice',
      () {
    final rows = buildConversationFeedRows(
      conversations: [
        V2TimConversation(
          conversationID: 'group_a',
          type: 2,
          groupID: 'a',
        ),
      ],
      includeArchivedEntry: true,
      includeGroupNoticeEntry: true,
      applications: const [],
      notices: [
        GroupSystemNoticeItem(
          id: 'n1',
          groupID: 'g1',
          groupName: 'Group',
          groupFaceUrl: '',
          type: GroupSystemNoticeType.grantAdministrator,
          operatorUserID: 'u1',
          operatorName: 'User',
          targetUserID: 'u2',
          targetName: 'Target',
          timestamp: 100,
        ),
      ],
      conversationTimestampMs: (_) => 300,
      groupNoticePinned: true,
    );

    expect(rows[0].kind, ConversationFeedRowKind.archived);
    expect(rows[1].kind, ConversationFeedRowKind.groupNotice);
  });

  test('patchConversationFeedRowsById replaces conversation refs by id', () {
    final cached = buildConversationFeedRows(
      conversations: [
        V2TimConversation(
          conversationID: 'c2c_a',
          type: 1,
          userID: 'a',
          unreadCount: 1,
          showName: 'Old',
        ),
      ],
      includeArchivedEntry: true,
      includeGroupNoticeEntry: false,
      applications: const [],
      notices: const [],
      conversationTimestampMs: (_) => 100,
    );
    final patched = patchConversationFeedRowsById(
      cached: cached,
      visible: [
        V2TimConversation(
          conversationID: 'c2c_a',
          type: 1,
          userID: 'a',
          unreadCount: 9,
          showName: 'New',
        ),
      ],
      conversationTimestampMs: (_) => 200,
    );

    expect(patched.first.kind, ConversationFeedRowKind.archived);
    expect(patched[1].kind, ConversationFeedRowKind.conversation);
    expect(patched[1].conversation?.unreadCount, 9);
    expect(patched[1].conversation?.showName, 'New');
    expect(patched[1].timestampMs, 200);
  });

  test('patchConversationFeedRowsById reuses the list on a true no-op', () {
    final conversation = V2TimConversation(conversationID: 'c2c_same');
    final cached = <ConversationFeedRow>[
      ConversationFeedRow.conversation(conversation, 100),
    ];

    final patched = patchConversationFeedRowsById(
      cached: cached,
      visible: <V2TimConversation>[conversation],
      conversationTimestampMs: (_) => 100,
    );

    expect(identical(patched, cached), isTrue);
  });

  test('patchConversationFeedRowsById keeps unchanged row objects', () {
    final unchanged = V2TimConversation(conversationID: 'c2c_same');
    final previousChanged = V2TimConversation(conversationID: 'c2c_changed');
    final nextChanged = V2TimConversation(conversationID: 'c2c_changed');
    final unchangedRow = ConversationFeedRow.conversation(unchanged, 100);
    final cached = <ConversationFeedRow>[
      unchangedRow,
      ConversationFeedRow.conversation(previousChanged, 90),
    ];

    final patched = patchConversationFeedRowsById(
      cached: cached,
      visible: <V2TimConversation>[unchanged, nextChanged],
      conversationTimestampMs: (row) => identical(row, nextChanged) ? 110 : 100,
    );

    expect(identical(patched, cached), isFalse);
    expect(identical(patched.first, unchangedRow), isTrue);
    expect(identical(patched.last.conversation, nextChanged), isTrue);
    expect(patched.last.timestampMs, 110);
  });

  test('computeGroupNoticeInsertTypeIndex places notice among non-pinned', () {
    expect(
      computeGroupNoticeInsertTypeIndex(
        groupNoticePinned: false,
        total: 5,
        pinnedCount: 2,
        nonPinnedNewerThanNoticeCount: 1,
      ),
      3,
    );
    expect(
      computeGroupNoticeInsertTypeIndex(
        groupNoticePinned: false,
        total: 5,
        pinnedCount: 2,
        nonPinnedNewerThanNoticeCount: 0,
      ),
      2,
    );
    expect(
      computeGroupNoticeInsertTypeIndex(
        groupNoticePinned: false,
        total: 5,
        pinnedCount: 2,
        nonPinnedNewerThanNoticeCount: 3,
      ),
      5,
    );
    expect(
      computeGroupNoticeInsertTypeIndex(
        groupNoticePinned: true,
        total: 5,
        pinnedCount: 2,
        nonPinnedNewerThanNoticeCount: 1,
      ),
      0,
    );
  });

  test('virtualFeed index mapping offsets around inline notice', () {
    expect(
      virtualFeedListIndexForTypeIndex(
        typeIndex: 2,
        headerCount: 1,
        noticeInsertAt: 2,
      ),
      4,
    );
    expect(
      virtualFeedListIndexForTypeIndex(
        typeIndex: 1,
        headerCount: 1,
        noticeInsertAt: 2,
      ),
      2,
    );
    expect(
      virtualFeedTypeIndexForBodyIndex(
        bodyIndex: 2,
        noticeInsertAt: 2,
        total: 5,
      ),
      isNull,
    );
    expect(
      virtualFeedTypeIndexForBodyIndex(
        bodyIndex: 3,
        noticeInsertAt: 2,
        total: 5,
      ),
      2,
    );
    expect(
      virtualFeedBodyIndexIsGroupNotice(bodyIndex: 2, noticeInsertAt: 2),
      isTrue,
    );
  });

  test('buildConversationFeedRows inserts notice by time among chats', () {
    final rows = buildConversationFeedRows(
      conversations: [
        V2TimConversation(
          conversationID: 'group_new',
          type: 2,
          groupID: 'new',
          isPinned: false,
        ),
        V2TimConversation(
          conversationID: 'group_old',
          type: 2,
          groupID: 'old',
          isPinned: false,
        ),
      ],
      includeArchivedEntry: false,
      includeGroupNoticeEntry: true,
      applications: const [],
      notices: [
        GroupSystemNoticeItem(
          id: 'n1',
          groupID: 'g1',
          groupName: 'Group',
          groupFaceUrl: '',
          type: GroupSystemNoticeType.grantAdministrator,
          operatorUserID: 'u1',
          operatorName: 'User',
          targetUserID: 'u2',
          targetName: 'Target',
          // 秒级 → normalize 成 200_000 ms，与会话 active_time 对齐
          timestamp: 200,
        ),
      ],
      conversationTimestampMs: (c) {
        if (c.conversationID == 'group_new') return 300000;
        return 100000;
      },
    );

    expect(rows[0].conversation?.conversationID, 'group_new');
    expect(rows[1].kind, ConversationFeedRowKind.groupNotice);
    expect(rows[2].conversation?.conversationID, 'group_old');
  });

  group('groupNoticeFeedSignature', () {
    GroupSystemNoticeItem notice({
      required String id,
      required int timestamp,
    }) {
      return GroupSystemNoticeItem(
        id: id,
        groupID: 'g1',
        groupName: 'Group',
        groupFaceUrl: '',
        type: GroupSystemNoticeType.grantAdministrator,
        operatorUserID: 'u1',
        operatorName: 'User',
        targetUserID: 'u2',
        targetName: 'Target',
        timestamp: timestamp,
      );
    }

    test('unchanged inputs keep the same signature', () {
      final notices = [notice(id: 'n1', timestamp: 200)];
      final a = groupNoticeFeedSignature(
        applications: const [],
        notices: notices,
        includeGroupNoticeEntry: true,
        groupNoticePinned: false,
        dismissWatermarkMs: 0,
      );
      final b = groupNoticeFeedSignature(
        applications: const [],
        notices: notices,
        includeGroupNoticeEntry: true,
        groupNoticePinned: false,
        dismissWatermarkMs: 0,
      );
      expect(a, b);
    });

    test('new notice changes signature', () {
      final before = groupNoticeFeedSignature(
        applications: const [],
        notices: [notice(id: 'n1', timestamp: 200)],
        includeGroupNoticeEntry: true,
        groupNoticePinned: false,
        dismissWatermarkMs: 0,
      );
      final after = groupNoticeFeedSignature(
        applications: const [],
        notices: [
          notice(id: 'n1', timestamp: 200),
          notice(id: 'n2', timestamp: 500),
        ],
        includeGroupNoticeEntry: true,
        groupNoticePinned: false,
        dismissWatermarkMs: 0,
      );
      expect(after, isNot(before));
    });

    test('dismiss watermark change alters signature', () {
      final notices = [notice(id: 'n1', timestamp: 200)];
      final before = groupNoticeFeedSignature(
        applications: const [],
        notices: notices,
        includeGroupNoticeEntry: true,
        groupNoticePinned: false,
        dismissWatermarkMs: 0,
      );
      final after = groupNoticeFeedSignature(
        applications: const [],
        notices: notices,
        includeGroupNoticeEntry: true,
        groupNoticePinned: false,
        dismissWatermarkMs: 100,
      );
      expect(after, isNot(before));
    });

    test('pinned flag change alters signature', () {
      final notices = [notice(id: 'n1', timestamp: 200)];
      final before = groupNoticeFeedSignature(
        applications: const [],
        notices: notices,
        includeGroupNoticeEntry: true,
        groupNoticePinned: false,
        dismissWatermarkMs: 0,
      );
      final after = groupNoticeFeedSignature(
        applications: const [],
        notices: notices,
        includeGroupNoticeEntry: true,
        groupNoticePinned: true,
        dismissWatermarkMs: 0,
      );
      expect(after, isNot(before));
    });
  });
}
