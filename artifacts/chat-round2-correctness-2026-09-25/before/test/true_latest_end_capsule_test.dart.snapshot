import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/back_to_bottom_capsule_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/true_latest_end.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TUIChatGlobalModel global;
  late String conv;
  var generation = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() {
    global = serviceLocator<TUIChatGlobalModel>();
    conv = '@TGS#true_latest_${++generation}';
    global.configureMessageWriterScope(
      ownerUserID: 'true-latest-reader',
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
    global.setFollowingLatest(conv, true, notify: false);
    global.setMessageListPosition(
      conv,
      HistoryMessagePosition.bottom,
      notify: false,
    );
  });

  tearDown(() {
    global.clearCurrentConversation();
    global.invalidateBoundedHistorySessions();
  });

  test('true latest end is the three-part conjunction', () {
    expect(
      TrueLatestEnd.atTrueLatestEnd(
        atListEnd: true,
        latestRowMaterialized: true,
        hasMissingNewer: false,
      ),
      isTrue,
    );
    expect(
      TrueLatestEnd.atTrueLatestEnd(
        atListEnd: true,
        latestRowMaterialized: true,
        hasMissingNewer: true,
      ),
      isFalse,
    );
    expect(
      TrueLatestEnd.isLatestRowMaterialized(
        latestConfirmedIdentityInBuiltList: true,
      ),
      isTrue,
    );
    expect(
      TrueLatestEnd.isLatestRowMaterialized(
        latestConfirmedIdentityInBuiltList: false,
      ),
      isFalse,
    );
  });

  test('following at true latest end admits a message with N=0 and no capsule',
      () async {
    await global.applyAppRealtimeMessage(_message(conv, 2));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(global.rawMessageList(conv)!.first.msgID, '$conv-2');
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.isFollowingLatest(conv), isTrue);
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: true,
        hasMissingNewer: false,
        liveUnreadCount: global.receivedNewMessageCountFor(conv),
        leftBottomByOneScreen: false,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isFalse,
    );
  });

  test('leaving latest counts 3 until their rows are visibly acknowledged',
      () async {
    global.setFollowingLatest(conv, false, notify: false);
    global.setMessageListPosition(
      conv,
      HistoryMessagePosition.awayTwoScreen,
      notify: false,
    );
    final incoming = [
      _message(conv, 2),
      _message(conv, 3),
      _message(conv, 4),
    ];
    for (final message in incoming) {
      await global.applyAppRealtimeMessage(message);
    }
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(global.remainingLiveIncomingCountFor(conv), 3);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: false,
        distanceFromLatestEdge: 400,
        viewportDimension: 800,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isTrue,
    );
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: false,
        distanceFromLatestEdge: 30,
        viewportDimension: 800,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isFalse,
    );

    await global.acknowledgeVisibleHistoryMessages(
      conv,
      incoming,
      isCurrent: () => true,
    );
    expect(
      global.remainingLiveIncomingCountFor(conv),
      0,
      reason: 'visible receipt must settle the three read identities',
    );
  });

  test('settle at true latest end zeros N once and restores following', () async {
    global.setFollowingLatest(conv, false, notify: false);
    global.setMessageListPosition(
      conv,
      HistoryMessagePosition.awayTwoScreen,
      notify: false,
    );
    for (var id = 2; id <= 4; id++) {
      await global.applyAppRealtimeMessage(_message(conv, id));
    }
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(global.remainingLiveIncomingCountFor(conv), 3);

    global.settleAtTrueLatestEnd(conv);
    expect(global.remainingLiveIncomingCountFor(conv), 0);
    expect(global.isFollowingLatest(conv), isTrue);
    expect(
      global.getMessageListPosition(conv),
      HistoryMessagePosition.bottom,
    );
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: true,
        hasMissingNewer: false,
        liveUnreadCount: 0,
        leftBottomByOneScreen: false,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isFalse,
    );
  });

  test('fake list end with missing newer never treats N as settled', () {
    expect(
      TrueLatestEnd.atTrueLatestEnd(
        atListEnd: true,
        latestRowMaterialized: true,
        hasMissingNewer: true,
      ),
      isFalse,
    );
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: false,
        hasMissingNewer: true,
        liveUnreadCount: 3,
        leftBottomByOneScreen: false,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isTrue,
    );
  });

  test('geometry viewport transition does not leave following or create N',
      () async {
    expect(global.isFollowingLatest(conv), isTrue);
    global.beginGeometryViewportTransition(conv);
    await global.applyAppRealtimeMessage(_message(conv, 2));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(global.isFollowingLatest(conv), isTrue);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.rawMessageList(conv)!.first.msgID, '$conv-2');
    global.endGeometryViewportTransition(conv);
    expect(global.isFollowingLatest(conv), isTrue);
    expect(global.receivedNewMessageCountFor(conv), 0);
  });

  test('nested geometry begin/end refuses leave until depth returns to zero',
      () {
    expect(global.isFollowingLatest(conv), isTrue);
    global.beginGeometryViewportTransition(conv);
    global.beginGeometryViewportTransition(conv);
    expect(global.isGeometryViewportTransitionActive(conv), isTrue);
    global.endGeometryViewportTransition(conv);
    expect(global.isGeometryViewportTransitionActive(conv), isTrue);
    global.setFollowingLatest(conv, false, notify: false);
    expect(global.isFollowingLatest(conv), isTrue);
    global.endGeometryViewportTransition(conv);
    expect(global.isGeometryViewportTransitionActive(conv), isFalse);
    expect(global.isFollowingLatest(conv), isTrue);
  });

  test('user drag overrides the geometry latch so leaving latest is honored',
      () {
    expect(global.isFollowingLatest(conv), isTrue);
    global.beginGeometryViewportTransition(conv);
    expect(global.isGeometryViewportTransitionActive(conv), isTrue);
    // 生产路径：用户上手拖拽 = setChatListUserScrolling(true)，
    // 它先清掉键盘期"曾在底"快照，再覆盖几何闸门。
    global.setChatListUserScrolling(true);
    expect(global.isGeometryViewportTransitionActive(conv), isFalse);
    global.setFollowingLatest(conv, false, notify: false);
    expect(global.isFollowingLatest(conv), isFalse);
    global.setChatListUserScrolling(false);
    global.endGeometryViewportTransition(conv);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(global.isGeometryViewportTransitionActive(conv), isFalse);
    // 新一轮几何边沿重新受保护。
    global.beginGeometryViewportTransition(conv);
    expect(global.isGeometryViewportTransitionActive(conv), isTrue);
    global.endGeometryViewportTransition(conv);
    expect(global.isGeometryViewportTransitionActive(conv), isFalse);
  });

  test('leaving the conversation resets a leaked geometry latch', () {
    global.beginGeometryViewportTransition(conv);
    expect(global.isGeometryViewportTransitionActive(conv), isTrue);
    // 键盘开着退出页面：协调器不会补发 onEnd。
    global.clearCurrentConversation();
    expect(global.isGeometryViewportTransitionActive(conv), isFalse);
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
    global.setFollowingLatest(conv, true, notify: false);
    global.setFollowingLatest(conv, false, notify: false);
    expect(global.isFollowingLatest(conv), isFalse);
    // 迟到的 onEnd 无害。
    global.endGeometryViewportTransition(conv);
    expect(global.isGeometryViewportTransitionActive(conv), isFalse);
    expect(global.isFollowingLatest(conv), isFalse);
  });

  test('tap-at-end with stale N settles and does not keep a leave latch', () {
    global.setFollowingLatest(conv, false, notify: false);
    global.receivedNewMessageCount = 5;
    expect(global.receivedNewMessageCountFor(conv), 5);

    global.settleAtTrueLatestEnd(conv);

    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.isFollowingLatest(conv), isTrue);
    expect(
      BackToBottomCapsulePolicy.shouldShow(
        atTrueLatestEnd: true,
        hasMissingNewer: false,
        liveUnreadCount: 0,
        leftBottomByOneScreen: true,
        presentationBottomLocked: false,
        programmaticScrollToBottom: false,
      ),
      isFalse,
      reason: 'true latest end must win over a stale one-screen leave latch',
    );
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
