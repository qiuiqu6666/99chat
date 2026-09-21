import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat header keeps a stable avatar identity and source', () {
    final header = File(
      'lib/src/widgets/chat_header_title.dart',
    ).readAsStringSync();
    final chat = File('lib/src/chat.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    expect(header.contains('final String conversationID;'), isTrue);
    expect(
      header.contains("'chat_header_avatar_group_\${widget.conversationID}'"),
      isTrue,
    );
    expect(
      header.contains("'chat_header_avatar_group_\${widget.title}'"),
      isFalse,
    );
    expect(
      header.contains(
        'UserAvatarHelper.usableAvatarOrEmpty(stableImFace).isNotEmpty',
      ),
      isTrue,
    );
    expect(
      chat.contains('GroupLocalStore.instance.readCached(groupId: groupId)'),
      isTrue,
    );
    expect(
      chat.contains('widget.selectedConversation.userID?.trim() != peerId'),
      isTrue,
    );
    expect(
      chat.contains(
        'final hasCachedAvatar = cachedAvatar.isNotEmpty &&',
      ),
      isTrue,
    );
    expect(chat.contains('final faceUrl = hasCachedAvatar'), isTrue);
    expect(
      chat.contains(
          'GroupMetadataRefreshCoordinator.instance\n        .readLocalPlaceholder(groupId)'),
      isTrue,
    );
    expect(chat.contains('snapshot.avatarUrl.isNotEmpty'), isTrue);
    expect(chat.contains('_cachedHeaderFaceUrl = snapshot.avatarUrl'), isTrue);
    expect(chat.contains('if (kProfileMode)'), isTrue);
    expect(chat.contains('normalized.hashCode.toUnsigned(32)'), isTrue);
  });
}
