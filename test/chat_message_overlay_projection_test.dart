import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_bubble_insert_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/utils/chat_message_overlay_projection.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimMessage text(int timestamp) => V2TimMessage.fromJson({
      'message_msg_id': 'sdk-$timestamp',
      'message_server_time': timestamp,
      'message_risk_type_identified': 0,
    })
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'text $timestamp');

V2TimMessage call(int timestamp) =>
    CallBubbleInsertService.buildTerminalBubbleMessage(CallResultRecord(
      callId: 'range-call',
      conversationId: 'c2c_peer',
      callerUserId: 'peer',
      operatorUserId: 'peer',
      peerUserId: 'peer',
      protocolType: CallProtocolType.hangup,
      durationSec: 12,
      endedAtMs: timestamp * 1000,
      isOutgoing: false,
    ))!;

List<V2TimMessage> realRows(List<V2TimMessage> rows) =>
    rows.where((m) => m.elemType != 11).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUpAll(setupServiceLocator);

  test('scrolling inside the same SDK window retains its newest local call',
      () async {
    final global = TUIChatGlobalModel();
    const conversationID = 'c2c_peer';
    final sdk = [text(30), text(20)];
    final newer = call(40);
    global.setMessageList(conversationID, sdk, replace: true);
    List<V2TimMessage> projected() => realRows(projectChatMessageOverlays(
        formalMessages: sdk,
        overlays: [newer],
        olderHistoryExhausted: false,
        includesLatestEdge: !global.memoryWindowMissingNewer(conversationID)));
    expect(projected().first.msgID, newer.msgID);
    global.setMessageListPosition(
        conversationID, HistoryMessagePosition.awayTwoScreen,
        notify: false);
    expect(global.getMessageListPosition(conversationID),
        HistoryMessagePosition.awayTwoScreen);
    expect(projected().first.msgID, newer.msgID);
    // An actual older/search window lacking the newest data still excludes it.
    global.markMemoryWindowMissingNewer(conversationID);
    expect(projected().any((m) => m.msgID == newer.msgID), isFalse);
    // Keep the real page wired to data coverage rather than scroll position.
    final wiring =
        RegExp(r'includesLatestEdge:([\s\S]*?)dividerIntervalSeconds:')
            .firstMatch(File('lib/src/chat.dart').readAsStringSync())!
            .group(1)!;
    expect(
        wiring, contains('!global.memoryWindowMissingNewer(conversationID)'));
    expect(wiring, isNot(contains('getMessageListPosition')));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    global.dispose();
  });

  test(
      'an old call waits for its SDK time range instead of following each page tail',
      () {
    final overlay = call(15);
    final sdk = List.generate(100, (i) => text(100 - i));
    for (final count in [20, 40, 60, 80]) {
      final page = sdk.take(count).toList();
      final displayed = projectChatMessageOverlays(
          formalMessages: page,
          overlays: [overlay],
          olderHistoryExhausted: false,
          includesLatestEdge: true);
      expect(displayed, same(page));
      expect(displayed.any((m) => m.msgID == overlay.msgID), isFalse);
    }
    final displayed = projectChatMessageOverlays(
        formalMessages: sdk,
        overlays: [overlay],
        olderHistoryExhausted: false,
        includesLatestEdge: true);
    final rows = realRows(displayed);
    expect(rows.where((m) => m.msgID == overlay.msgID), hasLength(1));
    final index = rows.indexWhere((m) => m.msgID == overlay.msgID);
    expect(rows[index - 1].timestamp, greaterThanOrEqualTo(15));
    expect(rows[index + 1].timestamp, lessThanOrEqualTo(15));
    expect(rows.where((m) => m.elemType == 1), hasLength(100));
  });

  test(
      'SDK exhaustion retains call-only older history and the latest edge retains new calls',
      () {
    final older = call(5);
    final sdk = [text(30), text(20)];
    final fullHistory = realRows(projectChatMessageOverlays(
        formalMessages: sdk,
        overlays: [older],
        olderHistoryExhausted: true,
        includesLatestEdge: true));
    expect(fullHistory.last.msgID, older.msgID);
    final newer = call(40);
    expect(
        realRows(projectChatMessageOverlays(
                formalMessages: sdk,
                overlays: [newer],
                olderHistoryExhausted: false,
                includesLatestEdge: true))
            .first
            .msgID,
        newer.msgID);
    expect(
        projectChatMessageOverlays(
            formalMessages: sdk,
            overlays: [newer],
            olderHistoryExhausted: false,
            includesLatestEdge: false),
        same(sdk));
    expect(
        realRows(projectChatMessageOverlays(
                formalMessages: [],
                overlays: [older],
                olderHistoryExhausted: true,
                includesLatestEdge: true))
            .single
            .msgID,
        older.msgID);
    expect(
        realRows(projectChatMessageOverlays(
                formalMessages: [],
                overlays: [older],
                olderHistoryExhausted: false,
                includesLatestEdge: false))
            .single
            .msgID,
        older.msgID);
  });

  test(
      'SDK and local records for the same call render one correctly ordered bubble',
      () {
    final local = call(25);
    final sdkCall = V2TimMessage.fromJson(local.toJson())
      ..msgID = 'sdk-call'
      ..id = 'sdk-call'
      ..localCustomData = '';
    final displayed = realRows(projectChatMessageOverlays(
        formalMessages: [text(30), sdkCall, text(20)],
        overlays: [local],
        olderHistoryExhausted: false,
        includesLatestEdge: true));
    expect(displayed.map((m) => m.msgID), ['sdk-30', 'sdk-call', 'sdk-20']);
    expect(CallingMessageDataProvider(displayed[1]).protocolType,
        CallProtocolType.hangup);
  });
}
