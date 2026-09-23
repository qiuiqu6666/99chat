import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// Match the controller type exposed by the vendored UIKit widget API.
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

Future<void> pump(WidgetTester tester, [Duration? duration]) async {
  final handler = FlutterError.onError;
  await tester.pump(duration);
  FlutterError.onError = handler;
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  var sequence = 0;
  late TUIChatGlobalModel global;
  late TUIChatSeparateViewModel model;
  late AutoScrollController scroll;
  late String conv;

  setUp(() {
    conv = '@TGS#history_incoming_${++sequence}';
    global = serviceLocator<TUIChatGlobalModel>();
    global.configureMessageWriterScope(
      ownerUserID: 'history_reader',
      accountGeneration: 1,
      domainGeneration: 1,
    );
    global.chatConfig = const TIMUIKitChatConfig(
      isAutoReportRead: false,
      inboundChunkRevealEnabled: true,
    );
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
        notify: false);
    model = TUIChatSeparateViewModel()
      ..conversationID = conv
      ..suppressReadReporting = true;
    scroll = AutoScrollController();
    global.bindActiveChatScrollController(
        conversationID: conv, scrollController: scroll);
    global.bindHistoryLiveWindowFreeze(
      conversationID: conv,
      freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
    );
  });

  V2TimMessage message(int id) => V2TimMessage.fromJson({
        'message_conv_id': conv,
        'message_conv_type': 2,
        'message_msg_id': '$conv-$id',
        'message_server_time': id,
        'message_status': 2,
        'message_risk_type_identified': 0,
      })
        ..groupID = conv
        ..seq = '$id'
        ..timestamp = id
        ..isSelf = false;

  Future<void> mount(
    WidgetTester tester, {
    bool tongue = false,
    int entryUnread = 0,
    Future<bool> Function(int)? onFirstUnread,
    bool Function()? beginTransition,
    Future<void> Function()? finishTransition,
  }) async {
    model.initialUnreadCount = entryUnread;
    final errorHandler = FlutterError.onError;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: global,
        child: MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: global,
              builder: (_, __) {
                // Keep a long scroll surface, but give the rendered rows
                // and the tongue the same current message identities.
                final messages =
                    global.rawMessageList(conv) ?? const <V2TimMessage>[];
                return Stack(
                  children: [
                    ListView.builder(
                      controller: scroll,
                      reverse: true,
                      itemExtent: 60,
                      itemCount: 100,
                      itemBuilder: (_, i) => Text(
                        i < messages.length
                            ? 'message:${messages[i].msgID}'
                            : 'history $i',
                      ),
                    ),
                    if (tongue)
                      TIMUIKitHistoryMessageListTongueContainer(
                        messageList: messages,
                        conversation: V2TimConversation(
                          conversationID: 'group_$conv',
                          groupID: conv,
                          type: 2,
                          unreadCount: entryUnread,
                        ),
                        scrollToIndexBySeq: (_) async => false,
                        scrollToFirstUnread:
                            onFirstUnread ?? (_) async => false,
                        beginWindowTransition: beginTransition,
                        finishWindowTransition: finishTransition,
                        scrollController: scroll,
                        model: model,
                        tongueItemBuilder: (tap, type, count) => TextButton(
                          onPressed: tap,
                          child: Text('${type.name}:$count'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    FlutterError.onError = errorHandler;
    await pump(tester);
  }

  Future<void> receive(WidgetTester tester, int id) async {
    await global.applyAppRealtimeMessage(message(id));
    await pump(tester, const Duration(milliseconds: 60));
    await pump(tester, const Duration(milliseconds: 60));
    await pump(tester);
  }

  void leaveLatest() {
    global.setFollowingLatest(conv, false, notify: false);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    global.clearActiveChatScrollController(conversationID: conv);
    global.setChatListUserScrolling(false);
    global.clearData();
    scroll.dispose();
    model.dispose();
    await pump(tester, const Duration(seconds: 1));
  }

  testWidgets('incoming while reading history is buffered off the visible list',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    final offset = scroll.offset;
    final pin = global.pinToBottomRequestSeq;
    final visibleIds = global.rawMessageList(conv)!.map((m) => m.msgID).toList();
    await receive(tester, 2);
    await receive(tester, 3);
    expect(model.hasHistoryReadingWindow, isTrue);
    expect(scroll.offset, offset);
    expect(global.pinToBottomRequestSeq, pin);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), visibleIds);
    expect(global.rawMessageList(conv)!.first.msgID, '$conv-1');
    expect(global.rawMessageList(conv)!.last.msgID, '$conv-1');
    expect(global.rawMessageList(conv)!.length, 1);
    expect(global.deferredIncomingBufferedCount(conv), 2);
    expect(global.receivedNewMessageCountFor(conv), 2);
    expect(global.unreadCountForTongueFor(conv), 2);
    expect(global.isActiveChatNearBottom(conv), isFalse);
    await unmount(tester);
  });

  testWidgets('incoming preserves historical window edge', (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest);
    final offset = scroll.offset;
    final pin = global.pinToBottomRequestSeq;
    await receive(tester, 2);
    await receive(tester, 3);
    expect(scroll.offset, offset);
    expect(global.pinToBottomRequestSeq, pin);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), ['$conv-1']);
    expect(global.deferredIncomingBufferedCount(conv), 2);
    expect(global.unreadCountForTongueFor(conv), 2);
    expect(global.isActiveChatNearBottom(conv), isFalse);
    await unmount(tester);
  });

  testWidgets('search replacement excludes messages received before the jump',
      (tester) async {
    global.setMessageList(conv, [message(999)]);
    await mount(tester);
    await receive(tester, 1000);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID),
        ['$conv-1000', '$conv-999']);
    // The latest message has already passed through the authoritative writer.
    // Search installs an entirely different window, without receiving anything.
    model.haveMoreLatestData = true;
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest);
    global.setMessageList(conv, [message(2), message(1)],
        replace: true, applyMemoryWindow: false);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID),
        ['$conv-2', '$conv-1']);
    final page = global.beginHistoryReconciliation(
      conversationID: conv,
      requestedSource: MessageReconciliationSource.cloud,
      networkState: MessageReconciliationNetworkState.online,
    );
    final commit = global.completeHistoryReconciliation(
      request: page,
      history: [message(3)],
      actualSource: MessageReconciliationSource.cloud,
      networkState: MessageReconciliationNetworkState.online,
      batchKind: MessageHistoryBatchKind.newerCatchUp,
      historyIsFinished: false,
      applyMemoryWindow: false,
    );
    expect(commit, isNotNull);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID),
        ['$conv-3', '$conv-2', '$conv-1']);
    // Returning to latest can read that message again; switching windows is
    // not deletion and must not erase its authority.
    global.setMessageList(conv, [message(1000), message(999)],
        replace: true, applyMemoryWindow: false);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID),
        ['$conv-1000', '$conv-999']);
    await unmount(tester);
  });

  for (final historyState in ['missing newer', 'search window', 'locating']) {
    testWidgets(
        'historical window edge cannot flush live messages across a gap ($historyState)',
        (tester) async {
      global.setMessageList(conv, [message(1)]);
      if (historyState == 'missing newer') {
        model.haveMoreLatestData = true;
      } else if (historyState == 'search window') {
        global.setMessageListPosition(
            conv, HistoryMessagePosition.notShowLatest);
      } else {
        global.beginSearchJump(conv);
      }
      await mount(tester);
      // This is the bottom of the loaded search window, not the conversation.
      expect(scroll.offset, scroll.position.minScrollExtent);
      await receive(tester, 1000);
      expect(global.deferredIncomingBufferedCount(conv), 1);
      global.setChatListUserScrolling(true);
      global.setChatListUserScrolling(false);
      expect(
          global.flushDeferredIncomingMessages(conv, notify: false), isFalse);
      expect(global.rawMessageList(conv)!.map((m) => m.msgID), ['$conv-1']);
      expect(global.deferredIncomingBufferedCount(conv), 1);
      // A contiguous SDK page must remain separate from the live tail.
      global.setMessageList(conv, [message(2), message(1)]);
      expect(
          global.flushDeferredIncomingMessages(conv, notify: false), isFalse);
      expect(global.rawMessageList(conv)!.map((m) => m.msgID),
          ['$conv-2', '$conv-1']);
      global.flushPendingIncomingMessagesForUserBottom(conv);
      expect(global.deferredIncomingBufferedCount(conv), 0);
      expect(global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-1000'),
          isTrue);
      await unmount(tester);
    });
  }

  testWidgets('far return stays live and accelerates to the latest edge',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    model.haveMoreLatestData = false;
    var began = 0;
    var finished = 0;
    await mount(tester, tongue: true, beginTransition: () {
      began++;
      return true;
    }, finishTransition: () async {
      finished++;
    });
    scroll.jumpTo(3000);
    leaveLatest();
    await pump(tester);
    final tongue = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
        find.byType(TIMUIKitHistoryMessageListTongueContainer));
    var done = false;
    final pending =
        tongue.scrollToLatestAndDismissUnreadCapsule().then((_) => done = true);
    for (var frame = 0; frame < 60 && !done; frame++) {
      await pump(tester, const Duration(milliseconds: 16));
    }
    expect(done, isTrue);
    await pending;
    expect(began, 0);
    expect(finished, 0);
    expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
    await unmount(tester);
  });

  for (final count in [99, 100]) {
    testWidgets('entry reminder is removed for count $count', (tester) async {
      global.setMessageList(conv, [message(1)]);
      final tapped = <int>[];
      await mount(tester, tongue: true, entryUnread: count,
          onFirstUnread: (value) async {
        tapped.add(value);
        return true;
      });
      final hint = find.text('showPrevious:$count');
      expect(hint, findsNothing);
      await receive(tester, 1000);
      expect(hint, findsNothing);
      expect(tapped, isEmpty);
      await unmount(tester);
    });
  }

  testWidgets(
      'dismissing entry unread preserves live messages buffered during the jump',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    global.lockEntryUnreadForTongue(conversationID: conv, unreadCount: 51);
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest);
    await receive(tester, 2);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    global.releaseEntryUnreadReminder(conv);
    expect(global.hasLockedEntryUnreadFor(conv), isFalse);
    expect(global.unreadCountForTongueFor(conv), 1);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    await unmount(tester);
  });

  testWidgets('user scroll cancels keyboard bottom snapshot before incoming',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    global.beginKeyboardViewportTransition(conv);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(1200);
    leaveLatest();
    global.setChatListUserScrolling(false);
    final pin = global.pinToBottomRequestSeq;
    await receive(tester, 2);
    await pump(tester, const Duration(milliseconds: 300));
    expect(global.pinToBottomRequestSeq, pin);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect(global.rawMessageList(conv)!.length, 1);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(scroll.offset, 1200);
    await unmount(tester);
  });

  testWidgets(
      'keyboard settle keeps history anchor when user is not at bottom',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    final offset = scroll.offset;
    final pin = global.pinToBottomRequestSeq;
    global.beginKeyboardViewportTransition(conv);
    global.endKeyboardViewportTransition(conv);
    await pump(tester);
    expect(scroll.offset, offset);
    expect(global.pinToBottomRequestSeq, pin);
    await unmount(tester);
  });

  testWidgets('burst is buffered until explicit return', (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    final pin = global.pinToBottomRequestSeq;
    for (var id = 2; id <= 10; id++) {
      await global.applyAppRealtimeMessage(message(id));
    }
    await receive(tester, 10);
    expect(global.rawMessageList(conv)!.length, 1);
    expect(global.deferredIncomingBufferedCount(conv), 9);
    expect(global.receivedNewMessageCountFor(conv), 9);
    expect(global.unreadCountForTongueFor(conv), 9);
    expect(global.pinToBottomRequestSeq, pin);
    expect(scroll.offset, 1200);
    global.flushPendingIncomingMessagesForUserBottom(conv);
    expect(global.rawMessageList(conv)!.length, 10);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    await unmount(tester);
  });

  testWidgets('latest window still receives visible messages at bottom',
      (tester) async {
    global.chatConfig = const TIMUIKitChatConfig(
      isAutoReportRead: false,
      inboundChunkRevealEnabled: false,
    );
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    await receive(tester, 2);
    expect(global.rawMessageList(conv)!.length, 2);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    expect(global.unreadCountForTongueFor(conv), 0);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.isFollowingLatest(conv), isTrue);
    expect(global.isActiveChatNearBottom(conv), isTrue);
    await unmount(tester);
  });

  testWidgets(
      'live capsule updates count even with unchanged viewport metrics and after dismissal',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    global.setUnreadTongueMetrics(
        conversationID: conv, remaining: 0, below: true);
    await mount(tester, tongue: true);
    Future<void> readHistory() async {
      global.setChatListUserScrolling(true);
      scroll.jumpTo(1200);
    leaveLatest();
      await pump(tester);
      global.setChatListUserScrolling(false);
      await pump(tester, const Duration(milliseconds: 250));
    }

    await readHistory();
    expect(find.text('toLatest:0'), findsOneWidget);
    await receive(tester, 2);
    expect(find.text('showUnread:1'), findsOneWidget);
    await receive(tester, 3);
    expect(find.text('showUnread:2'), findsOneWidget);
    await tester.tap(find.text('showUnread:2'));
    for (var i = 0; i < 20; i++) {
      await pump(tester, const Duration(milliseconds: 100));
    }
    expect(scroll.offset, 0);
    expect(global.unreadCountForTongueFor(conv), 0);
    await readHistory();
    await receive(tester, 4);
    expect(global.isUserScrollToBottomInProgress(conv), isFalse);
    expect(global.unreadCountForTongueFor(conv), 1);
    expect(global.getMessageListPosition(conv),
        HistoryMessagePosition.awayTwoScreen);
    expect(find.text('showUnread:1'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'latest window away inserts remain readable and clear on return',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester, tongue: true);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(1200);
    leaveLatest();
    await pump(tester);
    global.setChatListUserScrolling(false);
    await pump(tester, const Duration(milliseconds: 250));
    final offset = scroll.offset;
    final pin = global.pinToBottomRequestSeq;
    await receive(tester, 2);
    await receive(tester, 3);
    expect(scroll.offset, offset);
    expect(global.pinToBottomRequestSeq, pin);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), ['$conv-1']);
    expect(global.deferredIncomingBufferedCount(conv), 2);
    expect(global.receivedNewMessageCountFor(conv), 2);
    expect(find.text('showUnread:2'), findsOneWidget);
    await tester.tap(find.text('showUnread:2'));
    for (var i = 0; i < 20; i++) {
      await pump(tester, const Duration(milliseconds: 100));
    }
    expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
    expect(global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-3'), isTrue);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.unreadCountForTongueFor(conv), 0);
    expect(global.isFollowingLatest(conv), isTrue);
    await unmount(tester);
  });

  testWidgets(
      '24-80px band counts live arrivals without pin or buffer dump',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester, tongue: true);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(50);
    leaveLatest();
    await pump(tester);
    global.setChatListUserScrolling(false);
    await pump(tester, const Duration(milliseconds: 250));
    final offset = scroll.offset;
    final pin = global.pinToBottomRequestSeq;
    await receive(tester, 2);
    await receive(tester, 3);
    expect(scroll.offset, offset);
    expect(global.pinToBottomRequestSeq, pin);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), ['$conv-1']);
    expect(global.deferredIncomingBufferedCount(conv), 2);
    expect(global.receivedNewMessageCountFor(conv), 2);
    expect(global.unreadCountForTongueFor(conv), 2);
    expect(find.text('showUnread:2'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'slightly off bottom does not pin incoming even without explicit leave',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester, tongue: true);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(50);
    leaveLatest();
    await pump(tester);
    global.setChatListUserScrolling(false);
    await pump(tester, const Duration(milliseconds: 250));
    final offset = scroll.offset;
    final pin = global.pinToBottomRequestSeq;
    await receive(tester, 2);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(model.hasHistoryReadingWindow, isTrue);
    expect(scroll.offset, offset);
    expect(global.pinToBottomRequestSeq, pin);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), ['$conv-1']);
    expect(find.text('showUnread:1'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('unseen count does not decrease until return to latest',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester, tongue: true);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(1200);
    leaveLatest();
    await pump(tester);
    global.setChatListUserScrolling(false);
    await receive(tester, 2);
    await receive(tester, 3);
    expect(global.receivedNewMessageCountFor(conv), 2);
    expect(find.text('showUnread:2'), findsOneWidget);
    scroll.jumpTo(600);
    await pump(tester);
    expect(global.receivedNewMessageCountFor(conv), 2);
    expect(find.text('showUnread:2'), findsOneWidget);
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isTrue);
    model.resumeVisibleLiveWindow();
    await pump(tester);
    expect(global.isFollowingLatest(conv), isTrue);
    expect(global.remainingLiveIncomingCountFor(conv), 0);
    await unmount(tester);
  });

  testWidgets(
      'pagination prepend plus receive keeps the frozen newest edge',
      (tester) async {
    global.setMessageList(conv, [message(10), message(9), message(8)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    final offset = scroll.offset;
    final pin = global.pinToBottomRequestSeq;
    await receive(tester, 11);
    global.setMessageList(
      conv,
      [message(10), message(9), message(8), message(7)],
    );
    expect(model.hasHistoryReadingWindow, isTrue);
    expect(
      global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-11'),
      isFalse,
    );
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect(
      global.rawMessageList(conv)!.map((m) => m.msgID),
      ['$conv-10', '$conv-9', '$conv-8', '$conv-7'],
    );
    expect(scroll.offset, offset);
    expect(global.pinToBottomRequestSeq, pin);
    expect(global.isActiveChatNearBottom(conv), isFalse);
    await unmount(tester);
  });

  testWidgets(
      'physical away with stale following leaves and freezes the visible list',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester, tongue: true);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(1200);
    leaveLatest();
    await pump(tester);
    global.setChatListUserScrolling(false);
    await pump(tester, const Duration(milliseconds: 250));
    final offset = scroll.offset;
    final pin = global.pinToBottomRequestSeq;
    await receive(tester, 2);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(model.hasHistoryReadingWindow, isTrue);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), ['$conv-1']);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect(global.pinToBottomRequestSeq, pin);
    expect(scroll.offset, offset);
    expect(find.text('showUnread:1'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'scrolling toward latest attaches buffer without jumping to live tip',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    for (var id = 2; id <= 7; id++) {
      await receive(tester, id);
    }
    final pin = global.pinToBottomRequestSeq;
    expect(global.deferredIncomingBufferedCount(conv), 6);
    expect(global.isFollowingLatest(conv), isFalse);

    // 一次只接一档，缓冲不能被整批倒进可见列表。
    model.restoreTowardLatestFromUserScroll(revealLimit: 2);
    await pump(tester);
    await pump(tester);
    expect(global.deferredIncomingBufferedCount(conv), 4);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(global.pinToBottomRequestSeq, pin);
    expect(
        global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-2'), isTrue);
    expect(
        global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-3'), isTrue);
    expect(
        global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-7'), isFalse);

    // 缓冲清空之前，任何一次 restore 都不能恢复跟随最新端。
    while (global.deferredIncomingBufferedCount(conv) > 0) {
      global.endAttachingBufferedTowardLatest();
      await pump(tester, const Duration(milliseconds: 350));
      model.restoreTowardLatestFromUserScroll(revealLimit: 2);
      await pump(tester);
      await pump(tester);
      expect(global.isFollowingLatest(conv), isFalse);
    }
    expect(
        global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-7'), isTrue);
    expect(global.pinToBottomRequestSeq, pin);

    global.endAttachingBufferedTowardLatest();
    model.resumeVisibleLiveWindow();
    await pump(tester);
    expect(global.isFollowingLatest(conv), isTrue);
    await unmount(tester);
  });

  testWidgets(
      'confirm visible latest refuses to resume right after a buffered reveal',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    await receive(tester, 2);
    await receive(tester, 3);
    expect(global.deferredIncomingBufferedCount(conv), 2);
    model.restoreTowardLatestFromUserScroll(revealLimit: 2);
    await pump(tester);
    await pump(tester);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    global.endAttachingBufferedTowardLatest();
    final confirmed = await model.confirmVisibleLatestWindow(
      visibleMessages: global.rawMessageList(conv) ?? const <V2TimMessage>[],
      isStillAtLatestEdge: () => true,
    );
    expect(confirmed, isFalse);
    expect(global.isFollowingLatest(conv), isFalse);
    await unmount(tester);
  });

  testWidgets(
      'hot reveal preloads without consuming and exact visible IDs decrement once',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    await receive(tester, 2);
    await receive(tester, 3);
    await receive(tester, 4);
    final pin = global.pinToBottomRequestSeq;
    expect(global.deferredIncomingBufferedCount(conv), 3);
    expect(global.receivedNewMessageCountFor(conv), 3);

    for (var step = 1; step <= 3; step++) {
      expect(
        model.revealBufferedIncomingTowardLatest(limit: 1, skipCooldown: true),
        isTrue,
      );
      global.endAttachingBufferedTowardLatest();
      await pump(tester);
      await pump(tester);
      expect(global.deferredIncomingBufferedCount(conv), 3 - step);
      expect(global.receivedNewMessageCountFor(conv), 4 - step);
      expect(model.isLiveRestoreDataReady, isTrue);
      // Neither a generic cleanup nor an equivalent raw publication is a read.
      global.clearReceivedNewMessageCount(conversationID: conv);
      global.clearReceivedUnreadState(conversationID: conv);
      global.unlockEntryUnreadForTongue(conversationID: conv);
      global.setMessageList(conv, global.rawMessageList(conv)!);
      expect(global.receivedNewMessageCountFor(conv), 4 - step);
      final remainingBeforeAck = global.remainingLiveIncomingCountFor(conv);
      expect(await global.acknowledgeVisibleHistoryMessages(
          conv, [message(1 + step)], isCurrent: () => false), isFalse);
      expect(global.remainingLiveIncomingCountFor(conv), remainingBeforeAck);
      expect(await global.acknowledgeVisibleHistoryMessages(
          conv, [message(1 + step)], isCurrent: () => true), isTrue);
      expect(global.receivedNewMessageCountFor(conv), 3 - step);
      expect(global.remainingLiveIncomingCountFor(conv), remainingBeforeAck - 1);
      expect(await global.acknowledgeVisibleHistoryMessages(
          conv, [message(1 + step)], isCurrent: () => true), isFalse);
      expect(global.remainingLiveIncomingCountFor(conv), remainingBeforeAck - 1);
      expect(global.isFollowingLatest(conv), isFalse);
      expect(global.pinToBottomRequestSeq, pin);
      expect(
        global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-${1 + step}'),
        isTrue,
      );
      if (step < 3) {
        expect(
          global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-${2 + step}'),
          isFalse,
        );
      }
    }

    expect(model.hasCaughtUpToLiveLatest, isTrue);
    global.endAttachingBufferedTowardLatest();
    model.resumeVisibleLiveWindow();
    await pump(tester);
    expect(global.isFollowingLatest(conv), isTrue);
    await unmount(tester);
  });

  testWidgets('local unread survives optimistic removal and retires on accepted deletion',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    await receive(tester, 2);
    expect(model.revealBufferedIncomingTowardLatest(limit: 1, skipCooldown: true),
        isTrue);
    global.endAttachingBufferedTowardLatest();
    global.setMessageList(conv, [message(1)], replace: true, isDeleteMsg: true);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(model.isLiveRestoreDataReady, isTrue);
    // A failed optimistic delete puts the same unread row back.
    global.setMessageList(conv, [message(2), message(1)], replace: true);
    expect(global.receivedNewMessageCountFor(conv), 1);
    // The SDK success path retires the exact local identity, once.
    global.setMessageList(conv, [message(1)], replace: true, isDeleteMsg: true);
    global.retireDeletedLocalIncoming(conv, ['$conv-2']);
    global.retireDeletedLocalIncoming(conv, ['$conv-2']);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.unreadCountForTongueFor(conv), 0);
    await unmount(tester);
  });

  testWidgets('reveal without skipCooldown still honours the cooldown',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    await receive(tester, 2);
    await receive(tester, 3);
    expect(global.deferredIncomingBufferedCount(conv), 2);

    expect(model.revealBufferedIncomingTowardLatest(limit: 1), isTrue);
    expect(model.revealBufferedIncomingTowardLatest(limit: 1), isFalse);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    global.endAttachingBufferedTowardLatest();
    await pump(tester);
    await unmount(tester);
  });

  testWidgets(
      'capsule keeps showing remaining new messages at the physical bottom',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester, tongue: true);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(1200);
    leaveLatest();
    await pump(tester);
    global.setChatListUserScrolling(false);
    await pump(tester, const Duration(milliseconds: 250));
    await receive(tester, 2);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect(find.text('showUnread:1'), findsOneWidget);

    global.setChatListUserScrolling(true);
    scroll.jumpTo(0);
    await pump(tester);
    global.setChatListUserScrolling(false);
    await pump(tester, const Duration(milliseconds: 250));
    expect(find.text('showUnread:1'), findsOneWidget);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect(global.isFollowingLatest(conv), isFalse);
    await unmount(tester);
  });

  testWidgets(
      'revealing first 8 of 20 live rows does not FOLLOW',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    for (var id = 2; id <= 21; id++) {
      await receive(tester, id);
    }
    expect(global.deferredIncomingBufferedCount(conv), 20);
    expect(
      model.revealBufferedIncomingTowardLatest(limit: 8, skipCooldown: true),
      isTrue,
    );
    global.endAttachingBufferedTowardLatest();
    await pump(tester);
    expect(global.deferredIncomingBufferedCount(conv), 12);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(model.restoreTowardLatestFromUserScroll(revealLimit: 8), isFalse);
    expect(global.isFollowingLatest(conv), isFalse);
    await unmount(tester);
  });

  testWidgets(
      'COMMIT is allowed when N=12 remains after every live row is admitted',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester);
    scroll.jumpTo(1200);
    leaveLatest();
    for (var id = 2; id <= 13; id++) {
      await receive(tester, id);
    }
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isTrue);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    expect(global.remainingLiveIncomingCountFor(conv), 12);
    final idsBefore =
        global.rawMessageList(conv)!.map((m) => m.msgID).toList();
    expect(
      model.commitLiveFollowRestore(
        visit: global.unreadVisitGenerationFor(conv),
        restoreOpId: global.beginLiveFollowRestoreOp(conv),
        liveReceiveGeneration: global.liveReceiveGenerationFor(conv),
        targetTipId: '$conv-13',
        coveredIds: global.remainingLiveIncomingIdsFor(conv),
      ),
      isTrue,
    );
    expect(global.isFollowingLatest(conv), isTrue);
    expect(global.remainingLiveIncomingCountFor(conv), 0);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), idsBefore);
    await unmount(tester);
  });

  testWidgets(
      'capsule tap still jumps to latest in one shot after buffered incoming',
      (tester) async {
    global.setMessageList(conv, [message(1)]);
    await mount(tester, tongue: true);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(1200);
    leaveLatest();
    await pump(tester);
    global.setChatListUserScrolling(false);
    await pump(tester, const Duration(milliseconds: 250));
    await receive(tester, 2);
    await receive(tester, 3);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(find.text('showUnread:2'), findsOneWidget);
    await tester.tap(find.text('showUnread:2'));
    for (var i = 0; i < 20; i++) {
      await pump(tester, const Duration(milliseconds: 100));
    }
    expect(global.isFollowingLatest(conv), isTrue);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    expect(global.rawMessageList(conv)!.any((m) => m.msgID == '$conv-3'), isTrue);
    await unmount(tester);
  });
}
