import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';

/// Enrich only rows still muted when the lookup completes. Never restore a
/// removed row or replace authoritative mute/role fields with profile data.
List<V2TimGroupMemberFullInfo> mergeMutedMemberProfiles(
  List<V2TimGroupMemberFullInfo> current,
  List<V2TimGroupMemberFullInfo> profiles, {
  Set<String> authoritativeNames = const {},
  Set<String> authoritativeAvatars = const {},
  bool acceptEmpty = false,
}) {
  final byId = {
    for (final profile in profiles)
      ChatIdFormat.rawUserUid(profile.userID): profile
  };
  String? prefer(String? fresh, String? existing) =>
      fresh?.trim().isNotEmpty == true ? fresh : existing;
  return current.map((member) {
    final id = ChatIdFormat.rawUserUid(member.userID);
    final profile = byId[id];
    if (profile == null) return member;
    final next = V2TimGroupMemberFullInfo.fromJson(member.toJson());
    if (!authoritativeNames.contains(id)) {
      next.nickName = acceptEmpty ? profile.nickName ?? member.nickName
          : prefer(profile.nickName, member.nickName);
    }
    if (!authoritativeAvatars.contains(id)) {
      next.faceUrl = acceptEmpty ? profile.faceUrl ?? member.faceUrl
          : prefer(profile.faceUrl, member.faceUrl);
    }
    next.friendRemark = prefer(profile.friendRemark, member.friendRemark);
    next.nameCard = prefer(member.nameCard, profile.nameCard);
    return next;
  }).toList(growable: false);
}
