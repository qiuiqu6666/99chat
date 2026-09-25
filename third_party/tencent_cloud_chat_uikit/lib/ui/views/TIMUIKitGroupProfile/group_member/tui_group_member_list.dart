// ignore_for_file: must_be_immutable

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_member_feedback_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_kick_bridge.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_ui_group_member_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tim_uikit_back_button.dart';

import '../../../../theme/tui_theme.dart';

class GroupProfileMemberListPage extends StatefulWidget {
  List<V2TimGroupMemberFullInfo?> memberList;
  TUIGroupProfileModel model;
  final MemberPresenceLabelBuilder? presenceLabelBuilder;
  final MemberPresenceLoadingChecker? presenceLoadingChecker;
  final MemberPresenceOnlineResolver? presenceOnlineResolver;
  final void Function(List<String> userIds)? onMemberListLoaded;
  final Listenable? presenceListenable;
  final bool isShowOnlineStatus;
  final bool isChannel;

  GroupProfileMemberListPage({
    Key? key,
    required this.memberList,
    required this.model,
    this.presenceLabelBuilder,
    this.presenceLoadingChecker,
    this.presenceOnlineResolver,
    this.onMemberListLoaded,
    this.presenceListenable,
    this.isShowOnlineStatus = true,
    this.isChannel = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => GroupProfileMemberListPageState();
}

class GroupProfileMemberListPageState
    extends TIMUIKitState<GroupProfileMemberListPage> {
  String _keyword = '';
  late final GroupMemberCloudSearchController _cloudSearch;

  @override
  void initState() {
    super.initState();
    _cloudSearch = GroupMemberCloudSearchController(
      groupId: widget.model.groupID,
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(Future<void>.microtask(widget.model.loadMemberPageOnEntry));
  }

  @override
  void dispose() {
    _cloudSearch.dispose();
    super.dispose();
  }

  Future<void> _kickedOffMember(String userID) async {
    final res = await widget.model.kickOffMember([userID]);
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
      return;
    }
    GroupMemberFeedbackBridge.show(
      SelfHostedGroupKickBridge.formatMessage(success: true),
    );
  }

  void _handleSearchText(String text) {
    final next = text.trim().toLowerCase();
    if (next == _keyword) {
      return;
    }
    setState(() => _keyword = next);
    _cloudSearch.onKeywordChanged(text);
  }

  List<V2TimGroupMemberFullInfo?> _visibleMembers(
    List<V2TimGroupMemberFullInfo?> source,
  ) {
    final members = widget.model.membersWithBackendRoles(
      _keyword.isNotEmpty && _cloudSearch.usedCloud
          ? _cloudSearch.members
          : source,
    );
    return _keyword.isEmpty
        ? members
        : filterGroupMembersByKeyword(members, _keyword);
  }

  Widget _memberBody({
    required TUITheme theme,
    required List<V2TimGroupMemberFullInfo?> members,
  }) {
    final model = widget.model;
    if (model.isMemberEntryLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (model.hasMemberEntryError && model.groupMemberList.isEmpty) {
      return Center(
          child: TextButton(
        onPressed: model.loadMemberPageOnEntry,
        child: Text(TIM_t('群成员加载失败，点击重试')),
      ));
    }
    Widget retryMessage() => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(TIM_t('管理员列表加载失败')),
            TextButton(
              onPressed: model.isManagementMemberListLoading
                  ? null
                  : () => model.loadManagementMembers(),
              child: Text(TIM_t('重试')),
            ),
          ]),
        );
    final hasLocalRows = members.isNotEmpty ||
        model.groupMemberList
            .whereType<V2TimGroupMemberFullInfo>()
            .isNotEmpty ||
        model.hasLocalManagementPreview;
    if (!model.hasLoadedManagementMembers && !hasLocalRows) {
      return Center(
        child: model.hasManagementMemberListError
            ? retryMessage()
            : const CircularProgressIndicator(),
      );
    }
    return GroupProfileMemberList(
      customTopArea: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (model.hasManagementMemberListError) retryMessage(),
          GroupMemberSearchTextField(
            onTextChange: _handleSearchText,
            hintText: widget.isChannel ? '搜索订阅者' : TIM_t('搜索群成员'),
          ),
        ],
      ),
      memberList: members,
      ownerRoleLabel: widget.isChannel ? '创建人' : null,
      removeMember: _kickedOffMember,
      canSlideDelete: model.canKickOffMember(),
      canRemoveMember: model.canKickMember,
      touchBottomCallBack: _keyword.isEmpty
          ? () async {
              await widget.model.loadMoreGroupMembers();
            }
          : _cloudSearch.loadMore,
      presenceLabelBuilder: widget.presenceLabelBuilder,
      presenceLoadingChecker: widget.presenceLoadingChecker,
      presenceOnlineResolver: widget.presenceOnlineResolver,
      onMemberListLoaded: widget.onMemberListLoaded,
      presenceListenable: widget.presenceListenable,
      isShowOnlineStatus: widget.isShowOnlineStatus,
      emptyBuilder: _keyword.isEmpty
          ? null
          : (context) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _cloudSearch.usedCloud
                        ? (widget.isChannel ? '未找到匹配的订阅者' : TIM_t('未找到匹配的群成员'))
                        : (widget.isChannel
                            ? '当前已加载订阅者中无匹配结果'
                            : TIM_t('当前已加载成员中无匹配结果')),
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.weakTextColor ?? const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
      onTapMemberItem: (memberInfo, details) {
        if (widget.model.onClickUser != null) {
          widget.model.onClickUser!(memberInfo, details);
        }
      },
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;
    final isDesktopScreen =
        TUIKitScreenUtils.getFormFactor() == DeviceType.Desktop;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.model),
      ],
      builder: (BuildContext context, Widget? w) {
        final TUIGroupProfileModel groupProfileModel =
            Provider.of<TUIGroupProfileModel>(context);
        final members = _visibleMembers(groupProfileModel.groupMemberList);
        final option1 = groupProfileModel.displayedMemberCount().toString();
        if (isDesktopScreen) {
          return _memberBody(theme: theme, members: members);
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.isChannel
                  ? '$option1位订阅者'
                  : TIM_t_para("群成员({{option1}}人)", "群成员($option1人)")(
                      option1: option1),
              style: TextStyle(color: theme.appbarTextColor, fontSize: 17),
            ),
            shadowColor: theme.weakBackgroundColor,
            backgroundColor: theme.appbarBgColor ?? theme.primaryColor,
            iconTheme: IconThemeData(
              color: theme.primaryColor ?? const Color(0xFF1E90FF),
            ),
            leading: TIMUIKitBackButton(
              color: theme.primaryColor ?? const Color(0xFF1E90FF),
            ),
          ),
          body: _memberBody(theme: theme, members: members),
        );
      },
    );
  }
}
