import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_member_feedback_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_kick_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_role_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/group_member_picker_search_bar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tim_uikit_back_button.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

GlobalKey<DeleteGroupMemberPageState> deleteGroupMemberKey = GlobalKey();

class DeleteGroupMemberPage extends StatefulWidget {
  final TUIGroupProfileModel model;
  final VoidCallback? onClose;
  final MemberPresenceLabelBuilder? presenceLabelBuilder;
  final MemberPresenceLoadingChecker? presenceLoadingChecker;
  final void Function(List<String> userIds)? onMemberListLoaded;
  final Listenable? presenceListenable;

  const DeleteGroupMemberPage({
    Key? key,
    required this.model,
    this.onClose,
    this.presenceLabelBuilder,
    this.presenceLoadingChecker,
    this.onMemberListLoaded,
    this.presenceListenable,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => DeleteGroupMemberPageState();
}

class DeleteGroupMemberPageState extends TIMUIKitState<DeleteGroupMemberPage> {
  List<V2TimGroupMemberFullInfo> selectedGroupMember = [];
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';
  bool _submitting = false;
  List<V2TimGroupMemberFullInfo?> _deletableMembersCache =
      const <V2TimGroupMemberFullInfo?>[];
  late final GroupMemberCloudSearchController _cloudSearch;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(fn);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(fn);
      }
    });
  }

  /// 群主可踢普通成员与管理员；管理员只能踢普通成员；群主本人不可被踢。
  bool _isDeletableBySelf(V2TimGroupMemberFullInfo member) {
    final owner = widget.model.groupInfo?.owner;
    if (member.role == 400 ||
        (owner != null && owner.isNotEmpty &&
            ChatIdFormat.rawUserUid(member.userID) ==
                ChatIdFormat.rawUserUid(owner))) return false;
    return widget.model.canKickMember(member.userID);
  }

  bool get _permissionsReady =>
      widget.model.canKickOffMember() &&
      !widget.model.hasManagementMemberListError;

  bool get _ownerAdminsPending =>
      GroupRolePolicy.isOwnerRole(widget.model.backendSelfRole) &&
      !widget.model.hasLoadedManagementMembers &&
      !widget.model.hasManagementMemberListError;

  void _syncDeletableMembersCache() {
    if (_submitting && _deletableMembersCache.isNotEmpty) {
      return;
    }
    // Backend role updates can change candidates without changing the SDK page.
    final source = widget.model.membersWithBackendRoles(widget.model.groupMemberList);
    final seen = <String>{};
    final members = <V2TimGroupMemberFullInfo?>[];
    for (final member in source) {
      if (member == null || !_isDeletableBySelf(member)) {
        continue;
      }
      final userId = member.userID.trim();
      if (userId.isEmpty || seen.contains(userId)) {
        continue;
      }
      seen.add(userId);
      members.add(member);
    }
    members.sort((a, b) {
      final rank = GroupRolePolicy.memberSortRank(a?.role)
          .compareTo(GroupRolePolicy.memberSortRank(b?.role));
      if (rank != 0) return rank;
      return (a?.userID ?? '').compareTo(b?.userID ?? '');
    });
    _deletableMembersCache = members;
  }

  bool _sameSelectedMembers(List<V2TimGroupMemberFullInfo> next) {
    if (next.length != selectedGroupMember.length) {
      return false;
    }
    for (var i = 0; i < next.length; i++) {
      if (next[i].userID != selectedGroupMember[i].userID) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _cloudSearch = GroupMemberCloudSearchController(
      groupId: widget.model.groupID,
      onUpdate: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    unawaited(Future<void>.microtask(widget.model.loadMemberPageOnEntry));
    _searchController.addListener(() {
      final raw = _searchController.text;
      final next = raw.trim().toLowerCase();
      if (next != _keyword) {
        _safeSetState(() => _keyword = next);
      }
      _cloudSearch.onKeywordChanged(raw);
    });
  }

  @override
  void dispose() {
    _cloudSearch.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<V2TimGroupMemberFullInfo?> _filteredMembers() {
    _syncDeletableMembersCache();
    if (_keyword.isEmpty) {
      return _deletableMembersCache;
    }
    if (_cloudSearch.usedCloud || _cloudSearch.members.isNotEmpty) {
      return _cloudSearch.members
          .where(_isDeletableBySelf)
          .map<V2TimGroupMemberFullInfo?>((member) => member)
          .toList();
    }
    return filterGroupMembersByKeyword(_deletableMembersCache, _keyword);
  }

  Widget _pickerBody(TUITheme theme) {
    final ownerAdminsReady =
        GroupRolePolicy.isOwnerRole(widget.model.backendSelfRole) &&
            widget.model.hasLoadedManagementMembers;
    if (_ownerAdminsPending ||
        (widget.model.isMemberEntryLoading && !ownerAdminsReady)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.model.hasMemberEntryError &&
        widget.model.groupMemberList.isEmpty) {
      return Center(
          child: TextButton(
        onPressed: widget.model.loadMemberPageOnEntry,
        child: Text(TIM_t('群成员加载失败，点击重试')),
      ));
    }
    final members = _filteredMembers();
    return AbsorbPointer(
      absorbing: _submitting,
      child: Column(
        children: [
          if (!_permissionsReady && widget.model.hasManagementMemberListError)
            TextButton(
              onPressed: widget.model.loadManagementMembers,
              child: Text(TIM_t('群管理权限加载失败，点击重试')),
            ),
          GroupMemberPickerSearchBar(
            controller: _searchController,
            keyword: _keyword,
            onClear: _searchController.clear,
          ),
          Expanded(
            child: GroupProfileMemberList(
              memberList: members,
              canSelectMember: _permissionsReady,
              canSlideDelete: false,
              maxSelectNum: kContactListMaxGroupSelection,
              presenceLabelBuilder: widget.presenceLabelBuilder,
              presenceLoadingChecker: widget.presenceLoadingChecker,
              presenceListenable: widget.presenceListenable,
              onMemberListLoaded: widget.onMemberListLoaded,
              onSelectedMemberChange: (selectedMember) {
                if (!_permissionsReady) {
                  selectedGroupMember = [];
                  return;
                }
                if (_sameSelectedMembers(selectedMember)) {
                  return;
                }
                // The child also reconciles selection during didUpdateWidget.
                // Update the value now, but defer rebuilding during a frame.
                selectedGroupMember = List.of(selectedMember);
                _safeSetState(() {});
              },
              touchBottomCallBack: () async {
                if (_keyword.isEmpty) {
                  if (!widget.model.hasMoreGroupMembers ||
                      widget.model.isGroupMemberListLoadingMore) {
                    return;
                  }
                  await widget.model.loadMoreGroupMembers();
                  return;
                }
                if (_cloudSearch.usedCloud) {
                  await _cloudSearch.loadMore();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _invalidateMemberCache() {
    _deletableMembersCache = const <V2TimGroupMemberFullInfo?>[];
  }

  Future<void> _closePage() async {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    if (mounted) {
      await Navigator.maybePop(context, true);
    }
  }

  Future<void> submitDelete() async {
    if (_submitting ||
        !_permissionsReady ||
        widget.model.isMemberEntryLoading) {
      return;
    }
    if (selectedGroupMember.isEmpty) {
      GroupMemberFeedbackBridge.show(TIM_t('请选择成员'));
      return;
    }
    if (!selectedGroupMember.every(_isDeletableBySelf)) {
      GroupMemberFeedbackBridge.show(TIM_t('群管理权限已变化，请重新选择成员'));
      setState(() => selectedGroupMember = []);
      return;
    }
    setState(() => _submitting = true);
    try {
      final userIDs = selectedGroupMember
          .map((e) => e.userID.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final res = await widget.model.kickOffMember(userIDs);
      if (!mounted) {
        return;
      }
      if (res.code != 0) {
        GroupMemberFeedbackBridge.show(
          SelfHostedGroupKickBridge.formatMessage(
            success: false,
            code: res.code,
            desc: res.desc,
          ),
        );
        _invalidateMemberCache();
        setState(() {
          _submitting = false;
          selectedGroupMember = const <V2TimGroupMemberFullInfo>[];
        });
        return;
      }
      final partialSuccess =
          res.desc?.trim().toUpperCase() == 'PARTIAL_SUCCESS';
      GroupMemberFeedbackBridge.show(
        SelfHostedGroupKickBridge.formatMessage(
          success: true,
          desc: partialSuccess ? res.desc : null,
        ),
      );
      await _closePage();
    } catch (_) {
      if (!mounted) {
        return;
      }
      GroupMemberFeedbackBridge.show(
        SelfHostedGroupKickBridge.formatMessage(success: false),
      );
      _invalidateMemberCache();
      setState(() {
        _submitting = false;
        selectedGroupMember = const <V2TimGroupMemberFullInfo>[];
      });
    }
  }

  Widget _confirmButton(TUITheme theme) {
    return TextButton(
      onPressed: _submitting ||
              !_permissionsReady ||
              widget.model.isMemberEntryLoading ||
              selectedGroupMember.isEmpty
          ? null
          : submitDelete,
      child: _submitting
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.appbarTextColor,
              ),
            )
          : Text(
              TIM_t("确定"),
              style: TextStyle(
                color: theme.appbarTextColor,
                fontSize: 16,
              ),
            ),
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final theme = value.theme;

    return AnimatedBuilder(
      animation: widget.model,
      builder: (context, _) => TUIKitScreenUtils.getDeviceWidget(
          context: context,
          desktopWidget: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _pickerBody(theme),
          ),
          defaultWidget: Scaffold(
              appBar: AppBar(
                  title: Text(
                    TIM_t("删除群成员"),
                    style:
                        TextStyle(color: theme.appbarTextColor, fontSize: 17),
                  ),
                  actions: [
                    _confirmButton(theme),
                  ],
                  shadowColor: theme.weakDividerColor,
                  backgroundColor: theme.appbarBgColor ?? theme.primaryColor,
                  iconTheme: IconThemeData(
                    color: theme.appbarTextColor,
                  ),
                  leading: TIMUIKitBackButton(
                    color: theme.appbarTextColor,
                  )),
              body: _pickerBody(theme))),
    );
  }
}
