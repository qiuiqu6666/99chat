import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_ui_group_member_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

GlobalKey<_SelectNewGroupOwner> selectNewGroupOwnerKey = GlobalKey();

class SelectNewGroupOwner extends StatefulWidget {
  final String? groupID;
  final TUIGroupProfileModel model;
  final ValueChanged<List<V2TimGroupMemberFullInfo>>? onSelectedMember;

  const SelectNewGroupOwner({
    this.groupID,
    Key? key,
    required this.model,
    this.onSelectedMember,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SelectNewGroupOwner();
}

class _SelectNewGroupOwner extends TIMUIKitState<SelectNewGroupOwner> {
  final CoreServicesImpl _coreServicesImpl = serviceLocator<CoreServicesImpl>();
  List<V2TimGroupMemberFullInfo> selectedMember = [];
  String _keyword = '';
  late final GroupMemberCloudSearchController _cloudSearch;

  @override
  void initState() {
    super.initState();
    _cloudSearch = GroupMemberCloudSearchController(
      groupId: (widget.groupID ?? widget.model.groupID).trim(),
      localFallback: (keyword) =>
          GroupMemberLocalStore.instance.loadAsV2TimMembers(
        groupId: (widget.groupID ?? widget.model.groupID).trim(),
        keyword: keyword,
        limit: 100,
      ),
      onUpdate: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    unawaited(widget.model.ensureMemberListPage());
  }

  @override
  void dispose() {
    _cloudSearch.dispose();
    super.dispose();
  }

  void _handleSearchText(String text) {
    final next = text.trim().toLowerCase();
    if (next != _keyword) {
      setState(() => _keyword = next);
    }
    _cloudSearch.onKeywordChanged(text);
  }

  List<V2TimGroupMemberFullInfo?> _excludeSelf(
    List<V2TimGroupMemberFullInfo?> members,
  ) {
    final selfId = _coreServicesImpl.loginInfo.userID;
    return members.where((element) => element?.userID != selfId).toList();
  }

  List<V2TimGroupMemberFullInfo?> _visibleMembers() {
    final base = _excludeSelf(widget.model.groupMemberList);
    if (_keyword.isEmpty) {
      return base;
    }
    if (_cloudSearch.usedCloud || _cloudSearch.members.isNotEmpty) {
      return _excludeSelf(
        _cloudSearch.members
            .map<V2TimGroupMemberFullInfo?>((member) => member)
            .toList(),
      );
    }
    return filterGroupMembersByKeyword(base, _keyword);
  }

  onSubmit() {
    if (widget.onSelectedMember != null) {
      widget.onSelectedMember!(selectedMember);
    }
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;

    Widget memberBody() {
      return GroupProfileMemberList(
        customTopArea: PlatformUtils().isWeb
            ? null
            : GroupMemberSearchTextField(
                onTextChange: _handleSearchText,
              ),
        memberList: _visibleMembers(),
        canSlideDelete: false,
        canSelectMember: true,
        maxSelectNum: 1,
        onSelectedMemberChange: (member) {
          selectedMember = member;
          setState(() {});
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
      );
    }

    return AnimatedBuilder(
      animation: widget.model,
      builder: (context, _) => TUIKitScreenUtils.getDeviceWidget(
          context: context,
          defaultWidget: Scaffold(
              appBar: AppBar(
                shadowColor: theme.weakBackgroundColor,
                iconTheme: IconThemeData(
                  color: theme.appbarTextColor,
                ),
                backgroundColor: theme.appbarBgColor ?? theme.primaryColor,
                title: Text(
                  TIM_t("转让群主"),
                  style: TextStyle(
                    color: theme.appbarTextColor,
                    fontSize: 17,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      onSubmit();
                      Navigator.pop(context, selectedMember);
                    },
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
              body: memberBody()),
          desktopWidget: memberBody()),
    );
  }
}
