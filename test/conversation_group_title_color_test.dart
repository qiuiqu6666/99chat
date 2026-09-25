import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_group_title_color.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_type.dart';

void main() {
  const fallback = Color(0xFF111827);

  test('Community uses AppTokens.danger', () {
    expect(
      conversationGroupTitleColor(
        fallback: fallback,
        groupType: GroupType.Community,
      ),
      AppTokens.danger,
    );
  });

  test('non-Community and empty keep fallback', () {
    expect(
      conversationGroupTitleColor(fallback: fallback, groupType: GroupType.Work),
      fallback,
    );
    expect(
      conversationGroupTitleColor(
        fallback: fallback,
        groupType: GroupType.Public,
      ),
      fallback,
    );
    expect(
      conversationGroupTitleColor(fallback: fallback, groupType: null),
      fallback,
    );
    expect(
      conversationGroupTitleColor(fallback: fallback, groupType: ''),
      fallback,
    );
    expect(
      conversationGroupTitleColor(fallback: fallback, groupType: '  '),
      fallback,
    );
  });

  test('null fallback falls back to AppTokens.textPrimaryLight when not Community',
      () {
    expect(
      conversationGroupTitleColor(fallback: null, groupType: GroupType.Work),
      AppTokens.textPrimaryLight,
    );
  });

  test('channel row shows broadcast icon and normal title color', () {
    const owner = 'channel-title-test-owner';
    const groupId = 'channel-title-test-group';
    final store = GroupLocalStore.instance;
    store.debugOwnerUserIdOverride = owner;
    store.debugPutCachedRecord(
      ownerUserId: owner,
      record: MeGroupRecord(
        groupId: groupId,
        groupType: GroupType.Community,
        groupName: '频道昵称',
        displayAlias: '',
        avatarUrl: '',
        notice: '',
        memberCount: 2,
        myRole: 200,
        myNameCard: '',
        joinedAt: 1,
        updatedAt: 1,
        isChannel: true,
      ),
    );
    addTearDown(() {
      store.debugRemoveCachedRecord(ownerUserId: owner, groupId: groupId);
      store.debugClearOwnerOverride();
    });

    final title = buildGroupConversationListNickName(
      userId: null,
      name: '频道昵称',
      fallbackTitleColor: fallback,
      groupType: GroupType.Community,
      groupId: groupId,
    ) as Row;
    expect((title.children.first as Icon).icon, Icons.campaign_rounded);
    final name = (title.children.last as Flexible).child as Text;
    expect(name.data, '频道昵称');
    expect(name.style?.color, fallback);
  });
}
