import 'package:tencent_cloud_chat_uikit/ui/widgets/directory_list_row.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_input.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/tim_uikit_search_not_support.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tim_uikit_back_button.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

class TIMUIKitConversationMemberPickerPage extends StatefulWidget {
  const TIMUIKitConversationMemberPickerPage({
    super.key,
    required this.groupId,
    this.memberPresenceLabelBuilder,
    this.memberPresenceLoadingChecker,
    this.onMemberListLoaded,
    this.presenceListenable,
    this.cloudSearchInvoke,
  });

  final String groupId;
  @visibleForTesting
  final GroupMemberCloudSearchInvoke? cloudSearchInvoke;
  final MemberPresenceLabelBuilder? memberPresenceLabelBuilder;
  final MemberPresenceLoadingChecker? memberPresenceLoadingChecker;
  final void Function(List<String> userIds)? onMemberListLoaded;

  /// 业务侧在线状态刷新时触发列表重建（如 [ChangeNotifier]）。
  final Listenable? presenceListenable;

  @override
  State<TIMUIKitConversationMemberPickerPage> createState() =>
      _TIMUIKitConversationMemberPickerPageState();
}

class _TIMUIKitConversationMemberPickerPageState
    extends TIMUIKitState<TIMUIKitConversationMemberPickerPage> {
  static const _pageSize = 100;

  /// Bound each automatic batch; larger groups can continue from its cursor.
  static const _maxPages = 100;

  final GroupServices _groupServices = serviceLocator<GroupServices>();
  final FriendshipServices _friendshipServices =
      serviceLocator<FriendshipServices>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<V2TimGroupMemberFullInfo> _allMembers = [];
  Map<String, V2TimUserStatus> _userStatusById = {};
  bool _loading = false;
  bool _cacheHydrated = false;
  bool _membersComplete = false;
  bool _memberLoadFailed = false;
  String _nextMemberSeq = '0';
  final List<V2TimGroupMemberFullInfo> _remoteMembers = [];
  final Set<String> _remoteMemberIds = {};
  final Set<String> _completedMemberCursors = {};
  GroupMemberCloudSearchController? _cloudSearch;
  String _keyword = '';
  List<V2TimGroupMemberFullInfo> _searchMembers = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    widget.presenceListenable?.addListener(_onPresenceChanged);
    _loadMembers();
  }

  @override
  void dispose() {
    widget.presenceListenable?.removeListener(_onPresenceChanged);
    _cloudSearch?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onPresenceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<String> _memberUserIds(List<V2TimGroupMemberFullInfo> members) {
    return members
        .map((member) => member.userID?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _hydrateFromCache() async {
    if (!SelfHostedGroupBridge.enabled) {
      return;
    }
    final cached =
        await SelfHostedGroupBridge.loadCachedGroupMemberList(widget.groupId);
    if (!mounted || cached.isEmpty) {
      return;
    }
    final userIds = _memberUserIds(cached);
    setState(() {
      _allMembers = cached;
    });
    if (userIds.isNotEmpty) {
      widget.onMemberListLoaded?.call(userIds);
    }
  }

  Future<void> _loadMembers() async {
    if (_loading || _membersComplete) return;
    setState(() {
      _loading = true;
      _memberLoadFailed = false;
    });
    try {
      if (!_cacheHydrated) {
        _cacheHydrated = true;
        try {
          await _hydrateFromCache();
        } catch (error) {
          // Cache availability must not prevent a fresh member request.
          debugPrint('MemberPicker: cache read failed: $error');
        }
      }
      for (var pageCount = 0; mounted && pageCount < _maxPages; pageCount++) {
        final cursor = _nextMemberSeq;
        final res = await _groupServices.getGroupMemberList(
          groupID: widget.groupId,
          filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
          nextSeq: cursor,
          count: _pageSize,
        );
        if (!mounted) return;
        if (res.code != 0 || res.data == null) {
          _memberLoadFailed = true;
          break;
        }
        final page = (res.data!.memberInfoList ?? [])
            .whereType<V2TimGroupMemberFullInfo>()
            .where((member) => member.userID.trim().isNotEmpty)
            .toList();
        setState(() {
          _allMembers = mergeGroupMembersPreferIncoming(_allMembers, page);
        });
        // A local fallback is useful for display, but does not prove that the
        // server member list is complete. Retry the same remote cursor.
        if (res.desc == 'cached_page') {
          _memberLoadFailed = true;
          break;
        }
        for (final member in page) {
          if (_remoteMemberIds.add(member.userID.trim())) {
            _remoteMembers.add(member);
          }
        }
        final next = (res.data!.nextSeq ?? '').trim();
        if (next.isEmpty || next == '0') {
          _membersComplete = true;
          setState(() {
            _allMembers = List<V2TimGroupMemberFullInfo>.from(_remoteMembers);
          });
          break;
        }
        if (next == cursor || _completedMemberCursors.contains(next)) {
          _memberLoadFailed = true;
          break;
        }
        _completedMemberCursors.add(cursor);
        _nextMemberSeq = next;
      }
    } catch (error) {
      _memberLoadFailed = true;
      debugPrint('MemberPicker: member loading failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    final userIds = _memberUserIds(_allMembers);
    widget.onMemberListLoaded?.call(userIds);
    // Optional presence must never hold up the member list or its retry UI.
    unawaited(_refreshUserStatusInBackground(userIds));
  }

  bool _matchesMember(V2TimGroupMemberFullInfo member, String keyword) {
    return groupMemberMatchesKeyword(member, keyword) ||
        [member.nickName, member.nameCard, member.friendRemark].any(
          (name) => (name ?? '').toLowerCase().contains(keyword.toLowerCase()),
        );
  }

  void _onSearchChanged(String text, {bool force = false}) {
    final keyword = text.trim();
    if (_keyword == keyword && !force) return;
    // A new controller isolates both debounced and in-flight old queries.
    _cloudSearch?.dispose();
    _cloudSearch = null;
    setState(() {
      _keyword = keyword;
      _searchMembers = [];
      _searching = keyword.isNotEmpty;
    });
    if (keyword.isEmpty) return;
    _cloudSearch = GroupMemberCloudSearchController(
      groupId: widget.groupId,
      invoke: widget.cloudSearchInvoke,
      onUpdate: () {
        if (!mounted) return;
        setState(() {
          _searching = false;
          if (_cloudSearch?.usedCloud ?? false) {
            _searchMembers = List.of(_cloudSearch!.members);
          }
        });
        final ids = _memberUserIds(_searchMembers);
        if (ids.isNotEmpty) widget.onMemberListLoaded?.call(ids);
      },
    )..onKeywordChanged(keyword);
  }

  Future<void> _loadMoreSearch() async {
    final search = _cloudSearch;
    if (_searching ||
        search == null ||
        !search.usedCloud ||
        search.isFinished) {
      return;
    }
    setState(() => _searching = true);
    try {
      await search.loadMore();
    } finally {
      if (mounted && identical(search, _cloudSearch)) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _refreshUserStatusInBackground(List<String> userIds) async {
    try {
      await _loadUserStatus(userIds);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadUserStatus(List<String> userIds) async {
    if (userIds.isEmpty) {
      return;
    }
    const chunkSize = 500;
    final merged = <String, V2TimUserStatus>{};
    for (var i = 0; i < userIds.length; i += chunkSize) {
      final chunk = userIds.sublist(i, min(i + chunkSize, userIds.length));
      final statuses =
          await _friendshipServices.getUserStatus(userIDList: chunk);
      for (final status in statuses) {
        final id = status.userID?.trim() ?? '';
        if (id.isNotEmpty) {
          merged[id] = status;
        }
      }
    }
    _userStatusById = merged;
  }

  bool _isImOnline(String userId) {
    return _userStatusById[userId]?.statusType == 1;
  }

  String? _presenceSubtitle(String userId) {
    final builder = widget.memberPresenceLabelBuilder;
    if (builder == null) {
      return _isImOnline(userId) ? TIM_t('在线') : TIM_t('离线');
    }
    return builder(userId, _isImOnline(userId));
  }

  List<V2TimGroupMemberFullInfo> get _visibleMembers {
    if (_keyword.isEmpty) return _allMembers;
    final local = _allMembers
        .where((member) => _matchesMember(member, _keyword))
        .toList();
    return mergeGroupMembersPreferIncoming(local, _searchMembers);
  }

  Widget _buildMemberRow({
    required TUITheme theme,
    required V2TimGroupMemberFullInfo member,
    required String showName,
    required String userId,
  }) {
    final imOnline = _isImOnline(userId);
    final presenceLoading =
        widget.memberPresenceLoadingChecker?.call(userId, imOnline) ?? false;
    final subtitle = presenceLoading ? null : _presenceSubtitle(userId);
    final onlineStatus = _userStatusById[userId];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(member),
        child: DirectoryListRow(
          avatar: Avatar(
              faceUrl: member.faceUrl ?? '',
              showName: showName,
              onlineStatus: onlineStatus,
              borderRadius: BorderRadius.circular(999)),
          title: Text(showName,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  color: theme.darkTextColor)),
          subtitle: presenceLoading
              ? buildMemberPresenceSubtitleSkeleton(
                  baseColor: theme.weakTextColor,
                  lineHeight: MediaQuery.textScalerOf(context).scale(13) * 1.25)
              : subtitle == null || subtitle.isEmpty
                  ? null
                  : Text(subtitle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.25,
                          color: theme.weakTextColor)),
        ),
      ),
    );
  }

  Widget _buildMemberRowWithDivider({
    required TUITheme theme,
    required V2TimGroupMemberFullInfo member,
    required String showName,
    required String userId,
  }) {
    return _buildMemberRow(
        theme: theme, member: member, showName: showName, userId: userId);
  }

  Widget _buildFlatMemberList(
    TUITheme theme,
    List<V2TimGroupMemberFullInfo> members,
  ) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            notification.metrics.extentAfter < 200) {
          if (_keyword.isNotEmpty) {
            unawaited(_loadMoreSearch());
          } else if (!_memberLoadFailed) {
            unawaited(_loadMembers());
          }
        }
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: members.length,
        itemBuilder: (context, index) {
          final member = members[index];
          final showName = memberDisplayName(
            friendRemark: member.friendRemark,
            nameCard: member.nameCard,
            nickName: member.nickName,
            userID: member.userID,
          );
          final userId = member.userID?.trim() ?? '';
          return _buildMemberRowWithDivider(
            theme: theme,
            member: member,
            showName: showName,
            userId: userId,
          );
        },
      ),
    );
  }

  Widget _buildMemberListContent(
    TUITheme theme,
    List<V2TimGroupMemberFullInfo> members,
  ) {
    return _buildFlatMemberList(theme, members);
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    if (PlatformUtils().isWeb) {
      return TIMUIKitSearchNotSupport();
    }

    final theme = value.theme;
    final members = _visibleMembers;
    final listenable = widget.presenceListenable;

    return Scaffold(
      backgroundColor:
          theme.conversationItemBgColor ?? theme.wideBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.chatHeaderBgColor ?? theme.appbarBgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(
          color: theme.primaryColor ?? theme.chatHeaderBackTextColor,
        ),
        leading: TIMUIKitBackButton(
          color: theme.primaryColor ?? theme.chatHeaderBackTextColor,
        ),
        title: Text(
          TIM_t('选择群成员'),
          style: TextStyle(
            fontSize: 17,
            color: theme.chatHeaderTitleTextColor ?? theme.darkTextColor,
          ),
        ),
      ),
      body: Column(
        children: [
          TIMUIKitSearchInput(
            directoryStyle: true,
            controller: _searchController,
            focusNode: _searchFocusNode,
            isAutoFocus: false,
            onChange: _onSearchChanged,
            prefixIcon: Icon(
              Icons.search,
              size: 16,
              color: theme.weakTextColor ?? hexToColor('979797'),
            ),
          ),
          Expanded(
            child: _loading && members.isEmpty && _keyword.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      color: theme.primaryColor,
                      strokeWidth: 2,
                    ),
                  )
                : members.isEmpty
                    ? Center(
                        child: Text(
                          TIM_t(_loading || _searching ? '正在加载群成员…' : '暂无数据'),
                          style: TextStyle(color: theme.weakTextColor),
                        ),
                      )
                    : listenable == null
                        ? _buildMemberListContent(theme, members)
                        : AnimatedBuilder(
                            animation: listenable,
                            builder: (context, _) =>
                                _buildMemberListContent(theme, members),
                          ),
          ),
          if (_searching || (_loading && members.isNotEmpty))
            const LinearProgressIndicator(minHeight: 2),
          if (!_loading && !_membersComplete)
            SafeArea(
              top: false,
              child: TextButton(
                key: const ValueKey('member-list-retry'),
                onPressed: _loadMembers,
                child: Text(TIM_t(_memberLoadFailed ? '群成员加载失败，点击重试' : '加载更多')),
              ),
            ),
          if (!_searching &&
              _keyword.isNotEmpty &&
              _cloudSearch != null &&
              !_cloudSearch!.usedCloud &&
              (!_membersComplete || _searchMembers.isNotEmpty))
            SafeArea(
              top: false,
              child: TextButton(
                key: const ValueKey('member-search-retry'),
                onPressed: () => _onSearchChanged(_keyword, force: true),
                child: Text(TIM_t('搜索失败，点击重试')),
              ),
            ),
          if (!_searching &&
              _keyword.isNotEmpty &&
              (_cloudSearch?.usedCloud ?? false) &&
              !(_cloudSearch?.isFinished ?? true))
            SafeArea(
              top: false,
              child: TextButton(
                key: const ValueKey('member-search-more'),
                onPressed: _loadMoreSearch,
                child: Text(TIM_t('加载更多')),
              ),
            ),
        ],
      ),
    );
  }
}
