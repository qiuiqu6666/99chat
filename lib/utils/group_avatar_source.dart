import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';

/// An avatar URL and version always come from the same metadata snapshot.
class GroupAvatarSource {
  const GroupAvatarSource._(this.groupId, this.faceUrl, this.version);

  final String groupId;
  final String faceUrl;
  final int? version;

  factory GroupAvatarSource.fromCached({
    required String groupId,
    required String fallbackUrl,
    int? fallbackVersion,
  }) {
    final id = ChatIdFormat.normalizeGroupId(groupId);
    return GroupAvatarSource.resolve(
      groupId: id,
      fallbackUrl: fallbackUrl,
      fallbackVersion: fallbackVersion,
      local: GroupLocalStore.instance.readCached(groupId: id),
    );
  }

  factory GroupAvatarSource.resolve({
    required String groupId,
    required String fallbackUrl,
    int? fallbackVersion,
    MeGroupRecord? local,
  }) {
    final id = GroupLocalStore.groupEquivalenceKey(groupId);
    final localMatches = local != null &&
        GroupLocalStore.groupEquivalenceKey(local.groupId) == id;
    final localUrl = _displayUrl(local?.avatarUrl ?? '');
    // Versioned empty avatars represent a removal. Unversioned empty metadata
    // may be an incomplete SDK snapshot, so it can still use the caller's URL.
    final useLocal = localMatches &&
        (localUrl.isNotEmpty || local.avatarVersion > 0) &&
        (fallbackVersion == null || fallbackVersion <= local.avatarVersion);
    return GroupAvatarSource._(
      id,
      useLocal ? localUrl : _displayUrl(fallbackUrl),
      useLocal ? local.avatarVersion : fallbackVersion,
    );
  }

  static String _displayUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed == ConversationFaceUrl.defaultGroupFaceAsset) return '';
    if (trimmed.startsWith('assets/')) return trimmed;
    final usable = UserAvatarHelper.usableAvatarOrEmpty(trimmed);
    return usable.isEmpty
        ? ''
        : UserAvatarHelper.resolveDisplayUrl(usable) ?? usable;
  }

  String? cacheKeyFor(String variant) => UserAvatarHelper.cacheKey(
        ownerId: groupId,
        avatarVersion: version,
        isGroup: true,
        variant: variant,
      );

  String get cacheKey => cacheKeyFor('thumb') ?? faceUrl;

  /// List rows (40/48/54) and profile headers (56) share one decoded image.
  /// Larger in-page avatars use a separate tier; full-screen previews are lazy.
  static double cacheLogicalSize(double size) {
    if (size <= 64) return 64;
    if (size <= 128) return 128;
    return size;
  }

  AvatarImageWarmSource warmSource({double size = 40}) => AvatarImageWarmSource(
        url: faceUrl,
        cacheKey: cacheKey,
        cacheLogicalSize: cacheLogicalSize(size),
      );
}
