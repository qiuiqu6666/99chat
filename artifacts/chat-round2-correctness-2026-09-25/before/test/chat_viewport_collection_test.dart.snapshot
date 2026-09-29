import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_height_cache.dart';

V2TimMessage msg({
  required String id,
  required int seq,
  int? timestamp,
  int elemType = 1,
}) {
  return V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': id,
    'message_seq': seq,
    'message_server_time': timestamp ?? seq,
    'elem_type': elemType,
    'message_status': 2,
    'message_risk_type_identified': 0,
  });
}

void main() {
  setUp(() {
    ChatViewportCollection.instance.resetForTest();
  });

  group('ChatViewportReadiness', () {
    test('EMPTY_LOCAL is not ready and needs H0', () {
      final result = ChatViewportReadiness.classify(
        conversationKey: 'group_a',
        newestFirst: const <V2TimMessage>[],
        useSeqContiguity: true,
        viewportHeight: 560,
        source: ChatViewportSource.local,
      );
      expect(result.coverageState, ChatViewportCoverageState.emptyLocal);
      expect(result.isViewportReady, isFalse);
      expect(result.needsLatestRepair, isTrue);
    });

    test('EMPTY_VERIFIED is ready without H0', () {
      final coverage = MessageHistoryCoverage(
        conversationKey: 'group_a',
        isGroup: true,
        clearEpoch: 0,
        coverageRevision: 1,
        status: MessageHistoryCoverageStatus.verified,
        olderExhausted: true,
        newerHasMore: false,
        holes: const <MessageHistoryHole>[],
        cloudVerifiedAtMs: 10,
      );
      final result = ChatViewportReadiness.classify(
        conversationKey: 'group_a',
        newestFirst: const <V2TimMessage>[],
        useSeqContiguity: true,
        viewportHeight: 560,
        source: ChatViewportSource.cloudMerged,
        coverage: coverage,
      );
      expect(result.coverageState, ChatViewportCoverageState.emptyVerified);
      expect(result.isViewportReady, isTrue);
      expect(result.needsLatestRepair, isFalse);
    });

    test('20 short texts are PARTIAL when extent is below target', () {
      final messages = <V2TimMessage>[
        for (var i = 20; i >= 1; i--) msg(id: 't$i', seq: i),
      ];
      for (final message in messages) {
        ChatMessageHeightCache.instance.remember(message, 12);
      }
      final result = ChatViewportReadiness.classify(
        conversationKey: 'group_a',
        newestFirst: messages,
        useSeqContiguity: true,
        viewportHeight: 560,
        source: ChatViewportSource.local,
      );
      expect(result.continuousCount, 20);
      expect(result.coverageState, ChatViewportCoverageState.partialLocal);
      expect(result.isViewportReady, isFalse);
      expect(result.needsLatestRepair, isTrue);
    });

    test('6 large images can be READY by extent', () {
      final messages = <V2TimMessage>[
        for (var i = 6; i >= 1; i--)
          msg(id: 'img$i', seq: 100 + i, elemType: 3),
      ];
      for (final message in messages) {
        ChatMessageHeightCache.instance.remember(message, 220);
      }
      final result = ChatViewportReadiness.classify(
        conversationKey: 'group_a',
        newestFirst: messages,
        useSeqContiguity: true,
        viewportHeight: 560,
        source: ChatViewportSource.memory,
      );
      expect(result.coverageState, ChatViewportCoverageState.readyLocal);
      expect(result.isViewportReady, isTrue);
      expect(result.needsLatestRepair, isFalse);
    });

    test('stops at latest gap and does not splice older messages', () {
      final messages = <V2TimMessage>[
        msg(id: 'm1000', seq: 1000),
        msg(id: 'm999', seq: 999),
        msg(id: 'm998', seq: 998),
        msg(id: 'm997', seq: 997),
        msg(id: 'm989', seq: 989),
        msg(id: 'm988', seq: 988),
      ];
      final spine = ChatViewportReadiness.takeNewestContiguous(
        newestFirst: messages,
        useSeqContiguity: true,
      );
      expect(spine.map(ChatViewportReadiness.messageId), <String>[
        'm1000',
        'm999',
        'm998',
        'm997',
      ]);
      final result = ChatViewportReadiness.classify(
        conversationKey: 'group_a',
        newestFirst: messages,
        useSeqContiguity: true,
        viewportHeight: 560,
        source: ChatViewportSource.local,
      );
      expect(result.coverageState, ChatViewportCoverageState.gapLocal);
      expect(result.continuousCount, 4);
      expect(result.gapBeforeSeq, 996);
      expect(result.mountedMessageIds, isNot(contains('m989')));
      expect(result.needsLatestRepair, isTrue);
    });

    test('ancient hole does not mark latest viewport as GAP', () {
      final messages = <V2TimMessage>[
        for (var i = 1588; i >= 1565; i--) msg(id: 'm$i', seq: i),
      ];
      for (final message in messages) {
        ChatMessageHeightCache.instance.remember(message, 80);
      }
      final coverage = MessageHistoryCoverage(
        conversationKey: 'group_a',
        isGroup: true,
        clearEpoch: 0,
        coverageRevision: 1,
        status: MessageHistoryCoverageStatus.partial,
        olderExhausted: false,
        newerHasMore: false,
        holes: const <MessageHistoryHole>[
          MessageHistoryHole(
            key: 'old',
            kind: MessageHistoryHoleKind.groupSeq,
            status: MessageHistoryHoleStatus.open,
            startSeq: 10,
            endSeq: 40,
          ),
        ],
      );
      final result = ChatViewportReadiness.classify(
        conversationKey: 'group_a',
        newestFirst: messages,
        useSeqContiguity: true,
        viewportHeight: 560,
        source: ChatViewportSource.local,
        coverage: coverage,
      );
      expect(result.coverageState, ChatViewportCoverageState.readyLocal);
      expect(result.needsLatestRepair, isFalse);
    });

    test('merge keeps realtime 1589 when local returns 1588', () {
      final current = <V2TimMessage>[
        msg(id: 'm1589', seq: 1589, timestamp: 1589),
      ];
      final incoming = <V2TimMessage>[
        msg(id: 'm1588', seq: 1588, timestamp: 1588),
        msg(id: 'm1587', seq: 1587, timestamp: 1587),
      ];
      final merged = ChatViewportReadiness.mergePreserveRealtime(
        current: current,
        incoming: incoming,
      );
      expect(
        merged.map(ChatViewportReadiness.messageId),
        containsAll(<String>['m1589', 'm1588', 'm1587']),
      );
      expect(ChatViewportReadiness.messageId(merged.first), 'm1589');
      expect(
        ChatViewportReadiness.incomingIsStaleAgainstCurrent(
          current: current,
          incoming: incoming,
          useSeqContiguity: true,
        ),
        isTrue,
      );
    });
  });

  group('ChatViewportCollection initial snapshot', () {
    test('lockInitial stays on first window and rejects lastMessage half window',
        () {
      final collection = ChatViewportCollection.instance;
      const identity = SessionIdentity(ownerUserId: 'u1', generation: 1);
      collection.attach(conversationKey: 'c2c_a', identity: identity);
      final full = ChatViewportReadiness.classify(
        conversationKey: 'c2c_a',
        newestFirst: <V2TimMessage>[
          for (var i = 20; i >= 1; i--) msg(id: 'm$i', seq: i),
        ],
        useSeqContiguity: false,
        viewportHeight: 560,
        source: ChatViewportSource.local,
      );
      collection.lockInitial(full);
      final later = ChatViewportReadiness.classify(
        conversationKey: 'c2c_a',
        newestFirst: <V2TimMessage>[
          msg(id: 'm21', seq: 21),
        ],
        useSeqContiguity: false,
        viewportHeight: 560,
        source: ChatViewportSource.cloudMerged,
      );
      collection.lockInitial(later);
      expect(collection.initialState?.continuousCount, full.continuousCount);
      expect(
        collection.matchesInitialWindow(<V2TimMessage>[
          msg(id: 'm20', seq: 20),
        ]),
        isFalse,
      );
      expect(
        collection.matchesInitialWindow(<V2TimMessage>[
          for (var i = 20; i >= 1; i--) msg(id: 'm$i', seq: i),
        ]),
        isTrue,
      );
    });
  });

  group('ChatViewportCollection ticket', () {
    test('old openGeneration cannot replace current projection', () {
      final collection = ChatViewportCollection.instance;
      const identity = SessionIdentity(ownerUserId: 'u1', generation: 1);
      collection.attach(conversationKey: 'group_a', identity: identity);
      final firstGen = collection.openGeneration;
      collection.detachUi(
        conversationKey: 'group_a',
        openGeneration: firstGen,
      );
      collection.attach(conversationKey: 'group_a', identity: identity);
      final oldTicket = ChatViewportRepairTicket(
        ownerUserId: 'u1',
        accountGeneration: 1,
        conversationKey: 'group_a',
        openGeneration: firstGen,
        requestAnchorSeq: 1500,
      );
      expect(collection.acceptsTicket(oldTicket), isFalse);
      expect(collection.sameConversationCache(oldTicket), isTrue);
    });

    test('detachUi abandons that openGeneration and keeps it after reattach', () {
      final collection = ChatViewportCollection.instance;
      const identity = SessionIdentity(ownerUserId: 'u1', generation: 1);
      collection.attach(conversationKey: 'group_a', identity: identity);
      final firstGen = collection.openGeneration;
      expect(collection.isOpenGenerationAbandoned('group_a', firstGen), isFalse);
      collection.detachUi(
        conversationKey: 'group_a',
        openGeneration: firstGen,
      );
      expect(collection.isOpenGenerationAbandoned('group_a', firstGen), isTrue);
      expect(collection.isOpenGenerationAbandoned('group_a', 0), isFalse);
      collection.attach(conversationKey: 'group_a', identity: identity);
      expect(collection.isOpenGenerationAbandoned('group_a', firstGen), isTrue);
      expect(
        collection.isOpenGenerationAbandoned(
          'group_a',
          collection.openGeneration,
        ),
        isFalse,
      );
    });
  });
}
