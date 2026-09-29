import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

typedef GroupMemberCloudSearchInvoke = Future<
        V2TimValueCallback<V2GroupMemberInfoSearchResult>>
    Function(V2TimGroupMemberSearchParam param);

class GroupMemberCloudSearchPage {
  const GroupMemberCloudSearchPage({
    required this.members,
    required this.usedCloud,
    required this.isFinished,
    required this.nextCursor,
  });

  final List<V2TimGroupMemberFullInfo> members;
  final bool usedCloud;
  final bool isFinished;
  final String nextCursor;
}

class GroupMemberCloudSearch {
  static const int pageSize = 100;
  static const Duration debounce = Duration(milliseconds: 300);

  static const GroupMemberCloudSearchPage skipped = GroupMemberCloudSearchPage(
    members: <V2TimGroupMemberFullInfo>[],
    usedCloud: false,
    isFinished: true,
    nextCursor: '',
  );

  static List<V2TimGroupMemberFullInfo> membersForGroup(
    V2GroupMemberInfoSearchResult? data,
    String groupId,
  ) {
    final map = data?.groupMemberSearchResultItems;
    if (map == null || map.isEmpty) {
      return const <V2TimGroupMemberFullInfo>[];
    }
    final wanted = groupId.trim();
    if (wanted.isEmpty) {
      return const <V2TimGroupMemberFullInfo>[];
    }

    List<V2TimGroupMemberFullInfo> parse(dynamic raw) {
      if (raw is List<V2TimGroupMemberFullInfo>) {
        return List<V2TimGroupMemberFullInfo>.from(raw);
      }
      if (raw is List) {
        return raw.whereType<V2TimGroupMemberFullInfo>().toList();
      }
      return const <V2TimGroupMemberFullInfo>[];
    }

    if (map.containsKey(wanted)) {
      return parse(map[wanted]);
    }
    if (map.containsKey(groupId)) {
      return parse(map[groupId]);
    }
    for (final entry in map.entries) {
      if (entry.key.trim() == wanted) {
        return parse(entry.value);
      }
    }
    if (map.length == 1) {
      return parse(map.values.first);
    }
    return const <V2TimGroupMemberFullInfo>[];
  }

  static Future<GroupMemberCloudSearchPage> searchPage({
    required String groupId,
    required String keyword,
    String cursor = '',
    GroupMemberCloudSearchInvoke? invoke,
    bool skipCloud = false,
  }) async {
    final trimmedGroup = groupId.trim();
    final trimmedKeyword = keyword.trim();
    if (skipCloud ||
        kIsWeb ||
        trimmedGroup.isEmpty ||
        trimmedKeyword.isEmpty) {
      return skipped;
    }
    try {
      final runner = invoke ?? _defaultCloudSearch;
      final res = await runner(
        V2TimGroupMemberSearchParam(
          keywordList: [trimmedKeyword],
          groupIDList: [trimmedGroup],
          searchCount: pageSize,
          searchCursor: cursor,
        ),
      );
      if (res.code != 0) {
        return skipped;
      }
      final nextCursor = (res.data?.nextCursor ?? '').trim();
      final finished = res.data?.isFinished ?? nextCursor.isEmpty;
      return GroupMemberCloudSearchPage(
        members: membersForGroup(res.data, trimmedGroup)
            .where((member) => !GroupMemberStore.instance
                .isRemovalTombstoned(trimmedGroup, member.userID))
            .toList(),
        usedCloud: true,
        isFinished: finished || nextCursor.isEmpty,
        nextCursor: nextCursor,
      );
    } catch (_) {
      return skipped;
    }
  }

  static Future<V2TimValueCallback<V2GroupMemberInfoSearchResult>>
      _defaultCloudSearch(V2TimGroupMemberSearchParam param) {
    return TencentImSDKPlugin.v2TIMManager
        .getGroupManager()
        .searchCloudGroupMembers(param: param);
  }
}

typedef GroupMemberLocalSearchFallback = Future<List<V2TimGroupMemberFullInfo>>
    Function(String keyword);

class GroupMemberCloudSearchController {
  GroupMemberCloudSearchController({
    required this.groupId,
    this.invoke,
    this.skipCloud = false,
    this.localFallback,
    this.onUpdate,
  });

  final String groupId;
  final GroupMemberCloudSearchInvoke? invoke;
  final bool skipCloud;
  final GroupMemberLocalSearchFallback? localFallback;
  final VoidCallback? onUpdate;

  List<V2TimGroupMemberFullInfo> members = <V2TimGroupMemberFullInfo>[];
  bool usedCloud = false;
  bool isFinished = true;
  String nextCursor = '';
  String keyword = '';
  int generation = 0;

  Timer? _timer;
  bool _disposed = false;
  bool _loadingMore = false;

  void onKeywordChanged(String text) {
    final trimmed = text.trim();
    if (trimmed == keyword) {
      return;
    }
    keyword = trimmed;
    _timer?.cancel();
    generation++;
    if (trimmed.isEmpty) {
      members = <V2TimGroupMemberFullInfo>[];
      usedCloud = false;
      isFinished = true;
      nextCursor = '';
      onUpdate?.call();
      return;
    }
    _timer = Timer(GroupMemberCloudSearch.debounce, () {
      unawaited(_search(replace: true));
    });
  }

  Future<void> loadMore() async {
    if (!usedCloud ||
        isFinished ||
        nextCursor.isEmpty ||
        _loadingMore ||
        keyword.isEmpty) {
      return;
    }
    await _search(replace: false);
  }

  Future<void> _search({required bool replace}) async {
    final gen = generation;
    final cursor = replace ? '' : nextCursor;
    if (!replace) {
      _loadingMore = true;
    }
    try {
      final page = await GroupMemberCloudSearch.searchPage(
        groupId: groupId,
        keyword: keyword,
        cursor: cursor,
        invoke: invoke,
        skipCloud: skipCloud,
      );
      if (_disposed || gen != generation) {
        return;
      }
      if (!page.usedCloud) {
        usedCloud = false;
        nextCursor = '';
        final fallback = localFallback == null || keyword.isEmpty
            ? const <V2TimGroupMemberFullInfo>[]
            : await localFallback!(keyword);
        if (_disposed || gen != generation) {
          return;
        }
        members = fallback
            .where((member) => !GroupMemberStore.instance
                .isRemovalTombstoned(groupId, member.userID))
            .toList();
        isFinished = true;
        onUpdate?.call();
        return;
      }
      usedCloud = true;
      isFinished = page.isFinished;
      nextCursor = page.nextCursor;
      if (replace) {
        members = page.members;
      } else {
        final existing = members
            .map((m) => m.userID.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        members = [
          ...members,
          ...page.members.where((m) => !existing.contains(m.userID.trim())),
        ];
      }
      onUpdate?.call();
    } finally {
      if (!replace) {
        _loadingMore = false;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
