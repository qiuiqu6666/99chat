import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

void main() {
  test('group UID source keeps token; navigation copy uses resolver name', () {
    final source = V2TimConversation(
      conversationID: 'group_m2EQQO3N5CQ',
      groupID: 'm2EQQO3N5CQ',
      type: 2,
      showName: 'm2EQQO3N5CQ',
      faceUrl: '',
    );
    const display = SearchConversationDisplay(
      showName: '麦当劳+编10555+拉10151',
      faceUrl: 'https://example.com/g.png',
      isGroup: true,
      needsNameHydration: false,
      needsFaceHydration: false,
    );

    final navigable = overlaySearchConversationDisplay(
      source: source,
      display: display,
    );

    expect(navigable.showName, '麦当劳+编10555+拉10151');
    expect(navigable.faceUrl, 'https://example.com/g.png');
    expect(navigable.conversationID, 'group_m2EQQO3N5CQ');
    expect(navigable.groupID, 'm2EQQO3N5CQ');
    expect(navigable.type, 2);
    expect(source.showName, 'm2EQQO3N5CQ');
    expect(source.faceUrl, '');
  });

  test('c2c userId source keeps id; navigation copy uses nickname', () {
    final source = V2TimConversation(
      conversationID: 'c2c_user1',
      userID: 'user1',
      type: 1,
      showName: 'user1',
      faceUrl: '',
    );
    const display = SearchConversationDisplay(
      showName: '张三',
      faceUrl: 'https://example.com/u.png',
      isGroup: false,
      needsNameHydration: false,
      needsFaceHydration: false,
    );

    final navigable = overlaySearchConversationDisplay(
      source: source,
      display: display,
    );

    expect(navigable.showName, '张三');
    expect(navigable.faceUrl, 'https://example.com/u.png');
    expect(navigable.conversationID, 'c2c_user1');
    expect(navigable.userID, 'user1');
    expect(navigable.type, 1);
    expect(source.showName, 'user1');
    expect(source.faceUrl, '');
  });
}
