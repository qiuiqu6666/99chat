import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/contact_and_profile.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/me_and_tencent.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/app_update_service.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/left_bar.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_profile_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_group_notice_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_contact_subpage_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_archive_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_create_group_host.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_media_popout_host.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'conversation_and_chat.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/utils/launch_system_ui.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';

class HomePageWideScreen extends StatefulWidget {
  const HomePageWideScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => HomePageWideScreenState();
}

class HomePageWideScreenState extends State<HomePageWideScreen> {
  final V2TIMManager _sdkInstance = TIMUIKitCore.getSDKInstance();

  int homePageIndex = 0;
  V2TimConversation? currentC2CConversation;
  V2TimConversation? currentGroupConversation;
  MessageAnchor? currentC2CMessageAnchor;
  MessageAnchor? currentGroupMessageAnchor;

  @override
  initState() {
    super.initState();
    getLoginUserInfo();
    DesktopProfileHost.requestShowMessagesTab = _showMessagesTab;
    DesktopProfileHost.requestClosePeerPanels = _closeRightPanels;
    DesktopGroupNoticeHost.requestShowGroupTab = _showGroupTab;
    DesktopGroupNoticeHost.requestClosePeerPanels = _closeNoticePeers;
    DesktopArchiveHost.requestShowMessagesTab = _showMessagesTab;
    DesktopArchiveHost.requestShowGroupTab = _showGroupTab;
    DesktopArchiveHost.requestClosePeerPanels = _closeArchivePeers;
    DesktopCreateGroupHost.requestShowMessagesTab = _showMessagesTab;
    DesktopCreateGroupHost.requestShowGroupTab = _showGroupTab;
    DesktopCreateGroupHost.requestClosePeerPanels = _closeCreateGroupPeers;
    DesktopMediaPopoutHost.navigateToChat = _onMediaPopoutNavigate;
    ConversationRefreshBus.instance.revision
        .addListener(_onConversationRefreshBus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LaunchSystemUi.completeStartup(context);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          AppUpdateService.instance.check(context, manual: false);
        }
      });
    });
  }

  void _closeRightPanels() {
    DesktopGroupNoticeHost.close();
    DesktopArchiveHost.close();
    DesktopCreateGroupHost.close();
  }

  void _closeNoticePeers() {
    DesktopArchiveHost.close();
    DesktopCreateGroupHost.close();
  }

  void _closeArchivePeers() {
    DesktopGroupNoticeHost.close();
    DesktopCreateGroupHost.close();
  }

  void _closeCreateGroupPeers() {
    DesktopGroupNoticeHost.close();
    DesktopArchiveHost.close();
  }

  void _showMessagesTab() {
    if (!mounted || homePageIndex == 0) {
      return;
    }
    setState(() {
      homePageIndex = 0;
    });
  }

  void _showGroupTab() {
    if (!mounted || homePageIndex == 1) {
      return;
    }
    setState(() {
      homePageIndex = 1;
    });
  }

  @override
  void dispose() {
    if (DesktopProfileHost.requestShowMessagesTab == _showMessagesTab) {
      DesktopProfileHost.requestShowMessagesTab = null;
    }
    if (DesktopProfileHost.requestClosePeerPanels == _closeRightPanels) {
      DesktopProfileHost.requestClosePeerPanels = null;
    }
    if (DesktopGroupNoticeHost.requestShowGroupTab == _showGroupTab) {
      DesktopGroupNoticeHost.requestShowGroupTab = null;
    }
    if (DesktopGroupNoticeHost.requestClosePeerPanels == _closeNoticePeers) {
      DesktopGroupNoticeHost.requestClosePeerPanels = null;
    }
    if (DesktopArchiveHost.requestShowMessagesTab == _showMessagesTab) {
      DesktopArchiveHost.requestShowMessagesTab = null;
    }
    if (DesktopArchiveHost.requestShowGroupTab == _showGroupTab) {
      DesktopArchiveHost.requestShowGroupTab = null;
    }
    if (DesktopArchiveHost.requestClosePeerPanels == _closeArchivePeers) {
      DesktopArchiveHost.requestClosePeerPanels = null;
    }
    if (DesktopCreateGroupHost.requestShowMessagesTab == _showMessagesTab) {
      DesktopCreateGroupHost.requestShowMessagesTab = null;
    }
    if (DesktopCreateGroupHost.requestShowGroupTab == _showGroupTab) {
      DesktopCreateGroupHost.requestShowGroupTab = null;
    }
    if (DesktopCreateGroupHost.requestClosePeerPanels ==
        _closeCreateGroupPeers) {
      DesktopCreateGroupHost.requestClosePeerPanels = null;
    }
    if (DesktopMediaPopoutHost.navigateToChat == _onMediaPopoutNavigate) {
      DesktopMediaPopoutHost.navigateToChat = null;
    }
    ConversationRefreshBus.instance.revision
        .removeListener(_onConversationRefreshBus);
    super.dispose();
  }

  void _onConversationRefreshBus() {
    final events = ConversationRefreshBus.instance.lastEvents;
    final removedEvents = events
        .where((event) => event.reason == 'group_self_removed')
        .toList(growable: false);
    if (removedEvents.isEmpty) {
      return;
    }
    final currentId = currentGroupConversation?.conversationID.trim() ?? '';
    final matchesCurrent = removedEvents.any((event) {
      final targetId = event.conversationId?.trim() ?? '';
      return targetId.isEmpty ||
          currentId.isEmpty ||
          MessageConversationId.sameConversation(targetId, currentId);
    });
    if (!matchesCurrent) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      currentGroupConversation = null;
      currentGroupMessageAnchor = null;
    });
  }

  void _onMediaPopoutNavigate(
    V2TimConversation conversation,
    MessageAnchor? anchor,
  ) {
    _navigateToChat(conversation, anchor);
  }

  _navigateToChat(V2TimConversation conversation, [MessageAnchor? anchor]) {
    final isGroup = conversation.type == 2 ||
        ((conversation.groupID ?? '').trim().isNotEmpty) ||
        ((conversation.conversationID ?? '').toUpperCase().startsWith('GROUP'));
    DesktopProfileHost.close();
    DesktopGroupNoticeHost.close();
    DesktopArchiveHost.close();
    DesktopCreateGroupHost.close();
    setState(() {
      homePageIndex = isGroup ? 1 : 0;
      if (isGroup) {
        currentGroupConversation = conversation;
        currentGroupMessageAnchor = anchor;
      } else {
        currentC2CConversation = conversation;
        currentC2CMessageAnchor = anchor;
      }
    });
  }

  Future<void> getLoginUserInfo() async {
    if (PlatformUtils().isWeb) {
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      return;
    }
    final res = await _sdkInstance.getLoginUser();
    if (res.code == 0 && SessionIdentityService.instance.isCurrent(identity)) {
      final result = await _sdkInstance.getUsersInfo(userIDList: [res.data!]);

      if (result.code == 0 &&
          SessionIdentityService.instance.isCurrent(identity)) {
        Provider.of<LoginUserInfo>(context, listen: false)
            .setLoginUserInfo(result.data![0]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Provider.of<DefaultThemeData>(context);
    final isDark = themeData.currentThemeType == ThemeType.dark;
    final railColor = AppTokens.desktopNavRail(isDark);
    final railBorder = AppTokens.desktopNavRailBorder(isDark);
    final titleBarColor = AppTokens.desktopTitleBar(isDark);
    final titleBarBorder = AppTokens.desktopTitleBarBorder(isDark);
    final titleBarIcon = AppTokens.desktopTitleBarIcon(isDark);
    final isWindows = PlatformUtils().isWindows;

    void onNavChange(int index) {
      if (index == 2) {
        DesktopContactSubpageHost.close();
      }
      if (index != 0 && index != 1) {
        DesktopProfileHost.close();
        DesktopGroupNoticeHost.close();
        DesktopArchiveHost.close();
        DesktopCreateGroupHost.close();
      } else if (index == 0) {
        DesktopGroupNoticeHost.close();
        if (DesktopArchiveHost.scope == DesktopArchiveScope.group) {
          DesktopArchiveHost.close();
        }
        if (DesktopCreateGroupHost.args?.scope ==
            DesktopCreateGroupScope.group) {
          DesktopCreateGroupHost.close();
        }
      } else if (index == 1) {
        DesktopProfileHost.close();
        if (DesktopArchiveHost.scope == DesktopArchiveScope.c2c) {
          DesktopArchiveHost.close();
        }
        if (DesktopCreateGroupHost.args?.scope ==
            DesktopCreateGroupScope.c2c) {
          DesktopCreateGroupHost.close();
        }
      }
      setState(() {
        homePageIndex = index;
      });
    }

    Widget body = Column(
      children: [
        if (isWindows)
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: titleBarColor,
              border: Border(
                bottom: BorderSide(
                  color: titleBarBorder,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: MoveWindow()),
                MinimizeWindowButton(
                  colors: WindowButtonColors(
                    iconNormal: titleBarIcon,
                    iconMouseOver: isDark
                        ? const Color(0xFFFFFFFF)
                        : AppTokens.ink900,
                    mouseOver: titleBarBorder,
                  ),
                ),
                MaximizeWindowButton(
                  colors: WindowButtonColors(
                    iconNormal: titleBarIcon,
                    iconMouseOver: isDark
                        ? const Color(0xFFFFFFFF)
                        : AppTokens.ink900,
                    mouseOver: titleBarBorder,
                  ),
                ),
                CloseWindowButton(
                  colors: WindowButtonColors(
                    iconNormal: titleBarIcon,
                    iconMouseOver: const Color(0xFFFFFFFF),
                    mouseOver: const Color(0xFFC42B1C),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Row(
            children: [
              Container(
                width: 64,
                decoration: BoxDecoration(
                  color: railColor,
                  border: Border(
                    right: BorderSide(
                      color: railBorder,
                      width: 1,
                    ),
                  ),
                ),
                child: LeftBar(
                  index: homePageIndex,
                  onChange: onNavChange,
                  topInset: isWindows ? 0 : 40,
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: homePageIndex,
                  children: [
                    ConversationAndChat(
                      conversation: currentC2CConversation,
                      searchJumpAnchor: currentC2CMessageAnchor,
                      listScope: ConversationListScope.c2c,
                      showDesktopUserProfile: true,
                    ),
                    ConversationAndChat(
                      conversation: currentGroupConversation,
                      searchJumpAnchor: currentGroupMessageAnchor,
                      listScope: ConversationListScope.group,
                      showDesktopUserProfile: true,
                    ),
                    ContactsAndProfile(onNavigateToChat: _navigateToChat),
                    const MeAndTencent(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final desktopFont = AppTokens.desktopUiFontFamily;
    if (desktopFont == null) {
      return body;
    }
    return Theme(
      data: AppTokens.applyDesktopTypography(Theme.of(context)),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontFamily: desktopFont,
          fontFamilyFallback: AppTokens.desktopUiFontFamilyFallback,
        ),
        child: body,
      ),
    );
  }
}
