import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/group_avatar_source.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';

/// Group-avatar entry point. Page owners handle metadata refresh; rendering
/// only reads their committed local snapshot and never fetches group metadata.
class AppGroupAvatar extends StatelessWidget {
  const AppGroupAvatar({
    super.key,
    required this.groupId,
    required this.faceUrl,
    required this.showName,
    required this.size,
    this.avatarVersion,
    this.enablePreview = false,
    this.previewFaceUrl,
    this.previewUrlResolver,
  });

  final String groupId;
  final String faceUrl;
  final String showName;
  final double size;
  final int? avatarVersion;
  final bool enablePreview;
  final String? previewFaceUrl;
  final AvatarPreviewUrlResolver? previewUrlResolver;

  @override
  Widget build(BuildContext context) {
    final source = GroupAvatarSource.fromCached(
      groupId: groupId,
      fallbackUrl: faceUrl,
      fallbackVersion: avatarVersion,
    );
    final avatar = AppUserAvatar(
      // A recycled row must not retain a different group's image.
      key: ValueKey('group_avatar_${source.groupId}'),
      faceUrl: source.faceUrl,
      showName: showName,
      size: size,
      cacheLogicalSize: GroupAvatarSource.cacheLogicalSize(size),
      type: 2,
      ownerId: source.groupId,
      avatarVersion: source.version,
      avatarCacheKey: source.cacheKey,
      preferRasterPlaceholder: true,
    );
    if (!enablePreview) return avatar;
    return GestureDetector(
      onTap: () => Avatar(
        faceUrl: source.faceUrl,
        showName: showName,
        type: 2,
        previewFaceUrl: previewFaceUrl,
        previewUrlResolver: previewUrlResolver,
        avatarCacheKey: source.cacheKey,
        previewCacheKey: source.cacheKeyFor('preview'),
      ).openPreview(context),
      child: avatar,
    );
  }
}
