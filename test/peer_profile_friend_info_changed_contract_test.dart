import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'self-hosted friend info waits for versioned state before writing public profile',
      () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/'
      'tui_friendship_view_model.dart',
    ).readAsStringSync();

    expect(
      source.contains('UserProfileLocalBridge.upsertPublicProfileFromSnapshot'),
      isTrue,
    );
    final upsertAt = source
        .indexOf('UserProfileLocalBridge.upsertPublicProfileFromSnapshot');
    final selfHostedReturnAt = source.indexOf(
      'SelfHostedFriendshipBridge.enabled',
      source.indexOf('onFriendInfoChanged:'),
    );
    expect(upsertAt, greaterThanOrEqualTo(0));
    expect(selfHostedReturnAt, lessThan(upsertAt));

    expect(
      source.contains(
        'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/'
        'tui_chat_global_model.dart',
      ),
      isFalse,
    );
  });

  test('inbound messages upsert peer public profile snapshots', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/'
      'tui_chat_global_model.dart',
    ).readAsStringSync();

    expect(
      source.contains('UserProfileLocalBridge.upsertPublicProfileFromSnapshot'),
      isTrue,
    );
    expect(
        source.contains('_syncGroupMemberFromMessage(mountedMessage)'), isTrue);
  });
}
