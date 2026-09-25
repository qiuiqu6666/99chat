import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/directory_search_bar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/my_group_az_skeleton.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/my_group_list_controller.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_group_title_color.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_empty_state.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_group_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_list_role_badge.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';

class GroupList extends StatefulWidget {
  final bool channelOnly;
  final void Function(V2TimGroupInfo groupInfo, V2TimConversation conversation)?
      onTapItem;

  const GroupList({Key? key, this.onTapItem, this.channelOnly = false})
      : super(key: key);

  @override
  State<GroupList> createState() => _GroupListState();
}

class _GroupListState extends State<GroupList> {
  static const _footerMarker = '__group_count_footer__';
  static const _searchDebounce = Duration(milliseconds: 250);

  final sdkInstance = TIMUIKitCore.getSDKInstance();
  final MyGroupListController _controller = MyGroupListController.instance;
  final TextEditingController _searchController = TextEditingController();

  String _searchKeyword = '';
  Timer? _searchDebounceTimer;
  List<ISuspensionBeanImpl>? _effectiveListSource;
  List<ISuspensionBeanImpl> _effectiveList = const [];

  @override
  void initState() {
    super.initState();
    if (GroupLocalPerfFlags.myGroupListAzOptimizeEnabled) {
      _searchKeyword = '';
      _controller.addListener(_onControllerChanged);
      // Start the local snapshot read immediately during route construction;
      // waiting for the first post-frame callback made the list appear late.
      unawaited(_loadGroupsImmediately());
    }
  }

  Future<void> _loadGroupsImmediately() async {
    await _controller.clearSearch(reload: false);
    if (!mounted) return;
    await _controller.ensureLoaded();
    if (!mounted) return;
    GroupMembershipSyncService.instance.scheduleGroupListBackgroundSync();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    if (GroupLocalPerfFlags.myGroupListAzOptimizeEnabled) {
      _controller.removeListener(_onControllerChanged);
      _controller.setScrolling(false);
      // 离页清 keyword，避免再进仍是过滤结果；不 reload。
      unawaited(_controller.clearSearch(reload: false));
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _onGroupListScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _controller.setScrolling(true);
    } else if (notification is ScrollEndNotification) {
      _controller.setScrolling(false);
    } else if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _controller.setScrolling(false);
    }
    return false;
  }

  Future<void> _jumpToChatPage(
    BuildContext context,
    V2TimGroupInfo groupInfo,
    V2TimConversation conversation,
  ) async {
    if (widget.onTapItem != null) {
      widget.onTapItem!(groupInfo, conversation);
      return;
    }
    if (context.mounted) {
      openOrReuseAppChat(context, conversation);
    }
  }

  Future<void> _onTapSkeleton(MyGroupAzSkeleton skeleton) async {
    final groupInfo = skeleton.toV2TimGroupInfo();
    var conversation = skeleton.toConversation();
    final res = await sdkInstance
        .getConversationManager()
        .getConversation(conversationID: 'group_${groupInfo.groupID}');
    if (res.code == 0 && res.data != null) {
      conversation = skeleton.toConversation(sdkConversation: res.data!);
    }
    if (!mounted) {
      return;
    }
    await _jumpToChatPage(context, groupInfo, conversation);
  }

  Widget _buildGroupCountFooter(BuildContext context, int count) {
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final isDesktop =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final i18n = AppI18n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Center(
        child: Text(
          i18n.format(
            zhHans: widget.channelOnly ? '共{count}个频道' : '共{count}个群',
            zhHant: widget.channelOnly ? '共{count}個頻道' : '共{count}個群',
            en: widget.channelOnly ? '{count} channels' : '{count} groups',
            ja: widget.channelOnly ? 'チャンネル {count} 件' : 'グループ {count} 件',
            ko: widget.channelOnly ? '채널 {count}개' : '그룹 {count}개',
            vars: {'count': count.toString()},
          ),
          style: TextStyle(
            color: theme.weakTextColor ?? const Color(0xFF999999),
            fontSize: isDesktop ? 12 : 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildOptimizedItem(
    BuildContext context,
    MyGroupAzSkeleton skeleton,
  ) {
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final showName = skeleton.showName;
    final faceUrl = skeleton.avatarUrl;
    final isDesktopScreen = kIsWeb ||
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final itemBackgroundColor = theme.conversationItemBgColor ??
        theme.weakBackgroundColor ??
        Colors.white;
    final memberCount = skeleton.memberCount;
    final i18n = AppI18n.of(context);
    final memberCountLabel = i18n.format(
      zhHans: '{count}人',
      zhHant: '{count}人',
      en: '{count} members',
      ja: '{count}人',
      ko: '{count}명',
      vars: {'count': memberCount.toString()},
    );
    final avatarSize = DirectoryListStyle.avatarSize(isDesktopScreen);
    final avatarTextGap = DirectoryListStyle.avatarTextGap;
    final rowPad = DirectoryListStyle.verticalPadding;
    final titleFontSize = DirectoryListStyle.titleSize;
    final subtitleFontSize = DirectoryListStyle.subtitleSize;
    final minHeight =
        DirectoryListStyle.rowHeight(context, desktop: isDesktopScreen);

    final rowColor = isDesktopScreen
        ? (theme.wideBackgroundColor ?? itemBackgroundColor)
        : itemBackgroundColor;
    final dividerColor = DirectoryListStyle.dividerColor(context);
    return SizedBox(
      height: minHeight,
      child: Stack(
        children: [
          Positioned.fill(
            bottom: 0.6,
            child: Material(
              color: rowColor,
              child: InkWell(
                onTap: () => unawaited(_onTapSkeleton(skeleton)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, rowPad, 16, rowPad),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        height: avatarSize,
                        width: avatarSize,
                        margin: EdgeInsets.only(right: avatarTextGap),
                        child: AppGroupAvatar(
                          groupId: skeleton.groupId,
                          faceUrl: faceUrl,
                          showName: showName,
                          size: avatarSize,
                          avatarVersion: skeleton.avatarVersion,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildGroupTitleWithOptionalFlame(
                              name: showName,
                              groupType: skeleton.groupType,
                              flameSize: titleFontSize - 1,
                              style: TextStyle(
                                color: conversationGroupTitleColor(
                                  fallback:
                                      theme.conversationItemTitleTextColor ??
                                          theme.darkTextColor ??
                                          Colors.black,
                                  groupType: skeleton.groupType,
                                ),
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
                                    const Color(0xFF999999),
                                fontSize: subtitleFontSize,
                                height: DirectoryListStyle.lineHeight,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!widget.channelOnly &&
                          groupListSelfRoleKind(skeleton.myRole) !=
                              GroupListSelfRoleKind.member) ...[
                        const SizedBox(width: 8),
                        GroupListSelfRoleBadge(role: skeleton.myRole),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16 + avatarSize + avatarTextGap,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ColoredBox(
                color: dividerColor,
                child: const SizedBox(height: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizedGroupList(AppI18n i18n) {
    if (_controller.isLoading && _controller.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final showList = _controller.azShowList
        .where((row) => row.memberInfo.isChannel == widget.channelOnly)
        .toList();
    if (!_controller.isLoading && showList.isEmpty) {
      return AppEmptyState(
        message: i18n.t(
          zhHans: widget.channelOnly ? '暂无频道' : '暂无群聊',
          zhHant: widget.channelOnly ? '暫無頻道' : '暫無群聊',
          en: widget.channelOnly ? 'No channels yet' : 'No groups yet',
          ja: widget.channelOnly ? 'チャンネルはありません' : 'グループはありません',
          ko: widget.channelOnly ? '채널이 없습니다' : '그룹이 없습니다',
        ),
      );
    }

    if (widget.channelOnly || !identical(_effectiveListSource, showList)) {
      _effectiveListSource = showList;
      _effectiveList = <ISuspensionBeanImpl>[
        ...showList,
        ISuspensionBeanImpl<Object>(
          memberInfo: _footerMarker,
          tagIndex: '',
        ),
      ];
    }
    final effectiveList = _effectiveList;

    return NotificationListener<ScrollNotification>(
      onNotification: _onGroupListScrollNotification,
      child: ChangeNotifierProvider<TUIThemeViewModel>.value(
        value: serviceLocator<TUIThemeViewModel>(),
        child: AZListViewContainer(
          itemIdentity: (row) {
            final item = row.memberInfo;
            return item is MyGroupAzSkeleton
                ? 'group:${item.groupId}'
                : 'footer:$item';
          },
          isShowIndexBar: true,
          subduedStyle: true,
          memberList: effectiveList,
          itemBuilder: (context, index) {
            final memberInfo = effectiveList[index].memberInfo;
            if (memberInfo == _footerMarker) {
              return _buildGroupCountFooter(
                  context,
                  widget.channelOnly
                      ? showList.length
                      : _controller.displayCount);
            }
            return _buildOptimizedItem(
              context,
              memberInfo as MyGroupAzSkeleton,
            );
          },
        ),
      ),
    );
  }

  Widget _buildLegacyGroupList(AppI18n i18n) {
    return TIMUIKitGroup(
      onTapItem: (groupInfo, conversation) {
        unawaited(_jumpToChatPage(context, groupInfo, conversation));
      },
      emptyBuilder: (_) {
        return AppEmptyState(
          message: i18n.t(
            zhHans: widget.channelOnly ? '暂无频道' : '暂无群聊',
            zhHant: widget.channelOnly ? '暫無頻道' : '暫無群聊',
            en: widget.channelOnly ? 'No channels yet' : 'No groups yet',
            ja: widget.channelOnly ? 'チャンネルはありません' : 'グループはありません',
            ko: widget.channelOnly ? '채널이 없습니다' : '그룹이 없습니다',
          ),
        );
      },
      groupCollector: (groupInfo) {
        final groupID = groupInfo?.groupID ?? '';
        final isChannel =
            GroupLocalStore.instance.readCached(groupId: groupID)?.isChannel ??
                false;
        return !groupID.contains('im_discuss_') &&
            isChannel == widget.channelOnly;
      },
      searchKeyword: _searchKeyword,
      isShowIndexBar: true,
      showSelfRoleBadge: !widget.channelOnly,
      showGroupCount: true,
      groupCountFooterBuilder: _buildGroupCountFooter,
    );
  }

  Widget _buildGroupList(AppI18n i18n) {
    if (GroupLocalPerfFlags.myGroupListAzOptimizeEnabled) {
      return _buildOptimizedGroupList(i18n);
    }
    return _buildLegacyGroupList(i18n);
  }

  void _onSearchChanged(String value) {
    if (!GroupLocalPerfFlags.myGroupListAzOptimizeEnabled) {
      setState(() {
        _searchKeyword = value;
      });
      return;
    }
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      unawaited(_controller.setSearchKeyword(value));
    });
  }

  Widget _buildSearchBar(AppI18n i18n) => DirectorySearchBar(
        controller: _searchController,
        onChanged: _onSearchChanged,
        hint: i18n.t(
            zhHans: widget.channelOnly ? '搜索频道' : '搜索群聊',
            zhHant: widget.channelOnly ? '搜尋頻道' : '搜尋群聊',
            en: widget.channelOnly ? 'Search channels' : 'Search groups',
            ja: widget.channelOnly ? 'チャンネルを検索' : 'グループを検索',
            ko: widget.channelOnly ? '채널 검색' : '그룹 검색'),
      );

  Widget _buildPageBody(AppI18n i18n) {
    return Column(
      children: [
        _buildSearchBar(i18n),
        Expanded(child: _buildGroupList(i18n)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final i18n = AppI18n.of(context);

    return TUIKitScreenUtils.getDeviceWidget(
      context: context,
      desktopWidget: Container(
        color: theme.weakBackgroundColor ?? Colors.white,
        child: _buildPageBody(i18n),
      ),
      defaultWidget: Scaffold(
        backgroundColor: theme.weakBackgroundColor ?? Colors.white,
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          title: Text(
            i18n.t(
              zhHans: widget.channelOnly ? '频道' : '群聊',
              zhHant: widget.channelOnly ? '頻道' : '群聊',
              en: widget.channelOnly ? 'Channels' : 'Groups',
              ja: widget.channelOnly ? 'チャンネル' : 'グループ',
              ko: widget.channelOnly ? '채널' : '그룹',
            ),
            style: TextStyle(
              color:
                  theme.appbarTextColor ?? theme.darkTextColor ?? Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: theme.appbarBgColor ?? Colors.white,
          shadowColor: theme.weakDividerColor,
          iconTheme: IconThemeData(
            color: theme.primaryColor ?? const Color(0xFF1E90FF),
          ),
          leading: AppBackButton(
            color: theme.primaryColor ?? const Color(0xFF1E90FF),
          ),
        ),
        body: _buildPageBody(i18n),
      ),
    );
  }
}
