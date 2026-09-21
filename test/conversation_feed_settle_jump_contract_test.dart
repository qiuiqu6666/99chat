import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationTabStore.instance;
  setUp(store.clear);
  tearDown(store.clear);

  V2TimConversation row(String id, int order) => V2TimConversation(
      conversationID: 'c2c_$id', userID: id, type: 1, orderkey: order);

  test('scroll settle applies pending order once without rereading SDK', () {
    store.setItemsForTest(convType: 1, items: [row('a', 20), row('b', 10)]);
    final initial = store.conversations;
    store.setSortFrozenByScroll(true);
    store.applyPatches([row('b', 30)], reason: 'sdk_realtime');
    expect(
        store.conversations.map((r) => r.conversationID), ['c2c_a', 'c2c_b']);
    var notifications = 0;
    void changed() => notifications++;
    store.addListener(changed);
    try {
      store.setSortFrozenByScroll(false);
      expect(
          store.conversations.map((r) => r.conversationID), ['c2c_b', 'c2c_a']);
      expect(notifications, 1);
      final settled = store.conversations;
      store.setSortFrozenByScroll(false);
      expect(notifications, 1);
      expect(store.conversations, same(settled));
      expect(initial.map((r) => r.conversationID), ['c2c_a', 'c2c_b']);
    } finally {
      store.removeListener(changed);
    }
  });
}
