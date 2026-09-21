import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';
import 'package:tencent_cloud_chat_demo/utils/group_avatar_source.dart';

MeGroupRecord record(
        {String url = 'https://avatar.test/new.png', int version = 7}) =>
    MeGroupRecord(
      groupId: '@TGS#123ABC',
      groupType: 'Public',
      groupName: 'Group',
      displayAlias: '',
      avatarUrl: url,
      avatarVersion: version,
      notice: '',
      memberCount: 2,
      myRole: 200,
      myNameCard: '',
      joinedAt: 1,
      updatedAt: 1,
    );

void main() {
  test('group aliases resolve the same URL and version from local metadata',
      () {
    final sources = [
      for (final id in ['@TGS#123ABC', 'group_@TGS#123ABC', '123ABC'])
        GroupAvatarSource.resolve(
          groupId: id,
          fallbackUrl: 'https://avatar.test/stale.png',
          local: record(),
        ),
    ];
    expect(sources.map((s) => s.cacheKey).toSet(), hasLength(1));
    expect(sources.every((s) => s.faceUrl == record().avatarUrl), isTrue);
    expect(sources.every((s) => s.version == 7), isTrue);
  });

  test('missing versions follow URL changes and never pin a version-zero key',
      () {
    final old = GroupAvatarSource.resolve(
      groupId: 'group-one',
      fallbackUrl: 'https://avatar.test/a.png',
      fallbackVersion: 0,
    );
    final next = GroupAvatarSource.resolve(
      groupId: 'group-one',
      fallbackUrl: 'https://avatar.test/b.png',
    );
    expect(old.cacheKey, old.faceUrl);
    expect(next.cacheKey, next.faceUrl);
    expect(next.cacheKey, isNot(old.cacheKey));
    expect(old.cacheKeyFor('preview'), isNull);
  });

  test('URL signatures share a versioned cache; a new version invalidates it',
      () {
    GroupAvatarSource source(String url, int version) =>
        GroupAvatarSource.resolve(
          groupId: 'group-one',
          fallbackUrl: url,
          fallbackVersion: version,
        );
    final old = source('https://avatar.test/a.png?token=old', 1);
    final refreshed = source('https://avatar.test/a.png?token=new', 1);
    final updated = source(refreshed.faceUrl, 2);
    expect(old.cacheKey, refreshed.cacheKey);
    expect(refreshed.cacheKey, isNot(updated.cacheKey));
    expect(old.cacheKeyFor('preview'), isNot(old.cacheKey));
    expect(
      AvatarImageWarm.providerFor(
          url: old.faceUrl, cacheKey: old.cacheKey, cacheSize: 192),
      AvatarImageWarm.providerFor(
          url: refreshed.faceUrl, cacheKey: refreshed.cacheKey, cacheSize: 192),
    );
  });

  test(
      'empty incomplete metadata does not pair its version with a fallback URL',
      () {
    final source = GroupAvatarSource.resolve(
      groupId: '@TGS#123ABC',
      fallbackUrl: 'https://avatar.test/fallback.png',
      local: record(url: '', version: 0),
    );
    expect(source.cacheKey, 'https://avatar.test/fallback.png');
    expect(source.version, isNull);
  });

  test('versioned removal does not resurrect a stale conversation avatar', () {
    final source = GroupAvatarSource.resolve(
      groupId: '@TGS#123ABC',
      fallbackUrl: 'https://avatar.test/stale.png',
      local: record(url: '', version: 8),
    );
    expect(source.faceUrl, isEmpty);
  });

  test('a newer caller snapshot wins over older local metadata', () {
    final source = GroupAvatarSource.resolve(
      groupId: '@TGS#123ABC',
      fallbackUrl: 'https://avatar.test/newer.png',
      fallbackVersion: 8,
      local: record(),
    );
    expect(source.faceUrl, 'https://avatar.test/newer.png');
    expect(source.version, 8);
  });

  test('another group cannot supply the avatar version or URL', () {
    final source = GroupAvatarSource.resolve(
      groupId: 'other-group',
      fallbackUrl: 'https://avatar.test/other.png',
      local: record(),
    );
    expect(source.faceUrl, 'https://avatar.test/other.png');
    expect(source.version, isNull);
  });

  test('default assets stay local and never become media network requests', () {
    final source = GroupAvatarSource.resolve(
      groupId: 'group-one',
      fallbackUrl: ConversationFaceUrl.defaultGroupFaceAsset,
    );
    expect(source.faceUrl, isEmpty);
  });
}
