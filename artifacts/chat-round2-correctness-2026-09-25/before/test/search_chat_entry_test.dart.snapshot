import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/utils/search_chat_entry.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

V2TimMessage _message(String id) =>
    V2TimMessage.fromJson({'message_risk_type_identified': 0})..msgID = id;

void main() {
  test('contact search resolves SDK history metadata before chat entry',
      () async {
    final source = resolveSearchC2cConversation(
      friendInfo: V2TimFriendInfo(userID: 'peer', friendRemark: '我的备注'),
    );
    final latest = _message('latest');
    final sdk = V2TimConversation(
      conversationID: 'c2c_peer',
      userID: 'peer',
      type: 1,
      showName: 'SDK name',
      faceUrl: 'https://example.com/avatar.png',
      lastMessage: latest,
      unreadCount: 7,
      c2cReadTimestamp: 123,
    );
    final result = await resolveSearchChatEntry(
      source: source,
      loadConversation: (id) async {
        expect(id, 'c2c_peer');
        return sdk;
      },
    );
    expect(result.lastMessage, same(latest));
    expect(result.unreadCount, 7);
    expect(result.c2cReadTimestamp, 123);
    expect(result.userID, 'peer');
    expect(result.showName, '我的备注');
    expect(result.faceUrl, sdk.faceUrl);
    expect(source.lastMessage, isNull);
    expect(sdk.showName, 'SDK name');
    expect(result, isNot(same(sdk)));
  });

  test('group search replaces stale local history and group type', () async {
    final stale = V2TimConversation(
      conversationID: 'group_@TGS#room',
      groupID: '@TGS#room',
      type: 2,
      lastMessage: _message('stale'),
      groupType: '0',
      draftText: 'local draft',
      draftTimestamp: 123,
      faceUrl: 'https://example.com/group.png',
    );
    final source = resolveSearchGroupConversation(
      group: V2TimGroupInfo(
          groupID: '@TGS#room', groupType: 'Work', groupName: '群聊'),
      conversationByGroupId: {'@TGS#room': stale},
    );
    final latest = _message('group-latest');
    final result = await resolveSearchChatEntry(
      source: source,
      loadConversation: (_) async => V2TimConversation(
        conversationID: 'group_@TGS#room',
        groupID: '@TGS#room',
        type: 2,
        groupType: 'Work',
        lastMessage: latest,
        unreadCount: 4,
        groupReadSequence: 42,
      ),
    );
    expect(result.lastMessage, same(latest));
    expect(result.groupType, 'Work');
    expect(result.groupID, '@TGS#room');
    expect(result.groupReadSequence, 42);
    expect(result.unreadCount, 4);
    expect(result.showName, '群聊');
    expect(result.faceUrl, stale.faceUrl);
    expect(result.draftText, 'local draft');
    expect(result.draftTimestamp, 123);
    expect(stale.lastMessage!.msgID, 'stale');
    expect(stale.groupType, '0');
  });

  test('SDK empty history does not resurrect a stale search preview', () async {
    final source = V2TimConversation(
      conversationID: 'c2c_peer',
      userID: 'peer',
      type: 1,
      lastMessage: _message('deleted'),
    );
    final result = await resolveSearchChatEntry(
      source: source,
      loadConversation: (_) async => V2TimConversation(
        conversationID: 'c2c_peer',
        userID: 'peer',
        type: 1,
      ),
    );
    expect(result.lastMessage, isNull);
    expect(source.lastMessage!.msgID, 'deleted');
  });

  test('new chat or unavailable SDK retains the search entry', () async {
    final source = V2TimConversation(
      conversationID: 'c2c_new',
      userID: 'new',
      type: 1,
    );
    expect(
        await resolveSearchChatEntry(
          source: source,
          loadConversation: (_) async => null,
        ),
        same(source));
    expect(
        await resolveSearchChatEntry(
          source: source,
          loadConversation: (_) async => throw StateError('offline'),
        ),
        same(source));
  });

  test('slow SDK lookup cannot block navigation or mutate a later entry',
      () async {
    final pending = Completer<V2TimConversation?>();
    final source = V2TimConversation(
      conversationID: 'c2c_peer',
      userID: 'peer',
      type: 1,
    );
    final result = await resolveSearchChatEntry(
      source: source,
      loadConversation: (_) => pending.future,
      timeout: Duration.zero,
    );
    expect(result, same(source));
    pending.complete(V2TimConversation(
      conversationID: 'c2c_peer',
      userID: 'peer',
      type: 1,
      lastMessage: _message('late'),
    ));
    await Future<void>.delayed(Duration.zero);
    expect(result.lastMessage, isNull);
  });

  test('ignores SDK metadata belonging to a different chat', () async {
    final source = V2TimConversation(
      conversationID: 'c2c_peer',
      userID: 'peer',
      type: 1,
    );
    for (final other in [
      V2TimConversation(conversationID: 'c2c_other', userID: 'other', type: 1),
      V2TimConversation(conversationID: 'group_peer', groupID: 'peer', type: 2),
    ]) {
      expect(
          await resolveSearchChatEntry(
            source: source,
            loadConversation: (_) async => other,
          ),
          same(source));
    }
  });
}
