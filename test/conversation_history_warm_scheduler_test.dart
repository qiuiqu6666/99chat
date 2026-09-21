import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_warm_scheduler.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';

/// 不构造 [V2TimMessage]（其构造会拉 native SDK）；空列表足以测 map key 淘汰。
void _seedEmptyWindow(TUIChatGlobalModel global, String conversationID) {
  global.setMessageList(conversationID, <V2TimMessage>[], replace: true);
}

void main() {
  group('ConversationHistoryWarmScheduler.selectWarmCandidates', () {
    V2TimConversation c2c({
      required String userId,
      int unread = 0,
      String? conversationID,
    }) {
      return V2TimConversation(
        conversationID: conversationID ?? 'c2c_$userId',
        userID: userId,
        type: 1,
        unreadCount: unread,
      );
    }

    V2TimConversation group({required String groupId, int unread = 0}) {
      return V2TimConversation(
        conversationID: 'group_$groupId',
        groupID: groupId,
        type: 2,
        unreadCount: unread,
      );
    }

    test('unread first then preserve relative order, capped at sdkLimit', () {
      final selected = ConversationHistoryWarmScheduler.selectWarmCandidates(
        conversations: <V2TimConversation>[
          c2c(userId: 'a'),
          c2c(userId: 'b', unread: 2),
          c2c(userId: 'c'),
          c2c(userId: 'd', unread: 1),
          c2c(userId: 'e'),
        ],
        archivedIDs: const <String>{},
        loginUserId: 'me',
        shouldShowConversation: (_) => true,
        sdkLimit: 3,
      );

      expect(selected.map((c) => c.userID).toList(), <String>['b', 'd', 'a']);
    });

    test('c2c ranks ahead of groups while unread stays first per type', () {
      final selected = ConversationHistoryWarmScheduler.selectWarmCandidates(
        conversations: <V2TimConversation>[
          c2c(userId: 'a'),
          group(groupId: '@TGS#_@TGS#cAAA', unread: 0),
          c2c(userId: 'b', unread: 1),
          group(groupId: '@TGS#_@TGS#cBBB', unread: 2),
          c2c(userId: 'c'),
        ],
        archivedIDs: const <String>{},
        loginUserId: 'me',
        shouldShowConversation: (_) => true,
        sdkLimit: 5,
      );

      expect(selected.map((c) => c.userID ?? c.groupID).toList(), <String>[
        'b',
        'a',
        'c',
        '@TGS#_@TGS#cBBB',
        '@TGS#_@TGS#cAAA',
      ]);
    });

    test('reserves two group slots after preparing six c2c first', () {
      final selected = ConversationHistoryWarmScheduler.selectWarmCandidates(
        conversations: <V2TimConversation>[
          c2c(userId: 'a'),
          group(groupId: 'g0'),
          c2c(userId: 'b', unread: 1),
          c2c(userId: 'c'),
          c2c(userId: 'd'),
          group(groupId: 'g1', unread: 2),
          c2c(userId: 'e'),
          c2c(userId: 'f'),
          c2c(userId: 'g'),
          c2c(userId: 'h'),
          group(groupId: 'g2'),
        ],
        archivedIDs: const <String>{},
        loginUserId: 'me',
        shouldShowConversation: (_) => true,
      );

      expect(selected.map((c) => c.userID ?? c.groupID).toList(), <String>[
        'b',
        'a',
        'c',
        'd',
        'e',
        'f',
        'g1',
        'g0',
      ]);
    });

    test('filters system / self / archived / membership-hidden', () {
      final selected = ConversationHistoryWarmScheduler.selectWarmCandidates(
        conversations: <V2TimConversation>[
          c2c(userId: '10000'),
          c2c(userId: 'me', conversationID: 'c2c_me'),
          c2c(userId: 'peer'),
          group(groupId: 'g1'),
          c2c(userId: 'archived_peer'),
          c2c(userId: 'hidden_by_membership'),
        ],
        archivedIDs: const <String>{'c2c_archived_peer'},
        loginUserId: 'me',
        shouldShowConversation: (conversation) =>
            conversation.userID != 'hidden_by_membership',
        sdkLimit: 40,
      );

      expect(selected.map((c) => c.userID ?? c.groupID).toList(), <String>[
        'peer',
        'g1',
      ]);
    });
  });

  group('ConversationHistoryWarmScheduler.selectViewportCandidates', () {
    test('hardCap limits result size', () {
      final rows = List<V2TimConversation?>.generate(
        40,
        (i) =>
            V2TimConversation(conversationID: 'c2c_$i', userID: '$i', type: 1),
      );
      final selected =
          ConversationHistoryWarmScheduler.selectViewportCandidates(
        rowConversations: rows,
        scrollOffset: 0,
        viewportHeight: 720,
        hardCap: 5,
      );
      expect(selected.length, 5);
    });

    test('center candidate picks nearest conversation to viewport middle', () {
      final rows = <V2TimConversation?>[
        V2TimConversation(
          conversationID: 'group_top',
          groupID: 'top',
          type: 2,
        ),
        null,
        V2TimConversation(
          conversationID: 'group_center',
          groupID: 'center',
          type: 2,
        ),
        V2TimConversation(
          conversationID: 'group_after',
          groupID: 'after',
          type: 2,
        ),
      ];

      final selected =
          ConversationHistoryWarmScheduler.selectViewportCenterCandidate(
        rowConversations: rows,
        scrollOffset: 72,
        viewportHeight: 144,
        rowExtent: 72,
      );

      expect(selected?.conversationID, 'group_center');
    });

    test('center candidate skips non-conversation rows', () {
      final rows = <V2TimConversation?>[
        V2TimConversation(
          conversationID: 'group_top',
          groupID: 'top',
          type: 2,
        ),
        null,
        null,
        V2TimConversation(
          conversationID: 'group_after',
          groupID: 'after',
          type: 2,
        ),
      ];

      final selected =
          ConversationHistoryWarmScheduler.selectViewportCenterCandidate(
        rowConversations: rows,
        scrollOffset: 72,
        viewportHeight: 144,
        rowExtent: 72,
      );

      expect(selected?.conversationID, 'group_after');
    });
  });

  group('ConversationHistoryWarmScheduler.shouldSkipWarmFetch', () {
    test('skips when cached long enough and preview not ahead', () {
      expect(
        ConversationHistoryWarmScheduler.shouldSkipWarmFetch(
          cachedCount: HistoryMessageDartConstant.initialOpenFetchCount,
          previewAhead: false,
          warmCount: HistoryMessageDartConstant.initialOpenFetchCount,
        ),
        isTrue,
      );
    });

    test('does not skip when cached shorter than warmCount', () {
      expect(
        ConversationHistoryWarmScheduler.shouldSkipWarmFetch(
          cachedCount: 1,
          previewAhead: false,
          warmCount: HistoryMessageDartConstant.initialOpenFetchCount,
        ),
        isFalse,
      );
    });

    test('does not skip when preview ahead', () {
      expect(
        ConversationHistoryWarmScheduler.shouldSkipWarmFetch(
          cachedCount: HistoryMessageDartConstant.initialOpenFetchCount,
          previewAhead: true,
          warmCount: HistoryMessageDartConstant.initialOpenFetchCount,
        ),
        isFalse,
      );
    });
  });

  group('ConversationHistoryWarmScheduler pause/resume', () {
    setUp(() {
      ConversationHistoryWarmScheduler.instance.resetForTest();
    });

    test('pause blocks schedule until resume', () async {
      final scheduler = ConversationHistoryWarmScheduler.instance;
      scheduler.pauseForActiveChat(reason: 'test_open');
      expect(scheduler.isPausedForActiveChat, isTrue);
      await scheduler.runAfterConversationSync(reason: 'test_sync');
      expect(scheduler.isPausedForActiveChat, isTrue);
      scheduler.resumeAfterActiveChat(reason: 'test_leave');
      expect(scheduler.isPausedForActiveChat, isFalse);
    });

    test('feed scroll pause blocks sync warm without clearing chat pause',
        () async {
      final scheduler = ConversationHistoryWarmScheduler.instance;
      scheduler.setFeedScrolling(true, reason: 'test_scroll');
      expect(scheduler.isPausedForFeedScroll, isTrue);
      await scheduler.runAfterConversationSync(reason: 'test_sync');
      scheduler.pauseForActiveChat(reason: 'test_open');
      scheduler.setFeedScrolling(false, reason: 'test_scroll_end');
      expect(scheduler.isPausedForFeedScroll, isFalse);
      expect(scheduler.isPausedForActiveChat, isTrue);
      scheduler.resumeAfterActiveChat(reason: 'test_leave');
      expect(scheduler.isPausedForActiveChat, isFalse);
    });

    test('viewportWarmEnabled false skips viewport and press', () async {
      final scheduler = ConversationHistoryWarmScheduler.instance;
      ConversationHistoryWarmScheduler.viewportWarmEnabled = false;
      await scheduler.runViewportWarm(
        visibleOrdered: <V2TimConversation>[
          V2TimConversation(conversationID: 'c2c_x', userID: 'x', type: 1),
        ],
        reason: 'test',
      );
      scheduler.schedulePressWarm(
        V2TimConversation(conversationID: 'c2c_y', userID: 'y', type: 1),
      );
      expect(ConversationHistoryWarmScheduler.viewportWarmEnabled, isFalse);
    });

    test('touchMemoryWarm orders lru and respects cap bookkeeping', () {
      final scheduler = ConversationHistoryWarmScheduler.instance;
      for (var i = 0; i < 5; i++) {
        scheduler.touchMemoryWarm('k$i');
      }
      expect(scheduler.memoryLruForTest.keys.toList(), <String>[
        'k0',
        'k1',
        'k2',
        'k3',
        'k4',
      ]);
      scheduler.touchMemoryWarm('k0');
      expect(scheduler.memoryLruForTest.keys.last, 'k0');
    });
  });

  group('ConversationHistoryWarmScheduler memory release', () {
    late ConversationHistoryWarmScheduler scheduler;
    late TUIChatGlobalModel global;

    setUpAll(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      setupServiceLocator();
    });

    setUp(() {
      scheduler = ConversationHistoryWarmScheduler.instance;
      scheduler.resetForTest();
      ActiveChatRegistry.instance.reset();
      global = serviceLocator<TUIChatGlobalModel>();
      for (final key in global.messageListMap.keys.toList(growable: false)) {
        global.removeMessageList(key);
      }
    });

    tearDown(() {
      scheduler.resetForTest();
      ActiveChatRegistry.instance.reset();
      for (final key in global.messageListMap.keys.toList(growable: false)) {
        global.removeMessageList(key);
      }
    });

    test('evict keeps at most memoryWarmCap non-active windows', () {
      final cap = ConversationHistoryWarmScheduler.memoryWarmCap;
      for (var i = 0; i < cap + 5; i++) {
        final id = 'c2c_cap_$i';
        _seedEmptyWindow(global, id);
        scheduler.touchMemoryWarm(id);
      }
      scheduler.evictMemoryWarmForTest(global);

      final remaining = global.messageListMap.keys
          .where((k) => k.startsWith('c2c_cap_'))
          .length;
      expect(remaining, lessThanOrEqualTo(cap));
      expect(scheduler.memoryLruForTest.length, lessThanOrEqualTo(cap));
    });

    test('reconcile removes orphan map keys not in lru', () {
      _seedEmptyWindow(global, 'c2c_orphan');
      _seedEmptyWindow(global, 'c2c_kept');
      scheduler.touchMemoryWarm('c2c_kept');

      scheduler.reconcileStaleMessageMemory(global);

      expect(global.messageListMap.containsKey('c2c_orphan'), isFalse);
      expect(global.messageListMap.containsKey('c2c_kept'), isTrue);
    });

    test('active chat is not removed by reconcile', () {
      ActiveChatRegistry.instance.enter('c2c_active');
      _seedEmptyWindow(global, 'c2c_active');
      // 不进 LRU，仅靠 active 保护。
      scheduler.reconcileStaleMessageMemory(global);
      expect(global.messageListMap.containsKey('c2c_active'), isTrue);
    });

    test('leave trims immediately to warm window of 20', () {
      final messages = <V2TimMessage>[
        for (var i = 25; i >= 1; i--)
          V2TimMessage.fromJson({
            'message_conv_id': 'c2c_leave',
            'message_conv_type': 1,
            'message_msg_id': 'c2c_leave-$i',
            'message_server_time': i,
            'message_status': 2,
            'message_risk_type_identified': 0,
            if (i == 20) 'message_elem_type': 11,
          }),
      ];
      global.setMessageList('c2c_leave', messages, replace: true);
      scheduler.touchMemoryWarm('c2c_leave');
      ActiveChatRegistry.instance.leave('c2c_leave');
      scheduler.scheduleReleaseAfterChatLeave('c2c_leave');

      expect(global.messageListMap.containsKey('c2c_leave'), isTrue);
      expect(
        global.rawMessageCount('c2c_leave'),
        HistoryMessageDartConstant.initialOpenFetchCount,
      );
      expect(global.rawMessageList('c2c_leave')!.first.msgID, 'c2c_leave-25');
      expect(global.mayHaveOlderHistory('c2c_leave'), isTrue);
    });

    test('leave grace removes full window after delay unless re-entered', () {
      fakeAsync((async) {
        final messages = <V2TimMessage>[
          for (var i = 25; i >= 1; i--)
            V2TimMessage.fromJson({
              'message_conv_id': 'c2c_grace',
              'message_conv_type': 1,
              'message_msg_id': 'c2c_grace-$i',
              'message_server_time': i,
              'message_status': 2,
              'message_risk_type_identified': 0,
            }),
        ];
        global.setMessageList('c2c_grace', messages, replace: true);
        scheduler.touchMemoryWarm('c2c_grace');
        ActiveChatRegistry.instance.leave('c2c_grace');
        scheduler.scheduleReleaseAfterChatLeave('c2c_grace');

        expect(
          global.rawMessageCount('c2c_grace'),
          HistoryMessageDartConstant.initialOpenFetchCount,
        );

        async.elapse(const Duration(seconds: 14));
        expect(global.messageListMap.containsKey('c2c_grace'), isTrue);
        expect(
          global.rawMessageCount('c2c_grace'),
          HistoryMessageDartConstant.initialOpenFetchCount,
        );

        async.elapse(const Duration(seconds: 2));
        expect(global.messageListMap.containsKey('c2c_grace'), isFalse);
      });
    });

    test('leave grace skipped when re-entered before deadline', () {
      fakeAsync((async) {
        final messages = <V2TimMessage>[
          for (var i = 25; i >= 1; i--)
            V2TimMessage.fromJson({
              'message_conv_id': 'c2c_reenter',
              'message_conv_type': 1,
              'message_msg_id': 'c2c_reenter-$i',
              'message_server_time': i,
              'message_status': 2,
              'message_risk_type_identified': 0,
            }),
        ];
        global.setMessageList('c2c_reenter', messages, replace: true);
        scheduler.touchMemoryWarm('c2c_reenter');
        ActiveChatRegistry.instance.leave('c2c_reenter');
        scheduler.scheduleReleaseAfterChatLeave('c2c_reenter');

        expect(
          global.rawMessageCount('c2c_reenter'),
          HistoryMessageDartConstant.initialOpenFetchCount,
        );

        async.elapse(const Duration(seconds: 5));
        ActiveChatRegistry.instance.enter('c2c_reenter');
        async.elapse(const Duration(seconds: 20));
        expect(global.messageListMap.containsKey('c2c_reenter'), isTrue);
        expect(
          global.rawMessageCount('c2c_reenter'),
          HistoryMessageDartConstant.initialOpenFetchCount,
        );
      });
    });

    test('leave trim skipped when still active', () {
      final messages = <V2TimMessage>[
        for (var i = 25; i >= 1; i--)
          V2TimMessage.fromJson({
            'message_conv_id': 'c2c_active_leave',
            'message_conv_type': 1,
            'message_msg_id': 'c2c_active_leave-$i',
            'message_server_time': i,
            'message_status': 2,
            'message_risk_type_identified': 0,
          }),
      ];
      global.setMessageList('c2c_active_leave', messages, replace: true);
      ActiveChatRegistry.instance.enter('c2c_active_leave');
      scheduler.scheduleReleaseAfterChatLeave('c2c_active_leave');
      expect(global.rawMessageCount('c2c_active_leave'), 25);
    });

    test('leave trim no-op when already within warm count', () {
      final messages = <V2TimMessage>[
        for (var i = 10; i >= 1; i--)
          V2TimMessage.fromJson({
            'message_conv_id': 'c2c_small',
            'message_conv_type': 1,
            'message_msg_id': 'c2c_small-$i',
            'message_server_time': i,
            'message_status': 2,
            'message_risk_type_identified': 0,
          }),
      ];
      global.setMessageList('c2c_small', messages, replace: true);
      ActiveChatRegistry.instance.leave('c2c_small');
      scheduler.scheduleReleaseAfterChatLeave('c2c_small');
      expect(global.rawMessageCount('c2c_small'), 10);
    });
  });

  test('viewport local warm unions existing history instead of peek-replace',
      () {
    final source = File(
      'lib/src/services/conversation_history_warm_scheduler.dart',
    ).readAsStringSync();
    expect(source, contains('ConversationWarmMode.viewportLocal'));
    expect(source, contains('mergeHistoricalWithInMemory'));
    expect(
      source,
      contains('Tiny peeks must not invalidate that.'),
    );
  });
}
