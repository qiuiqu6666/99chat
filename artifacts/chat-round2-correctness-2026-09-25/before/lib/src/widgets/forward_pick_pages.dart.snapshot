import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/utils/friend_search_cache.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';
import 'package:tencent_cloud_chat_demo/utils/group_avatar_source.dart';
import 'package:tencent_cloud_chat_demo/utils/search_conversation_display.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/user_display_profile.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/official_account_name_label.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_coverage.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_history_coverage_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/history_search_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/ui/utils/desktop_modal_layout.dart';
import 'package:tencent_cloud_chat_demo/src/ui/components/app_search_bar.dart';
import 'package:tencent_cloud_chat_demo/utils/navigation_routes.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_list_with_presence.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_style_search_bar.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroup/tim_uikit_group.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';

bool _officialSearchProfileRevisionBound = false;

void registerAppUIKitExtensions(TUIChatGlobalModel globalModel) {
  globalModel.appMessageHistoryCoverageRepository ??=
      HistoryCoverageStore.instance;
  globalModel.appIm06HistoryCoverageStore ??=
      Im06MessageHistoryCoverageStoreAdapter(
    MessageHistoryCoverageStore.instance,
  );
  globalModel.appMessageReconciliationNetworkStateProvider ??= () {
    final reachability = NetworkStatusService.instance.status.value;
    if (reachability == NetworkReachability.offline) {
      return MessageReconciliationNetworkState.offline;
    }
    // Cloud eligibility follows the socket itself, not the handshake display
    // window. Whether a result may be certified as server-verified is decided
    // separately by ChatHistoryVerificationGate (server sync + provenance).
    if (reachability == NetworkReachability.online &&
        ImConnectStatusService.isTransportReady) {
      return MessageReconciliationNetworkState.online;
    }
    return MessageReconciliationNetworkState.unknown;
  };
  globalModel.appSearchBarBuilder ??= (context, controller, onChanged) {
    return buildAppSearchBarInset(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      minHeight: 44,
      fontSize: 15,
      context: context,
      controller: controller,
      onChanged: onChanged,
    );
  };
  globalModel.appContactPresenceBridgeBuilder ??= (context) {
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    final localSetting = Provider.of<LocalSetting>(context, listen: false);
    final friendship = serviceLocator<TUIFriendShipViewModel>();
    final showOnlineStatus = localSetting.isShowOnlineStatus;
    return AppContactPresenceBridge(
      presenceListenable: presence,
      presenceLabelBuilder: (userId, imOnline) {
        if (!showOnlineStatus) {
          return '';
        }
        return presence.listLabelFor(
          userId: userId,
          imOnline: imOnline,
          isMutualFriend: friendCanMessage(friendship, userId),
        );
      },
      presenceLoadingChecker: (userId, imOnline) {
        if (!showOnlineStatus) {
          return false;
        }
        return presence.isLastSeenLoading(
          userId: userId,
          imOnline: imOnline,
          isMutualFriend: friendCanMessage(friendship, userId),
        );
      },
      presenceOnlineResolver: (userId, imOnline) {
        if (!showOnlineStatus) {
          return false;
        }
        return presence.shouldShowPresence(
              userId,
              isMutualFriend: friendCanMessage(friendship, userId),
            ) &&
            presence.resolveOnline(userId: userId, imOnline: imOnline);
      },
      onContactListLoaded: (userIds) {
        if (!showOnlineStatus) {
          return;
        }
        presence.ensure(userIds);
      },
    );
  };
  globalModel.appForwardSelectFriendPage =
      (context) => const ForwardSelectFriendPage();
  globalModel.appForwardSelectGroupPage =
      (context) => const ForwardSelectGroupPage();
  globalModel.appForwardRecentConversations = () =>
      List<V2TimConversation>.from(
          ChatSessionController.instance.conversations);
  globalModel.appForwardRecentConversationsListenable =
      ChatSessionController.instance;
  globalModel.appSearchFaceUrlResolver =
      (userId, fallbackFaceUrl) => UserDisplayProfile.avatar(
            userId: userId,
            fallbackIm: fallbackFaceUrl,
          );
  globalModel.appSearchGroupFaceUrlResolver = (groupId, fallbackFaceUrl) {
    final url = GroupAvatarSource.fromCached(
      groupId: groupId,
      fallbackUrl: fallbackFaceUrl,
    ).faceUrl.trim();
    if (url.isEmpty || url.startsWith('assets/')) {
      return '';
    }
    if (url == ConversationFaceUrl.defaultGroupFaceAsset) {
      return '';
    }
    if (UserAvatarHelper.isDefaultPlaceholder(url)) {
      return '';
    }
    return url;
  };
  globalModel.appSearchGroupNameResolver = (groupId) {
    final name = GroupLocalStore.instance
            .readCached(groupId: groupId)
            ?.groupName
            .trim() ??
        '';
    return name.isEmpty ? null : name;
  };
  globalModel.appSearchConversationDisplayResolver =
      resolveAppSearchConversationDisplay;
  serviceLocator<TUISearchViewModel>().appSearchDisplayHydrator =
      hydrateAppSearchConversationDisplays;
  globalModel.appSearchNameBuilder =
      (context, userId, name) => OfficialAccountNameLabelForUser(
            userId: userId,
            name: name,
            style: DefaultTextStyle.of(context).style.copyWith(
                  fontSize: 16,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                ),
          );
  if (!_officialSearchProfileRevisionBound) {
    _officialSearchProfileRevisionBound = true;
    PlatformOfficialAccountService.infoRevision.addListener(
      globalModel.notifyListeners,
    );
  }
  // Search can open before the conversation page has refreshed official
  // profiles. Warm both official accounts and notify the search UI when the
  // real IM avatars arrive, instead of leaving the generic placeholder.
  unawaited(PlatformOfficialAccountService.ensureSubscribed());
  globalModel.appRootNavigator = () => AppNavigator.key.currentState;
}

void installForwardPickPages() {
  setupServiceLocator();
  TUIChatGlobalModel.registerAppExtensions = registerAppUIKitExtensions;
  registerAppUIKitExtensions(serviceLocator<TUIChatGlobalModel>());
}

Future<V2TimConversation?> openForwardSelectFriendPage(BuildContext context) {
  TUIChatGlobalModel.ensureAppExtensionsRegistered();
  final useNestedDesktopRoute =
      DesktopModalLayout.isDesktop(context) || TUIKitWidePopup.isShow;
  return Navigator.of(context).push<V2TimConversation>(
    useNestedDesktopRoute
        ? MaterialPageRoute(
            builder: (context) => const ForwardSelectFriendPage(),
          )
        : NavigationRoutes.push(
            builder: (context) => const ForwardSelectFriendPage(),
          ),
  );
}

Future<V2TimConversation?> openForwardSelectGroupPage(BuildContext context) {
  TUIChatGlobalModel.ensureAppExtensionsRegistered();
  final useNestedDesktopRoute =
      DesktopModalLayout.isDesktop(context) || TUIKitWidePopup.isShow;
  return Navigator.of(context).push<V2TimConversation>(
    useNestedDesktopRoute
        ? MaterialPageRoute(
            builder: (context) => const ForwardSelectGroupPage(),
          )
        : NavigationRoutes.push(
            builder: (context) => const ForwardSelectGroupPage(),
          ),
  );
}

class ForwardSelectFriendPage extends StatefulWidget {
  final void Function(V2TimFriendInfo friend)? onTapItem;
  final String? title;

  const ForwardSelectFriendPage({
    super.key,
    this.onTapItem,
    this.title,
  });

  @override
  State<ForwardSelectFriendPage> createState() =>
      _ForwardSelectFriendPageState();
}

class _ForwardSelectFriendPageState extends State<ForwardSelectFriendPage> {
  Timer? _searchDebounce;
  String _searchKeyword = '';
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _searchKeyword = value.trim().toLowerCase());
    });
  }

  final FriendSearchCache _searchCache = FriendSearchCache();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCache.clear();
    _searchController.dispose();
    super.dispose();
  }

  String _friendName(V2TimFriendInfo item) {
    final remark = item.friendRemark?.trim() ?? '';
    if (remark.isNotEmpty) return remark;
    final nick = item.userProfile?.nickName?.trim() ?? '';
    if (nick.isNotEmpty) return nick;
    return item.userID;
  }

  bool _matchesSearch(V2TimFriendInfo item, String keyword) {
    if (keyword.isEmpty) {
      return true;
    }
    final name = _friendName(item);
    return _searchCache.matches(item.userID, name, keyword);
  }

  Future<V2TimConversation> _buildConversation(V2TimFriendInfo item) async {
    final conversationID = 'c2c_${item.userID}';
    final res = await TencentImSDKPlugin.v2TIMManager
        .getConversationManager()
        .getConversation(conversationID: conversationID);
    if (res.code == 0 && res.data != null) {
      return res.data!;
    }
    return V2TimConversation(
      conversationID: conversationID,
      userID: item.userID,
      type: 1,
      showName: item.friendRemark?.isNotEmpty == true
          ? item.friendRemark
          : ((item.userProfile?.nickName?.isNotEmpty == true)
              ? item.userProfile?.nickName
              : item.userID),
      faceUrl: item.userProfile?.faceUrl,
    );
  }

  Future<void> _handleTap(V2TimFriendInfo item) async {
    if (widget.onTapItem != null) {
      widget.onTapItem!(item);
      return;
    }
    final conversation = await _buildConversation(item);
    if (!mounted) return;
    Navigator.pop(context, conversation);
  }

  Widget _buildSearchBar(BuildContext context) {
    final builder = serviceLocator<TUIChatGlobalModel>().appSearchBarBuilder;
    if (builder != null) {
      return builder(
        context,
        _searchController,
        (_) => setState(() {}),
      );
    }
    return ContactStyleSearchBar(
      controller: _searchController,
      onChanged: _onSearchChanged,
      showCancel: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final i18n = AppI18n.of(context);
    final keyword = _searchKeyword;
    final title = widget.title ??
        i18n.t(
          zhHans: '选择朋友',
          zhHant: '選擇朋友',
          en: 'Select Friend',
          ja: '友達を選択',
          ko: '친구 선택',
        );

    return Scaffold(
      backgroundColor: theme.weakBackgroundColor ?? Colors.white,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: theme.appbarBgColor ?? theme.weakBackgroundColor,
        title: Text(
          title,
          style: TextStyle(
            color: theme.appbarTextColor ?? theme.darkTextColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: IconThemeData(
          color: theme.primaryColor ?? const Color(0xFF1E90FF),
        ),
        leading: AppBackButton(
          color: theme.primaryColor ?? const Color(0xFF1E90FF),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(context),
          Expanded(
            child: ContactListWithPresence(
              isShowOnlineStatus: true,
              onTapItem: _handleTap,
              filterKey: keyword,
              filterItem: (item) {
                if (PlatformOfficialAccountService
                    .shouldHideFromContactAndPickers(item.userID)) {
                  return false;
                }
                return _matchesSearch(item, keyword);
              },
              emptyBuilder: (_) => Center(
                child: Text(
                  keyword.isEmpty
                      ? i18n.t(
                          zhHans: '暂无联系人',
                          zhHant: '暫無聯絡人',
                          en: 'No contacts',
                          ja: '連絡先がありません',
                          ko: '연락처 없음',
                        )
                      : i18n.t(
                          zhHans: '未找到相关联系人',
                          zhHant: '未找到相關聯絡人',
                          en: 'No matching contacts',
                          ja: '該当する連絡先が見つかりません',
                          ko: '관련 연락처를 찾을 수 없습니다',
                        ),
                  style: TextStyle(
                    color: theme.weakTextColor ?? Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ForwardSelectGroupPage extends StatefulWidget {
  final void Function(V2TimGroupInfo groupInfo, V2TimConversation conversation)?
      onTapItem;
  final String? title;
  final bool Function(V2TimGroupInfo? groupInfo)? groupCollector;

  const ForwardSelectGroupPage({
    super.key,
    this.onTapItem,
    this.title,
    this.groupCollector,
  });

  @override
  State<ForwardSelectGroupPage> createState() => _ForwardSelectGroupPageState();
}

class _ForwardSelectGroupPageState extends State<ForwardSelectGroupPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSearchBar(BuildContext context) {
    final builder = serviceLocator<TUIChatGlobalModel>().appSearchBarBuilder;
    if (builder != null) {
      return builder(
        context,
        _searchController,
        (_) => setState(() {}),
      );
    }
    return ContactStyleSearchBar(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      showCancel: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final i18n = AppI18n.of(context);
    final title = widget.title ??
        i18n.t(
          zhHans: '选择群聊',
          zhHant: '選擇群聊',
          en: 'Select Group',
          ja: 'グループを選択',
          ko: '그룹 선택',
        );

    return Scaffold(
      backgroundColor: theme.weakBackgroundColor ?? Colors.white,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: theme.appbarBgColor ?? theme.weakBackgroundColor,
        title: Text(
          title,
          style: TextStyle(
            color: theme.appbarTextColor ?? theme.darkTextColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: IconThemeData(
          color: theme.primaryColor ?? const Color(0xFF1E90FF),
        ),
        leading: AppBackButton(
          color: theme.primaryColor ?? const Color(0xFF1E90FF),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(context),
          Expanded(
            child: TIMUIKitGroup(
              searchKeyword: _searchController.text,
              isShowIndexBar: true,
              groupCollector: widget.groupCollector,
              onTapItem: widget.onTapItem ??
                  (groupInfo, conversation) {
                    Navigator.pop(context, conversation);
                  },
              emptyBuilder: (context) => Center(
                child: Text(
                  _searchController.text.trim().isEmpty
                      ? i18n.t(
                          zhHans: '暂无群聊',
                          zhHant: '暫無群聊',
                          en: 'No groups',
                          ja: 'グループがありません',
                          ko: '그룹 없음',
                        )
                      : i18n.t(
                          zhHans: '未找到相关群聊',
                          zhHant: '未找到相關群聊',
                          en: 'No matching groups',
                          ja: '該当するグループが見つかりません',
                          ko: '관련 그룹을 찾을 수 없습니다',
                        ),
                  style: TextStyle(
                    color: theme.weakTextColor ?? Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
