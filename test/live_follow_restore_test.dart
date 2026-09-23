import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TUIChatGlobalModel global;
  late TUIChatSeparateViewModel model;
  late String conv;
  var generation = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() {
    global = serviceLocator<TUIChatGlobalModel>();
    conv = '@TGS#live_follow_${++generation}';
    global.configureMessageWriterScope(
      ownerUserID: 'live-follow-reader',
      accountGeneration: generation,
      domainGeneration: 1,
    );
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
    global.setMessageList(
      conv,
      [_message(conv, 1)],
      replace: true,
      applyMemoryWindow: false,
    );
    global.setFollowingLatest(conv, false, notify: false);
    global.setMessageListPosition(
      conv,
      HistoryMessagePosition.awayTwoScreen,
      notify: false,
    );
    model = TUIChatSeparateViewModel()
      ..conversationID = conv
      ..suppressReadReporting = true;
    global.bindHistoryLiveWindowFreeze(
      conversationID: conv,
      freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
    );
    model.freezeVisibleHistoryWindowIfNeeded();
  });

  Future<void> waitUntil(bool Function() ready) async {
    for (var i = 0; i < 25; i++) {
      if (ready()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  tearDown(() {
    global.clearCurrentConversation();
    global.invalidateBoundedHistorySessions();
    model.dispose();
  });

  test('buffer records remaining; ACK does not change it', () async {
    final first = _message(conv, 2);
    await global.applyAppRealtimeMessage(first);
    await waitUntil(() => global.remainingLiveIncomingCountFor(conv) == 1);
    expect(global.remainingLiveIncomingCountFor(conv), 1);
    expect(global.liveReceiveGenerationFor(conv), greaterThan(0));
    final gen = global.liveReceiveGenerationFor(conv);

    await global.acknowledgeVisibleHistoryMessages(
      conv,
      [first],
      isCurrent: () => true,
    );
    expect(global.remainingLiveIncomingCountFor(conv), 1);
    expect(global.liveReceiveGenerationFor(conv), gen);
  });

  test('markLiveIncomingSeen reduces remaining and is visit-permanent',
      () async {
    final first = _message(conv, 2);
    await global.applyAppRealtimeMessage(first);
    await waitUntil(() => global.remainingLiveIncomingCountFor(conv) == 1);
    global.markLiveIncomingSeen(
      conversationID: conv,
      ids: [TUIChatGlobalModel.liveIncomingIdentity(first)],
    );
    expect(global.remainingLiveIncomingCountFor(conv), 0);

    global.settleAtTrueLatestEnd(conv);
    expect(global.remainingLiveIncomingCountFor(conv), 0);
    global.setFollowingLatest(conv, false, notify: false);
    await global.applyAppRealtimeMessage(first);
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) > 0 ||
        global.liveReceiveGenerationFor(conv) > 0);
    expect(global.remainingLiveIncomingCountFor(conv), 0);
  });

  test('buffer-only arrival increments receive generation', () async {
    final before = global.liveReceiveGenerationFor(conv);
    await global.applyAppRealtimeMessage(_message(conv, 2));
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) == 1);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect(global.liveReceiveGenerationFor(conv), greaterThan(before));
    expect(global.unadmittedRemainingLiveCountFor(conv), 1);
  });

  test('N can stay positive after all live rows are admitted', () async {
    await global.applyAppRealtimeMessage(_message(conv, 2));
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) == 1);
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isTrue);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    expect(global.unadmittedRemainingLiveCountFor(conv), 0);
    expect(global.remainingLiveIncomingCountFor(conv), greaterThan(0));
  });

  test('revealing 8 of 20 keeps CATCHING UP and refuses COMMIT', () async {
    for (var id = 2; id <= 21; id++) {
      await global.applyAppRealtimeMessage(_message(conv, id));
    }
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) == 20);
    expect(global.deferredIncomingBufferedCount(conv), 20);
    expect(model.revealBufferedIncomingTowardLatest(limit: 8, skipCooldown: true),
        isTrue);
    global.endAttachingBufferedTowardLatest();
    expect(global.deferredIncomingBufferedCount(conv), 12);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(model.restoreTowardLatestFromUserScroll(revealLimit: 8), isFalse);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(
      model.commitLiveFollowRestore(
        visit: global.unreadVisitGenerationFor(conv),
        restoreOpId: global.beginLiveFollowRestoreOp(conv),
        liveReceiveGeneration: global.liveReceiveGenerationFor(conv),
        targetTipId: '$conv-9',
        coveredIds: global.remainingLiveIncomingIdsFor(conv),
      ),
      isFalse,
    );
    expect(global.isFollowingLatest(conv), isFalse);
  });

  test('COMMIT succeeds with N=12 after all live rows are admitted', () async {
    for (var id = 2; id <= 13; id++) {
      await global.applyAppRealtimeMessage(_message(conv, id));
    }
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) == 12);
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isTrue);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    expect(global.remainingLiveIncomingCountFor(conv), 12);
    final idsBefore =
        global.rawMessageList(conv)!.map((m) => m.msgID).toList();
    var modelNotifies = 0;
    model.addListener(() => modelNotifies++);
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
    expect(modelNotifies, 1);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.hasDurableHistoryDeferred(conv), isFalse);
  });

  test('partial coverage cannot restore FOLLOW or clear unread', () async {
    for (var id = 2; id <= 3; id++) {
      await global.applyAppRealtimeMessage(_message(conv, id));
    }
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) == 2);
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isTrue);
    final before = global.receivedNewMessageCountFor(conv);
    expect(model.commitLiveFollowRestore(
      visit: global.unreadVisitGenerationFor(conv),
      restoreOpId: global.beginLiveFollowRestoreOp(conv),
      liveReceiveGeneration: global.liveReceiveGenerationFor(conv),
      coveredIds: {'$conv-2'},
    ), isFalse);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(global.remainingLiveIncomingCountFor(conv), 2);
    expect(global.receivedNewMessageCountFor(conv), before);
  });

  test('buffer-only arrival invalidates a stale COMMIT snapshot', () async {
    await global.applyAppRealtimeMessage(_message(conv, 2));
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) == 1);
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isTrue);
    final staleGen = global.liveReceiveGenerationFor(conv);
    await global.applyAppRealtimeMessage(_message(conv, 3));
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) == 1);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect(global.liveReceiveGenerationFor(conv), greaterThan(staleGen));
    expect(
      model.commitLiveFollowRestore(
        visit: global.unreadVisitGenerationFor(conv),
        restoreOpId: global.beginLiveFollowRestoreOp(conv),
        liveReceiveGeneration: staleGen,
        targetTipId: '$conv-2',
        coveredIds: global.remainingLiveIncomingIdsFor(conv),
      ),
      isFalse,
    );
    expect(global.isFollowingLatest(conv), isFalse);
  });

  test('COMMIT keeps a trailing SENDING row in the visible sequence', () async {
    await global.applyAppRealtimeMessage(_message(conv, 2));
    await waitUntil(() => global.deferredIncomingBufferedCount(conv) == 1);
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isTrue);
    final sending = _message(conv, 99)
      ..isSelf = true
      ..status = 1;
    global.setMessageList(
      conv,
      [sending, ...?global.rawMessageList(conv)],
      replace: true,
      applyMemoryWindow: false,
    );
    final idsBefore =
        global.rawMessageList(conv)!.map((m) => m.msgID).toList();
    expect(
      model.commitLiveFollowRestore(
        visit: global.unreadVisitGenerationFor(conv),
        restoreOpId: global.beginLiveFollowRestoreOp(conv),
        liveReceiveGeneration: global.liveReceiveGenerationFor(conv),
        targetTipId: '$conv-2',
        coveredIds: global.remainingLiveIncomingIdsFor(conv),
      ),
      isTrue,
    );
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), idsBefore);
    expect(global.rawMessageList(conv)!.first.status, 1);
  });
}

V2TimMessage _message(String conv, int id) => V2TimMessage.fromJson({
      'message_msg_id': '$conv-$id',
      'message_server_time': id,
      'message_risk_type_identified': 0,
    })
      ..groupID = conv
      ..seq = '$id'
      ..isSelf = false
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: '$id');
