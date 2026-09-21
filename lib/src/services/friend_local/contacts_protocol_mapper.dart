import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

String contactsEntityIdFromSyncJson(Map<String, dynamic> json) {
  return ChatIdFormat.rawUserUid(
    (json['id'] ??
            json['noticeId'] ??
            json['notice_id'] ??
            json['userId'] ??
            json['user_id'] ??
            json['groupId'] ??
            json['group_id'] ??
            json['peerUserId'] ??
            json['peer_user_id'] ??
            json['friendUserId'] ??
            json['friend_user_id'] ??
            '')
        .toString(),
  );
}

MeFriendRecord meFriendRecordFromSyncProtocolItem(SyncProtocolItem item) {
  final data = Map<String, dynamic>.from(item.data);
  final id = ChatIdFormat.rawUserUid(item.id);
  data['friendUserId'] = id;
  data['itemVersion'] = item.itemVersion;
  final record = MeFriendRecord.fromJson(data);
  return record.copyWith(
    friendUserId: id,
    itemVersion: item.itemVersion,
  );
}

MeFriendRecord? meFriendRecordFromSyncChangeEvent(SyncChangeEvent event) {
  if (event.isDelete) {
    return null;
  }
  final data = Map<String, dynamic>.from(event.data);
  final id = ChatIdFormat.rawUserUid(event.id);
  data['friendUserId'] = id;
  data['itemVersion'] = event.itemVersion;
  final record = MeFriendRecord.fromJson(data);
  return record.copyWith(
    friendUserId: id,
    itemVersion: event.itemVersion,
  );
}
