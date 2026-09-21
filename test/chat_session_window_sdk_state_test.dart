import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_window_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

V2TimConversation _row(String id, {int type = 1}) => V2TimConversation(
      conversationID: '${type == 1 ? 'c2c' : 'group'}_$id',
      type: type,
      userID: type == 1 ? id : null,
      groupID: type == 2 ? id : null,
      showName: id,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationTabStore.instance;
  final window = ChatSessionWindowState.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.clear();
    window.reset();
  });

  tearDown(() {
    store.clear();
    window.reset();
  });

  test('SDK window reads stay current without a Controller adoption', () {
    final first = _row('first');
    final group = _row('group', type: 2);
    store.setItemsForTest(convType: 1, items: [first], finished: false);
    store.setItemsForTest(convType: 2, items: [group], finished: true);

    expect(window.hydratedStartOffsetForType(1), 0);
    expect(window.hydratedLengthForType(1), 1);
    expect(window.hydratedEndOffsetForType(1), 1);
    expect(
        window.totalCountForType(1), 1 + ConversationTabStore.defaultPageSize);
    expect(window.totalCountForType(2), 1);
    expect(window.conversationAtTypeIndex(1, 0), same(first));
    expect(window.conversationAtTypeIndex(2, 0), same(group));

    final replacement = _row('replacement');
    store.setItemsForTest(
        convType: 1, items: [replacement, first], finished: true);

    expect(window.hydratedLengthForType(1), 2);
    expect(window.hydratedEndOffsetForType(1), 2);
    expect(window.totalCountForType(1), 2);
    expect(window.typeIndexOfConversationId(1, first.conversationID), 1);
    expect(window.conversationAtTypeIndex(1, 0), same(replacement));
    expect(window.isTypeIndexLiveHydrated(1, 1), isTrue);
    expect(window.isTypeIndexLiveHydrated(1, 2), isFalse);

    store.clear();
    expect(window.hydratedLengthForType(1), 0);
    expect(window.hydratedEndOffsetForType(2), 0);
    expect(window.totalCountForType(1), 0);
    expect(window.typeIndexOfConversationId(1, first.conversationID), isNull);
    expect(window.conversationAtTypeIndex(2, 0), isNull);
  });

  test('invalid types and indices never fall through to a C2C row', () {
    store.setItemsForTest(convType: 1, items: [_row('only')], finished: true);

    expect(window.hydratedLengthForType(0), 0);
    expect(window.hydratedEndOffsetForType(3), 0);
    expect(window.totalCountForType(0), 0);
    expect(window.isTypeIndexLiveHydrated(1, -1), isFalse);
    expect(window.isTypeIndexLiveHydrated(0, 0), isFalse);
    expect(window.typeIndexOfConversationId(0, 'c2c_only'), isNull);
    expect(window.conversationAtTypeIndex(0, 0), isNull);
    expect(window.conversationAtTypeIndex(1, -1), isNull);
  });
}
