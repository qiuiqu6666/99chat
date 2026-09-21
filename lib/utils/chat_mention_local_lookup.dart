import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// Membership lookups only: never searches the server or infers membership
/// from a cached display name, public profile, or historical conversation.
class ChatMentionLocalLookup {
  ChatMentionLocalLookup._();

  static Future<V2TimFriendInfo?> friend(String userId) async {
    final id = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty) return null;
    final record = await MeFriendApi.instance.cachedByUserId(id);
    if (record != null) {
      // An explicit local non-friend record wins over stale SDK friendship.
      return record.canMessage || record.inMyFriendList || record.isFriend
          ? record.toV2TimFriendInfo()
          : null;
    }
    for (final item in serviceLocator<TUIFriendShipViewModel>().friendList ??
        const <V2TimFriendInfo>[]) {
      if (ChatIdFormat.rawUserUid(item.userID) == id) return item;
    }
    return null;
  }

  static Future<V2TimGroupInfo?> joinedGroup(String key) async {
    final record = await GroupLocalStore.instance.read(groupId: key);
    if (record == null || !const [200, 300, 400].contains(record.myRole)) {
      return null;
    }
    return record.toV2TimGroupInfo();
  }
}
