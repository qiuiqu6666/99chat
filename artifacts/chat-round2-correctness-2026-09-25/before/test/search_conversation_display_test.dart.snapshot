import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/search_conversation_display.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('① friend hint wins over store name', () {
    DisplayNameStore.instance.setC2C('hintuser1', 'Store名', notify: false);
    final display = resolveAppSearchConversationDisplay(
      conversationId: 'c2c_hintuser1',
      friendHint: V2TimFriendInfo(
        userID: 'hintuser1',
        friendRemark: '备注甲',
        userProfile: V2TimUserFullInfo(
          userID: 'hintuser1',
          nickName: '昵称',
          faceUrl: 'https://example.com/a.png',
        ),
      ),
    );
    expect(display.showName, '备注甲');
    expect(display.faceUrl, 'https://example.com/a.png');
    expect(display.isGroup, isFalse);
    expect(display.needsNameHydration, isFalse);
    expect(display.needsFaceHydration, isFalse);
  });

  test('② DisplayNameStore fills C2C when no hint', () {
    DisplayNameStore.instance.setC2C('storeuser2', '店名乙', notify: false);
    final display = resolveAppSearchConversationDisplay(
      conversationId: 'c2c_storeuser2',
    );
    expect(display.showName, '店名乙');
    expect(display.isGroup, isFalse);
  });

  test('C2C without profile falls back to userID', () {
    final display = resolveAppSearchConversationDisplay(
      conversationId: 'c2c_m24WQS3N5CJ',
    );
    expect(display.showName, 'm24WQS3N5CJ');
    expect(display.faceUrl, isEmpty);
    expect(display.isGroup, isFalse);
    expect(display.needsNameHydration, isTrue);
    expect(display.needsFaceHydration, isTrue);
  });

  test('group hint supplies name and face, avatar is group', () {
    final display = resolveAppSearchConversationDisplay(
      conversationId: 'group_searchgroup1',
      groupHint: V2TimGroupInfo(
        groupID: 'searchgroup1',
        groupType: 'Work',
        groupName: '天使群',
        faceUrl: 'https://example.com/g.png',
      ),
    );
    expect(display.showName, '天使群');
    expect(display.faceUrl, 'https://example.com/g.png');
    expect(display.isGroup, isTrue);
    expect(display.needsNameHydration, isFalse);
    expect(display.needsFaceHydration, isFalse);
  });

  test('ID-like names are not usable and sanitizer drops them', () {
    expect(sanitizedSearchUserNickName('u1', 'u1'), isEmpty);
    expect(sanitizedSearchUserNickName('u1', '昵称丙'), '昵称丙');
    expect(sanitizedSearchGroupName('g1', 'g1'), isEmpty);
    expect(sanitizedSearchGroupName('g1', '周末局'), '周末局');
    final built = buildSearchConversationDisplay(
      showName: 'u9',
      faceUrl: '',
      isGroup: false,
      fallbackId: 'u9',
    );
    expect(built.showName, 'u9');
    expect(built.needsNameHydration, isTrue);
    expect(built.isGroup, isFalse);
    final groupBuilt = buildSearchConversationDisplay(
      showName: '',
      faceUrl: '',
      isGroup: true,
      fallbackId: 'g9',
    );
    expect(groupBuilt.isGroup, isTrue);
    expect(groupBuilt.showName, 'g9');
  });
}
