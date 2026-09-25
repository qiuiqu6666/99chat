import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_folder_chip_bar.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mute change updates folder color without changing unread quantity', () {
    final aggregate = ConversationUnreadAggregate.instance;
    aggregate.resetForTest();
    addTearDown(aggregate.resetForTest);
    V2TimConversation row(int mute) => V2TimConversation(
      conversationID: 'c2c_peer', type: 1, userID: 'peer',
      unreadCount: 120, recvOpt: mute,
    );
    aggregate.applySdkConversations([row(0)]);
    expect(aggregate.hasNotifiableUnreadForIds(['c2c_peer']), isTrue);
    final revision = aggregate.sdkUnreadRevision.value;
    aggregate.applySdkConversations([row(1)]);
    expect(aggregate.hasNotifiableUnreadForIds(['c2c_peer']), isFalse);
    expect(aggregate.rawUnreadChangesSince(revision), contains('c2c_peer'));
    aggregate.applySdkConversations([row(0)]);
    expect(aggregate.hasNotifiableUnreadForIds(['c2c_peer']), isTrue);
  });

  testWidgets('folder badge is red for normal unread and gray for muted only', (tester) async {
    Future<void> show(bool notifiable) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ConversationFolderChipBar(
        folders: [ConversationFolder(folderId: 'f', name: '分组', sortOrder: 0, members: const {})],
        selectedFolderId: 'f', unreadForFolder: (_) => 120,
        hasNotifiableUnreadForFolder: (_) => notifiable,
        onSelectAll: () {}, onSelectFolder: (_) {}, onCreateFolder: () {},
        reorderEditing: false,
      )),
    ));
    Color? badgeColor() {
      final container = tester.widget<Container>(find.ancestor(
        of: find.text('99+'), matching: find.byType(Container)).first);
      return (container.decoration as BoxDecoration).color;
    }
    await show(true);
    expect(badgeColor(), const Color(0xFFFF524B));
    await show(false);
    expect(badgeColor(), const Color(0xFFA8A8AE));
  });
}
