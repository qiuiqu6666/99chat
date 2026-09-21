import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_member_change.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_join_option.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_leave_diag_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_governance_trace.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/object_url_normalize.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';

import 'api_client.dart';
import '../services/network/network_task_scheduler.dart';
import '../services/session_identity.dart';

/// `/me/groups` 分页拉取中被调用方中止（滚动让路等）。
class MeGroupsFetchAborted implements Exception {
  const MeGroupsFetchAborted();

  @override
  String toString() => 'MeGroupsFetchAborted';
}

class GroupMembersRoleQuery {
  static const admins = 'admins';
  static const members = 'members';

  static bool isValid(String? role) =>
      role == null || role == admins || role == members;
}

class GroupMembersPage {
  const GroupMembersPage({
    required this.groupId,
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    this.hasMore,
  });

  final String groupId;
  final List<GroupMemberRecord> items;
  final int total;
  final int limit;
  final int offset;
  final bool? hasMore;
}

class MeGroupsPage {
  const MeGroupsPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    this.hasMore,
  });

  final List<MeGroupRecord> items;
  final int total;
  final int limit;
  final int offset;
  final bool? hasMore;
}

class MutedGroupMemberRecord {
  const MutedGroupMemberRecord({
    required this.userId,
    required this.muteUntilSec,
    required this.nameCard,
    required this.imRole,
    this.nickname,
    this.avatarUrl,
  });

  final String userId;
  final int muteUntilSec;
  final String nameCard;
  final String imRole;
  /// Null means omitted; an explicit empty string means no public value.
  final String? nickname;
  final String? avatarUrl;

  factory MutedGroupMemberRecord.fromJson(Map<String, dynamic> json) {
    String? profileField(List<String> keys) {
      for (final key in keys) {
        if (!json.containsKey(key)) continue;
        final value = json[key];
        if (value == null) return '';
        if (value is String) return value.trim();
      }
      return null;
    }
    return MutedGroupMemberRecord(
      nickname: profileField(const ['nickname', 'nickName']),
      avatarUrl: profileField(const ['avatarUrl', 'avatar_url', 'faceUrl']),
      userId: ChatIdFormat.rawUserUid(
        json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      ),
      muteUntilSec: MeGroupApi._parseMuteUntil(
        json['muteUntilSec'] ?? json['mute_until_sec'] ?? json['muteUntil'],
      ),
      nameCard: json['nameCard']?.toString().trim() ??
          json['name_card']?.toString().trim() ??
          '',
      imRole: json['imRole']?.toString().trim() ??
          json['im_role']?.toString().trim() ??
          '',
    );
  }
}

class GroupMutedMembersResponse {
  const GroupMutedMembersResponse({
    required this.members,
    required this.isAllMuted,
  });

  final List<MutedGroupMemberRecord> members;
  final bool isAllMuted;
}

enum GroupKickMemberStatus { removed, failed }

class GroupKickMemberResult {
  const GroupKickMemberResult({
    required this.userId,
    required this.status,
    this.code,
  });

  final String userId;
  final GroupKickMemberStatus status;
  final String? code;

  factory GroupKickMemberResult.fromJson(Map<String, dynamic> json) {
    final userId = ChatIdFormat.rawUserUid(
      json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
    );
    final statusRaw = json['status']?.toString().trim().toLowerCase() ?? '';
    final status = statusRaw == 'removed'
        ? GroupKickMemberStatus.removed
        : GroupKickMemberStatus.failed;
    return GroupKickMemberResult(
      userId: userId,
      status: status,
      code: json['code']?.toString(),
    );
  }
}

class GroupKickMembersResponse {
  const GroupKickMembersResponse({
    required this.groupId,
    required this.results,
    this.memberCount,
    this.topLevelCode,
  });

  final String groupId;
  final List<GroupKickMemberResult> results;
  final int? memberCount;
  final String? topLevelCode;

  List<String> get removedUserIds => results
      .where((item) => item.status == GroupKickMemberStatus.removed)
      .map((item) => item.userId)
      .where((id) => id.isNotEmpty)
      .toList(growable: false);

  bool get hasRemoved =>
      results.any((item) => item.status == GroupKickMemberStatus.removed);

  bool get allFailed =>
      results.isNotEmpty &&
      results.every((item) => item.status == GroupKickMemberStatus.failed);

  factory GroupKickMembersResponse.fromPayload(
    dynamic payload, {
    required String groupId,
    required List<String> requested,
  }) {
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      final rawResults = map['results'] ?? map['items'];
      if (rawResults is List && rawResults.isNotEmpty) {
        final parsed = rawResults
            .whereType<Map>()
            .map(
              (item) => GroupKickMemberResult.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false);
        if (parsed.isNotEmpty) {
          return GroupKickMembersResponse(
            groupId: _readGroupId(map['groupId'] ?? map['group_id'], groupId),
            results: parsed,
            memberCount: _optionalInt(
              map['memberCount'] ?? map['member_count'],
            ),
          );
        }
      }
      final code = map['code']?.toString();
      if (code != null && code.isNotEmpty) {
        return GroupKickMembersResponse(
          groupId: groupId,
          results: requested
              .map(
                (userId) => GroupKickMemberResult(
                  userId: userId,
                  status: GroupKickMemberStatus.failed,
                  code: code,
                ),
              )
              .toList(growable: false),
          topLevelCode: code,
        );
      }
    }
    return GroupKickMembersResponse(
      groupId: groupId,
      results: requested
          .map(
            (userId) => GroupKickMemberResult(
              userId: userId,
              status: GroupKickMemberStatus.failed,
              code: 'INVALID_RESPONSE',
            ),
          )
          .toList(growable: false),
      topLevelCode: 'INVALID_RESPONSE',
    );
  }

  factory GroupKickMembersResponse.fromDioError(
    DioError error, {
    required String groupId,
    required List<String> requested,
  }) {
    return GroupKickMembersResponse(
      groupId: groupId,
      results: requested
          .map(
            (userId) => GroupKickMemberResult(
              userId: userId,
              status: GroupKickMemberStatus.failed,
              code: MeGroupApi.readDioCode(error),
            ),
          )
          .toList(growable: false),
      topLevelCode: MeGroupApi.readDioCode(error),
    );
  }

  static int? _optionalInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _readGroupId(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isNotEmpty ? text : fallback;
  }
}

enum GroupMemberRoleBatchStatus { accepted, failed }

class GroupMemberRoleBatchResult {
  const GroupMemberRoleBatchResult({
    required this.userId,
    required this.status,
    this.code,
  });

  final String userId;
  final GroupMemberRoleBatchStatus status;
  final String? code;

  factory GroupMemberRoleBatchResult.fromJson(Map<String, dynamic> json) {
    final userId = ChatIdFormat.rawUserUid(
      json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
    );
    final statusRaw = json['status']?.toString().trim().toLowerCase() ?? '';
    final status = statusRaw == 'accepted'
        ? GroupMemberRoleBatchStatus.accepted
        : GroupMemberRoleBatchStatus.failed;
    return GroupMemberRoleBatchResult(
      userId: userId,
      status: status,
      code: json['code']?.toString(),
    );
  }
}

class GroupMemberRoleBatchResponse {
  const GroupMemberRoleBatchResponse({
    required this.groupId,
    required this.role,
    required this.results,
    this.topLevelCode,
  });

  final String groupId;
  final int role;
  final List<GroupMemberRoleBatchResult> results;
  final String? topLevelCode;

  List<String> get acceptedUserIds => results
      .where((item) => item.status == GroupMemberRoleBatchStatus.accepted)
      .map((item) => item.userId)
      .where((id) => id.isNotEmpty)
      .toList(growable: false);

  bool get hasAccepted => acceptedUserIds.isNotEmpty;

  bool get allFailed =>
      results.isNotEmpty &&
      results.every((item) => item.status == GroupMemberRoleBatchStatus.failed);

  factory GroupMemberRoleBatchResponse.fromPayload(
    dynamic payload, {
    required String groupId,
    required int role,
    required List<String> requested,
  }) {
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      final parsedRole = _optionalInt(map['role']) ?? role;
      final rawResults = map['results'] ?? map['items'];
      if (rawResults is List && rawResults.isNotEmpty) {
        final parsed = rawResults
            .whereType<Map>()
            .map(
              (item) => GroupMemberRoleBatchResult.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false);
        if (parsed.isNotEmpty) {
          return GroupMemberRoleBatchResponse(
            groupId: _readGroupId(map['groupId'] ?? map['group_id'], groupId),
            role: parsedRole,
            results: parsed,
          );
        }
      }
      final code = map['code']?.toString();
      if (code != null && code.isNotEmpty) {
        return GroupMemberRoleBatchResponse(
          groupId: groupId,
          role: parsedRole,
          results: requested
              .map(
                (userId) => GroupMemberRoleBatchResult(
                  userId: userId,
                  status: GroupMemberRoleBatchStatus.failed,
                  code: code,
                ),
              )
              .toList(growable: false),
          topLevelCode: code,
        );
      }
      // 无 results 但 HTTP 已成功：视为整批 accepted（兼容精简响应）。
      if (requested.isNotEmpty &&
          (code == null || code.isEmpty || code.toLowerCase() == 'ok')) {
        return GroupMemberRoleBatchResponse(
          groupId: _readGroupId(map['groupId'] ?? map['group_id'], groupId),
          role: parsedRole,
          results: requested
              .map(
                (userId) => GroupMemberRoleBatchResult(
                  userId: userId,
                  status: GroupMemberRoleBatchStatus.accepted,
                ),
              )
              .toList(growable: false),
        );
      }
    }
    return GroupMemberRoleBatchResponse(
      groupId: groupId,
      role: role,
      results: requested
          .map(
            (userId) => GroupMemberRoleBatchResult(
              userId: userId,
              status: GroupMemberRoleBatchStatus.failed,
              code: 'INVALID_RESPONSE',
            ),
          )
          .toList(growable: false),
      topLevelCode: 'INVALID_RESPONSE',
    );
  }

  factory GroupMemberRoleBatchResponse.fromDioError(
    DioError error, {
    required String groupId,
    required int role,
    required List<String> requested,
  }) {
    return GroupMemberRoleBatchResponse(
      groupId: groupId,
      role: role,
      results: requested
          .map(
            (userId) => GroupMemberRoleBatchResult(
              userId: userId,
              status: GroupMemberRoleBatchStatus.failed,
              code: MeGroupApi.readDioCode(error),
            ),
          )
          .toList(growable: false),
      topLevelCode: MeGroupApi.readDioCode(error),
    );
  }

  static int? _optionalInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _readGroupId(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isNotEmpty ? text : fallback;
  }
}

class MeGroupWriteResult {
  const MeGroupWriteResult({
    required this.committed,
    this.group,
    this.errorCode = '',
  });

  final bool committed;
  final MeGroupRecord? group;
  final String errorCode;
}

/// 群列表、群资料、群成员 REST API（展示唯一数据源）。
class MeGroupApi {
  MeGroupApi._();

  static final MeGroupApi instance = MeGroupApi._();

  final _confirmedDetails = <String,
      ({
    SessionIdentity identity,
    DateTime receivedAt,
    MeGroupRecord record,
  })>{};
  int _detailCacheGeneration = 0;
  int _detailRequestSequence = 0;
  final _detailRequests = <String, int>{};

  /// Only REST-confirmed roles may be reused by chat and profile views.
  MeGroupRecord? confirmedGroupDetail(String groupId) {
    final cached = _confirmedDetails[ChatIdFormat.apiGroupId(groupId)];
    if (cached == null ||
        !SessionIdentityService.instance.isCurrent(cached.identity) ||
        DateTime.now().difference(cached.receivedAt) >
            const Duration(minutes: 5)) {
      return null;
    }
    return cached.record;
  }

  void clearConfirmedGroupDetails() {
    _detailCacheGeneration++;
    _confirmedDetails.clear();
    _detailRequests.clear();
  }

  Dio get _dio => ApiClient.instance.dio;

  String _groupPath(String groupId) =>
      '/group/${Uri.encodeComponent(ChatIdFormat.apiGroupId(groupId))}';

  /// 默认 limit=100、上限 200（削峰）；`refresh=true` 仅建群失败 recovery 使用。
  ///
  /// 拼参铁律：只带合法数字/布尔；不传空串、`undefined`、`null`；
  /// `offset==0` 省略（走服务端默认）；`refresh` 仅在 `true` 时带 `refresh=true`。
  Future<MeGroupsPage> fetchMyGroupsPage({
    int limit = 100,
    int offset = 0,
    bool refresh = false,
    Map<String, MeGroupRecord> preserveIsAllMutedFrom = const {},
  }) async {
    final res = await NetworkTaskScheduler.instance.run(
      dedupeKey: 'me_groups:$offset:${refresh ? 1 : 0}',
      priority: refresh
          ? NetworkTaskPriority.userInitiated
          : NetworkTaskPriority.backgroundSync,
      task: () => _dio.get(
        '/me/groups',
        queryParameters: buildMeGroupsQuery(
          limit: limit,
          offset: offset,
          refresh: refresh,
        ),
      ),
    );
    return _parseGroupsPage(
      res.data,
      fallbackLimit: limit,
      fallbackOffset: offset,
      preserveIsAllMutedFrom: preserveIsAllMutedFrom,
    );
  }

  /// 构造 `/me/groups` query；保证不会出现空 key / 非法值（防 Spring 绑定 400）。
  @visibleForTesting
  static Map<String, dynamic> buildMeGroupsQuery({
    int? limit,
    int? offset,
    bool refresh = false,
  }) {
    final q = <String, dynamic>{};
    if (limit != null) {
      q['limit'] = limit.clamp(1, 200);
    }
    if (offset != null && offset > 0) {
      q['offset'] = offset;
    }
    if (refresh) {
      // 显式字符串，避免空串或其它非布尔字面量。
      q['refresh'] = 'true';
    }
    return q;
  }

  Future<List<MeGroupRecord>> fetchMyGroupsFromNetwork({
    bool refresh = false,
    Map<String, MeGroupRecord> preserveIsAllMutedFrom = const {},
    Future<bool> Function()? shouldContinueAfterPage,
    Future<void> Function(List<MeGroupRecord> page)? onPageLoaded,
    int? maxPages,
    void Function(bool complete)? onFetchComplete,
  }) async {
    final all = <MeGroupRecord>[];
    var offset = 0;
    const limit = 100;
    var total = 0;
    var emptyPageRetries = 0;
    var pageCount = 0;
    var complete = true;
    do {
      final page = await fetchMyGroupsPage(
        limit: limit,
        offset: offset,
        refresh: refresh && offset == 0,
        preserveIsAllMutedFrom: preserveIsAllMutedFrom,
      );
      pageCount++;
      all.addAll(page.items);
      if (page.items.isNotEmpty && onPageLoaded != null) {
        await onPageLoaded(page.items);
      }
      if (page.total > 0) {
        total = page.total;
      }
      final previousOffset = offset;
      offset += page.items.length;
      if (page.items.isEmpty) {
        final moreExpected =
            page.hasMore == true || (total > 0 && offset < total);
        // A transient empty page may still carry hasMore=true. Retry the same
        // offset a bounded number of times instead of treating it as an
        // authoritative end and losing the remaining groups on cold start.
        if (moreExpected && emptyPageRetries++ < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          offset = previousOffset;
          continue;
        }
        if (moreExpected) {
          throw StateError(
            '/me/groups incomplete at offset=$offset total=$total',
          );
        }
        break;
      }
      emptyPageRetries = 0;
      final more = page.hasMore ??
          (total > 0 ? offset < total : page.items.length >= limit);
      if (more && maxPages != null && pageCount >= maxPages) {
        complete = false;
        break;
      }
      if (more && shouldContinueAfterPage != null) {
        final ok = await shouldContinueAfterPage();
        if (!ok) {
          throw const MeGroupsFetchAborted();
        }
      }
      // Protect against a broken API repeatedly returning the same page.
      if (offset <= previousOffset) {
        break;
      }
      if (!more) {
        break;
      }
    } while (true);
    onFetchComplete?.call(complete);
    return all;
  }

  Future<MeGroupRecord?> fetchGroupDetail(
    String groupId, {
    bool refresh = false,
    MeGroupRecord? preserveIsAllMutedFrom,
    // Callers that own a metadata write generation commit the returned detail
    // themselves. Standalone detail requests persist before completing.
    bool persistLocally = true,
  }) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return null;
    }
    final authenticatedOwner = ChatIdFormat.rawUserUid(
      ApiClient.instance.authenticatedUserId,
    );
    final contactOwner = ChatIdFormat.rawUserUid(
      ContactSocialCacheStore.safeLoginUserId(),
    );
    if (authenticatedOwner.isNotEmpty &&
        contactOwner.isNotEmpty &&
        authenticatedOwner != contactOwner) {
      return null;
    }
    final identity = SessionIdentityService.instance.capture(
      ownerUserId: authenticatedOwner.isNotEmpty ? authenticatedOwner : null,
    );
    if (identity.ownerUserId.isEmpty) {
      return null;
    }
    bool isCurrentIdentity() {
      if (!SessionIdentityService.instance.isGenerationCurrent(
        identity.generation,
      )) {
        return false;
      }
      final currentAuthenticatedOwner = ChatIdFormat.rawUserUid(
        ApiClient.instance.authenticatedUserId,
      );
      final currentContactOwner = ChatIdFormat.rawUserUid(
        ContactSocialCacheStore.safeLoginUserId(),
      );
      if (currentAuthenticatedOwner.isEmpty && currentContactOwner.isEmpty) {
        return false;
      }
      return (currentAuthenticatedOwner.isEmpty ||
              currentAuthenticatedOwner == identity.ownerUserId) &&
          (currentContactOwner.isEmpty ||
              currentContactOwner == identity.ownerUserId);
    }

    if (!isCurrentIdentity()) {
      return null;
    }
    final apiId = ChatIdFormat.apiGroupId(id);
    final dedupeId = apiId.isNotEmpty ? apiId : id;
    final cacheGeneration = _detailCacheGeneration;
    final requestKey =
        '${identity.ownerUserId}:${identity.generation}:$dedupeId';
    final requestSequence = ++_detailRequestSequence;
    _detailRequests[requestKey] = requestSequence;
    final writeGeneration = persistLocally
        ? GroupLocalStore.instance.beginMetadataWrite(
            ownerUserId: identity.ownerUserId, groupId: id)
        : null;
    try {
      final payload = await NetworkTaskScheduler.instance.run<dynamic>(
        dedupeKey:
            'me_group_detail:${identity.ownerUserId}:${identity.generation}:'
            '$dedupeId:${refresh ? 1 : 0}',
        priority: refresh
            ? NetworkTaskPriority.userInitiated
            : NetworkTaskPriority.backgroundSync,
        task: () async {
          if (!isCurrentIdentity()) {
            return null;
          }
          final res = await _dio.get(
            _groupPath(id),
            queryParameters:
                refresh ? <String, dynamic>{'refresh': true} : null,
          );
          if (!isCurrentIdentity()) {
            return null;
          }
          return unwrapApiPayload(res.data);
        },
      );
      if (!isCurrentIdentity()) {
        return null;
      }
      if (payload is! Map) {
        return null;
      }
      final detail = MeGroupRecord.fromJson(
        Map<String, dynamic>.from(payload),
        preserveIsAllMutedFrom: preserveIsAllMutedFrom,
        authoritativeDetail: true,
      );
      if (persistLocally &&
          cacheGeneration == _detailCacheGeneration &&
          _detailRequests[requestKey] == requestSequence &&
          detail.groupId.trim().isNotEmpty &&
          GroupLocalStore.groupEquivalenceKey(detail.groupId) ==
              GroupLocalStore.groupEquivalenceKey(id)) {
        await GroupLocalStore.instance.upsert(
          ownerUserId: identity.ownerUserId,
          record: detail,
          writeGeneration: writeGeneration,
        );
        if (!isCurrentIdentity()) return null;
      }
      if (cacheGeneration == _detailCacheGeneration &&
          _detailRequests[requestKey] == requestSequence &&
          detail.groupId.trim().isNotEmpty &&
          detail.hasSuppliedField('myRole') &&
          const [200, 300, 400].contains(detail.myRole)) {
        _confirmedDetails.removeWhere((_, entry) =>
            !SessionIdentityService.instance.isCurrent(entry.identity));
        _confirmedDetails.remove(dedupeId);
        _confirmedDetails[dedupeId] = (
          identity: identity,
          receivedAt: DateTime.now(),
          record: detail,
        );
        while (_confirmedDetails.length > 64) {
          _confirmedDetails.remove(_confirmedDetails.keys.first);
        }
      }
      return detail;
    } finally {
      if (_detailRequests[requestKey] == requestSequence) {
        _detailRequests.remove(requestKey);
      }
    }
  }

  /// 全屏群头像预览专用。调用方只能在用户明确进入全屏预览后触发。
  Future<GroupAvatarPreviewResult> fetchGroupAvatarPreview(
    String groupId,
  ) async {
    final id = ChatIdFormat.apiGroupId(groupId);
    if (id.isEmpty) {
      throw const FormatException('groupId is empty');
    }
    final res = await _dio.get(
      '/groups/${Uri.encodeComponent(id)}/avatar-preview',
    );
    final payload = unwrapApiPayload(res.data);
    return GroupAvatarPreviewResult.fromJson(
      payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
    );
  }

  /// 单成员邀请来源；返回值仅包含邀请字段，不能覆盖完整成员资料。
  Future<GroupMemberRecord> fetchGroupMemberInviter({
    required String groupId,
    required String userId,
  }) async {
    final gid = ChatIdFormat.apiGroupId(groupId);
    final uid = ChatIdFormat.rawUserUid(userId);
    if (gid.isEmpty || uid.isEmpty) {
      throw const FormatException('groupId or userId is empty');
    }
    final res = await _dio.get(
      '${_groupPath(gid)}/members/${Uri.encodeComponent(uid)}/inviter',
    );
    final payload = unwrapApiPayload(res.data);
    if (payload is! Map) {
      throw const FormatException('Invalid member inviter response');
    }
    final record = GroupMemberRecord.fromJson(
      Map<String, dynamic>.from(payload),
    );
    if (record.userId != uid) {
      throw const FormatException('Member inviter response userId mismatch');
    }
    return record;
  }

  Future<GroupMembersPage> fetchGroupMembersPage({
    required String groupId,
    int limit = 50,
    int offset = 0,
    String? role,
  }) async {
    final candidates = ChatIdFormat.apiGroupIdCandidates(groupId);
    if (candidates.isEmpty || !GroupMembersRoleQuery.isValid(role)) {
      return const GroupMembersPage(
        groupId: '',
        items: <GroupMemberRecord>[],
        total: 0,
        limit: 50,
        offset: 0,
        hasMore: null,
      );
    }
    DioError? lastError;
    GroupMembersPage? lastEmpty;
    for (final id in candidates) {
      try {
        final res = await _dio.get(
          '${_groupPath(id)}/members',
          queryParameters: <String, dynamic>{
            'limit': limit.clamp(1, 100),
            'offset': offset < 0 ? 0 : offset,
            if (role != null) 'role': role,
          },
        );
        final page = _parseMembersPage(
          res.data,
          fallbackGroupId: id,
          fallbackLimit: limit,
          fallbackOffset: offset,
        );
        // A successful role-filtered page may legitimately be empty (no admins).
        // Only unfiltered first pages need the legacy group-ID fallback.
        if (role == null &&
            offset <= 0 &&
            page.items.isEmpty &&
            id != candidates.last) {
          lastEmpty = page;
          debugPrint('MeGroupApi.fetchGroupMembersPage empty retry id=$id');
          continue;
        }
        return page;
      } on DioError catch (error) {
        lastError = error;
        final status = error.response?.statusCode ?? 0;
        final code = readDioCode(error).toUpperCase();
        final retryable = status == 404 ||
            status == 400 ||
            code.contains('NOT_FOUND') ||
            code.contains('GROUP_NOT_FOUND') ||
            code.contains('INVALID');
        if (retryable && id != candidates.last) {
          debugPrint(
            'MeGroupApi.fetchGroupMembersPage retry id=$id status=$status code=$code',
          );
          continue;
        }
        rethrow;
      }
    }
    if (lastEmpty != null) {
      return lastEmpty;
    }
    if (lastError != null) {
      throw lastError;
    }
    return GroupMembersPage(
      groupId: candidates.first,
      items: const <GroupMemberRecord>[],
      total: 0,
      limit: limit,
      offset: offset,
      hasMore: null,
    );
  }

  Future<MeGroupWriteResult> updateGroup({
    required String groupId,
    String? groupName,
    String? notice,
  }) async {
    final id = groupId.trim();
    final body = <String, dynamic>{};
    if (groupName != null) {
      body['groupName'] = groupName.trim();
    }
    if (notice != null) {
      body['notice'] = notice;
    }
    try {
      final res = await _dio.put(_groupPath(id), data: body);
      final envelope = readApiWriteEnvelope(res.data);
      if (envelope.isBusinessError) {
        return MeGroupWriteResult(
          committed: false,
          errorCode: envelope.businessCode,
        );
      }
      return MeGroupWriteResult(
        committed: true,
        group: _tryParseCommittedGroup(
          envelope.payload,
          fallbackGroupId: id,
        ),
      );
    } on DioError catch (e) {
      return MeGroupWriteResult(
        committed: false,
        errorCode: readDioCode(e),
      );
    }
  }

  MeGroupRecord? _tryParseCommittedGroup(
    dynamic payload, {
    required String fallbackGroupId,
  }) {
    if (payload is! Map) {
      return null;
    }
    try {
      final map = Map<String, dynamic>.from(payload);
      for (final key in const ['group', 'groupProfile', 'profile']) {
        final nested = map[key];
        if (nested is Map) {
          final nestedMap = Map<String, dynamic>.from(nested);
          if (_readGroupIdFromMap(nestedMap) != null) {
            return MeGroupRecord.fromJson(nestedMap);
          }
        }
      }
      if (_readGroupIdFromMap(map) != null) {
        return MeGroupRecord.fromJson(map);
      }
      return null;
    } catch (e) {
      debugPrint(
        'group_update_committed_but_parse_failed groupId=$fallbackGroupId error=$e',
      );
      return null;
    }
  }

  Future<MeGroupRecord> createGroup({
    required String groupType,
    required String groupName,
    List<String> memberUserIds = const <String>[],
    String? avatarUrl,
    GroupJoinOptions? joinOptions,
    String? introduction,
  }) async {
    final normalizedMembers = memberUserIds
        .map(ChatIdFormat.rawUserUid)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final body = <String, dynamic>{
      'groupType': groupType.trim(),
      'groupName': groupName.trim(),
      if (normalizedMembers.isNotEmpty) 'memberUserIds': normalizedMembers,
      if (avatarUrl != null && avatarUrl.trim().isNotEmpty)
        'avatarUrl': avatarUrl.trim(),
      if (joinOptions != null) 'joinOptions': joinOptions.toJson(),
      if (introduction != null && introduction.trim().isNotEmpty)
        'introduction': introduction.trim(),
    };
    final res = await _dio.post('/group', data: body);
    return _parseCreateGroupResponse(res);
  }

  MeGroupRecord _parseCreateGroupResponse(Response<dynamic> res) {
    final payload = unwrapApiPayload(res.data);
    if (payload is! Map) {
      throw _invalidCreateGroupResponse(res, 'INVALID_RESPONSE');
    }
    final map = Map<String, dynamic>.from(payload);
    _throwIfCreateGroupBusinessError(map, res);

    for (final key in const ['group', 'groupProfile', 'profile']) {
      final nested = map[key];
      if (nested is Map) {
        final record = MeGroupRecord.fromJson(
          Map<String, dynamic>.from(nested),
        );
        if (record.groupId.trim().isNotEmpty) {
          return record;
        }
      }
    }

    final record = MeGroupRecord.fromJson(map);
    if (record.groupId.trim().isNotEmpty) {
      return record;
    }
    throw _invalidCreateGroupResponse(res, 'INVALID_RESPONSE');
  }

  void _throwIfCreateGroupBusinessError(
    Map<String, dynamic> map,
    Response<dynamic> res,
  ) {
    if (_readGroupIdFromMap(map) != null) {
      return;
    }
    final code = map['code']?.toString().trim() ?? '';
    if (code.isEmpty || code == '0' || code.toLowerCase() == 'ok') {
      return;
    }
    throw DioError(
      requestOptions: res.requestOptions,
      response: res,
      type: DioErrorType.response,
      error: code,
    );
  }

  String? _readGroupIdFromMap(Map<String, dynamic> map) {
    for (final key in const ['groupId', 'group_id', 'groupID']) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    for (final key in const ['group', 'groupProfile', 'profile']) {
      final nested = map[key];
      if (nested is Map) {
        final id = _readGroupIdFromMap(Map<String, dynamic>.from(nested));
        if (id != null) {
          return id;
        }
      }
    }
    return null;
  }

  DioError _invalidCreateGroupResponse(Response<dynamic> res, String code) {
    return DioError(
      requestOptions: res.requestOptions,
      response: res,
      type: DioErrorType.response,
      error: code,
    );
  }

  Future<V2TimCallback> leaveGroup(String groupId) async {
    final id = groupId.trim();
    final path = '${_groupPath(id)}/leave';
    GroupLeaveDiagLog.log(
      'leave_api_start',
      groupId: id,
      extras: <String, Object?>{'method': 'POST', 'path': path},
    );
    try {
      final res = await _dio.post(path);
      GroupLeaveDiagLog.log(
        'leave_api_ok',
        groupId: id,
        extras: <String, Object?>{'status': res.statusCode, 'body': res.data},
      );
      return successCallback();
    } on DioError catch (e) {
      final code = readDioCode(e);
      GroupLeaveDiagLog.log(
        'leave_api_fail',
        groupId: id,
        extras: <String, Object?>{
          'code': code,
          'status': e.response?.statusCode,
          'body': e.response?.data,
        },
      );
      return failureCallback(code);
    }
  }

  Future<V2TimCallback> dismissGroup(String groupId) async {
    final id = groupId.trim();
    final path = '${_groupPath(id)}/dismiss';
    GroupLeaveDiagLog.log(
      'dismiss_api_start',
      groupId: id,
      extras: <String, Object?>{'method': 'POST', 'path': path},
    );
    try {
      final res = await _dio.post(path);
      GroupLeaveDiagLog.log(
        'dismiss_api_ok',
        groupId: id,
        extras: <String, Object?>{'status': res.statusCode, 'body': res.data},
      );
      return successCallback();
    } on DioError catch (e) {
      final code = readDioCode(e);
      GroupLeaveDiagLog.log(
        'dismiss_api_fail',
        groupId: id,
        extras: <String, Object?>{
          'code': code,
          'status': e.response?.statusCode,
          'body': e.response?.data,
        },
      );
      return failureCallback(code);
    }
  }

  Future<V2TimCallback> kickMember({
    required String groupId,
    required String userId,
  }) async {
    final response = await kickMembers(groupId: groupId, userIds: [userId]);
    if (response.topLevelCode != null &&
        response.topLevelCode != 'ok' &&
        !response.hasRemoved) {
      return failureCallback(response.topLevelCode!);
    }
    if (!response.hasRemoved) {
      final firstCode =
          response.results.map((item) => item.code?.trim()).firstWhere(
                (code) => code != null && code.isNotEmpty,
                orElse: () => null,
              );
      return failureCallback(firstCode ?? 'KICK_FAILED');
    }
    return successCallback();
  }

  /// 批量踢人：`DELETE /group/{groupId}/members`，单次最多 100 人。
  Future<GroupKickMembersResponse> kickMembers({
    required String groupId,
    required List<String> userIds,
  }) async {
    final id = groupId.trim();
    final normalized = userIds
        .map(ChatIdFormat.rawUserUid)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (id.isEmpty || normalized.isEmpty) {
      return GroupKickMembersResponse(
        groupId: id,
        results: const <GroupKickMemberResult>[],
        topLevelCode: 'INVALID_INPUT',
      );
    }
    if (normalized.length > 100) {
      return GroupKickMembersResponse(
        groupId: id,
        results: normalized
            .map(
              (userId) => GroupKickMemberResult(
                userId: userId,
                status: GroupKickMemberStatus.failed,
                code: 'BATCH_TOO_LARGE',
              ),
            )
            .toList(growable: false),
        topLevelCode: 'BATCH_TOO_LARGE',
      );
    }
    try {
      final res = await _dio.delete(
        '${_groupPath(id)}/members',
        data: <String, dynamic>{'userIds': normalized},
      );
      return GroupKickMembersResponse.fromPayload(
        unwrapApiPayload(res.data),
        groupId: id,
        requested: normalized,
      );
    } on DioError catch (e) {
      return GroupKickMembersResponse.fromDioError(
        e,
        groupId: id,
        requested: normalized,
      );
    }
  }

  Future<GroupMemberRecord> setMemberRole({
    required String groupId,
    required String userId,
    required int role,
  }) async {
    final id = groupId.trim();
    final memberId = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty || memberId.isEmpty) {
      throw DioError(
        requestOptions: RequestOptions(path: _groupPath(id)),
        type: DioErrorType.other,
        error: 'INVALID_INPUT',
      );
    }
    final res = await _dio.put(
      '${_groupPath(id)}/members/${Uri.encodeComponent(memberId)}/role',
      data: <String, dynamic>{'role': role},
    );
    final parsed = _parseMemberRoleResponse(
      res.data,
      memberId: memberId,
      role: role,
    );
    if (parsed != null) {
      return parsed;
    }
    return GroupMemberRecord(
      userId: memberId,
      nickname: '',
      avatarUrl: '',
      friendRemark: '',
      nameCard: '',
      role: role,
      joinedAt: 0,
      isSelf: false,
    );
  }

  /// 批量设/取消管理员：`PUT /group/{groupId}/members/roles`（受理即返回）。
  ///
  /// 一次最多 30 人（去重后）；最终成功以 TCP `member_role_changed` 为准。
  Future<GroupMemberRoleBatchResponse> setMemberRoles({
    required String groupId,
    required int role,
    required List<String> userIds,
  }) async {
    final id = groupId.trim();
    final seen = <String>{};
    final normalized = <String>[];
    for (final raw in userIds) {
      final uid = ChatIdFormat.rawUserUid(raw);
      if (uid.isEmpty || !seen.add(uid)) {
        continue;
      }
      normalized.add(uid);
    }
    if (id.isEmpty || normalized.isEmpty) {
      return GroupMemberRoleBatchResponse(
        groupId: id,
        role: role,
        results: const <GroupMemberRoleBatchResult>[],
        topLevelCode: 'INVALID_INPUT',
      );
    }
    if (role != 200 && role != 300) {
      return GroupMemberRoleBatchResponse(
        groupId: id,
        role: role,
        results: normalized
            .map(
              (userId) => GroupMemberRoleBatchResult(
                userId: userId,
                status: GroupMemberRoleBatchStatus.failed,
                code: 'INVALID_INPUT',
              ),
            )
            .toList(growable: false),
        topLevelCode: 'INVALID_INPUT',
      );
    }
    if (normalized.length > 30) {
      return GroupMemberRoleBatchResponse(
        groupId: id,
        role: role,
        results: normalized
            .map(
              (userId) => GroupMemberRoleBatchResult(
                userId: userId,
                status: GroupMemberRoleBatchStatus.failed,
                code: 'BATCH_TOO_LARGE',
              ),
            )
            .toList(growable: false),
        topLevelCode: 'BATCH_TOO_LARGE',
      );
    }
    try {
      final res = await _dio.put(
        '${_groupPath(id)}/members/roles',
        data: <String, dynamic>{'role': role, 'userIds': normalized},
      );
      return GroupMemberRoleBatchResponse.fromPayload(
        unwrapApiPayload(res.data),
        groupId: id,
        role: role,
        requested: normalized,
      );
    } on DioError catch (e) {
      return GroupMemberRoleBatchResponse.fromDioError(
        e,
        groupId: id,
        role: role,
        requested: normalized,
      );
    }
  }

  GroupMemberRecord? _parseMemberRoleResponse(
    dynamic raw, {
    required String memberId,
    required int role,
  }) {
    final payload = unwrapApiPayload(raw);
    if (payload is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(payload);
    final nested = map['member'];
    if (nested is Map) {
      return GroupMemberRecord.fromJson(Map<String, dynamic>.from(nested));
    }
    if (map.containsKey('userId') ||
        map.containsKey('user_id') ||
        map.containsKey('role')) {
      return GroupMemberRecord.fromJson(map);
    }
    return null;
  }

  Future<V2TimCallback> transferOwner({
    required String groupId,
    required String newOwnerUserId,
  }) async {
    final id = groupId.trim();
    final ownerId = ChatIdFormat.rawUserUid(newOwnerUserId);
    if (id.isEmpty || ownerId.isEmpty) {
      GroupGovernanceTrace.log(
        'transfer_owner_invalid_input',
        extras: <String, Object?>{'groupId': id, 'newOwnerUserId': ownerId},
      );
      return failureCallback('INVALID_INPUT');
    }
    final path = '${_groupPath(id)}/transfer-owner';
    GroupGovernanceTrace.log(
      'transfer_owner_request',
      extras: <String, Object?>{
        'method': 'POST',
        'path': path,
        'groupId': id,
        'newOwnerUserId': ownerId,
      },
    );
    try {
      final res = await _dio.post(
        path,
        data: <String, dynamic>{'newOwnerUserId': ownerId},
      );
      GroupGovernanceTrace.log(
        'transfer_owner_response',
        extras: <String, Object?>{
          'status': res.statusCode,
          'groupId': id,
          'newOwnerUserId': ownerId,
          'body': res.data,
        },
      );
      return successCallback();
    } on DioError catch (e) {
      final code = readDioCode(e);
      GroupGovernanceTrace.log(
        'transfer_owner_error',
        extras: <String, Object?>{
          'status': e.response?.statusCode,
          'groupId': id,
          'newOwnerUserId': ownerId,
          'code': code,
          'body': e.response?.data,
          'message': e.message,
        },
      );
      return failureCallback(code);
    }
  }

  Future<V2TimCallback> muteAllMembers({
    required String groupId,
    required bool shutUpAllMember,
  }) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return failureCallback('INVALID_INPUT');
    }
    try {
      final res = await _dio.put(
        '${_groupPath(id)}/mute-all',
        data: <String, dynamic>{'shutUpAllMember': shutUpAllMember},
      );
      final envelope = readApiWriteEnvelope(res.data);
      if (envelope.isBusinessError) {
        return failureCallback(envelope.businessCode);
      }
      return successCallback();
    } on DioError catch (e) {
      return failureCallback(readDioCode(e));
    }
  }

  Future<V2TimCallback> muteMember({
    required String groupId,
    required String userId,
    required int muteSeconds,
  }) async {
    final id = groupId.trim();
    final memberId = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty || memberId.isEmpty) {
      return failureCallback('INVALID_INPUT');
    }
    try {
      await _dio.put(
        '${_groupPath(id)}/members/${Uri.encodeComponent(memberId)}/mute',
        data: <String, dynamic>{'muteSeconds': muteSeconds},
      );
      return successCallback();
    } on DioError catch (e) {
      return failureCallback(readDioCode(e));
    }
  }

  Future<GroupMutedMembersResponse?> fetchMutedMembers(String groupId,
      {bool rethrowErrors = false}) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return null;
    }
    try {
      final res = await _dio.get('${_groupPath(id)}/members/muted');
      final payload = unwrapApiPayload(res.data);
      if (payload is! Map) {
        return null;
      }
      final map = Map<String, dynamic>.from(payload);
      final rawMembers = map['members'];
      final members = rawMembers is List
          ? rawMembers
              .whereType<Map>()
              .map(
                (item) => MutedGroupMemberRecord.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) => item.userId.isNotEmpty)
              .toList(growable: false)
          : const <MutedGroupMemberRecord>[];
      return GroupMutedMembersResponse(
        members: members,
        isAllMuted: _parseBool(map['isAllMuted'] ?? map['is_all_muted']),
      );
    } catch (e) {
      debugPrint('[MeGroupApi] fetchMutedMembers error: $e');
      if (rethrowErrors) rethrow;
      return null;
    }
  }

  Future<MeGroupRecord> updateMyNameCard({
    required String groupId,
    required String nameCard,
  }) async {
    final id = groupId.trim();
    final res = await _dio.put(
      '${_groupPath(id)}/members/me',
      data: <String, dynamic>{'nameCard': nameCard.trim()},
    );
    final envelope = readApiWriteEnvelope(res.data);
    if (envelope.isBusinessError) {
      throw DioError(
        requestOptions: res.requestOptions,
        response: res,
        type: DioErrorType.response,
        error: envelope.businessCode,
      );
    }
    final payload = envelope.payload;
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      if (map.containsKey('groupId') || map.containsKey('group_id')) {
        return MeGroupRecord.fromJson(map);
      }
      return MeGroupRecord(
        groupId: id,
        groupType: '',
        groupName: '',
        displayAlias: '',
        avatarUrl: '',
        notice: '',
        memberCount: 0,
        myRole: 0,
        myNameCard: nameCard.trim(),
        joinedAt: 0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    return MeGroupRecord(
      groupId: id,
      groupType: '',
      groupName: '',
      displayAlias: '',
      avatarUrl: '',
      notice: '',
      memberCount: 0,
      myRole: 0,
      myNameCard: nameCard.trim(),
      joinedAt: 0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  MeGroupsPage _parseGroupsPage(
    dynamic raw, {
    required int fallbackLimit,
    required int fallbackOffset,
    Map<String, MeGroupRecord> preserveIsAllMutedFrom = const {},
  }) {
    final payload = unwrapApiPayload(raw);
    if (payload is List) {
      final items = payload
          .whereType<Map>()
          .map((e) {
            final itemMap = Map<String, dynamic>.from(e);
            final groupId = itemMap['groupId']?.toString().trim() ??
                itemMap['group_id']?.toString().trim() ??
                itemMap['groupID']?.toString().trim() ??
                '';
            return MeGroupRecord.fromJson(
              itemMap,
              preserveIsAllMutedFrom: preserveIsAllMutedFrom[groupId],
            );
          })
          .where((e) => e.groupId.isNotEmpty)
          .toList(growable: false);
      return MeGroupsPage(
        items: items,
        total: 0,
        limit: fallbackLimit,
        offset: fallbackOffset,
      );
    }
    if (payload is! Map) {
      return MeGroupsPage(
        items: const <MeGroupRecord>[],
        total: 0,
        limit: fallbackLimit,
        offset: fallbackOffset,
      );
    }
    final map = Map<String, dynamic>.from(payload);
    final list = extractApiList(
      map,
      listKeys: const ['items', 'groups', 'results'],
    );
    final items = list
        .whereType<Map>()
        .map((e) {
          final itemMap = Map<String, dynamic>.from(e);
          final groupId = itemMap['groupId']?.toString().trim() ??
              itemMap['group_id']?.toString().trim() ??
              itemMap['groupID']?.toString().trim() ??
              '';
          return MeGroupRecord.fromJson(
            itemMap,
            preserveIsAllMutedFrom: preserveIsAllMutedFrom[groupId],
          );
        })
        .where((e) => e.groupId.isNotEmpty)
        .toList(growable: false);
    final hasMore = _optionalBool(
      map['hasMore'] ?? map['has_more'] ?? map['next'] ?? map['hasNext'],
    );
    return MeGroupsPage(
      items: items,
      total: _asInt(map['total'], fallback: 0),
      limit: _asInt(map['limit'], fallback: fallbackLimit),
      offset: _asInt(map['offset'], fallback: fallbackOffset),
      hasMore: hasMore,
    );
  }

  static bool? _optionalBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }

  GroupMembersPage _parseMembersPage(
    dynamic raw, {
    required String fallbackGroupId,
    required int fallbackLimit,
    required int fallbackOffset,
  }) {
    final payload = unwrapApiPayload(raw);
    if (payload is! Map) {
      return GroupMembersPage(
        groupId: fallbackGroupId,
        items: const <GroupMemberRecord>[],
        total: 0,
        limit: fallbackLimit,
        offset: fallbackOffset,
        hasMore: null,
      );
    }
    final map = Map<String, dynamic>.from(payload);
    final list = extractApiList(
      map,
      listKeys: const ['items', 'members', 'results'],
    );
    final items = list
        .whereType<Map>()
        .map((e) => GroupMemberRecord.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.userId.isNotEmpty)
        .toList(growable: false);
    return GroupMembersPage(
      groupId: _asString(map['groupId'] ?? map['group_id'], fallbackGroupId),
      items: items,
      // total 缺失时用 0 表示未知，禁止回落成 items.length（否则满页会被当成没有下一页）。
      total: _asInt(map['total'], fallback: 0),
      limit: _asInt(map['limit'], fallback: fallbackLimit),
      offset: _asInt(map['offset'], fallback: fallbackOffset),
      hasMore: _optionalBool(
        map['hasMore'] ?? map['has_more'] ?? map['next'] ?? map['hasNext'],
      ),
    );
  }

  static int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _asString(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isNotEmpty ? text : fallback;
  }

  static V2TimCallback successCallback() => V2TimCallback(code: 0, desc: 'ok');

  static V2TimCallback failureCallback(String desc) =>
      V2TimCallback(code: -1, desc: desc);

  static String readDioCode(DioError error) {
    final data = error.response?.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final code = map['code']?.toString().trim();
      if (code != null && code.isNotEmpty) {
        return code;
      }
      final message = map['message']?.toString().trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
    final message = error.message.trim();
    return message.isNotEmpty ? message : 'REQUEST_FAILED';
  }

  /// 查询当前用户在群中的禁言状态。
  /// GET /group/{groupId}/members/me/mute-status
  Future<({int muteUntil, bool isAllMuted})?> fetchMyMuteStatus(
    String groupId,
  ) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return null;
    }
    try {
      final res = await _dio.get('${_groupPath(id)}/members/me/mute-status');
      final payload = unwrapApiPayload(res.data);
      if (payload is! Map) {
        return null;
      }
      final map = Map<String, dynamic>.from(payload);
      final muteUntil = _parseMuteUntil(map['muteUntil'] ?? map['mute_until']);
      final isAllMuted = _parseBool(map['isAllMuted'] ?? map['is_all_muted']);
      return (muteUntil: muteUntil, isAllMuted: isAllMuted);
    } catch (_) {
      return null;
    }
  }

  /// 群成员流增量：`GET /me/groups/{groupId}/members/changes?since_seq=`
  Future<GroupMemberChangesPage> fetchGroupMemberChanges({
    required String groupId,
    required int sinceSeq,
    int limit = 100,
  }) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return const GroupMemberChangesPage(
        nextSeq: 0,
        hasMore: false,
        events: <GroupMemberChangeEvent>[],
      );
    }
    final safeLimit = limit.clamp(1, 200);
    final since = sinceSeq < 0 ? 0 : sinceSeq;
    final encoded = Uri.encodeComponent(ChatIdFormat.apiGroupId(id));
    try {
      final res = await _dio.get(
        '/me/groups/$encoded/members/changes',
        queryParameters: <String, dynamic>{
          'since_seq': since,
          'limit': safeLimit,
        },
      );
      final payload = unwrapApiPayload(res.data);
      if (payload is Map) {
        return GroupMemberChangesPage.fromJson(
          Map<String, dynamic>.from(payload),
        );
      }
      return const GroupMemberChangesPage(
        nextSeq: 0,
        hasMore: false,
        events: <GroupMemberChangeEvent>[],
      );
    } on DioError catch (e) {
      final code = readDioCode(e).toUpperCase();
      final status = e.response?.statusCode;
      if (status == 410 ||
          code.contains('CURSOR_EXPIRED') ||
          code.contains('SEQ_EXPIRED') ||
          code.contains('INVALID_CURSOR') ||
          code.contains('CURSOR_INVALID')) {
        throw GroupMemberCursorExpiredException(code);
      }
      rethrow;
    }
  }

  static int _parseMuteUntil(dynamic value) {
    if (value == null) return 0;
    int parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else {
      parsed = int.tryParse(value?.toString() ?? '') ?? 0;
    }
    if (parsed <= 0) return 0;
    // 毫秒转秒
    return parsed >= 1000000000000 ? parsed ~/ 1000 : parsed;
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }
}

class GroupAvatarPreviewResult {
  const GroupAvatarPreviewResult({
    required this.previewUrl,
    required this.avatarVersion,
  });

  final String previewUrl;
  final int avatarVersion;

  factory GroupAvatarPreviewResult.fromJson(Map<String, dynamic> json) {
    return GroupAvatarPreviewResult(
      previewUrl: normalizeObjectUrl(
        (json['previewUrl'] ?? json['preview_url'])?.toString().trim() ?? '',
      ),
      avatarVersion: _readIntValue(
        json['avatarVersion'] ?? json['avatar_version'],
      ),
    );
  }
}

int _readIntValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}
