import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';
import 'package:tencent_cloud_chat_demo/utils/group_avatar_source.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/user_display_profile.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

const int _searchDisplayImBatchSize = 100;

@visibleForTesting
Future<V2TimConversation?> Function(String conversationId)?
    debugSearchConversationLookup;

@visibleForTesting
Future<List<V2TimUserFullInfo>?> Function(List<String> userIds)?
    debugSearchGetUsersInfo;

@visibleForTesting
Future<List<V2TimGroupInfoResult>?> Function(List<String> groupIds)?
    debugSearchGetGroupsInfo;

final Map<String, Future<void>> _userHydrateFutures = <String, Future<void>>{};
final Map<String, Future<void>> _groupHydrateFutures = <String, Future<void>>{};

bool _usableAppFace(String? url) {
  final text = UserAvatarHelper.usableAvatarOrEmpty(url);
  if (text.isEmpty || text.startsWith('assets/')) {
    return false;
  }
  if (text == ConversationFaceUrl.defaultGroupFaceAsset) {
    return false;
  }
  return isUsableSearchFaceUrl(text);
}

@visibleForTesting
String sanitizedSearchUserNickName(String userId, String? nick) {
  final text = nick?.trim() ?? '';
  if (!isUsableSearchC2cDisplayName(text, userId)) {
    return '';
  }
  return text;
}

@visibleForTesting
String sanitizedSearchGroupName(String groupId, String? name) {
  final text = name?.trim() ?? '';
  if (!isUsableSearchGroupDisplayName(text, groupId)) {
    return '';
  }
  return text;
}

SearchConversationDisplay resolveAppSearchConversationDisplay({
  required String conversationId,
  V2TimFriendInfo? friendHint,
  V2TimGroupInfo? groupHint,
}) {
  final id = conversationId.trim();
  if (isGroupConversationId(id)) {
    return _resolveGroupDisplay(
      conversationId: id,
      groupHint: groupHint,
    );
  }
  return _resolveC2cDisplay(
    conversationId: id,
    friendHint: friendHint,
  );
}

SearchConversationDisplay _resolveGroupDisplay({
  required String conversationId,
  V2TimGroupInfo? groupHint,
}) {
  final groupId = groupIdFromConversationId(conversationId) ??
      searchStripConversationPrefix(conversationId);
  final hintName = (groupHint?.groupName ?? '').trim();
  final hintFace = (groupHint?.faceUrl ?? '').trim();
  String localName = '';
  try {
    localName = GroupLocalStore.instance
            .readCached(groupId: groupId)
            ?.groupName
            .trim() ??
        '';
  } catch (_) {
    localName = '';
  }
  final storeName = lookupSearchGroupStoreName(groupId)?.trim() ?? '';

  String name = '';
  if (isUsableSearchGroupDisplayName(localName, groupId)) {
    name = localName;
  } else if (isUsableSearchGroupDisplayName(hintName, groupId)) {
    name = hintName;
  } else if (isUsableSearchGroupDisplayName(storeName, groupId)) {
    name = storeName;
  } else {
    final resolved = preferSearchGroupShowName(
      groupName: hintName,
      storeName: storeName,
      localGroupName: localName,
      groupId: groupId,
    );
    name = isUsableSearchGroupDisplayName(resolved, groupId)
        ? resolved
        : groupId;
  }

  String face = '';
  if (_usableAppFace(hintFace)) {
    face = hintFace;
  } else {
    try {
      face = GroupAvatarSource.fromCached(
        groupId: groupId,
        fallbackUrl: hintFace,
      ).faceUrl.trim();
    } catch (_) {
      face = '';
    }
    if (!_usableAppFace(face)) {
      face = '';
    }
  }

  return buildSearchConversationDisplay(
    showName: name,
    faceUrl: face,
    isGroup: true,
    fallbackId: groupId,
  );
}

SearchConversationDisplay _resolveC2cDisplay({
  required String conversationId,
  V2TimFriendInfo? friendHint,
}) {
  final userId = conversationId.toLowerCase().startsWith('c2c_')
      ? conversationId.substring(4).trim()
      : conversationId;
  final hintRemark = (friendHint?.friendRemark ?? '').trim();
  final hintNick = (friendHint?.userProfile?.nickName ?? '').trim();
  final hintFace = (friendHint?.userProfile?.faceUrl ?? '').trim();

  String name = '';
  if (isUsableSearchC2cDisplayName(hintRemark, userId)) {
    name = hintRemark;
  } else if (isUsableSearchC2cDisplayName(hintNick, userId)) {
    name = hintNick;
  } else {
    final resolved = UserDisplayProfile.name(
      userId: userId,
      imRemark: hintRemark.isEmpty ? null : hintRemark,
      imNickName: hintNick.isEmpty ? null : hintNick,
    );
    name = isUsableSearchC2cDisplayName(resolved, userId) ? resolved : userId;
  }

  String face = '';
  if (_usableAppFace(hintFace)) {
    face = hintFace;
  } else {
    face = UserDisplayProfile.avatar(
      userId: userId,
      fallbackIm: hintFace,
    );
    if (!_usableAppFace(face)) {
      face = '';
    }
  }

  return buildSearchConversationDisplay(
    showName: name,
    faceUrl: face,
    isGroup: false,
    fallbackId: userId,
  );
}

Future<void> hydrateAppSearchConversationDisplays(
  List<String> conversationIds,
) async {
  final users = <String>{};
  final groups = <String>{};
  for (final raw in conversationIds) {
    final id = raw.trim();
    if (id.isEmpty) {
      continue;
    }
    final current = resolveAppSearchConversationDisplay(conversationId: id);
    if (!current.needsNameHydration && !current.needsFaceHydration) {
      continue;
    }
    if (current.isGroup) {
      groups.add(
        groupIdFromConversationId(id) ?? searchStripConversationPrefix(id),
      );
    } else {
      users.add(
        id.toLowerCase().startsWith('c2c_') ? id.substring(4).trim() : id,
      );
    }
  }
  users.removeWhere((id) => id.isEmpty);
  groups.removeWhere((id) => id.isEmpty);

  await Future.wait<void>([
    _hydrateUsers(users.toList(growable: false)),
    _hydrateGroups(groups.toList(growable: false)),
  ]);
}

Future<void> _hydrateUsers(List<String> userIds) async {
  if (userIds.isEmpty) {
    return;
  }
  final stillMissing = <String>[];
  for (final userId in userIds) {
    await _applyConversationProfile(userId: userId);
    final after = resolveAppSearchConversationDisplay(
      conversationId: 'c2c_$userId',
    );
    if (after.needsNameHydration || after.needsFaceHydration) {
      stillMissing.add(userId);
    }
  }
  if (stillMissing.isEmpty) {
    return;
  }
  await _fetchUsersDeduped(stillMissing);
}

Future<void> _hydrateGroups(List<String> groupIds) async {
  if (groupIds.isEmpty) {
    return;
  }
  final stillMissing = <String>[];
  for (final groupId in groupIds) {
    await _applyConversationProfile(groupId: groupId);
    final after = resolveAppSearchConversationDisplay(
      conversationId: 'group_$groupId',
    );
    if (after.needsNameHydration || after.needsFaceHydration) {
      stillMissing.add(groupId);
    }
  }
  if (stillMissing.isEmpty) {
    return;
  }
  await _fetchGroupsDeduped(stillMissing);
}

Future<void> _applyConversationProfile({
  String? userId,
  String? groupId,
}) async {
  final lookupId = userId != null && userId.isNotEmpty
      ? 'c2c_$userId'
      : (groupId != null && groupId.isNotEmpty ? 'group_$groupId' : '');
  if (lookupId.isEmpty) {
    return;
  }
  V2TimConversation? conversation;
  try {
    conversation = debugSearchConversationLookup != null
        ? await debugSearchConversationLookup!(lookupId)
        : await ConversationLocalStore.instance.conversationById(lookupId);
  } catch (_) {
    conversation = null;
  }
  if (conversation == null) {
    return;
  }
  if (userId != null && userId.isNotEmpty) {
    await _writeUserDisplayCache(
      userId: userId,
      nickName: conversation.showName,
      faceUrl: conversation.faceUrl,
    );
    return;
  }
  if (groupId != null && groupId.isNotEmpty) {
    await _writeGroupDisplayCache(
      groupId: groupId,
      groupType: conversation.groupType,
      groupName: conversation.showName,
      faceUrl: conversation.faceUrl,
    );
  }
}

Future<void> _fetchUsersDeduped(List<String> userIds) async {
  final toWait = <Future<void>>[];
  final toFetch = <String>[];
  for (final id in userIds) {
    final existing = _userHydrateFutures[id];
    if (existing != null) {
      toWait.add(existing);
    } else {
      toFetch.add(id);
    }
  }
  if (toFetch.isNotEmpty) {
    late final Future<void> fetch;
    fetch = () async {
      try {
        for (final chunk in _chunk(toFetch, _searchDisplayImBatchSize)) {
          await _fetchAndSaveUsers(chunk);
        }
      } finally {
        for (final id in toFetch) {
          _userHydrateFutures.remove(id);
        }
      }
    }();
    for (final id in toFetch) {
      _userHydrateFutures[id] = fetch;
    }
    toWait.add(fetch);
  }
  if (toWait.isNotEmpty) {
    await Future.wait(toWait);
  }
}

Future<void> _fetchGroupsDeduped(List<String> groupIds) async {
  final toWait = <Future<void>>[];
  final toFetch = <String>[];
  for (final id in groupIds) {
    final existing = _groupHydrateFutures[id];
    if (existing != null) {
      toWait.add(existing);
    } else {
      toFetch.add(id);
    }
  }
  if (toFetch.isNotEmpty) {
    late final Future<void> fetch;
    fetch = () async {
      try {
        for (final chunk in _chunk(toFetch, _searchDisplayImBatchSize)) {
          await _fetchAndSaveGroups(chunk);
        }
      } finally {
        for (final id in toFetch) {
          _groupHydrateFutures.remove(id);
        }
      }
    }();
    for (final id in toFetch) {
      _groupHydrateFutures[id] = fetch;
    }
    toWait.add(fetch);
  }
  if (toWait.isNotEmpty) {
    await Future.wait(toWait);
  }
}

Future<void> _fetchAndSaveUsers(List<String> userIds) async {
  List<V2TimUserFullInfo>? users;
  try {
    users = debugSearchGetUsersInfo != null
        ? await debugSearchGetUsersInfo!(userIds)
        : await serviceLocator<FriendshipServices>()
            .getUsersInfo(userIDList: userIds);
  } catch (_) {
    users = null;
  }
  for (final user in users ?? const <V2TimUserFullInfo>[]) {
    final id = user.userID?.trim() ?? '';
    if (id.isEmpty) {
      continue;
    }
    await _writeUserDisplayCache(
      userId: id,
      nickName: user.nickName,
      faceUrl: user.faceUrl,
    );
  }
}

Future<void> _fetchAndSaveGroups(List<String> groupIds) async {
  List<V2TimGroupInfoResult>? results;
  try {
    results = debugSearchGetGroupsInfo != null
        ? await debugSearchGetGroupsInfo!(groupIds)
        : await serviceLocator<GroupServices>()
            .getGroupsInfo(groupIDList: groupIds);
  } catch (_) {
    results = null;
  }
  for (final result in results ?? const <V2TimGroupInfoResult>[]) {
    final info = result.groupInfo;
    if (info == null) {
      continue;
    }
    await _writeGroupDisplayCache(
      groupId: info.groupID,
      groupType: info.groupType,
      groupName: info.groupName,
      faceUrl: info.faceUrl,
      preserveInfo: info,
    );
  }
}

Future<void> _writeUserDisplayCache({
  required String userId,
  String? nickName,
  String? faceUrl,
}) async {
  final id = userId.trim();
  if (id.isEmpty) {
    return;
  }
  final nick = sanitizedSearchUserNickName(id, nickName);
  final face = _usableAppFace(faceUrl) ? faceUrl!.trim() : '';
  if (nick.isEmpty && face.isEmpty) {
    return;
  }
  if (nick.isNotEmpty) {
    DisplayNameStore.instance.setC2C(id, nick, notify: false);
  }
  try {
    await UserProfileLocalService.instance.saveUserFullInfo(
      V2TimUserFullInfo(
        userID: id,
        nickName: nick,
        faceUrl: face,
      ),
    );
  } catch (_) {}
}

Future<void> _writeGroupDisplayCache({
  required String groupId,
  String? groupType,
  String? groupName,
  String? faceUrl,
  V2TimGroupInfo? preserveInfo,
}) async {
  final id = groupId.trim();
  if (id.isEmpty) {
    return;
  }
  final name = sanitizedSearchGroupName(id, groupName);
  final face = _usableAppFace(faceUrl) ? faceUrl!.trim() : '';
  if (name.isEmpty && face.isEmpty) {
    return;
  }
  final owner = GroupLocalStore.instance.currentOwnerUserId();
  final existing = GroupLocalStore.instance.readCached(groupId: id);
  final info = V2TimGroupInfo(
    groupID: id,
    groupType: (preserveInfo?.groupType ?? groupType ?? existing?.groupType ?? '')
        .trim(),
    groupName: name,
    faceUrl: face,
  );
  final record = MeGroupRecord.fromV2TimGroupInfo(
    info,
    preserveFrom: existing,
  );
  try {
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: record,
      fillMissingDisplayOnly: true,
    );
    if (GroupLocalStore.instance.currentOwnerUserId() != owner) return;
    final committedName = GroupLocalStore.instance
        .readCached(groupId: id, ownerUserId: owner)
        ?.groupName;
    final displayName = sanitizedSearchGroupName(id, committedName ?? name);
    if (displayName.isNotEmpty) {
      DisplayNameStore.instance.setGroup(id, displayName, notify: false);
    }
  } catch (_) {}
}

List<List<String>> _chunk(List<String> ids, int size) {
  if (ids.isEmpty) {
    return const <List<String>>[];
  }
  final out = <List<String>>[];
  for (var i = 0; i < ids.length; i += size) {
    final end = i + size > ids.length ? ids.length : i + size;
    out.add(ids.sublist(i, end));
  }
  return out;
}
