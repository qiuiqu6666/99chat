import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/object_url_normalize.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';

class MeGroupRecord {
  MeGroupRecord({
    required this.groupId,
    required this.groupType,
    required this.groupName,
    required this.displayAlias,
    required this.avatarUrl,
    this.avatarPreviewUrl = '',
    this.avatarVersion = 0,
    required this.notice,
    required this.memberCount,
    required this.myRole,
    required this.myNameCard,
    required this.joinedAt,
    required this.updatedAt,
    this.ownerUserId = '',
    this.noticeUpdatedAt = 0,
    this.noticeUpdatedBy = '',
    this.isAllMuted = false,
    this.gameEnabled = false,
    Set<String>? suppliedFields,
  }) : _suppliedFields =
            suppliedFields == null ? null : Set.unmodifiable(suppliedFields);

  // Transport-only presence information; persisted records are complete.
  // Empty/zero/false supplied by the server remain explicit updates.
  final Set<String>? _suppliedFields;

  /// Whether a transport payload explicitly supplied [field]. Persisted
  /// records have no presence metadata, so callers can distinguish an
  /// unknown field from an intentional empty/zero update before applying a
  /// display-only fallback.
  bool hasSuppliedField(String field) =>
      _suppliedFields?.contains(field) ?? false;

  MeGroupRecord resolvingMissingFieldsFrom(MeGroupRecord? previous) {
    final supplied = _suppliedFields;
    if (supplied == null || previous == null) return this;
    return MeGroupRecord(
      groupId: groupId,
      groupType:
          supplied.contains('groupType') ? groupType : previous.groupType,
      groupName:
          supplied.contains('groupName') ? groupName : previous.groupName,
      displayAlias: supplied.contains('displayAlias')
          ? displayAlias
          : previous.displayAlias,
      avatarUrl:
          supplied.contains('avatarUrl') ? avatarUrl : previous.avatarUrl,
      avatarPreviewUrl: supplied.contains('avatarPreviewUrl')
          ? avatarPreviewUrl
          : previous.avatarPreviewUrl,
      avatarVersion: supplied.contains('avatarVersion')
          ? avatarVersion
          : previous.avatarVersion,
      notice: supplied.contains('notice') ? notice : previous.notice,
      memberCount:
          supplied.contains('memberCount') ? memberCount : previous.memberCount,
      myRole: supplied.contains('myRole') ? myRole : previous.myRole,
      myNameCard:
          supplied.contains('myNameCard') ? myNameCard : previous.myNameCard,
      joinedAt: supplied.contains('joinedAt') ? joinedAt : previous.joinedAt,
      updatedAt:
          supplied.contains('updatedAt') ? updatedAt : previous.updatedAt,
      ownerUserId:
          supplied.contains('ownerUserId') ? ownerUserId : previous.ownerUserId,
      noticeUpdatedAt: supplied.contains('noticeUpdatedAt')
          ? noticeUpdatedAt
          : previous.noticeUpdatedAt,
      noticeUpdatedBy: supplied.contains('noticeUpdatedBy')
          ? noticeUpdatedBy
          : previous.noticeUpdatedBy,
      isAllMuted:
          supplied.contains('isAllMuted') ? isAllMuted : previous.isAllMuted,
      gameEnabled:
          supplied.contains('gameEnabled') ? gameEnabled : previous.gameEnabled,
    );
  }

  final String groupId;
  final String groupType;
  final String groupName;
  final String displayAlias;
  final String avatarUrl;
  final String avatarPreviewUrl;
  final int avatarVersion;
  final String notice;
  final int memberCount;
  final int myRole;
  final String myNameCard;
  final int joinedAt;
  final int updatedAt;
  final String ownerUserId;
  final int noticeUpdatedAt;

  /// 最近修改群公告的用户 userId；历史数据可能为空。
  final String noticeUpdatedBy;
  final bool isAllMuted;

  /// 后端群资料开关；缺失或无法解析时按关闭处理。
  final bool gameEnabled;

  MeGroupRecord copyWith({
    String? groupId,
    String? groupType,
    String? groupName,
    String? displayAlias,
    String? avatarUrl,
    String? avatarPreviewUrl,
    int? avatarVersion,
    String? notice,
    int? memberCount,
    int? myRole,
    String? myNameCard,
    int? joinedAt,
    int? updatedAt,
    String? ownerUserId,
    int? noticeUpdatedAt,
    String? noticeUpdatedBy,
    bool? isAllMuted,
    bool? gameEnabled,
  }) {
    return MeGroupRecord(
      groupId: groupId ?? this.groupId,
      groupType: groupType ?? this.groupType,
      groupName: groupName ?? this.groupName,
      displayAlias: displayAlias ?? this.displayAlias,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarPreviewUrl: avatarPreviewUrl ?? this.avatarPreviewUrl,
      avatarVersion: avatarVersion ?? this.avatarVersion,
      notice: notice ?? this.notice,
      memberCount: memberCount ?? this.memberCount,
      myRole: myRole ?? this.myRole,
      myNameCard: myNameCard ?? this.myNameCard,
      joinedAt: joinedAt ?? this.joinedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      noticeUpdatedAt: noticeUpdatedAt ?? this.noticeUpdatedAt,
      noticeUpdatedBy: noticeUpdatedBy ?? this.noticeUpdatedBy,
      isAllMuted: isAllMuted ?? this.isAllMuted,
      gameEnabled: gameEnabled ?? this.gameEnabled,
      suppliedFields: _suppliedFields == null
          ? null
          : <String>{
              ..._suppliedFields!,
              if (groupType != null) 'groupType',
              if (groupName != null) 'groupName',
              if (displayAlias != null) 'displayAlias',
              if (avatarUrl != null) 'avatarUrl',
              if (avatarPreviewUrl != null) 'avatarPreviewUrl',
              if (avatarVersion != null) 'avatarVersion',
              if (notice != null) 'notice',
              if (memberCount != null) 'memberCount',
              if (myRole != null) 'myRole',
              if (myNameCard != null) 'myNameCard',
              if (joinedAt != null) 'joinedAt',
              if (updatedAt != null) 'updatedAt',
              if (ownerUserId != null) 'ownerUserId',
              if (noticeUpdatedAt != null) 'noticeUpdatedAt',
              if (noticeUpdatedBy != null) 'noticeUpdatedBy',
              if (isAllMuted != null) 'isAllMuted',
              if (gameEnabled != null) 'gameEnabled',
            },
    );
  }

  factory MeGroupRecord.fromJson(
    Map<String, dynamic> json, {
    MeGroupRecord? preserveIsAllMutedFrom,
    bool authoritativeDetail = false,
  }) {
    final rawGroupId = _asString(
      json['groupId'] ?? json['group_id'] ?? json['groupID'],
    );
    // 本地存储/REST 用后端群 ID，禁止加成 `@TGS#_@TGS#`。
    final apiId = ChatIdFormat.apiGroupId(rawGroupId);
    final groupId = apiId.isNotEmpty ? apiId : rawGroupId;
    return MeGroupRecord(
      groupId: groupId,
      groupType: _asString(json['groupType'] ?? json['group_type']),
      groupName: _asString(json['groupName'] ?? json['group_name']),
      displayAlias: authoritativeDetail &&
              (json.containsKey('displayAlias') ||
                  json.containsKey('display_alias'))
          ? _asString(json['displayAlias'] ?? json['display_alias'])
          : ChatIdFormat.displayGroupAlias(
              _asString(json['displayAlias'] ?? json['display_alias']),
              groupIdFallback: rawGroupId,
            ),
      avatarUrl: normalizeObjectUrl(
        _asString(json['avatarUrl'] ?? json['avatar_url'] ?? json['faceUrl']),
      ),
      avatarPreviewUrl: normalizeObjectUrl(
        _asString(json['avatarPreviewUrl'] ?? json['avatar_preview_url']),
      ),
      avatarVersion: _asInt(json['avatarVersion'] ?? json['avatar_version']),
      notice: _asString(json['notice'] ?? json['notification']),
      memberCount: _asInt(json['memberCount'] ?? json['member_count']),
      myRole: _asInt(json['myRole'] ?? json['my_role'] ?? json['role']),
      myNameCard: _asString(json['myNameCard'] ?? json['my_name_card']),
      joinedAt: _parseTimestampMs(json['joinedAt'] ?? json['joined_at']),
      updatedAt: _parseTimestampMs(json['updatedAt'] ?? json['updated_at']),
      ownerUserId: _asString(json['ownerUserId'] ?? json['owner_user_id']),
      noticeUpdatedAt: _parseTimestampMs(
        json['noticeUpdatedAt'] ?? json['notice_updated_at'],
      ),
      noticeUpdatedBy: ChatIdFormat.rawUserUid(
        _asString(json['noticeUpdatedBy'] ?? json['notice_updated_by']),
      ),
      isAllMuted: jsonHasIsAllMutedField(json)
          ? parseBoolLikeIM(
              json['isAllMuted'] ??
                  json['is_all_muted'] ??
                  json['shutUpAllMember'] ??
                  json['shut_up_all_member'],
            )
          : (preserveIsAllMutedFrom?.isAllMuted ?? false),
      gameEnabled: parseBoolLikeIM(json['gameEnabled'] ?? json['game_enabled']),
      suppliedFields: <String>{
        if (json['groupType'] != null || json['group_type'] != null)
          'groupType',
        if (json['groupName'] != null || json['group_name'] != null)
          'groupName',
        if (json['displayAlias'] != null ||
            json['display_alias'] != null ||
            (authoritativeDetail &&
                (json.containsKey('displayAlias') ||
                    json.containsKey('display_alias'))))
          'displayAlias',
        if (json['avatarUrl'] != null ||
            json['avatar_url'] != null ||
            json['faceUrl'] != null)
          'avatarUrl',
        if (json['avatarPreviewUrl'] != null ||
            json['avatar_preview_url'] != null)
          'avatarPreviewUrl',
        if (json['avatarVersion'] != null || json['avatar_version'] != null)
          'avatarVersion',
        if (json['notice'] != null || json['notification'] != null) 'notice',
        if (json['memberCount'] != null || json['member_count'] != null)
          'memberCount',
        if (json['myRole'] != null ||
            json['my_role'] != null ||
            json['role'] != null)
          'myRole',
        if (json['myNameCard'] != null || json['my_name_card'] != null)
          'myNameCard',
        if (json['joinedAt'] != null ||
            json['joined_at'] != null ||
            (authoritativeDetail &&
                (json.containsKey('joinedAt') ||
                    json.containsKey('joined_at'))))
          'joinedAt',
        if (json['updatedAt'] != null || json['updated_at'] != null)
          'updatedAt',
        if (json['ownerUserId'] != null || json['owner_user_id'] != null)
          'ownerUserId',
        if (json['noticeUpdatedAt'] != null ||
            json['notice_updated_at'] != null ||
            (authoritativeDetail &&
                (json.containsKey('noticeUpdatedAt') ||
                    json.containsKey('notice_updated_at'))))
          'noticeUpdatedAt',
        if (json['noticeUpdatedBy'] != null ||
            json['notice_updated_by'] != null ||
            (authoritativeDetail &&
                (json.containsKey('noticeUpdatedBy') ||
                    json.containsKey('notice_updated_by'))))
          'noticeUpdatedBy',
        if (json['isAllMuted'] != null ||
            json['is_all_muted'] != null ||
            json['shutUpAllMember'] != null ||
            json['shut_up_all_member'] != null)
          'isAllMuted',
        if (json['gameEnabled'] != null || json['game_enabled'] != null)
          'gameEnabled',
      },
    );
  }

  /// REST `GET /group/{id}` 与群列表 item 目前不含禁言字段时，保留本地值。
  static bool jsonHasIsAllMutedField(Map<String, dynamic> json) {
    return json.containsKey('isAllMuted') ||
        json.containsKey('is_all_muted') ||
        json.containsKey('shutUpAllMember') ||
        json.containsKey('shut_up_all_member');
  }

  /// 兼容 REST bool 与 IM/TCP 的 `"On"` / `"Off"` 字符串。
  static bool parseBoolLikeIM(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = value?.toString().trim().toLowerCase() ?? '';
    if (text.isEmpty) {
      return false;
    }
    if (text == 'off' || text == 'false' || text == '0' || text == 'no') {
      return false;
    }
    return text == 'on' || text == 'true' || text == '1' || text == 'yes';
  }

  factory MeGroupRecord.fromV2TimGroupInfo(
    V2TimGroupInfo info, {
    MeGroupRecord? preserveFrom,
  }) {
    final custom = info.customInfo ?? const <String, String>{};
    final sdkRole = info.role ?? 0;
    final sdkCount = info.memberCount ?? 0;
    final gameFromCustom = custom.containsKey('gameEnabled')
        ? MeGroupRecord.parseBoolLikeIM(custom['gameEnabled'])
        : null;
    final joinMs = (info.joinTime ?? 0) > 0 ? (info.joinTime! * 1000) : 0;
    final infoMs =
        (info.lastInfoTime ?? 0) > 0 ? (info.lastInfoTime! * 1000) : 0;
    // A confirmed REST/local notice (including a clear) is newer than an
    // unversioned or older SDK snapshot. Keep its text and provenance together.
    final preserveNotice = preserveFrom != null &&
        preserveFrom.noticeUpdatedAt > 0 &&
        infoMs <= preserveFrom.noticeUpdatedAt;
    return MeGroupRecord(
      groupId: info.groupID,
      groupType: info.groupType.trim().isNotEmpty
          ? info.groupType.trim()
          : (preserveFrom?.groupType ?? ''),
      // SDK snapshots have no comparable group-name revision. Only fill an
      // unknown name; REST detail and confirmed edits own subsequent changes.
      groupName: (preserveFrom?.groupName ?? '').trim().isNotEmpty
          ? preserveFrom!.groupName
          : (info.groupName ?? '').trim(),
      displayAlias: (custom['displayAlias'] ?? '').trim().isNotEmpty
          ? custom['displayAlias']!.trim()
          : (preserveFrom?.displayAlias ?? ''),
      avatarUrl: (info.faceUrl ?? '').trim().isNotEmpty
          ? info.faceUrl!.trim()
          : (preserveFrom?.avatarUrl ?? ''),
      avatarPreviewUrl: preserveFrom?.avatarPreviewUrl ?? '',
      avatarVersion: preserveFrom?.avatarVersion ?? 0,
      notice: preserveNotice
          ? preserveFrom.notice
          : ((info.notification ?? '').trim().isNotEmpty
              ? info.notification!.trim()
              : (preserveFrom?.notice ?? '')),
      memberCount: sdkCount,
      myRole: sdkRole > 0 ? sdkRole : (preserveFrom?.myRole ?? 0),
      myNameCard: preserveFrom?.myNameCard ?? '',
      joinedAt: joinMs > 0 ? joinMs : (preserveFrom?.joinedAt ?? 0),
      updatedAt: infoMs > 0 ? infoMs : (preserveFrom?.updatedAt ?? 0),
      ownerUserId: (info.owner ?? '').trim().isNotEmpty
          ? ChatIdFormat.rawUserUid(info.owner)
          : (preserveFrom?.ownerUserId ?? ''),
      noticeUpdatedAt: preserveNotice
          ? preserveFrom.noticeUpdatedAt
          : (infoMs > 0 ? infoMs : (preserveFrom?.noticeUpdatedAt ?? 0)),
      noticeUpdatedBy: preserveNotice
          ? preserveFrom.noticeUpdatedBy
          : ((custom['noticeUpdatedBy'] ?? '').trim().isNotEmpty
              ? custom['noticeUpdatedBy']!.trim()
              : (preserveFrom?.noticeUpdatedBy ?? '')),
      isAllMuted: info.isAllMuted ?? preserveFrom?.isAllMuted ?? false,
      gameEnabled: gameFromCustom ?? (preserveFrom?.gameEnabled ?? false),
    );
  }

  V2TimGroupInfo toV2TimGroupInfo() {
    final customInfo = <String, String>{};
    if (displayAlias.isNotEmpty) {
      customInfo['displayAlias'] = displayAlias;
    }
    if (noticeUpdatedBy.isNotEmpty) {
      customInfo['noticeUpdatedBy'] = noticeUpdatedBy;
    }
    customInfo['gameEnabled'] = gameEnabled.toString();
    // IM：短码 m2… 原样；mc… → @TGS#_mc…；误加成 @TGS#_@TGS#m2… 回退短码。
    final imGroupId = ChatIdFormat.isIMGroupOrCommunityId(groupId)
        ? ChatIdFormat.normalizeGroupId(groupId)
        : groupId;
    return V2TimGroupInfo(
      groupID: imGroupId.isNotEmpty ? imGroupId : groupId,
      groupType: groupType,
      groupName: groupName,
      faceUrl: avatarUrl,
      notification: notice,
      memberCount: memberCount,
      role: myRole,
      owner: ownerUserId.isNotEmpty ? ownerUserId : null,
      joinTime: joinedAt > 0 ? joinedAt ~/ 1000 : null,
      lastInfoTime: noticeUpdatedAt > 0 ? noticeUpdatedAt ~/ 1000 : null,
      isAllMuted: isAllMuted,
      customInfo: customInfo.isEmpty ? null : customInfo,
    );
  }

  V2TimGroupInfoResult toV2TimGroupInfoResult() {
    return V2TimGroupInfoResult(
      resultCode: 0,
      resultMessage: '',
      groupInfo: toV2TimGroupInfo(),
    );
  }

  static String _asString(dynamic value) => value?.toString().trim() ?? '';

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _parseTimestampMs(dynamic value) {
    final parsed = _asInt(value);
    if (parsed <= 0) return 0;
    return parsed < 1000000000000 ? parsed * 1000 : parsed;
  }
}

class GroupMemberRecord {
  GroupMemberRecord({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.friendRemark,
    required this.nameCard,
    required this.role,
    required this.joinedAt,
    required this.isSelf,
    this.muteUntil = 0,
    this.invitedByUserId = '',
    this.invitedByNickname = '',
    this.joinChannel = '',
  });

  final String userId;
  final String nickname;
  final String avatarUrl;
  final String friendRemark;
  final String nameCard;
  final int role;
  final int joinedAt;
  final bool isSelf;
  final int muteUntil;

  /// 邀请人业务 userId；无则空串。
  final String invitedByUserId;

  /// 邀请人昵称；无则空串。
  final String invitedByNickname;

  /// `invite` | `group_id` | 空（历史/未知）。
  final String joinChannel;

  String get displayName {
    if (nameCard.trim().isNotEmpty) return nameCard.trim();
    if (friendRemark.trim().isNotEmpty) return friendRemark.trim();
    if (nickname.trim().isNotEmpty) return nickname.trim();
    return userId;
  }

  GroupMemberRecord copyWith({
    String? userId,
    String? nickname,
    String? avatarUrl,
    String? friendRemark,
    String? nameCard,
    int? role,
    int? joinedAt,
    bool? isSelf,
    int? muteUntil,
    String? invitedByUserId,
    String? invitedByNickname,
    String? joinChannel,
  }) {
    return GroupMemberRecord(
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      friendRemark: friendRemark ?? this.friendRemark,
      nameCard: nameCard ?? this.nameCard,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      isSelf: isSelf ?? this.isSelf,
      muteUntil: muteUntil ?? this.muteUntil,
      invitedByUserId: invitedByUserId ?? this.invitedByUserId,
      invitedByNickname: invitedByNickname ?? this.invitedByNickname,
      joinChannel: joinChannel ?? this.joinChannel,
    );
  }

  /// IM 回写不含邀请字段时，保留本地已有的入群时间 / 邀请人。
  GroupMemberRecord mergingJoinMetaFrom(GroupMemberRecord previous) {
    return copyWith(
      invitedByUserId: invitedByUserId.isNotEmpty
          ? invitedByUserId
          : previous.invitedByUserId,
      invitedByNickname: invitedByNickname.isNotEmpty
          ? invitedByNickname
          : previous.invitedByNickname,
      joinChannel:
          joinChannel.isNotEmpty ? joinChannel : previous.joinChannel,
      joinedAt: joinedAt > 0 ? joinedAt : previous.joinedAt,
    );
  }

  factory GroupMemberRecord.fromV2Tim(
    V2TimGroupMemberFullInfo member, {
    String selfUserId = '',
  }) {
    final userId = ChatIdFormat.rawUserUid(member.userID);
    return GroupMemberRecord(
      userId: userId,
      nickname: member.nickName ?? '',
      avatarUrl: member.faceUrl ?? '',
      friendRemark: member.friendRemark ?? '',
      nameCard: member.nameCard ?? '',
      role: member.role ?? 200,
      joinedAt: (member.joinTime ?? 0) > 0 ? member.joinTime! * 1000 : 0,
      isSelf:
          userId.isNotEmpty && userId == ChatIdFormat.rawUserUid(selfUserId),
      muteUntil: member.muteUntil ?? 0,
    );
  }

  factory GroupMemberRecord.fromJson(Map<String, dynamic> json) {
    return GroupMemberRecord(
      userId: ChatIdFormat.rawUserUid(
        json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      ),
      nickname: _asString(json['nickname'] ?? json['nickName']),
      avatarUrl: _asString(
        json['avatarUrl'] ?? json['avatar_url'] ?? json['faceUrl'],
      ),
      friendRemark: _asString(json['friendRemark'] ?? json['friend_remark']),
      nameCard: _asString(json['nameCard'] ?? json['name_card']),
      role: _asInt(json['role']),
      joinedAt: _parseTimestampMs(json['joinedAt'] ?? json['joined_at']),
      isSelf: _asBool(json['isSelf'] ?? json['is_self']),
      muteUntil: _parseMuteUntil(
        json['muteUntil'] ?? json['mute_until'] ?? json['muteUntilSec'],
      ),
      invitedByUserId: ChatIdFormat.rawUserUid(
        json['invitedByUserId']?.toString() ??
            json['invited_by_user_id']?.toString() ??
            '',
      ),
      invitedByNickname: _asString(
        json['invitedByNickname'] ?? json['invited_by_nickname'],
      ),
      joinChannel: _normalizeJoinChannel(
        json['joinChannel'] ?? json['join_channel'],
      ),
    );
  }

  static String _normalizeJoinChannel(dynamic value) {
    final raw = _asString(value).toLowerCase();
    if (raw == 'invite' || raw == 'group_id') {
      return raw;
    }
    return '';
  }

  static String _asString(dynamic value) => value?.toString().trim() ?? '';

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  static int _parseTimestampMs(dynamic value) {
    final parsed = _asInt(value);
    if (parsed <= 0) return 0;
    return parsed < 1000000000000 ? parsed * 1000 : parsed;
  }

  static int _parseMuteUntil(dynamic value) {
    final parsed = _asInt(value);
    if (parsed <= 0) return 0;
    return parsed >= 1000000000000 ? parsed ~/ 1000 : parsed;
  }
}
