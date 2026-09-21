import 'dart:async';

import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_list_role_badge.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/listener_model/tui_group_listener_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';

typedef GroupItemBuilder = Widget Function(BuildContext context, V2TimGroupInfo groupInfo);
typedef GroupCountFooterBuilder = Widget Function(BuildContext context, int count);

const _groupCountFooterMarker = '__group_count_footer__';

class TIMUIKitGroup extends StatefulWidget {
  final void Function(V2TimGroupInfo groupInfo, V2TimConversation conversation)? onTapItem;
  final Widget Function(BuildContext context)? emptyBuilder;
  final GroupItemBuilder? itemBuilder;

  /// the filter for group conversation
  final bool Function(V2TimGroupInfo? groupInfo)? groupCollector;

  /// local search keyword for group name, group id, and pinyin
  final String searchKeyword;

  /// control whether to show the alphabet index bar on mobile
  final bool isShowIndexBar;

  /// show total group count footer at the bottom of the scroll list
  final bool showGroupCount;

  /// custom footer for [showGroupCount]; defaults to a centered weak text row
  final GroupCountFooterBuilder? groupCountFooterBuilder;

  /// 列表项右侧展示当前用户在群内的角色（群主/管理员/普通成员）。
  final bool showSelfRoleBadge;

  const TIMUIKitGroup({
    Key? key,
    this.onTapItem,
    this.emptyBuilder,
    this.itemBuilder,
    this.groupCollector,
    this.searchKeyword = "",
    this.isShowIndexBar = false,
    this.showGroupCount = false,
    this.groupCountFooterBuilder,
    this.showSelfRoleBadge = false,
  })
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _TIMUIKitGroupState();
}

class _TIMUIKitGroupState extends TIMUIKitState<TIMUIKitGroup> {
  final TUIFriendShipViewModel _friendshipViewModel = serviceLocator<TUIFriendShipViewModel>();
  final TUIGroupListenerModel _groupListenerModel = serviceLocator<TUIGroupListenerModel>();
  List<V2TimGroupInfo> _directoryGroups = const <V2TimGroupInfo>[];

  String _getShowName(V2TimGroupInfo item) {
    final groupName = item.groupName?.trim() ?? "";
    final groupID = item.groupID;
    return groupName.isNotEmpty ? groupName : groupID;
  }

  bool _matchesSearch(V2TimGroupInfo item) {
    return groupDirectoryMatchesSearchKeyword(
      groupName: item.groupName ?? '',
      groupId: item.groupID,
      keyword: widget.searchKeyword,
    );
  }

  List<ISuspensionBeanImpl<V2TimGroupInfo>> _getShowList(List<V2TimGroupInfo> groupList) {
    final List<ISuspensionBeanImpl<V2TimGroupInfo>> showList = List.empty(growable: true);
    for (var i = 0; i < groupList.length; i++) {
      final item = groupList[i];

      final showName = _getShowName(item);
      showList.add(
        ISuspensionBeanImpl(
          memberInfo: item,
          tagIndex: memberSuspensionIndexTag(showName),
        ),
      );
    }

    SuspensionUtil.sortListBySuspensionTag(showList);

    return showList;
  }

  Widget _itemBuilder(BuildContext context, V2TimGroupInfo groupInfo) {
    final theme = Provider.of<TUIThemeViewModel>(context).theme;
    final showName = _getShowName(groupInfo);
    final faceUrl = groupInfo.faceUrl ?? "";
    final isDesktopScreen = kIsWeb ||
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final itemBackgroundColor =
        theme.conversationItemBgColor ?? theme.weakBackgroundColor ?? Colors.white;
    final memberCount = groupInfo.memberCount ?? 0;
    final memberCountLabel =
        TIM_t_para("{{option1}}人", "$memberCount人")(option1: '$memberCount');
    // 与通讯录 ContactListWithPresence 桌面密度对齐。
    final avatarSize = DirectoryListStyle.avatarSize(isDesktopScreen);
    final avatarTextGap = DirectoryListStyle.avatarTextGap;
    final rowPad = DirectoryListStyle.verticalPadding;
    final titleFontSize = DirectoryListStyle.titleSize;
    final subtitleFontSize = DirectoryListStyle.subtitleSize;
    final minHeight = DirectoryListStyle.rowHeight(context, desktop: isDesktopScreen);

    return Material(
      color: isDesktopScreen
          ? (theme.wideBackgroundColor ?? itemBackgroundColor)
          : itemBackgroundColor,
      child: InkWell(
        onTap: (() async {
          if (widget.onTapItem != null) {
            V2TimConversation conversation = V2TimConversation(
              conversationID: "group_${groupInfo.groupID}",
              groupID: groupInfo.groupID,
              type: 2,
              showName: groupInfo.groupName,
              groupType: groupInfo.groupType,
              faceUrl: groupInfo.faceUrl,
            );
            final res = await TencentImSDKPlugin.v2TIMManager
                .getConversationManager()
                .getConversation(conversationID: "group_${groupInfo.groupID}");
            if (res.code == 0 && res.data != null) {
              conversation = res.data!;
            }
            widget.onTapItem!(groupInfo, conversation);
          }
        }),
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: EdgeInsets.only(top: rowPad, left: 16),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.only(right: 16, bottom: rowPad),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: avatarSize,
                      width: avatarSize,
                      margin: EdgeInsets.only(right: avatarTextGap),
                      child: Avatar(
                        faceUrl: faceUrl,
                        showName: showName,
                        type: 2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            showName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.conversationItemTitleTextColor ??
                                  theme.darkTextColor ??
                                  Colors.black,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w500,
                              height: DirectoryListStyle.lineHeight,
                            ),
                          ),
                          const SizedBox(height: DirectoryListStyle.textGap),
                          Text(
                            memberCountLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.weakTextColor ??
                                  theme.conversationItemLastMessageTextColor ??
                                  CommonColor.weakTextColor,
                              fontSize: subtitleFontSize,
                              height: DirectoryListStyle.lineHeight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.showSelfRoleBadge && groupListSelfRoleKind(groupInfo.role) != GroupListSelfRoleKind.member) ...[
                      const SizedBox(width: 8),
                      GroupListSelfRoleBadge(role: groupInfo.role),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: avatarSize + avatarTextGap),
                child: Container(
                  height: 0.6,
                  color: DirectoryListStyle.dividerColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  GroupItemBuilder _getItemBuilder() {
    return widget.itemBuilder ?? _itemBuilder;
  }

  Widget _buildGroupCountFooter(BuildContext context, int count, TUITheme theme) {
    final builder = widget.groupCountFooterBuilder;
    if (builder != null) {
      return builder(context, count);
    }
    final isDesktopScreen =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Center(
        child: Text(
          '$count groups',
          style: TextStyle(
            color: theme.weakTextColor ?? CommonColor.weakTextColor,
            fontSize: isDesktopScreen ? 12 : 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    ImSdkRelationshipDirectory.instance.addListener(_onDirectoryChange);
    _syncGroupsFromDirectory();
    unawaited(
      ImSdkRelationshipReconcileService.instance
          .requestFirstSnapshot(reason: 'enter_my_groups'),
    );
  }

  @override
  void dispose() {
    ImSdkRelationshipDirectory.instance.removeListener(_onDirectoryChange);
    super.dispose();
  }

  void _onDirectoryChange(RelationshipDirectoryChange change) {
    if (change.kind != RelationshipListKind.groups) {
      return;
    }
    _syncGroupsFromDirectory();
  }

  void _syncGroupsFromDirectory() {
    final directory = ImSdkRelationshipDirectory.instance;
    _directoryGroups = <V2TimGroupInfo>[
      for (final id in directory.groupOrderedIds)
        if (directory.group(id) != null) directory.group(id)!.toV2TimGroupInfo(),
    ];
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _friendshipViewModel),
        ChangeNotifierProvider.value(value: _groupListenerModel),
        ChangeNotifierProvider.value(value: serviceLocator<TUIThemeViewModel>()),
      ],
      builder: (BuildContext context, Widget? w) {
        final theme = Provider.of<TUIThemeViewModel>(context).theme;
        final NeedUpdate? needUpdate = Provider.of<TUIGroupListenerModel>(context).needUpdate;
        if (needUpdate != null) {
          _groupListenerModel.needUpdate = null;
          switch (needUpdate.updateType) {
            case UpdateType.kickedFromGroup:
            case UpdateType.groupDismissed:
              ImSdkRelationshipDirectory.instance
                  .applyGroupRemoves(<String>[needUpdate.groupID]);
              break;
            default:
              break;
          }
        }
        List<V2TimGroupInfo> groupList = _directoryGroups.isNotEmpty
            ? _directoryGroups
            : Provider.of<TUIFriendShipViewModel>(context).groupList;
        if (widget.groupCollector != null) {
          groupList = groupList.where(widget.groupCollector!).toList();
        }
        if (widget.searchKeyword.trim().isNotEmpty) {
          groupList = groupList.where(_matchesSearch).toList();
        }
        if (groupList.isNotEmpty) {
          final showList = _getShowList(groupList);
          final effectiveList = widget.showGroupCount
              ? [
                  ...showList,
                  ISuspensionBeanImpl<Object>(
                    memberInfo: _groupCountFooterMarker,
                    tagIndex: '',
                  ),
                ]
              : showList;
          return Container(
            color: theme.weakBackgroundColor ?? Colors.white,
            child: AZListViewContainer(
                isShowIndexBar: widget.isShowIndexBar,
                subduedStyle: true,
                memberList: effectiveList,
                itemBuilder: (context, index) {
                  final memberInfo = effectiveList[index].memberInfo;
                  if (memberInfo == _groupCountFooterMarker) {
                    return _buildGroupCountFooter(context, groupList.length, theme);
                  }
                  final groupInfo = memberInfo as V2TimGroupInfo;
                  final itemBuilder = _getItemBuilder();
                  return itemBuilder(context, groupInfo);
                }),
          );
        }

        if (widget.emptyBuilder != null) {
          return widget.emptyBuilder!(context);
        }

        return Container();
      },
    );
  }
}
