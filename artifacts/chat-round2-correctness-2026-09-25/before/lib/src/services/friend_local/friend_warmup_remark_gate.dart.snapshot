import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

/// Cold-start warmup credibility for friend remarks.
///
/// [DisplayNameStore.c2c] is only the current cache and never counts as
/// [trustedDisplayedIm]. Explicit `remarkKnown && remark == ''` is a value,
/// not an absence — no `_firstNonEmpty` / merge fallback belongs here.
class FriendWarmupRemarkGate {
  FriendWarmupRemarkGate._();

  /// IM remark, or a non-placeholder conversation showName.
  static String trustedDisplayedIm({
    required String userId,
    String? conversationShowName,
    String? localNickname,
  }) {
    final id = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty) {
      return '';
    }
    final imRemark =
        ImSdkRelationshipDirectory.instance.friend(id)?.remark.trim() ?? '';
    if (imRemark.isNotEmpty) {
      return imRemark;
    }
    final show = conversationShowName?.trim() ?? '';
    if (show.isEmpty || DisplayNameStore.isRawUserIdDisplayName(id, show)) {
      return '';
    }
    final localNick = localNickname?.trim() ?? '';
    if (localNick.isNotEmpty && show == localNick) {
      return '';
    }
    final imNick =
        ImSdkRelationshipDirectory.instance.friend(id)?.nickname.trim() ?? '';
    if (imNick.isNotEmpty && show == imNick) {
      return '';
    }
    return show;
  }

  /// Whether warmup/hydrate may write this local record into memory/Store.
  static bool shouldApplyLocalRemark(
    MeFriendRecord record, {
    String? conversationShowName,
  }) {
    final id = ChatIdFormat.rawUserUid(record.friendUserId);
    if (id.isEmpty) {
      return false;
    }
    if (!record.remarkKnown) {
      return false;
    }
    final localRemark = record.remark.trim();
    if (localRemark.isEmpty) {
      return true;
    }
    final displayedIm = trustedDisplayedIm(
      userId: id,
      conversationShowName: conversationShowName,
      localNickname: record.friendNickname,
    );
    if (displayedIm.isNotEmpty && displayedIm != localRemark) {
      return false;
    }
    return true;
  }
}
