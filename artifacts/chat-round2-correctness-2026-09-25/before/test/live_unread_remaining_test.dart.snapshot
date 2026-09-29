import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  test('followingLatest defaults true and leave does not clear unseen', () {
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = '@TGS#following_latest_state';
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
        notify: false);
    expect(global.isFollowingLatest(conv), isTrue);
    global.setFollowingLatest(conv, false, notify: false);
    expect(global.isFollowingLatest(conv), isFalse);
    expect(global.receivedNewMessageCountFor(conv), 0);
    global.setFollowingLatest(conv, true, notify: false);
    expect(global.isFollowingLatest(conv), isTrue);
  });

  test('restore followingLatest clears unseenSinceLeave', () {
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = '@TGS#following_latest_clear';
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
        notify: false);
    global.setFollowingLatest(conv, false, notify: false);
    global.setFollowingLatest(conv, true, notify: false);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.unreadCountForTongueFor(conv), 0);
  });
}
