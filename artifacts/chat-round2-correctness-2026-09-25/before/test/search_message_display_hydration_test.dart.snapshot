import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/search_conversation_display.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});

  tearDown(() {
    debugSearchConversationLookup = null;
    debugSearchGetUsersInfo = null;
    debugSearchGetGroupsInfo = null;
  });

  test('stale generation still hydrates but does not notify', () async {
    var notified = false;
    List<String>? received;
    await runSearchMessageDisplayHydration(
      generation: 1,
      currentGeneration: () => 2,
      conversationIds: const ['c2c_a', 'group_g'],
      hydrator: (ids) async {
        received = ids;
      },
      onCurrent: () => notified = true,
    );
    expect(received, ['c2c_a', 'group_g']);
    expect(notified, isFalse);
  });

  test('current generation notifies after hydrator', () async {
    var notified = false;
    await runSearchMessageDisplayHydration(
      generation: 7,
      currentGeneration: () => 7,
      conversationIds: const ['c2c_b'],
      hydrator: (ids) async {},
      onCurrent: () => notified = true,
    );
    expect(notified, isTrue);
  });

  test('load-more conversation IDs are collected and de-duplicated', () {
    final firstPage = [
      V2TimMessageSearchResultItem(conversationID: 'c2c_a', messageCount: 2),
      V2TimMessageSearchResultItem(conversationID: 'group_g', messageCount: 1),
    ];
    final merged = [
      ...firstPage,
      V2TimMessageSearchResultItem(conversationID: 'c2c_b', messageCount: 3),
      V2TimMessageSearchResultItem(conversationID: 'c2c_a', messageCount: 4),
    ];
    expect(
      collectSearchMessageConversationIds(merged),
      ['c2c_a', 'group_g', 'c2c_b'],
    );
  });

  test('hydration writes usable IM name then resolver leaves ID fallback behind',
      () async {
    debugSearchConversationLookup = (id) async => null;
    debugSearchGetUsersInfo = (ids) async => [
          V2TimUserFullInfo(
            userID: 'hydrateuser9',
            nickName: '异步昵称',
            faceUrl: 'https://example.com/h.png',
          ),
        ];
    debugSearchGetGroupsInfo = (ids) async => const [];

    await hydrateAppSearchConversationDisplays(const ['c2c_hydrateuser9']);

    final display = resolveAppSearchConversationDisplay(
      conversationId: 'c2c_hydrateuser9',
    );
    expect(display.showName, '异步昵称');
    expect(display.faceUrl, 'https://example.com/h.png');
    expect(display.needsNameHydration, isFalse);
  });

  test('IM nickname equal to userId does not replace a missing name with ID',
      () async {
    debugSearchConversationLookup = (id) async => V2TimConversation(
          conversationID: id,
          userID: 'iduser8',
          type: 1,
          showName: 'iduser8',
          faceUrl: '',
        );
    debugSearchGetUsersInfo = (ids) async => [
          V2TimUserFullInfo(
            userID: 'iduser8',
            nickName: 'iduser8',
            faceUrl: '',
          ),
        ];

    await hydrateAppSearchConversationDisplays(const ['c2c_iduser8']);
    final display = resolveAppSearchConversationDisplay(
      conversationId: 'c2c_iduser8',
    );
    expect(display.showName, 'iduser8');
    expect(display.needsNameHydration, isTrue);
  });
}
