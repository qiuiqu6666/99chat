import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/restore_work_pacer.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_page_ui_notifiers.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
  });

  test('loading animation cannot starve recovery, explicit interaction can',
      () {
    var now = DateTime(2026);
    var foreground = true;
    final gate = BackgroundMediaGate(
      platformBusy: () => true,
      isForeground: () => foreground,
      now: () => now,
    );
    for (var i = 0; i < 10; i++) {
      expect(gate.canStart, false);
      now = now.add(const Duration(milliseconds: 100));
      expect(gate.canStartOptionalWork, true);
    }
    final owner = Object();
    gate.setBusy(owner, true);
    expect(gate.canStartOptionalWork, false);
    gate.setBusy(owner, false);
    expect(gate.canStartOptionalWork, false);
    now = now.add(const Duration(milliseconds: 201));
    expect(gate.canStartOptionalWork, true);
    gate.pauseKeyboard();
    expect(gate.canStartOptionalWork, false);
    gate.resumeKeyboard();
    expect(gate.canStartOptionalWork, false);
    now = now.add(const Duration(milliseconds: 201));
    expect(gate.canStartOptionalWork, true);
    gate.didChangeMetrics();
    expect(gate.canStartOptionalWork, true);
    now = now.add(const Duration(milliseconds: 201));
    foreground = false;
    expect(gate.canStartOptionalWork, false);
  });

  test('open-page scrolling and search jump pause recovery; detach releases it',
      () async {
    final global = serviceLocator<TUIChatGlobalModel>();
    final page = ChatPageUiNotifiers();
    global.attachOpenChatPageUi(
      conversationId: 'c2c_batch2',
      historyPosition: page.historyPosition,
      userScrolling: page.userScrolling,
    );
    page.userScrolling.value = true;
    expect(BackgroundMediaGate.instance.canStartOptionalWork, false);
    page.userScrolling.value = false;
    global.setSearchJumpStatus('c2c_batch2', SearchJumpStatus.loading);
    final pacer = RestoreWorkPacer(
      isScrolling: () => false,
      isForeground: () => true,
      hasOpenChat: () => true,
    );
    var granted = false;
    final recovery = pacer
        .beforePage(isCurrent: () => true, firstPage: true)
        .then((value) => granted = value);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(granted, false);
    global.detachOpenChatPageUi(
      historyPosition: page.historyPosition,
      userScrolling: page.userScrolling,
    );
    // A late response for a closed page must not hold the background gate.
    global.setSearchJumpStatus('c2c_batch2', SearchJumpStatus.loading);
    await recovery.timeout(const Duration(seconds: 2));
    expect(granted, true);
    global.clearSearchJumpStatus('c2c_batch2');
    page.dispose();
  });

  test('ordered and unordered windows preserve comparator and list ownership',
      () {
    final rows = List.generate(
        120,
        (i) => V2TimMessage.fromJson({
              'message_msg_id': 'id$i',
              'message_server_time': 1700000000 + i,
              'message_risk_type_identified': 0,
            }));
    final expected = List<V2TimMessage>.from(rows)
      ..sort((a, b) => TUIChatGlobalModel.compareMessagesChronological(b, a));
    for (final input in [rows, expected, expected.reversed.toList()]) {
      final before = List<V2TimMessage>.from(input);
      final result = TUIChatGlobalModel.sortMessagesNewestFirst(input);
      expect(result, orderedEquals(expected));
      expect(input, orderedEquals(before));
      expect(identical(input, result), false);
    }
  });
}
