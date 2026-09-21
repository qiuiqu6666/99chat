import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_reset_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_trust.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/open_viewport_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peek_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimMessage _msg(
  int seq, {
  String? msgID,
  String? groupID,
  String? userID,
  bool isSelf = false,
  int status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': msgID ?? 'm$seq',
    'message_server_time': 1700000000 + seq,
    'message_risk_type_identified': 0,
  })
    ..seq = '$seq'
    ..isSelf = isSelf
    ..elemType = 1
    ..timestamp = 1700000000 + seq;
  message.status = status;
  if (groupID != null) {
    message.groupID = groupID;
  }
  if (userID != null) {
    message.userID = userID;
  }
  return message;
}

List<V2TimMessage> _window(int newest, int count, {String? groupID}) =>
    List.generate(
      count,
      (i) => _msg(newest - i, groupID: groupID),
    );

ConversationPeekLoadResult _peek(
  List<V2TimMessage> messages, {
  bool receivedCloudResponse = true,
  bool hasMoreOlder = true,
}) {
  return ConversationPeekLoadResult(
    messages: messages,
    hasMoreOlder: hasMoreOlder,
    isFinished: !hasMoreOlder,
    receivedCloudResponse: receivedCloudResponse,
    batchKind: MessageHistoryBatchKind.latestWindow,
  );
}

ChatOpenViewportResult _cacheEntry(String key) {
  return ChatOpenViewportResult(
    conversationKey: key,
    mountedMessageIds: const <String>['m1'],
    anchor: const ChatViewportAnchor(msgID: 'm1', seq: 1),
    estimatedContentExtent: 800,
    viewportTargetExtent: 600,
    coverageState: ChatViewportCoverageState.readyLocal,
    isContiguous: true,
    needsLatestRepair: false,
    reachedKnownLocalBoundary: false,
    source: ChatViewportSource.cache,
    continuousCount: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TUIChatGlobalModel global;
  late ValueNotifier<NetworkReachability> network;
  late int epoch;
  var cloudCalls = 0;
  var localCalls = 0;
  Future<ConversationPeekLoadResult> Function(V2TimConversation)? cloudLoader;
  Future<ConversationPeekLoadResult> Function(V2TimConversation)? localLoader;
  var syncPending = false;
  var transportReady = true;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() {
    global = serviceLocator<TUIChatGlobalModel>();
    global.configureMessageWriterScope(
      ownerUserID: 'reset-owner',
      accountGeneration: 1,
      domainGeneration: 1,
    );
    // Provenance needs an online network state for freshness / trust.
    global.appMessageReconciliationNetworkStateProvider =
        () => MessageReconciliationNetworkState.online;
    ChatLatestWindowTrust.instance.clear();
    ChatHistoryRecoveryCoordinator.instance.resetForTest();
    ChatLatestWindowResetService.instance.resetForTest();
    ChatLatestWindowResetService.debugEnvironment = null;
    ChatViewportCollection.instance.resetForTest();
    OpenViewportCache.instance.resetForTest();
    OpenViewportCache.debugRecoveryEpochProvider = null;
    network = ValueNotifier(NetworkReachability.online);
    epoch = 3;
    cloudCalls = 0;
    localCalls = 0;
    cloudLoader = null;
    localLoader = null;
    syncPending = false;
    transportReady = true;
    ChatLatestWindowResetService.debugEnvironment = LatestWindowResetEnvironment(
      recoveryEpoch: () => epoch,
      transportReady: () => transportReady,
      serverSyncPending: () => syncPending,
      networkStatus: network,
      isIdentityCurrent: (_) => true,
      fastRetryDelays: const <Duration>[
        Duration.zero,
        Duration(milliseconds: 5),
        Duration(milliseconds: 5),
      ],
      slowRetryDelays: const <Duration>[
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
      ],
      inPagePollInterval: const Duration(milliseconds: 5),
      loadCloud: (conversation) async {
        cloudCalls++;
        final loader = cloudLoader;
        if (loader == null) {
          throw StateError('unexpected cloud load');
        }
        return loader(conversation);
      },
      loadLocal: (conversation) async {
        localCalls++;
        final loader = localLoader;
        if (loader == null) {
          throw StateError('unexpected local load');
        }
        return loader(conversation);
      },
    );
  });

  tearDown(() {
    ChatLatestWindowResetService.instance.resetForTest();
    ChatLatestWindowResetService.debugEnvironment = null;
    ChatLatestWindowTrust.instance.clear();
    ChatHistoryRecoveryCoordinator.instance.resetForTest();
    ChatViewportCollection.instance.resetForTest();
    OpenViewportCache.instance.resetForTest();
    OpenViewportCache.debugRecoveryEpochProvider = null;
    network.dispose();
  });

  V2TimConversation c2cConversation({
    required String userID,
    V2TimMessage? lastMessage,
  }) {
    return V2TimConversation(
      conversationID: 'c2c_$userID',
      type: 1,
      userID: userID,
      lastMessage: lastMessage,
    );
  }

  V2TimConversation groupConversation({
    required String groupID,
    V2TimMessage? lastMessage,
  }) {
    return V2TimConversation(
      conversationID: 'group_$groupID',
      type: 2,
      groupID: groupID,
      lastMessage: lastMessage,
    );
  }

  int attachPage(String key, {ConvType type = ConvType.c2c}) {
    global.setCurrentConversation(CurrentConversation(key, type), notify: false);
    ChatViewportCollection.instance.attach(
      conversationKey: key,
      identity: const SessionIdentity(
        ownerUserId: 'reset-owner',
        generation: 1,
      ),
      attachSource: 'test',
    );
    return ChatViewportCollection.instance.openGeneration;
  }

  group('OpenViewportCache epoch stamp', () {
    test('stale epoch makes peek return null', () {
      var current = 1;
      OpenViewportCache.debugRecoveryEpochProvider = () => current;
      OpenViewportCache.instance.put('c2c_u1', _cacheEntry('c2c_u1'));
      expect(OpenViewportCache.instance.peek('c2c_u1'), isNotNull);
      current = 2;
      expect(OpenViewportCache.instance.peek('c2c_u1'), isNull);
    });
  });

  group('offline provisional', () {
    test('fresh LOCAL contiguous window installs without trust', () async {
      network.value = NetworkReachability.offline;
      final preview = _msg(560, userID: 'u1');
      final conversation = c2cConversation(userID: 'u1', lastMessage: preview);
      final key = 'c2c_u1';
      global.setMessageList(key, _window(100, 5), replace: true);
      final openGeneration = attachPage(key);
      localLoader = (_) async => _peek(_window(560, 20), receivedCloudResponse: false);

      final outcome = await ChatLatestWindowResetService.instance.runForOpen(
        conversation: conversation,
        globalModel: global,
        openGeneration: openGeneration,
      );

      expect(outcome, LatestWindowResetOutcome.offlineProvisional);
      expect(localCalls, 1);
      expect(cloudCalls, 0);
      expect(ChatLatestWindowTrust.instance.trustedEpochFor(key), isNull);
      expect(ChatLatestWindowResetService.instance.isProvisional(key), isTrue);
      expect(global.rawMessageCount(key), 20);
      expect(global.rawMessageList(key)!.first.seq, '560');
    });

    test('group LOCAL with seq hole becomes offlineNoLocal / failed', () async {
      network.value = NetworkReachability.offline;
      final groupID = 'g_hole';
      final conversation = groupConversation(
        groupID: groupID,
        lastMessage: _msg(100, groupID: groupID),
      );
      final openGeneration = attachPage(groupID, type: ConvType.group);
      // Hole between 100 and 97.
      localLoader = (_) async => _peek(<V2TimMessage>[
            _msg(100, groupID: groupID),
            _msg(99, groupID: groupID),
            _msg(97, groupID: groupID),
          ], receivedCloudResponse: false);

      final outcome = await ChatLatestWindowResetService.instance.runForOpen(
        conversation: conversation,
        globalModel: global,
        openGeneration: openGeneration,
      );

      expect(outcome, LatestWindowResetOutcome.failed);
      expect(ChatLatestWindowTrust.instance.trustedEpochFor(groupID), isNull);
      expect(global.rawMessageCount(groupID), 0);
    });

    test('network online after offline provisional starts CLOUD reset', () async {
      network.value = NetworkReachability.offline;
      final preview = _msg(600, userID: 'u2');
      final conversation = c2cConversation(userID: 'u2', lastMessage: preview);
      final key = 'c2c_u2';
      final openGeneration = attachPage(key);
      localLoader = (_) async => _peek(_window(560, 20), receivedCloudResponse: false);

      expect(
        await ChatLatestWindowResetService.instance.runForOpen(
          conversation: conversation,
          globalModel: global,
          openGeneration: openGeneration,
        ),
        LatestWindowResetOutcome.offlineProvisional,
      );
      expect(ChatLatestWindowTrust.instance.trustedEpochFor(key), isNull);

      final cloudDone = Completer<void>();
      cloudLoader = (_) async {
        cloudDone.complete();
        return _peek(_window(600, 20));
      };
      global.setMessageListPosition(key, HistoryMessagePosition.bottom);
      global.setFollowingLatest(key, true, notify: false);

      network.value = NetworkReachability.online;
      await cloudDone.future.timeout(const Duration(seconds: 2));
      final inFlight =
          ChatLatestWindowResetService.instance.inFlightFutureFor(key);
      expect(inFlight, isNotNull);
      final onlineOutcome = await inFlight!
          .timeout(const Duration(seconds: 2));
      expect(onlineOutcome, LatestWindowResetOutcome.trusted);
      expect(ChatLatestWindowTrust.instance.trustedEpochFor(key), epoch);
      expect(global.rawMessageList(key)!.first.seq, '600');
      // Must replace the offline provisional window, not append across a hole.
      expect(global.rawMessageCount(key), lessThanOrEqualTo(20));
      expect(cloudCalls, greaterThan(0));
    });
  });

  group('in-page position recheck', () {
    test('user scrolls away during fetch → deferred, no restamp', () async {
      final preview = _msg(600, userID: 'u3');
      final conversation = c2cConversation(userID: 'u3', lastMessage: preview);
      final key = 'c2c_u3';
      final openGeneration = attachPage(key);
      // Seed a distinct old window so we can detect unwanted restamp.
      global.setMessageList(key, _window(100, 5), replace: true);
      global.setMessageListPosition(key, HistoryMessagePosition.bottom);
      global.setFollowingLatest(key, true, notify: false);

      final gate = Completer<void>();
      cloudLoader = (_) async {
        await gate.future;
        return _peek(_window(600, 20));
      };

      final future = ChatLatestWindowResetService.instance.runInPage(
        conversation: conversation,
        globalModel: global,
        openGeneration: openGeneration,
        reason: 'test_scroll_away',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cloudCalls, 1);

      // Leave the bottom while the request is in flight.
      global.setFollowingLatest(key, false, notify: false);
      global.setMessageListPosition(key, HistoryMessagePosition.notShowLatest);
      gate.complete();

      expect(await future, LatestWindowResetOutcome.deferred);
      expect(global.rawMessageList(key)!.first.seq, '100');
      expect(ChatLatestWindowTrust.instance.trustedEpochFor(key), isNull);
    });
  });

  group('operation token supersession', () {
    test('old async callback must not install after openGeneration bumps',
        () async {
      final preview = _msg(600, userID: 'u4');
      final conversation = c2cConversation(userID: 'u4', lastMessage: preview);
      final key = 'c2c_u4';
      final firstGeneration = attachPage(key);
      global.setMessageList(key, _window(100, 5), replace: true);

      final gate = Completer<void>();
      cloudLoader = (_) async {
        await gate.future;
        return _peek(_window(600, 20));
      };

      final first = ChatLatestWindowResetService.instance.runForOpen(
        conversation: conversation,
        globalModel: global,
        openGeneration: firstGeneration,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // New open takes over: detach abandons the old generation, then attach
      // bumps openGeneration so the in-flight op is no longer current.
      ChatViewportCollection.instance.detachUi(
        conversationKey: key,
        openGeneration: firstGeneration,
      );
      final secondGeneration = attachPage(key);
      expect(secondGeneration, greaterThan(firstGeneration));
      gate.complete();

      expect(await first, isNot(LatestWindowResetOutcome.trusted));
      // Stale op must not have installed the cloud window.
      expect(global.rawMessageList(key)?.first.seq, isNot('600'));
    });
  });

  group('single-owner wipe', () {
    test('windowAlreadyCleared prevents a second removeMessageList', () async {
      final preview = _msg(600, userID: 'u5');
      final conversation = c2cConversation(userID: 'u5', lastMessage: preview);
      final key = 'c2c_u5';
      final openGeneration = attachPage(key);
      global.setMessageList(key, _window(100, 5), replace: true);
      // Mimic prepareOpenViewport: wipe once outside the service, then hand
      // ownership with windowAlreadyCleared so the service must not wipe again.
      global.removeMessageList(key);
      final wipesBefore =
          ChatLatestWindowResetService.instance.debugWipeInvocations;

      cloudLoader = (_) async => _peek(_window(600, 20));
      final outcome = await ChatLatestWindowResetService.instance.runForOpen(
        conversation: conversation,
        globalModel: global,
        openGeneration: openGeneration,
        windowAlreadyCleared: true,
      );

      expect(outcome, LatestWindowResetOutcome.trusted);
      expect(
        ChatLatestWindowResetService.instance.debugWipeInvocations,
        wipesBefore,
      );
      expect(global.rawMessageList(key)!.first.seq, '600');
    });

    test('without windowAlreadyCleared the service wipes exactly once',
        () async {
      final preview = _msg(600, userID: 'u5b');
      final conversation = c2cConversation(userID: 'u5b', lastMessage: preview);
      final key = 'c2c_u5b';
      final openGeneration = attachPage(key);
      global.setMessageList(key, _window(100, 5), replace: true);
      final wipesBefore =
          ChatLatestWindowResetService.instance.debugWipeInvocations;

      cloudLoader = (_) async => _peek(_window(600, 20));
      final outcome = await ChatLatestWindowResetService.instance.runForOpen(
        conversation: conversation,
        globalModel: global,
        openGeneration: openGeneration,
      );

      expect(outcome, LatestWindowResetOutcome.trusted);
      expect(
        ChatLatestWindowResetService.instance.debugWipeInvocations,
        wipesBefore + 1,
      );
    });
  });

  group('slow retry keeps operation alive', () {
    test('operation stays in-flight past the fast attempts', () async {
      final preview = _msg(600, userID: 'u6');
      final conversation = c2cConversation(userID: 'u6', lastMessage: preview);
      final key = 'c2c_u6';
      final openGeneration = attachPage(key);

      // First three cloud attempts mismatch; fourth hangs until we release it
      // so the operation is observably still alive after the fast budget.
      final fourthGate = Completer<void>();
      cloudLoader = (_) async {
        if (cloudCalls < 4) {
          return _peek(_window(100, 20)); // behind preview → edge mismatch
        }
        await fourthGate.future;
        return _peek(_window(600, 20));
      };

      final future = ChatLatestWindowResetService.instance.runForOpen(
        conversation: conversation,
        globalModel: global,
        openGeneration: openGeneration,
      );
      // Wait until the fourth attempt has started (past 0/5/5ms fast delays).
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        ChatLatestWindowResetService.instance.isResetInFlight(key),
        isTrue,
      );
      expect(cloudCalls, greaterThanOrEqualTo(4));
      fourthGate.complete();
      expect(await future.timeout(const Duration(seconds: 2)),
          LatestWindowResetOutcome.trusted);
      expect(ChatLatestWindowTrust.instance.trustedEpochFor(key), epoch);
    });
  });
}
