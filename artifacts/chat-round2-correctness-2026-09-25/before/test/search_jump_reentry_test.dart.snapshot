import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

class _DeferredSearchModel extends TUIChatSeparateViewModel {
  final response = Completer<bool>();
  MessageAnchor? requestedAnchor;

  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}

  @override
  void initForEachConversation(ConvType convType, String convID,
      ValueChanged<String>? onChangeInputField,
      {String? groupID,
      String? groupType,
      List<V2TimGroupMemberFullInfo?>? preGroupMemberList}) {
    // Production init strips the UI conversation prefix before SDK calls.
    conversationID = convID.startsWith('c2c_') ? convID.substring(4) : convID;
    conversationType = convType;
  }

  @override
  Future<bool> loadListForSpecificMessage(
      {MessageAnchor? anchor,
      int? seq,
      V2TimMessage? targetMessage,
      int? searchJumpRequest}) {
    requestedAnchor = anchor;
    if (searchJumpRequest != null &&
        !globalModel.isCurrentSearchJumpRequest(
            conversationID, searchJumpRequest)) {
      return Future.value(false);
    }
    return response.future;
  }
}

V2TimMessage _message(String id) => V2TimMessage.fromJson({
      'message_risk_type_identified': 0,
    })
      ..msgID = id
      ..seq = id == 'a' ? '100' : '200'
      ..elemType = 1
      ..timestamp = 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  TIMUIKitChatProviderScope open(
      String conv, String id, _DeferredSearchModel model,
      {ConvType type = ConvType.group}) {
    final target = _message(id);
    return TIMUIKitChatProviderScope(
      model: model,
      conversationID: conv,
      conversationType: type,
      initFindingMsg: target,
      searchJumpAnchor: MessageAnchor(
          conversationID: conv,
          convType: type.index,
          msgID: id,
          seq: target.seq),
      builder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  test('C2C route and SDK peer share jump request and terminal status', () {
    final global = serviceLocator<TUIChatGlobalModel>();
    const route = 'c2c_n3ed0ljxtg';
    const peer = 'n3ed0ljxtg';
    final request = global.beginSearchJump(route);
    expect(global.searchJumpRequestFor(peer), request);
    expect(global.isCurrentSearchJumpRequest(peer, request), isTrue);
    expect(global.getSearchJumpStatus(peer), SearchJumpStatus.loading);
    global.setSearchJumpStatus(peer, SearchJumpStatus.positioning,
        requestID: request);
    expect(global.getSearchJumpStatus(route), SearchJumpStatus.positioning);
    global.setSearchJumpStatus(route, SearchJumpStatus.failed,
        requestID: request);
    expect(global.getSearchJumpStatus(peer), SearchJumpStatus.failed);
    final next = global.beginSearchJump(peer);
    expect(next, greaterThan(request));
    global.setSearchJumpStatus(route, SearchJumpStatus.success,
        requestID: request);
    expect(global.getSearchJumpStatus(peer), SearchJumpStatus.loading);
    global.clearSearchJumpStatus(route);
    expect(global.getSearchJumpStatus(peer), SearchJumpStatus.idle);
  });

  test('real C2C loader accepts the route request under its SDK peer ID',
      () async {
    const route = 'c2c_real_search_peer';
    const peer = 'real_search_peer';
    final global = serviceLocator<TUIChatGlobalModel>();
    final request = global.beginSearchJump(route);
    final target = _message('real-target');
    final model = TUIChatSeparateViewModel()
      ..conversationID = peer
      ..conversationType = ConvType.c2c
      ..suppressReadReporting = true
      ..chatConfig = const TIMUIKitChatConfig(
          isAutoReportRead: false, isShowReadingStatus: false);
    // No SDK account is configured in this fixture. Both neighbouring reads
    // are unavailable; the clicked message is still a usable target window.
    final loaded = await model.loadListForSpecificMessage(
      anchor: MessageAnchor(
          conversationID: route, convType: 1, msgID: target.msgID),
      targetMessage: target,
      searchJumpRequest: request,
    );
    expect(loaded, isTrue);
    expect(global.rawMessageList(route)!.single.msgID, target.msgID);
    expect(global.rawMessageList(peer)!.single.msgID, target.msgID);
    global.setSearchJumpStatus(peer, SearchJumpStatus.success,
        requestID: request);
    expect(global.getSearchJumpStatus(route), SearchJumpStatus.success);
    model.dispose();
  });

  test('group aliases share status without colliding with a C2C peer', () {
    final global = serviceLocator<TUIChatGlobalModel>();
    final request = global.beginSearchJump('group_@TGS#alias_search');
    expect(global.searchJumpRequestFor('@TGS#alias_search'), request);
    global.setSearchJumpStatus('@TGS#alias_search', SearchJumpStatus.success,
        requestID: request);
    expect(global.getSearchJumpStatus('group_@TGS#alias_search'),
        SearchJumpStatus.success);
    expect(
        global.getSearchJumpStatus('c2c_alias_search'), SearchJumpStatus.idle);
  });

  testWidgets('C2C search exception releases loading immediately',
      (tester) async {
    const conv = 'c2c_failure_peer';
    final global = serviceLocator<TUIChatGlobalModel>();
    final model = _DeferredSearchModel();
    open(conv, 'a', model, type: ConvType.c2c);
    await tester.pump(const Duration(milliseconds: 1));
    model.response.completeError(StateError('SDK failure'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(global.getSearchJumpStatus(conv), SearchJumpStatus.failed);
    expect(tester.takeException(), isNull);
    model.dispose();
  });

  testWidgets(
      'C2C search timeout cannot leave loading or overwrite the next jump',
      (tester) async {
    const conv = 'c2c_timeout_peer';
    final global = serviceLocator<TUIChatGlobalModel>();
    final first = _DeferredSearchModel();
    open(conv, 'a', first, type: ConvType.c2c);
    await tester.pump(const Duration(milliseconds: 1));
    expect(global.getSearchJumpStatus(conv), SearchJumpStatus.loading);
    await tester.pump(const Duration(seconds: 12));
    expect(global.getSearchJumpStatus(conv), SearchJumpStatus.failed);
    final second = _DeferredSearchModel();
    open(conv, 'b', second, type: ConvType.c2c);
    await tester.pump(const Duration(milliseconds: 1));
    global.setMessageList(conv, [_message('b')],
        replace: true, applyMemoryWindow: false);
    second.response.complete(true);
    await tester.pump(const Duration(milliseconds: 1));
    first.response.complete(true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(global.getSearchJumpStatus(conv), SearchJumpStatus.positioning);
    expect(global.messageListMap[conv]!.single.msgID, 'b');
    first.dispose();
    second.dispose();
  });

  test('failed request cannot enter the around-window loader again', () async {
    const conv = 'c2c_cancelled_peer';
    final global = serviceLocator<TUIChatGlobalModel>();
    final request = global.beginSearchJump(conv);
    global.setSearchJumpStatus(conv, SearchJumpStatus.failed,
        requestID: request);
    final model = TUIChatSeparateViewModel()
      ..conversationID = conv
      ..conversationType = ConvType.c2c;
    expect(
        await model.loadListForSpecificMessage(
            targetMessage: _message('a'), searchJumpRequest: request),
        isFalse);
    model.dispose();
  });

  test('second click cannot consume success from the previous window',
      () async {
    const conv = '@TGS#reentry';
    final global = serviceLocator<TUIChatGlobalModel>();
    final first = _DeferredSearchModel();
    open(conv, 'a', first);
    await Future<void>.delayed(Duration.zero);
    global.setMessageList(conv, [_message('a'), _message('b')],
        replace: true, applyMemoryWindow: false);
    first.response.complete(true);
    await Future<void>.delayed(Duration.zero);
    global.setSearchJumpStatus(conv, SearchJumpStatus.success);
    final previousRequest = global.searchJumpRequestFor(conv);

    final second = _DeferredSearchModel();
    open(conv, 'b', second);
    // This assertion runs before the deferred SDK load or first page frame.
    expect(global.getSearchJumpStatus(conv), SearchJumpStatus.loading);
    expect(global.searchJumpRequestFor(conv), greaterThan(previousRequest));
    await Future<void>.delayed(Duration.zero);
    expect(second.requestedAnchor?.msgID, 'b');
    global.setMessageList(conv, [_message('b')],
        replace: true, applyMemoryWindow: false);
    second.response.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(global.getSearchJumpStatus(conv), SearchJumpStatus.positioning);
    global.setSearchJumpStatus(conv, SearchJumpStatus.success,
        requestID: previousRequest);
    expect(global.getSearchJumpStatus(conv), SearchJumpStatus.positioning);
    first.dispose();
    second.dispose();
  });

  test('late failure from an earlier click cannot replace the new window',
      () async {
    const conv = '@TGS#reentry_race';
    final global = serviceLocator<TUIChatGlobalModel>();
    final first = _DeferredSearchModel();
    open(conv, 'a', first);
    await Future<void>.delayed(Duration.zero);
    final second = _DeferredSearchModel();
    open(conv, 'b', second);
    await Future<void>.delayed(Duration.zero);
    global.setMessageList(conv, [_message('b')],
        replace: true, applyMemoryWindow: false);
    second.response.complete(true);
    await Future<void>.delayed(Duration.zero);
    first.response.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(global.getSearchJumpStatus(conv), SearchJumpStatus.positioning);
    expect(global.messageListMap[conv]!.single.msgID, 'b');
    first.dispose();
    second.dispose();
  });
}
