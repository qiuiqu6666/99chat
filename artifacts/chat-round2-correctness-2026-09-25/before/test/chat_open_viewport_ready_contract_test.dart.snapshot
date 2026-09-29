import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_entry_snapshot.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_viewport_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';

void main() {
  group('ChatEntrySnapshot.isViewportReady', () {
    ChatEntrySnapshot snap({
      int messageCount = 0,
      bool initialHistoryLoaded = false,
      bool mayHaveOlderHistory = true,
      bool completeOpenWindow = false,
      bool emptyConfirmed = false,
    }) {
      return ChatEntrySnapshot(
        conversationKey: 'c2c_u1',
        conversationID: 'c2c_u1',
        requestId: 1,
        messageCount: messageCount,
        initialHistoryLoaded: initialHistoryLoaded,
        mayHaveOlderHistory: mayHaveOlderHistory,
        completeOpenWindow: completeOpenWindow,
        emptyConfirmed: emptyConfirmed,
        capturedAtMs: 0,
      );
    }

    test('empty confirmed is not ready', () {
      expect(
        snap(emptyConfirmed: true, initialHistoryLoaded: true).isViewportReady,
        isFalse,
      );
    });

    test('complete open window is ready', () {
      expect(
        snap(
          messageCount: HistoryMessageDartConstant.initialOpenFetchCount,
          completeOpenWindow: true,
          initialHistoryLoaded: true,
        ).isViewportReady,
        isTrue,
      );
    });

    test('short exhausted window is ready', () {
      expect(
        snap(
          messageCount: 3,
          initialHistoryLoaded: true,
          mayHaveOlderHistory: false,
        ).isViewportReady,
        isTrue,
      );
    });

    test('thin loaded window with older history is not ready', () {
      expect(
        snap(
          messageCount: 3,
          initialHistoryLoaded: true,
          mayHaveOlderHistory: true,
          completeOpenWindow: false,
        ).isViewportReady,
        isFalse,
      );
    });
  });

  group('ChatOpenViewportCoordinator requestId', () {
    test('reset clears coordinator state', () {
      final c = ChatOpenViewportCoordinator.instance;
      c.resetForTest();
      expect(c.currentRequestId, 0);
      expect(c.phase, ChatOpenViewportPhase.idle);
    });
  });

  group('source contracts', () {
    test('tap path starts local snapshot without blocking navigation', () {
      final conv = File('lib/src/conversation.dart').readAsStringSync();
      expect(
        conv.contains('final prepareTask = coordinator.prepareOpenViewport('),
        isTrue,
      );
      expect(conv.contains('markTransitioning'), isTrue);
      final prepareAt = conv.indexOf('prepareOpenViewport');
      final pushAt = conv.indexOf('openOrReuseAppChat');
      expect(prepareAt, greaterThanOrEqualTo(0));
      expect(pushAt, greaterThan(prepareAt));
      expect(
        conv.substring(prepareAt, pushAt).contains(
              'await coordinator.ensureLocalSnapshotForOpen',
            ),
        isFalse,
      );
    });

    test('route local snapshot handoff has a bounded wait', () {
      final route =
          File('lib/src/navigation/app_chat_route.dart').readAsStringSync();
      final coord = File(
        'lib/src/services/chat_open_viewport_coordinator.dart',
      ).readAsStringSync();
      final localAt = route.indexOf('prepareOpenViewport');
      final pushAt = route.indexOf('return navigator.push<T>');
      expect(route.contains('await ChatOpenViewportCoordinator.instance'), isTrue);
      expect(localAt, greaterThanOrEqualTo(0));
      expect(pushAt, greaterThan(localAt));
      expect(route.contains('cloudGraceBudget'), isFalse);
      expect(route.contains('prepareOpenViewport('), isTrue);
      expect(route.contains('waitElapsed >= 270'), isFalse);
      expect(
        route.contains('ChatOpenViewportCoordinator.localBudget'),
        isTrue,
      );
      expect(coord.contains('.timeout(cloudGrace'), isFalse);
      expect(coord.contains("'awaitGrace': false"), isTrue);
      expect(coord.contains('unawaited('), isTrue);
      expect(coord.contains('repairOpenViewport('), isTrue);
    });

    test('chat first frame waits for locked viewport snapshot', () {
      final chat = File('lib/src/chat.dart').readAsStringSync();
      expect(chat.contains('_canAcceptViewportWindow'), isTrue);
      expect(chat.contains('_firstViewportWindowLogged'), isTrue);
      expect(chat.contains('matchesInitialWindow'), isTrue);
    });

    test('ChatOpenPerf prints to logcat in debug/profile', () {
      final perf = File('lib/src/services/chat_open_perf_log.dart').readAsStringSync();
      expect(perf.contains('print(line)'), isTrue);
      expect(perf.contains('debugPrint(line)'), isFalse);
    });

    test('chat mounts one stable real tree on the first route frame', () {
      final chat = File('lib/src/chat.dart').readAsStringSync();
      expect(chat.contains('_mountStableChatBody'), isTrue);
      expect(chat.contains("'stable_chat_body_mounted'"), isTrue);
      expect(chat.contains('_heavyChatBodyMounted'), isFalse);
      expect(chat.contains('_buildChatTransitionShell'), isFalse);
      expect(chat.contains('takeOpenWasViewportReady'), isFalse);
    });

    test('background prepare stays bounded to 400ms', () {
      final coord = File(
        'lib/src/services/chat_open_viewport_coordinator.dart',
      ).readAsStringSync();
      expect(coord.contains('prepareTimeout'), isTrue);
      expect(coord.contains('milliseconds: 400'), isTrue);
      expect(
        ChatOpenViewportCoordinator.prepareTimeout,
        const Duration(milliseconds: 400),
      );
      expect(coord.contains('不能再'), isTrue);
    });

    test('chat route isolates first paint with RepaintBoundary', () {
      final route =
          File('lib/src/navigation/app_chat_route.dart').readAsStringSync();
      expect(route.contains('RepaintBoundary('), isTrue);
      final boundaryAt = route.indexOf('RepaintBoundary(');
      final chatAt = route.indexOf('Chat(');
      expect(boundaryAt, greaterThanOrEqualTo(0));
      expect(chatAt, greaterThan(boundaryAt));
    });

    test('warm window count stays 20', () {
      expect(HistoryMessageDartConstant.initialOpenFetchCount, 20);
    });
  });
}
