import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final phase in [
    SearchJumpStatus.loading,
    SearchJumpStatus.positioning
  ]) {
    test('$phase blocks background bottom updates and pin requests', () {
      final global = TUIChatGlobalModel();
      const conv = '@TGS#search_position';
      global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
          notify: false);
      global.setSearchJumpStatus(conv, phase);
      final pins = global.pinToBottomRequestSeq;
      expect(global.isSearchJumpPending(conv), isTrue);
      global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
          notify: false);
      global.requestPinToBottom(conv, force: true);
      expect(global.getMessageListPosition(conv),
          HistoryMessagePosition.notShowLatest);
      expect(global.pinToBottomRequestSeq, pins);

      // Only the widget's layout proof releases the positioning phase.
      global.setSearchJumpStatus(conv, SearchJumpStatus.success);
      expect(global.isSearchJumpPending(conv), isFalse);
      global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
          notify: false);
      expect(
          global.getMessageListPosition(conv), HistoryMessagePosition.bottom);
      global.dispose();
    });
  }

  test('failed jump releases protection for a recent-history fallback', () {
    final global = TUIChatGlobalModel();
    const conv = '@TGS#search_failed';
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    global.setSearchJumpStatus(conv, SearchJumpStatus.positioning);
    global.setSearchJumpStatus(conv, SearchJumpStatus.failed);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    expect(global.isSearchJumpPending(conv), isFalse);
    expect(global.getMessageListPosition(conv), HistoryMessagePosition.bottom);
    global.dispose();
  });
}
