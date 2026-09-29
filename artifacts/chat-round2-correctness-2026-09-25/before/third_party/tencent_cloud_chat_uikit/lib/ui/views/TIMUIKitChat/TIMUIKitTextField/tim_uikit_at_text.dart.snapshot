import 'dart:async';
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tim_uikit_back_button.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_ui_group_member_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

class AtText extends StatefulWidget {
  final String? groupID;
  final V2TimGroupInfo? groupInfo;
  final List<V2TimGroupMemberFullInfo?>? groupMemberList;

  /// 兼容旧入参；分页以本页网络返回的 nextSeq 为准，勿信会话 open-shell 的 seq=0。
  final String? initialNextSeq;
  final VoidCallback? closeFunc;
  final Function(List<V2TimGroupMemberFullInfo> memberInfo)? onChooseMember;
  final bool canAtAll;

  // some Group type cant @all
  final String? groupType;

  const AtText({
    this.groupID,
    this.groupType,
    Key? key,
    this.groupInfo,
    this.groupMemberList,
    this.initialNextSeq,
    this.closeFunc,
    this.onChooseMember,
    this.canAtAll = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AtTextState();
}

class _AtTextState extends TIMUIKitState<AtText> {
  final TUISelfInfoViewModel _selfInfoViewModel =
      serviceLocator<TUISelfInfoViewModel>();
  final GroupServices _groupServices = serviceLocator<GroupServices>();

  List<V2TimGroupMemberFullInfo> selectedGroupMemberList = [];
  List<V2TimGroupMemberFullInfo?> _members = [];

  /// 仅由本页 getGroupMemberList 写入；勿用聊天 open-shell 的假 seq=0。
  String _nextSeq = '0';
  String _keyword = '';
  bool _loadingFirst = false;
  bool _loadingMore = false;
  late final GroupMemberCloudSearchController _cloudSearch;
  StreamSubscription<({String groupID, Set<String> userIDs})>?
      _removalSubscription;

  bool get _hasMoreMembers {
    final seq = _nextSeq.trim();
    return seq.isNotEmpty && seq != '0';
  }

  @override
  void initState() {
    super.initState();
    _cloudSearch = GroupMemberCloudSearchController(
      groupId: widget.groupID?.trim() ?? '',
      localFallback: (keyword) =>
          GroupMemberLocalStore.instance.loadAsV2TimMembers(
        groupId: widget.groupID?.trim() ?? '',
        keyword: keyword,
        limit: 100,
      ),
      onUpdate: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    GroupMemberStore.instance.addListener(_syncMembersFromStore);
    _removalSubscription = GroupMemberStore.instance.removals.listen((event) {
      if (!mounted || event.groupID != widget.groupID?.trim()) return;
      setState(() {
        _members
            .removeWhere((member) => event.userIDs.contains(member?.userID));
        selectedGroupMemberList
            .removeWhere((member) => event.userIDs.contains(member.userID));
      });
    });
    // 瞬时种子（可能是 open-shell 残缺集）；正式窗口与群成员列表一致：seq=0 首页 + 触底续页。
    _members = List<V2TimGroupMemberFullInfo?>.from(
      widget.groupMemberList ?? const <V2TimGroupMemberFullInfo?>[],
    );
    // 忽略 initialNextSeq：open-shell 常把它留在 "0"，会误判「没有更多」。
    _nextSeq = '0';

    final gid = widget.groupID?.trim() ?? '';
    if (gid.isEmpty) {
      return;
    }
    unawaited(_bootstrapMemberWindow(gid));
  }

  @override
  void dispose() {
    _removalSubscription?.cancel();
    _cloudSearch.dispose();
    GroupMemberStore.instance.removeListener(_syncMembersFromStore);
    super.dispose();
  }

  void _syncMembersFromStore() {
    final groupID = widget.groupID?.trim() ?? '';
    if (groupID.isEmpty || !mounted) return;
    final shared = GroupMemberStore.instance.membersForGroup(groupID);
    if (shared.isEmpty) return;
    final currentIds = _members
        .map((member) => member?.userID.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    // A bounded cache is not a complete membership snapshot.
    final merged = <String, V2TimGroupMemberFullInfo>{
      for (final member in _members.whereType<V2TimGroupMemberFullInfo>())
        member.userID: member,
      for (final member in shared) member.userID: member,
    };
    final sharedIds = merged.keys.toList();
    if (listEquals(currentIds, sharedIds)) return;
    setState(() {
      _members = List<V2TimGroupMemberFullInfo?>.from(merged.values);
    });
  }

  /// 对齐群成员页：可选本地首窗 hydrate → 必拉网络第 1 页 → 触底续页。
  Future<void> _bootstrapMemberWindow(String groupID) async {
    await _hydrateFromCache(groupID);
    if (!mounted) {
      return;
    }
    await _loadPage(groupID: groupID, seq: '0', isFirst: true);
    if (!mounted) {
      return;
    }
    // Additional pages load only when the user approaches the list end.
  }

  Future<void> _hydrateFromCache(String groupID) async {
    if (!SelfHostedGroupBridge.enabled) {
      return;
    }
    try {
      final cached =
          await SelfHostedGroupBridge.loadCachedGroupMemberList(groupID);
      if (!mounted || cached.isEmpty) {
        return;
      }
      const pageSize = 100;
      final window =
          cached.length > pageSize ? cached.sublist(0, pageSize) : cached;
      GroupMemberStore.instance.putMembers(groupID, window, notify: false);
      setState(() {
        _members = List<V2TimGroupMemberFullInfo?>.from(window);
      });
    } catch (_) {}
  }

  void _submitAtMemberList() {
    if (widget.closeFunc != null) {
      widget.closeFunc!();
    }

    if (widget.onChooseMember != null) {
      widget.onChooseMember!(selectedGroupMemberList);
    } else {
      Navigator.pop(context, selectedGroupMemberList);
    }
  }

  List<V2TimGroupMemberFullInfo?> _excludeSelf(
    List<V2TimGroupMemberFullInfo?> members,
  ) {
    final selfId = _selfInfoViewModel.loginInfo?.userID?.trim() ?? '';
    return members
        .where(
          (member) =>
              member != null &&
              member.userID.trim().isNotEmpty &&
              member.userID != selfId,
        )
        .toList();
  }

  List<V2TimGroupMemberFullInfo?> _visibleMembers() {
    if (_keyword.isEmpty) {
      return _excludeSelf(_members);
    }
    if (_cloudSearch.usedCloud || _cloudSearch.members.isNotEmpty) {
      return _excludeSelf(
        _cloudSearch.members
            .map<V2TimGroupMemberFullInfo?>((member) => member)
            .toList(),
      );
    }
    return filterGroupMembersByKeyword(_excludeSelf(_members), _keyword);
  }

  void _handleSearchText(String text) {
    final next = text.trim().toLowerCase();
    if (next != _keyword) {
      setState(() => _keyword = next);
    }
    _cloudSearch.onKeywordChanged(text);
  }

  Future<void> _loadMoreMembers() async {
    final gid = widget.groupID?.trim() ?? '';
    if (_keyword.isNotEmpty) {
      if (_cloudSearch.usedCloud) {
        await _cloudSearch.loadMore();
      }
      return;
    }
    if (gid.isEmpty || !_hasMoreMembers || _loadingMore || _loadingFirst) {
      return;
    }
    _loadingMore = true;
    try {
      await _loadPage(groupID: gid, seq: _nextSeq, isFirst: false);
    } finally {
      _loadingMore = false;
    }
  }

  /// 只拉一页；禁止递归整表。触底请用 [_loadMoreMembers]。
  Future<void> _loadPage({
    required String groupID,
    required String seq,
    required bool isFirst,
  }) async {
    // 有种子/缓存时静默刷新首页，避免整页转圈；空列表才显示 loading。
    final showFirstSpinner = isFirst && _members.isEmpty;
    if (showFirstSpinner && mounted) {
      setState(() => _loadingFirst = true);
    }
    try {
      final res = await _groupServices.getGroupMemberList(
        groupID: groupID,
        filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
        count: 100,
        nextSeq: seq,
      );
      final page = res.data;
      if (res.code != 0 || page == null) {
        return;
      }
      final pageMembers = page.memberInfoList ?? const [];
      GroupMemberStore.instance.putMembers(
        groupID,
        pageMembers,
        notify: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (isFirst) {
          _members = List<V2TimGroupMemberFullInfo?>.from(pageMembers);
        } else {
          final existing = _members
              .map((e) => e?.userID.trim() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
          final appended = pageMembers
              .where((m) => !existing.contains(m.userID.trim()))
              .toList(growable: false);
          _members = [..._members, ...appended];
        }
        _nextSeq = (page.nextSeq ?? '0').trim();
        if (_nextSeq.isEmpty) {
          _nextSeq = '0';
        }
      });
    } finally {
      if (isFirst && mounted && _loadingFirst) {
        setState(() => _loadingFirst = false);
      }
    }
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;

    Widget mentionedMembersBody() {
      if (_loadingFirst && _members.isEmpty) {
        return Center(
          child: LoadingAnimationWidget.staggeredDotsWave(
            color: theme.primaryColor ?? Colors.grey,
            size: 40,
          ),
        );
      }
      final presenceBridge = serviceLocator<TUIChatGlobalModel>()
          .appContactPresenceBridgeBuilder
          ?.call(context);
      return GroupProfileMemberList(
        groupType: widget.groupType ?? "",
        memberList: _visibleMembers(),
        canAtAll: widget.canAtAll && _keyword.isEmpty,
        canSelectMember: true,
        canSlideDelete: false,
        presenceListenable: presenceBridge?.presenceListenable,
        presenceLabelBuilder: presenceBridge?.presenceLabelBuilder,
        presenceLoadingChecker: presenceBridge?.presenceLoadingChecker,
        presenceOnlineResolver: presenceBridge?.presenceOnlineResolver,
        onMemberListLoaded: presenceBridge?.onContactListLoaded,
        onSelectedMemberChange: (selectedMemberList) {
          selectedGroupMemberList = selectedMemberList;
          final isAtAllSelected = selectedGroupMemberList.any(
            (element) =>
                element.userID == GroupProfileMemberList.AT_ALL_USER_ID,
          );

          if (isAtAllSelected) {
            _submitAtMemberList();
          }
        },
        touchBottomCallBack: _loadMoreMembers,
        customTopArea: PlatformUtils().isWeb
            ? null
            : GroupMemberSearchTextField(
                onTextChange: _handleSearchText,
              ),
      );
    }

    return TUIKitScreenUtils.getDeviceWidget(
      context: context,
      desktopWidget: mentionedMembersBody(),
      defaultWidget: Scaffold(
        appBar: AppBar(
          shadowColor: theme.weakBackgroundColor,
          iconTheme: IconThemeData(
            color: theme.appbarTextColor,
          ),
          backgroundColor: theme.appbarBgColor ?? theme.primaryColor,
          leading: TIMUIKitBackButton(
            color: theme.appbarTextColor,
          ),
          centerTitle: true,
          title: Text(
            TIM_t("选择提醒人"),
            style: TextStyle(
              color: theme.appbarTextColor,
              fontSize: 17,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _submitAtMemberList,
              child: Text(
                TIM_t("确定"),
                style: TextStyle(
                  color: theme.appbarTextColor,
                  fontSize: 14,
                ),
              ),
            )
          ],
        ),
        body: mentionedMembersBody(),
      ),
    );
  }
}
