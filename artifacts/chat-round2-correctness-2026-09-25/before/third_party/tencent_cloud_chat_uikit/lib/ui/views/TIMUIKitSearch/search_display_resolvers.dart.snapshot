import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

String resolveSearchUserFaceUrl({
  required String userId,
  required String fallbackFaceUrl,
}) {
  return serviceLocator<TUIChatGlobalModel>()
          .appSearchFaceUrlResolver
          ?.call(userId, fallbackFaceUrl) ??
      fallbackFaceUrl;
}

String resolveSearchGroupFaceUrl({
  required String groupId,
  required String fallbackFaceUrl,
}) {
  return serviceLocator<TUIChatGlobalModel>()
          .appSearchGroupFaceUrlResolver
          ?.call(groupId, fallbackFaceUrl) ??
      fallbackFaceUrl;
}

String? lookupSearchGroupLocalName(String groupId) {
  final id = groupId.trim();
  if (id.isEmpty) {
    return null;
  }
  final name = serviceLocator<TUIChatGlobalModel>()
      .appSearchGroupNameResolver
      ?.call(id)
      ?.trim();
  if (name == null || name.isEmpty) {
    return null;
  }
  return name;
}

SearchConversationDisplay resolveSearchConversationDisplay({
  required String conversationId,
  V2TimFriendInfo? friendHint,
  V2TimGroupInfo? groupHint,
}) {
  final hooked = serviceLocator<TUIChatGlobalModel>()
      .appSearchConversationDisplayResolver
      ?.call(
        conversationId: conversationId,
        friendHint: friendHint,
        groupHint: groupHint,
      );
  if (hooked != null) {
    return hooked;
  }
  final id = conversationId.trim();
  final treatAsGroup = isGroupConversationId(id);
  if (treatAsGroup) {
    final groupId =
        groupIdFromConversationId(id) ?? searchStripConversationPrefix(id);
    final title = preferSearchGroupShowName(
      groupName: groupHint?.groupName,
      storeName: lookupSearchGroupStoreName(groupId),
      localGroupName: lookupSearchGroupLocalName(groupId),
      groupId: groupId,
    );
    final face = resolveSearchGroupFaceUrl(
      groupId: groupId,
      fallbackFaceUrl: groupHint?.faceUrl ?? '',
    );
    return buildSearchConversationDisplay(
      showName: title,
      faceUrl: face,
      isGroup: true,
      fallbackId: groupId,
    );
  }
  final userId = id.toLowerCase().startsWith('c2c_')
      ? id.substring(4).trim()
      : (friendHint?.userID.trim() ?? id);
  final title = preferSearchC2cShowName(
    friendRemark: friendHint?.friendRemark,
    storeName: userId.isEmpty ? '' : DisplayNameStore.instance.c2c(userId),
    nickName: friendHint?.userProfile?.nickName,
    userID: userId,
  );
  final face = resolveSearchUserFaceUrl(
    userId: userId,
    fallbackFaceUrl: friendHint?.userProfile?.faceUrl ?? '',
  );
  return buildSearchConversationDisplay(
    showName: title,
    faceUrl: face,
    isGroup: false,
    fallbackId: userId,
  );
}
