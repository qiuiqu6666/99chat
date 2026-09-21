import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

V2TimConversation _row(int index, {int unread = 0}) => V2TimConversation(
      conversationID: 'c2c_$index',
      type: 1,
      userID: '$index',
      unreadCount: unread,
      orderkey: 100000 - index,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUp(() {
    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.debugFetchByIdsOverride = null;
    ConversationTabStore.instance.clear();
    ConversationTabStore.instance.notifyColdStartEnded();
  });

  tearDown(() {
    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.debugFetchByIdsOverride = null;
    ConversationTabStore.instance.clear();
  });

  test('bounded window restores both directions without losing IDs', () async {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(
        convType: 1, items: List.generate(600, _row), nextSeq: '1');
    ConversationTabStore.debugFetchOverride = (
            {required int convType,
            required String nextSeq,
            required int count}) async =>
        (
          conversationList: List.generate(100, (i) => _row(600 + i)),
          nextSeq: '2',
          isFinished: false,
          code: 0,
          desc: ''
        );
    ConversationTabStore.debugFetchByIdsOverride = (ids) async => (
          conversationList:
              ids.map((id) => _row(int.parse(id.substring(4)))).toList(),
          code: 0
        );
    await tab.loadMore(convType: 1, count: 100, viewportAnchorId: 'c2c_590');
    void verify() {
      final visible = tab.itemsForType(1).map((r) => r.conversationID).toList();
      expect(visible, hasLength(600));
      final all = [
        ...tab.detachedHeadIdsForTest(1),
        ...visible,
        ...tab.detachedTailIdsForTest(1)
      ];
      expect(all, List.generate(700, (i) => 'c2c_$i'));
    }

    verify();
    expect(
        await tab.restoreNewerPrefixForViewport(convType: 1, count: 100), 100);
    verify();
    expect(tab.itemsForType(1).first.conversationID, 'c2c_0');
    expect(
        await tab.restoreOlderSuffixForViewport(convType: 1, count: 100), 100);
    verify();
    expect(tab.itemsForType(1).last.conversationID, 'c2c_699');
  });

  test('new hot conversation appears at head while idle without growing cache',
      () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(
        convType: 1, items: List.generate(600, _row), nextSeq: '1');
    tab.applyPatches([_row(-1, unread: 3)]);
    expect(tab.itemsForType(1), hasLength(600));
    expect(tab.itemsForType(1).first.conversationID, 'c2c_-1');
    expect(tab.detachedTailIdsForTest(1), ['c2c_599']);
  });

  test('append keeps window intact below capacity', () async {
    expect(
      ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType,
      greaterThan(110),
    );
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(
      convType: 1,
      items: List<V2TimConversation>.generate(30, _row),
      nextSeq: '1',
    );
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async =>
        (
          conversationList: List<V2TimConversation>.generate(
            80,
            (index) => _row(30 + index),
          ),
          nextSeq: '2',
          isFinished: false,
          code: 0,
          desc: '',
        );

    await tab.loadMore(
      convType: 1,
      count: 80,
      viewportAnchorId: 'c2c_29',
    );

    final ids = tab.itemsForType(1).map((row) => row.conversationID).toList();
    expect(ids, hasLength(110));
    expect(ids.first, 'c2c_0');
    expect(ids.last, 'c2c_109');
    expect(tab.windowTrimmedForType(1), isFalse);
    expect(tab.detachedHeadIdsForTest(1), isEmpty);
    expect(tab.detachedTailIdsForTest(1), isEmpty);
  });

  test('newer unread patch stays in the untrimmed window', () async {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(
      convType: 1,
      items: List<V2TimConversation>.generate(30, _row),
      nextSeq: '1',
    );
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async =>
        (
          conversationList: List<V2TimConversation>.generate(
            80,
            (index) => _row(30 + index),
          ),
          nextSeq: '2',
          isFinished: false,
          code: 0,
          desc: '',
        );
    await tab.loadMore(
      convType: 1,
      count: 80,
      viewportAnchorId: 'c2c_29',
    );

    tab.applyPatches([_row(-1, unread: 3)..orderkey = 200000]);
    final ids = tab.itemsForType(1).map((row) => row.conversationID).toSet();
    expect(ids, contains('c2c_-1'));
    expect(tab.detachedHeadIdsForTest(1), isEmpty);
  });

  test('loadFirstPage reset clears detached ids', () async {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(
      convType: 1,
      items: List<V2TimConversation>.generate(30, _row),
      nextSeq: '1',
    );
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async =>
        (
          conversationList: List<V2TimConversation>.generate(
            80,
            (index) => _row(30 + index),
          ),
          nextSeq: '0',
          isFinished: true,
          code: 0,
          desc: '',
        );
    await tab.loadMore(
      convType: 1,
      count: 80,
      viewportAnchorId: 'c2c_29',
    );
    expect(tab.windowTrimmedForType(1), isFalse);

    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async =>
        (
          conversationList: List<V2TimConversation>.generate(
            ConversationTabStore.coldStartFirstPageSize,
            _row,
          ),
          nextSeq: '1',
          isFinished: false,
          code: 0,
          desc: '',
        );
    await tab.loadFirstPage(
      convType: 1,
      count: ConversationTabStore.coldStartFirstPageSize,
    );
    expect(tab.detachedHeadIdsForTest(1), isEmpty);
    expect(tab.detachedTailIdsForTest(1), isEmpty);
    expect(tab.windowTrimmedForType(1), isFalse);
  });
}
