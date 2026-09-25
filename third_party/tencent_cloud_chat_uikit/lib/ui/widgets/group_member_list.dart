import 'dart:async';

import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/directory_list_row.dart';
// ignore_for_file: must_be_immutable

import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable_plus_plus/flutter_slidable_plus_plus.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/profile/user_profile_local_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_role_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/radio_button.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';

class _MemberListCacheEntry {
  _MemberListCacheEntry(this.member)
      : userID = member?.userID,
        role = member?.role,
        friendRemark = member?.friendRemark,
        nameCard = member?.nameCard,
        nickName = member?.nickName;

  final V2TimGroupMemberFullInfo? member;
  final String? userID;
  final int? role;
  final String? friendRemark;
  final String? nameCard;
  final String? nickName;

  bool matches(V2TimGroupMemberFullInfo? other) {
    return identical(member, other) &&
        userID == other?.userID &&
        role == other?.role &&
        friendRemark == other?.friendRemark &&
        nameCard == other?.nameCard &&
        nickName == other?.nickName;
  }
}

class GroupProfileMemberList extends StatefulWidget {
  static String AT_ALL_USER_ID = "__kImSDK_MesssageAtALL__";
  final List<V2TimGroupMemberFullInfo?> memberList;
  final Function(String userID)? removeMember;
  final bool canSlideDelete;
  final bool Function(String userID)? canRemoveMember;
  final bool canSelectMember;
  final bool canAtAll;

  // when the @ need filter some group types
  final String? groupType;
  final Function(List<V2TimGroupMemberFullInfo> selectedMember)?
      onSelectedMemberChange;
  // notice: onTapMemberItem and onSelectedMemberChange use together will triger together
  final Function(
          V2TimGroupMemberFullInfo memberInfo, TapDownDetails? tapDetails)?
      onTapMemberItem;
  // When sliding to the bottom bar callBack
  final FutureOr<void> Function()? touchBottomCallBack;

  final int? maxSelectNum;

  final MemberPresenceLabelBuilder? presenceLabelBuilder;
  final MemberPresenceLoadingChecker? presenceLoadingChecker;
  final MemberPresenceOnlineResolver? presenceOnlineResolver;
  final void Function(List<String> userIds)? onMemberListLoaded;
  final Listenable? presenceListenable;

  /// Whether this surface may render or request presence information.
  final bool isShowOnlineStatus;

  /// Overrides the owner badge on surfaces with channel terminology.
  final String? ownerRoleLabel;

  /// 列表为空时自定义占位（如搜索无结果）；未传则显示「暂无群成员」。
  final WidgetBuilder? emptyBuilder;

  Widget? customTopArea;

  GroupProfileMemberList({
    Key? key,
    required this.memberList,
    this.groupType,
    this.removeMember,
    this.canSlideDelete = true,
    this.canRemoveMember,
    this.canSelectMember = false,
    this.canAtAll = false,
    this.onSelectedMemberChange,
    this.onTapMemberItem,
    this.customTopArea,
    this.touchBottomCallBack,
    this.maxSelectNum,
    this.presenceLabelBuilder,
    this.presenceLoadingChecker,
    this.presenceOnlineResolver,
    this.onMemberListLoaded,
    this.presenceListenable,
    this.isShowOnlineStatus = true,
    this.ownerRoleLabel,
    this.emptyBuilder,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _GroupProfileMemberListState();
}

class _GroupProfileMemberListState
    extends TIMUIKitState<GroupProfileMemberList> {
  final TUIFriendShipViewModel _friendShipModel =
      serviceLocator<TUIFriendShipViewModel>();
  final Set<String> _selectedUserIds = {};
  final List<String> _selectedUserIdOrder = [];
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _loadMoreInFlight = false;
  static const _nearBottomThreshold = 5;
  final Set<String> _presenceRequestedUserIds = <String>{};
  bool _presenceLoadScheduled = false;
  List<ISuspensionBeanImpl>? _cachedShowList;
  List<_MemberListCacheEntry>? _cachedShowListSource;
  bool? _cachedCanAtAll;
  String? _cachedGroupType;
  Map<String, V2TimUserStatus> _onlineStatusByUserId =
      <String, V2TimUserStatus>{};
  final ValueNotifier<int> _onlineStatusRevision = ValueNotifier<int>(0);
  late int _friendDisplayRevision;

  String? _normalizeUserId(String userId) {
    final id = userId.trim();
    return id.isEmpty ? null : id;
  }

  bool _isSelected(V2TimGroupMemberFullInfo member) {
    final id = _normalizeUserId(member.userID);
    if (id == null) {
      return false;
    }
    return _selectedUserIds.contains(id);
  }

  List<V2TimGroupMemberFullInfo> _selectedMembers() {
    if (_selectedUserIdOrder.isEmpty) {
      return const [];
    }
    final byId = <String, V2TimGroupMemberFullInfo>{};
    for (final member in widget.memberList) {
      if (member == null) {
        continue;
      }
      final id = _normalizeUserId(member.userID);
      if (id != null) {
        byId[id] = member;
      }
    }
    final selected = <V2TimGroupMemberFullInfo>[];
    for (final id in _selectedUserIdOrder) {
      final member = byId[id];
      if (member != null) {
        selected.add(member);
      } else if (_isAtAllMember(id)) {
        selected.add(
          V2TimGroupMemberFullInfo(
            userID: GroupProfileMemberList.AT_ALL_USER_ID,
            nickName: TIM_t("所有人"),
          ),
        );
      }
    }
    return selected;
  }

  void _notifySelectionChanged() {
    widget.onSelectedMemberChange?.call(_selectedMembers());
  }

  void _applySelectionChange() {
    _notifySelectionChanged();
    setState(() {});
  }

  void _setSelection(V2TimGroupMemberFullInfo member, bool checked) {
    final id = _normalizeUserId(member.userID);
    if (id == null) {
      return;
    }

    if (checked) {
      if (_selectedUserIds.contains(id)) {
        return;
      }
      if (widget.maxSelectNum != null &&
          _selectedUserIds.length >= widget.maxSelectNum!) {
        return;
      }
      _selectedUserIds.add(id);
      _selectedUserIdOrder.add(id);
    } else {
      if (!_selectedUserIds.contains(id)) {
        return;
      }
      _selectedUserIds.remove(id);
      _selectedUserIdOrder.remove(id);
    }
    _applySelectionChange();
  }

  void _toggleSelection(V2TimGroupMemberFullInfo member) {
    _setSelection(member, !_isSelected(member));
  }

  void _reconcileSelectionWithMemberList() {
    final previousOrder = List<String>.from(_selectedUserIdOrder);
    final available = widget.memberList
        .whereType<V2TimGroupMemberFullInfo>()
        .map((member) => _normalizeUserId(member.userID))
        .whereType<String>()
        .toSet();
    _selectedUserIds.removeWhere((id) => !available.contains(id));
    _selectedUserIdOrder.removeWhere((id) => !available.contains(id));
    final selectionChanged =
        previousOrder.length != _selectedUserIdOrder.length ||
            !_listEqualsStrings(previousOrder, _selectedUserIdOrder);
    if (!mounted || !selectionChanged) {
      return;
    }
    setState(() {});
    if (widget.canSelectMember) {
      _notifySelectionChanged();
    }
  }

  bool _listEqualsStrings(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  bool _sameMemberList(
    List<V2TimGroupMemberFullInfo?> a,
    List<V2TimGroupMemberFullInfo?> b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i]?.userID != b[i]?.userID || a[i]?.role != b[i]?.role) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _friendDisplayRevision = _friendShipModel.friendListRevision;
    _refreshOnlineStatusIndex();
    _friendShipModel.addListener(_onFriendshipChanged);
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
    _schedulePresenceLoad();
  }

  @override
  void didUpdateWidget(GroupProfileMemberList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameMemberList(oldWidget.memberList, widget.memberList)) {
      _cachedShowList = null;
      _cachedShowListSource = null;
      _cachedCanAtAll = null;
      _cachedGroupType = null;
      _reconcileSelectionWithMemberList();
    }
    if (!_sameMemberList(oldWidget.memberList, widget.memberList) ||
        oldWidget.onMemberListLoaded != widget.onMemberListLoaded) {
      _schedulePresenceLoad();
    }
    // 首页未铺满时也尝试续页。
    if (!_sameMemberList(oldWidget.memberList, widget.memberList)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onItemPositionsChanged();
        }
      });
    }
  }

  @override
  void dispose() {
    _friendShipModel.removeListener(_onFriendshipChanged);
    _onlineStatusRevision.dispose();
    _itemPositionsListener.itemPositions
        .removeListener(_onItemPositionsChanged);
    super.dispose();
  }

  void _onItemPositionsChanged() {
    // Presence/privacy is only needed for rows the user can currently see.
    // Loading it for every newly fetched member caused 40 per-user HTTP
    // requests for every 100-member page in large groups.
    _schedulePresenceLoad();
    if (widget.touchBottomCallBack == null) {
      return;
    }
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      return;
    }
    final showCount = _cachedShowList?.length ?? widget.memberList.length;
    if (showCount <= 0) {
      return;
    }
    var maxIndex = 0;
    for (final position in positions) {
      if (position.index > maxIndex) {
        maxIndex = position.index;
      }
    }
    if (maxIndex >= showCount - _nearBottomThreshold) {
      _triggerLoadMore();
    }
  }

  void _triggerLoadMore() {
    final cb = widget.touchBottomCallBack;
    if (cb == null || _loadMoreInFlight) {
      return;
    }
    _loadMoreInFlight = true;
    unawaited(Future<void>.sync(cb).whenComplete(() {
      _loadMoreInFlight = false;
    }));
  }

  bool _isAtAllMember(String userId) =>
      userId == GroupProfileMemberList.AT_ALL_USER_ID;

  void _refreshOnlineStatusIndex() {
    final next = <String, V2TimUserStatus>{};
    for (final status in _friendShipModel.userStatusList) {
      final userId = status.userID?.trim() ?? '';
      if (userId.isNotEmpty) {
        next[userId] = status;
      }
    }
    _onlineStatusByUserId = next;
  }

  void _onFriendshipChanged() {
    _refreshOnlineStatusIndex();
    if (!mounted) return;
    final displayRevision = _friendShipModel.friendListRevision;
    if (displayRevision != _friendDisplayRevision) {
      _friendDisplayRevision = displayRevision;
      // Display names no longer affect row order. Rebuild mounted rows only;
      // do not recreate or sort the full member projection.
      setState(() {});
      return;
    }
    // Presence notifications only affect mounted rows. Avoid revalidating
    // every loaded member and rebuilding the indexed viewport for each one.
    _onlineStatusRevision.value++;
  }

  void _schedulePresenceLoad() {
    if (!widget.isShowOnlineStatus) {
      return;
    }
    if (_presenceLoadScheduled) {
      return;
    }
    _presenceLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presenceLoadScheduled = false;
      if (!mounted) return;
      // Positions belong to the last built projection. Do not revalidate all
      // loaded member signatures on every scroll frame just to read its rows.
      final showList = _cachedShowList ?? _getShowList(widget.memberList);
      final positions = _itemPositionsListener.itemPositions.value;
      final visibleMembers = positions.isEmpty
          ? showList.take(20).map((item) => item.memberInfo)
          : positions
              .map((position) => position.index)
              .where((index) => index >= 0 && index < showList.length)
              .map((index) => showList[index].memberInfo);
      final ids = visibleMembers
          .whereType<V2TimGroupMemberFullInfo>()
          .map((member) => member.userID.trim())
          .where((id) => id.isNotEmpty && !_isAtAllMember(id))
          .where(_presenceRequestedUserIds.add)
          .toList(growable: false);
      if (ids.isEmpty) return;
      debugPrint(
        '[GroupMemberPresence] visible_request count=${ids.length} '
        'total=${showList.length}',
      );
      widget.onMemberListLoaded?.call(ids);
    });
  }

  String _getShowName(V2TimGroupMemberFullInfo? item) {
    return memberDisplayName(
      friendRemark: item?.friendRemark,
      nameCard: item?.nameCard,
      nickName: item?.nickName,
      userID: item?.userID,
    );
  }

  bool _isSelfMember(String userId) {
    final id = userId.trim();
    final self =
        serviceLocator<TUISelfInfoViewModel>().loginInfo?.userID?.trim() ?? '';
    return id.isNotEmpty && self.isNotEmpty && id == self;
  }

  V2TimUserStatus? _getOnlineStatus(V2TimGroupMemberFullInfo memberInfo) {
    final userId = memberInfo.userID;
    if (userId.isEmpty) {
      return null;
    }
    if (_isSelfMember(userId)) {
      return V2TimUserStatus(userID: userId, statusType: 1);
    }
    return _onlineStatusByUserId[userId.trim()];
  }

  bool _isMemberOnline(V2TimUserStatus? status, String userId) {
    return _isSelfMember(userId) || status?.statusType == 1;
  }

  String _getStatusLabel(bool imOnline, String userId) {
    final builder = widget.presenceLabelBuilder;
    if (builder != null) {
      return builder(userId, imOnline);
    }
    return imOnline ? TIM_t("在线") : TIM_t("离线");
  }

  int _roleSortRank(int? role) => GroupRolePolicy.memberSortRank(role);

  bool _sameCachedShowListSource(
    List<V2TimGroupMemberFullInfo?> memberList,
  ) {
    final cached = _cachedShowListSource;
    if (cached == null ||
        cached.length != memberList.length ||
        _cachedCanAtAll != widget.canAtAll ||
        _cachedGroupType != widget.groupType) {
      return false;
    }
    for (var i = 0; i < memberList.length; i++) {
      if (!cached[i].matches(memberList[i])) {
        return false;
      }
    }
    return true;
  }

  List<ISuspensionBeanImpl> _getShowList(
    List<V2TimGroupMemberFullInfo?> memberList,
  ) {
    final cached = _cachedShowList;
    if (cached != null && _sameCachedShowListSource(memberList)) {
      return cached;
    }
    final managers =
        <({ISuspensionBeanImpl row, int roleRank, int sourceIndex})>[];
    final ordinaryMembers = <ISuspensionBeanImpl>[];
    for (var i = 0; i < memberList.length; i++) {
      final item = memberList[i];
      final row = ISuspensionBeanImpl(memberInfo: item, tagIndex: '');
      if (GroupRolePolicy.isManagerRole(item?.role)) {
        managers.add((
          row: row,
          roleRank: _roleSortRank(item?.role),
          sourceIndex: i,
        ));
      } else {
        ordinaryMembers.add(row);
      }
    }

    // Keep the server/pagination order. Only the explicit business priority
    // remains: owner, then administrators, then ordinary members.
    managers.sort((a, b) {
      final byRole = a.roleRank.compareTo(b.roleRank);
      return byRole != 0 ? byRole : a.sourceIndex.compareTo(b.sourceIndex);
    });
    final showList = <ISuspensionBeanImpl>[
      ...managers.map((entry) => entry.row),
      ...ordinaryMembers,
    ];

    // add @everyone item
    if (widget.canAtAll) {
      final canAtGroupType = ["Work", "Public", "Meeting", "Community"];
      if (canAtGroupType.contains(widget.groupType)) {
        showList.insert(
            0,
            ISuspensionBeanImpl(
                memberInfo: V2TimGroupMemberFullInfo(
                    userID: GroupProfileMemberList.AT_ALL_USER_ID,
                    nickName: TIM_t("所有人")),
                tagIndex: ""));
      }
    }

    _cachedShowListSource =
        memberList.map(_MemberListCacheEntry.new).toList(growable: false);
    _cachedCanAtAll = widget.canAtAll;
    _cachedGroupType = widget.groupType;
    _cachedShowList = showList;
    return showList;
  }

  Widget? _buildRoleBadge(
    TUITheme theme,
    int? role, {
    required bool isDesktopScreen,
  }) {
    final badgeKey = GroupRolePolicy.roleBadgeKey(role);
    if (badgeKey == null) {
      return null;
    }
    return DirectoryStatusLabel(
      label: badgeKey == 'owner'
          ? (widget.ownerRoleLabel ?? TIM_t("群主"))
          : TIM_t("管理员"),
      color: badgeKey == 'owner'
          ? (theme.primaryColor ?? CommonColor.primaryColor)
          : const Color(0xFFB86E00),
    );
  }

  Widget _buildListItem(
      BuildContext context, V2TimGroupMemberFullInfo memberInfo) {
    final theme = Provider.of<TUIThemeViewModel>(context).theme;
    final isDesktopScreen =
        TUIKitScreenUtils.getFormFactor() == DeviceType.Desktop;
    final isGroupMember =
        memberInfo.role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
    final itemBackgroundColor = theme.conversationItemBgColor ??
        theme.wideBackgroundColor ??
        Colors.white;
    return AnimatedBuilder(
      animation: Listenable.merge([
        if (widget.isShowOnlineStatus) _onlineStatusRevision,
        if (widget.presenceListenable != null) widget.presenceListenable!,
        if (UserProfileLocalBridge.changeListenable != null)
          UserProfileLocalBridge.changeListenable!,
      ]),
      builder: (context, _) {
        final onlineStatus = _getOnlineStatus(memberInfo);
        final userId = memberInfo.userID;
        final isAtAllMember = _isAtAllMember(userId);
        final imOnline = _isMemberOnline(onlineStatus, userId);
        final effectiveOnline = !widget.isShowOnlineStatus || isAtAllMember
            ? false
            : (widget.presenceOnlineResolver?.call(userId, imOnline) ??
                imOnline);
        final presenceLoading = widget.isShowOnlineStatus &&
            !isAtAllMember &&
            (widget.presenceLoadingChecker?.call(userId, imOnline) ?? false);
        final statusLabel = !widget.isShowOnlineStatus || isAtAllMember
            ? ''
            : (presenceLoading
                ? ''
                : _getStatusLabel(
                    effectiveOnline,
                    userId,
                  ));
        final avatarOnlineStatus = !widget.isShowOnlineStatus || isAtAllMember
            ? null
            : (widget.presenceOnlineResolver != null
                ? V2TimUserStatus(
                    userID: userId,
                    statusType: effectiveOnline ? 1 : 0,
                  )
                : onlineStatus);
        final atSelectionLimit = widget.maxSelectNum != null &&
            _selectedUserIds.length >= widget.maxSelectNum! &&
            !_isSelected(memberInfo);
        final roleBadge = _buildRoleBadge(
          theme,
          memberInfo.role,
          isDesktopScreen: isDesktopScreen,
        );
        return Container(
            color: itemBackgroundColor,
            child: Slidable(
                endActionPane: widget.canSlideDelete &&
                        (widget.canRemoveMember?.call(memberInfo.userID) ??
                            isGroupMember)
                    ? ActionPane(motion: const DrawerMotion(), children: [
                        SlidableAction(
                          onPressed: (_) {
                            if (widget.removeMember != null &&
                                (widget.canRemoveMember?.call(memberInfo.userID) ??
                                    isGroupMember)) {
                              widget.removeMember!(memberInfo.userID);
                            }
                          },
                          flex: 1,
                          backgroundColor:
                              theme.cautionColor ?? CommonColor.cautionColor,
                          autoClose: true,
                          label: TIM_t("删除"),
                        )
                      ])
                    : null,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      widget.onTapMemberItem?.call(memberInfo, null);
                      if (widget.canSelectMember && !atSelectionLimit) {
                        _toggleSelection(memberInfo);
                      }
                    },
                    child: DirectoryListRow(
                      leading: !widget.canSelectMember
                          ? null
                          : CheckBoxButton(
                              disabled: atSelectionLimit,
                              isChecked: _isSelected(memberInfo),
                              onChanged: atSelectionLimit
                                  ? null
                                  : (checked) =>
                                      _setSelection(memberInfo, checked),
                            ),
                      avatar: Avatar(
                        faceUrl: UserProfileLocalBridge.cachedAvatarUrl(
                            memberInfo.userID,
                            fallback: memberInfo.faceUrl),
                        showName: _getShowName(memberInfo),
                        type: 1,
                        onlineStatus: avatarOnlineStatus,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      title: Text(_getShowName(memberInfo),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: DirectoryListStyle.titleSize,
                              fontWeight: FontWeight.w500,
                              color: theme.darkTextColor,
                              height: DirectoryListStyle.lineHeight)),
                      subtitle: presenceLoading
                          ? buildMemberPresenceSubtitleSkeleton(
                              baseColor: theme.weakTextColor,
                              lineHeight:
                                  MediaQuery.textScalerOf(context).scale(13) *
                                      1.25)
                          : statusLabel.isEmpty
                              ? null
                              : Text(statusLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: DirectoryListStyle.subtitleSize,
                                      color: theme.weakTextColor,
                                      height: DirectoryListStyle.lineHeight)),
                      trailing: roleBadge,
                    ),
                  ),
                )));
      },
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;

    final isDesktopScreen =
        TUIKitScreenUtils.getFormFactor() == DeviceType.Desktop;

    final showList = _getShowList(widget.memberList);
    return Container(
      color: isDesktopScreen
          ? (theme.wideBackgroundColor ?? Colors.white)
          : theme.weakBackgroundColor,
      child: SafeArea(
          child: Column(
        children: [
          widget.customTopArea != null ? widget.customTopArea! : Container(),
          Expanded(
            child: (showList.isEmpty)
                ? (widget.emptyBuilder?.call(context) ??
                    Center(
                      child: Text(
                        TIM_t("暂无群成员"),
                        style: TextStyle(
                          color: theme.weakTextColor,
                          fontSize: isDesktopScreen ? 14 : 15,
                        ),
                      ),
                    ))
                : Container(
                    padding: isDesktopScreen
                        ? const EdgeInsets.only(bottom: 8)
                        : null,
                    child: AZListViewContainer(
                        cacheExtent: 240,
                        itemIdentity: (item) =>
                            (item.memberInfo as V2TimGroupMemberFullInfo)
                                .userID,
                        subduedStyle: true,
                        memberList: showList,
                        isShowIndexBar: false,
                        itemPositionsListener: _itemPositionsListener,
                        itemBuilder: (context, index) {
                          final memberInfo = showList[index].memberInfo
                              as V2TimGroupMemberFullInfo;

                          return _buildListItem(context, memberInfo);
                        }),
                  ),
          )
        ],
      )),
    );
  }
}
