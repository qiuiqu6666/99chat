import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_search_bar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_list.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/group_list.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/search.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_empty_state.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_list_with_presence.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_demo/utils/profile_page_nav.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_demo/src/utils/contact_conversation_peek.dart';
import 'package:tencent_cloud_chat_demo/src/all_group_application_list.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_contact_subpage_host.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_unread_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/perf_timeline.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_ui.dart';
import 'newContact.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_activity.dart';
import 'package:tencent_cloud_chat_demo/src/ui/utils/desktop_modal_layout.dart';

class Contact extends StatefulWidget {
  final ValueChanged<String>? onTapItem;

  const Contact({Key? key, this.onTapItem}) : super(key: key);

  /// Tests inject an IM friend list without calling the native SDK.
  @visibleForTesting
  static Future<List<V2TimFriendInfo>> Function()? debugLoadImFriends;

  @override
  State<StatefulWidget> createState() => _ContactState();
}

class _ContactState extends State<Contact> {
  final TUIFriendShipViewModel _friendShipModel =
      serviceLocator<TUIFriendShipViewModel>();
  List<V2TimFriendInfo> _imFriends = const [];
  Future<void>? _imFriendsLoadTask;
  Future<void>? _friendshipUIKitLoadTask;
  bool _imFriendsLoaded = false;
  bool _imFriendsReloadPending = false;
  int _friendListRevision = -1;
  int _modelFriendCount = -1;
  SessionIdentity? _identity;
  bool _tabActive = true;

  @override
  void initState() {
    super.initState();
    PerfTimeline.instant('contact_page_enter');
    StartupPerfLog.markTagged(
      'contact_init_start',
      category: 'cold_start',
      details: const <String, Object>{'tabName': 'contact'},
    );
    _identity = SessionIdentityService.instance.capture();
    _friendShipModel.addListener(_onFriendshipModelChanged);
    PeerProfileRefreshBus.instance.revision.addListener(_onPeerProfileRefresh);
    ImSdkRelationshipDirectory.instance.addListener(_onDirectoryChange);
    unawaited(_loadImFriends());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PerfTimeline.instant('contact_page_first_frame');
      unawaited(_loadFriendshipUIKitForContactPage());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabActive = HomeTabActivity.isActiveOf(context);
    final identity = SessionIdentityService.instance.capture();
    final identityChanged = _identity != identity;
    if (identityChanged) {
      _identity = identity;
      setState(() {
        _imFriends = const [];
        _imFriendsLoaded = false;
      });
    }
    if (identityChanged || (tabActive && !_tabActive)) {
      unawaited(_loadImFriends());
    }
    _tabActive = tabActive;
  }

  @override
  void dispose() {
    _friendShipModel.removeListener(_onFriendshipModelChanged);
    ImSdkRelationshipDirectory.instance.removeListener(_onDirectoryChange);
    PeerProfileRefreshBus.instance.revision.removeListener(_onPeerProfileRefresh);
    super.dispose();
  }

  void _onPeerProfileRefresh() {
    if (!mounted) return;
    unawaited(_loadImFriends());
  }

  void _onFriendshipModelChanged() {
    if (!mounted) return;
    final revision = _friendShipModel.friendListRevision;
    final count = _friendShipModel.friendList?.length ?? 0;
    if (revision == _friendListRevision && count == _modelFriendCount) {
      return;
    }
    _friendListRevision = revision;
    _modelFriendCount = count;
    unawaited(_loadImFriends());
  }

  Future<void> _loadImFriends() {
    final running = _imFriendsLoadTask;
    if (running != null) {
      _imFriendsReloadPending = true;
      return running;
    }
    late final Future<void> task;
    task = _readImFriends().whenComplete(() {
      if (identical(_imFriendsLoadTask, task)) {
        _imFriendsLoadTask = null;
        if (_imFriendsReloadPending && mounted) {
          _imFriendsReloadPending = false;
          unawaited(_loadImFriends());
        }
      }
    });
    _imFriendsLoadTask = task;
    return task;
  }

  void _onDirectoryChange(RelationshipDirectoryChange change) {
    if (!mounted || change.kind != RelationshipListKind.friends) {
      return;
    }
    if (change.snapshotCompleted && !_imFriendsLoaded) {
      setState(() => _imFriendsLoaded = true);
    }
  }

  Future<void> _readImFriends() async {
    final identity =
        _identity ?? SessionIdentityService.instance.capture();
    try {
      final loader = Contact.debugLoadImFriends;
      if (loader != null) {
        final friends = await loader();
        if (!mounted) return;
        if (_identity != null && _identity != identity) return;
        setState(() {
          _imFriends = List<V2TimFriendInfo>.unmodifiable(friends);
          _imFriendsLoaded = true;
        });
        return;
      }
      await ImSdkRelationshipReconcileService.instance
          .requestFirstSnapshot(reason: 'enter_contacts');
      if (!mounted) return;
      if (_identity != null && _identity != identity) return;
      setState(() {
        _imFriendsLoaded =
            ImSdkRelationshipDirectory.instance.hasCompleteFriendSnapshot ||
                _imFriendsLoaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imFriendsLoaded = true;
      });
    }
  }

  /// 新的朋友申请仍走 UIKit；好友名单本身只读 IM SNS。
  Future<void> _loadFriendshipUIKitForContactPage() {
    final running = _friendshipUIKitLoadTask;
    if (running != null) return running;
    late final Future<void> task;
    task = _loadFriendshipUIKit().whenComplete(() {
      if (identical(_friendshipUIKitLoadTask, task)) {
        _friendshipUIKitLoadTask = null;
      }
    });
    _friendshipUIKitLoadTask = task;
    return task;
  }

  Future<void> _loadFriendshipUIKit() async {
    try {
      await _friendShipModel.loadContactApplicationData();
    } catch (_) {}
  }

  Widget _buildContactLoadingPlaceholder(
    BuildContext context, {
    required bool includeTopEntries,
  }) {
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final isDark = ThemeData.estimateBrightnessForColor(
          theme.weakBackgroundColor ?? AppColors.background(dark: false),
        ) ==
        Brightness.dark;
    final lineColor = (theme.weakDividerColor ?? AppColors.line(dark: isDark))
        .withValues(alpha: 0.35);
    final subLineColor = lineColor.withValues(alpha: 0.55);
    final blockColor = (theme.weakDividerColor ?? AppColors.line(dark: isDark))
        .withValues(alpha: 0.6);
    final dividerColor = theme.weakDividerColor ?? AppColors.line(dark: isDark);

    final desktop = kIsWeb ||
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final avatarSize = DirectoryListStyle.avatarSize(desktop);
    final rowHeight = DirectoryListStyle.rowHeight(context, desktop: desktop);
    final dividerInset = 16 + avatarSize + DirectoryListStyle.avatarTextGap;

    Widget buildPlaceholder({bool detail = false, int index = 0}) => SizedBox(
          height: rowHeight,
          child: Column(children: [
            Expanded(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                        color: blockColor, shape: BoxShape.circle)),
                const SizedBox(width: DirectoryListStyle.avatarTextGap),
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                          width: 120 + (index % 3) * 24,
                          height: 16,
                          decoration: BoxDecoration(
                              color: lineColor,
                              borderRadius: BorderRadius.circular(999))),
                      if (detail) ...[
                        const SizedBox(height: DirectoryListStyle.textGap),
                        Container(
                            width: 72 + (index % 2) * 16,
                            height: 13,
                            decoration: BoxDecoration(
                                color: subLineColor,
                                borderRadius: BorderRadius.circular(999))),
                      ],
                    ])),
              ]),
            )),
            Padding(
                padding: EdgeInsets.only(left: dividerInset),
                child: Container(height: 0.6, color: dividerColor)),
          ]),
        );
    Widget buildTopPlaceholder() => buildPlaceholder();
    Widget buildFriendPlaceholder(int index) =>
        buildPlaceholder(detail: true, index: index);

    return ListView(
      key: const PageStorageKey<String>('contact_loading_placeholder'),
      children: [
        if (includeTopEntries) ...[
          buildTopPlaceholder(),
          buildTopPlaceholder(),
          buildTopPlaceholder(),
        ],
        for (var i = 0; i < 7; i++) buildFriendPlaceholder(i),
      ],
    );
  }

  _topListItemTap(String id) {
    switch (id) {
      case "newContact":
        unawaited(_openNewFriends());
        break;
      case "groupList":
        final isWideScreen =
            TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
        if (isWideScreen) {
        } else {
          Navigator.push(
            context,
            AppMaterialPageRoute(
              settings: const RouteSettings(name: AppRoutes.myGroupList),
              builder: (context) => const GroupList(),
            ),
          );
        }
        break;
      case "groupNotice":
        unawaited(GroupNoticeUnreadService.instance.markRead());
        if (DesktopModalLayout.isDesktop(context)) {
          DesktopContactSubpageHost.open(DesktopContactSubpage.groupNotice);
        } else {
          Navigator.push(
            context,
            AppMaterialPageRoute(
              builder: (context) => const AllGroupApplicationListPage(),
            ),
          );
        }
        break;
      default:
        break;
    }
  }

  Future<void> _openNewFriends() async {
    await FriendRequestNoticeService.instance.commitObservedAsRead();
    if (!mounted) {
      return;
    }
    if (DesktopModalLayout.isDesktop(context)) {
      DesktopContactSubpageHost.open(DesktopContactSubpage.newFriends);
      return;
    }
    Navigator.push(
      context,
      AppMaterialPageRoute(builder: (context) => const NewContact()),
    );
  }

  String _getImagePathByID(String id) {
    final themeType = Provider.of<DefaultThemeData>(context).currentThemeType;
    final themeTypeSuffix = themeType == ThemeType.dark ? 'solemn' : 'brisk';
    switch (id) {
      case "newContact":
        return "assets/newContact_$themeTypeSuffix.png";
      case "groupList":
        return "assets/groupList_$themeTypeSuffix.png";
      case "groupNotice":
        return conversationGroupNoticeEntryIconAsset;
      case "customerService":
        return "assets/customerService.png";
      default:
        return "";
    }
  }

  Widget _buildTopEntryAvatar(String id) {
    final size = (kIsWeb ||
            TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop)
        ? 48.0
        : 46.0;
    final Widget avatar;
    if (id == 'groupNotice') {
      avatar = buildConversationSystemEntryAvatar(
        conversationGroupNoticeEntryIconAsset,
        size: size,
        scale: 1.5,
      );
    } else {
      avatar = SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: Image.asset(_getImagePathByID(id), fit: BoxFit.cover),
        ),
      );
    }

    if (id != 'newContact' && id != 'groupNotice') {
      return avatar;
    }

    if (id == 'groupNotice') {
      return AnimatedBuilder(
        animation: GroupNoticeUnreadService.instance,
        builder: (context, child) {
          final count = GroupNoticeUnreadService.instance.unreadCount;
          if (count <= 0) {
            return child!;
          }
          final label = count > 99 ? '99+' : '$count';
          return Stack(
            clipBehavior: Clip.none,
            children: [
              child!,
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTokens.danger,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: avatar,
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable:
          FriendRequestNoticeService.instance.pendingApplicationCount,
      builder: (context, count, child) {
        if (count <= 0) {
          return child!;
        }
        final label = count > 99 ? '99+' : '$count';
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppTokens.danger,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: avatar,
    );
  }

  Future<void> _openSearch() async {
    await Navigator.push(
      context,
      AppMaterialPageRoute(
        settings: const RouteSettings(name: AppRoutes.search),
        builder: (context) => Search(
          onTapConversation: (conversation, anchor) async {
            await openChatWithAnchor(context, conversation, anchor: anchor);
          },
        ),
      ),
    );
  }

  void _showContactPeek(V2TimFriendInfo friend) {
    unawaited(ContactConversationPeek.show(context, friend: friend));
  }

  @override
  Widget build(BuildContext context) {
    // The same selector must own the list while hidden, otherwise switching
    // tabs recreates its grouped projection, subscriptions and scroll state.
    return Selector2<LocalSetting, DefaultThemeData, (bool, TUITheme)>(
      selector: (_, settings, themeModel) => (
        settings.isShowOnlineStatus,
        themeModel.theme,
      ),
      builder: (context, data, _) => _buildContactBody(
        context,
        localSetting: context.read<LocalSetting>(),
        theme: data.$2,
      ),
    );
  }

  Widget _buildContactBody(
    BuildContext context, {
    required LocalSetting localSetting,
    required TUITheme theme,
  }) {
    final i18n = AppI18n.of(context);
    final isWideScreen =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final friendList = Contact.debugLoadImFriends != null ? _imFriends : null;
    return Container(
      color: theme.weakBackgroundColor ?? Colors.white,
      child: Column(
        children: [
          if (!isWideScreen) ConversationSearchBar(onTap: _openSearch),
          Expanded(
            child: !_imFriendsLoaded
                ? _buildContactLoadingPlaceholder(
                    context,
                    includeTopEntries: !isWideScreen,
                  )
                : ContactListWithPresence(
                    friends: friendList,
                    isShowOnlineStatus: localSetting.isShowOnlineStatus,
                    showContactCount: true,
                    topList: [
                      TopListItem(
                        name: i18n.t(
                          zhHans: '新的朋友',
                          zhHant: '新的朋友',
                          en: 'New Friends',
                          ja: '新しい友達',
                          ko: '새 친구',
                        ),
                        id: "newContact",
                        icon: _buildTopEntryAvatar("newContact"),
                        onTap: () {
                          _topListItemTap("newContact");
                        },
                      ),
                      TopListItem(
                        name: i18n.t(
                          zhHans: '群通知',
                          zhHant: '群組通知',
                          en: 'Group Notices',
                          ja: 'グループ通知',
                          ko: '그룹 알림',
                        ),
                        id: "groupNotice",
                        icon: _buildTopEntryAvatar("groupNotice"),
                        onTap: () {
                          _topListItemTap("groupNotice");
                        },
                      ),
                      if (!isWideScreen)
                        TopListItem(
                          name: i18n.t(
                            zhHans: '我的群聊',
                            zhHant: '我的群聊',
                            en: 'My Groups',
                            ja: 'マイグループ',
                            ko: '내 그룹',
                          ),
                          id: "groupList",
                          icon: _buildTopEntryAvatar("groupList"),
                          onTap: () {
                            _topListItemTap("groupList");
                          },
                        ),
                    ],
                    onTapItem: (item) {
                      if (widget.onTapItem != null) {
                        widget.onTapItem!(item.userID);
                      } else {
                        ProfilePageNav.openUserProfile(
                          context,
                          userID: item.userID,
                          addSource: 'contacts',
                          initialAvatarUrl: item.userProfile?.faceUrl,
                        );
                      }
                    },
                    onLongPressItem: _showContactPeek,
                    emptyBuilder: (context) => AppEmptyState(
                      message: i18n.t(
                        zhHans: '无联系人',
                        zhHant: '無聯絡人',
                        en: 'No contacts',
                        ja: '連絡先がありません',
                        ko: '연락처가 없습니다',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
