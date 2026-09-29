import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_index_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_chat_state.dart';

void main() {
  final store = GroupLiveIndexStore.instance;
  setUp(store.clear);
  tearDown(store.clear);

  GroupLiveIndexSnapshot snapshot(String description) => GroupLiveIndexSnapshot(
        revision: 1,
        items: [
          GroupLiveIndexItem(
              groupId: 'group_room',
              liveSessionId: 'live1',
              status: GroupLiveStatus.live,
              version: 1,
              roomName: 'title',
              description: description)
        ],
      );

  test('index description is available immediately when chat opens', () {
    store.applySnapshot(snapshot('主播在线讲解'));
    final chat = GroupLiveChatState()..seedFromIndex('group_room');
    expect(chat.activeSession?.description, '主播在线讲解');
    chat.dispose();
  });

  test('local session caches description', () {
    store.applyLocalSession(const GroupLiveSession(
        liveSessionId: 'live1',
        groupId: 'group_room',
        roomName: 'title',
        anchorUserId: 'anchor',
        status: GroupLiveStatus.live,
        description: '直播说明'));
    expect(store.itemForGroup('group_room')?.description, '直播说明');
  });

  test('description-only changes notify and explicit removal clears cache', () {
    store.applySnapshot(snapshot('old'));
    var notifications = 0;
    void listener() => notifications++;
    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));
    store.applySnapshot(snapshot('new'));
    expect(notifications, 1);
    expect(store.itemForGroup('group_room')?.description, 'new');
    store.applySnapshot(snapshot('new'));
    expect(notifications, 1);
    store.applySnapshot(snapshot(''));
    expect(notifications, 2);
    expect(store.itemForGroup('group_room')?.description, '');
  });
}
