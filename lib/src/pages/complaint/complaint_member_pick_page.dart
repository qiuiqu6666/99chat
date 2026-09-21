import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/utils/group_at_mention.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_ui_group_member_search.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';

/// 群投诉：先选被投诉成员，再进入原因页。
class ComplaintMemberPickPage extends StatefulWidget {
  const ComplaintMemberPickPage({
    super.key,
    required this.model,
  });

  final TUIGroupProfileModel model;

  static Future<V2TimGroupMemberFullInfo?> open(
    BuildContext context, {
    required TUIGroupProfileModel model,
  }) {
    return Navigator.of(context).push<V2TimGroupMemberFullInfo>(
      AppMaterialPageRoute(
        builder: (_) => ComplaintMemberPickPage(model: model),
      ),
    );
  }

  @override
  State<ComplaintMemberPickPage> createState() =>
      _ComplaintMemberPickPageState();
}

class _ComplaintMemberPickPageState extends State<ComplaintMemberPickPage> {
  String _keyword = '';
  late final GroupMemberCloudSearchController _cloudSearch;

  @override
  void initState() {
    super.initState();
    _cloudSearch = GroupMemberCloudSearchController(
      groupId: widget.model.groupID,
      localFallback: (keyword) =>
          GroupMemberLocalStore.instance.loadAsV2TimMembers(
        groupId: widget.model.groupID,
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
    Iterable<V2TimGroupMemberFullInfo?> members,
  ) {
    final selfId =
        serviceLocator<TUISelfInfoViewModel>().loginInfo?.userID?.trim() ?? '';
    return members
        .whereType<V2TimGroupMemberFullInfo>()
        .where((m) => m.userID.trim().isNotEmpty && m.userID.trim() != selfId)
        .map<V2TimGroupMemberFullInfo?>((m) => m)
        .toList();
  }

  List<V2TimGroupMemberFullInfo?> _visibleMembers() {
    if (_keyword.isEmpty) {
      return _excludeSelf(widget.model.groupMemberList);
    }
    if (_cloudSearch.usedCloud || _cloudSearch.members.isNotEmpty) {
      return _excludeSelf(_cloudSearch.members);
    }
    return filterGroupMembersByKeyword(
      _excludeSelf(widget.model.groupMemberList),
      _keyword,
    );
  }

  void _onPick(V2TimGroupMemberFullInfo member) {
    Navigator.of(context).pop(member);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final isDark = Provider.of<DefaultThemeData>(context, listen: false)
            .currentThemeType ==
        ThemeType.dark;
    final i18n = AppI18n.of(context);
    final bg = theme.appbarBgColor ?? AppColors.card(dark: isDark);
    final textColor = theme.darkTextColor ?? AppColors.text(dark: isDark);

    return AnimatedBuilder(
      animation: widget.model,
      builder: (context, _) => Scaffold(
        backgroundColor: theme.weakBackgroundColor ??
            (isDark ? AppColors.darkBackground : const Color(0xFFF1F1F1)),
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: theme.primaryColor ?? AppColors.primaryBlue,
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            i18n.t(
              zhHans: '选择投诉对象',
              zhHant: '選擇投訴對象',
              en: 'Select User to Report',
              ja: '通報対象を選択',
              ko: '신고 대상 선택',
            ),
            style: TextStyle(
              color: textColor,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: GroupProfileMemberList(
          customTopArea: GroupMemberSearchTextField(
            onTextChange: _handleSearchText,
          ),
          memberList: _visibleMembers(),
          canSlideDelete: false,
          canSelectMember: false,
          onTapMemberItem: (member, _) => _onPick(member),
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
    );
  }
}

/// 展示名：群名片 / 昵称 / userId。
String complaintMemberDisplayName(V2TimGroupMemberFullInfo member) {
  return GroupAtMention.showName(member);
}
