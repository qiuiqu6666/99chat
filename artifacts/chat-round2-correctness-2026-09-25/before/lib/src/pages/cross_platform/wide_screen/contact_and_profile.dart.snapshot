import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/all_group_application_list.dart';
import 'package:tencent_cloud_chat_demo/src/contact.dart';
import 'package:tencent_cloud_chat_demo/src/friend_request_audit_page.dart';
import 'package:tencent_cloud_chat_demo/src/group_list.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/friend_request_record.dart';
import 'package:tencent_cloud_chat_demo/src/multi_platform_widget/search_entry/search_entry.dart';
import 'package:tencent_cloud_chat_demo/src/multi_platform_widget/search_entry/search_entry_wide.dart';
import 'package:tencent_cloud_chat_demo/src/newContact.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_contact_subpage_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_esc_back.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/empty_widget.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/search.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/user_profile.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

class ContactsAndProfile extends StatefulWidget {
  final void Function(V2TimConversation conversation, [MessageAnchor? anchor])
      onNavigateToChat;

  const ContactsAndProfile({Key? key, required this.onNavigateToChat})
      : super(key: key);

  @override
  State<ContactsAndProfile> createState() => _ContactsAndProfileState();
}

class _ContactsAndProfileState extends State<ContactsAndProfile> {
  final TIMUIKitConversationController _conversationController =
      TIMUIKitConversationController();

  bool isShowSearch = false;
  String? selectedItem;
  FriendRequestRecord? _selectedFriendRequest;

  @override
  void initState() {
    super.initState();
    DesktopEscBack.register(_onDesktopEscBack);
    DesktopContactSubpageHost.pageNotifier.addListener(_onContactSubpageChanged);
  }

  @override
  void dispose() {
    DesktopContactSubpageHost.pageNotifier
        .removeListener(_onContactSubpageChanged);
    DesktopEscBack.unregister(_onDesktopEscBack);
    super.dispose();
  }

  void _onContactSubpageChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      if (!DesktopContactSubpageHost.isOpen) {
        _selectedFriendRequest = null;
      }
    });
  }

  bool _onDesktopEscBack() {
    if (!mounted || !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    if (DesktopContactSubpageHost.isOpen) {
      DesktopContactSubpageHost.close();
      return true;
    }
    if (isShowSearch) {
      setState(() => isShowSearch = false);
      return true;
    }
    if (selectedItem != null && selectedItem!.isNotEmpty) {
      setState(() => selectedItem = null);
      return true;
    }
    return false;
  }

  Widget _savedProfilePane() {
    if (selectedItem != null &&
        selectedItem!.isNotEmpty &&
        !selectedItem!.startsWith('group_')) {
      return UserProfile(
        userID: selectedItem!,
        onClickSendMessage: (V2TimConversation conversation) {
          widget.onNavigateToChat(conversation);
        },
      );
    }
    return const EmptyWidget(
      title: '\u901a\u8baf\u5f55 & \u7fa4\u804a',
      description:
          '\u8bf7\u9009\u62e9\u8054\u7cfb\u4eba\u6216\u7fa4\u804a\uff0c\u4ee5\u67e5\u770b\u8be6\u60c5',
    );
  }

  Widget _buildRightPane({required bool showNewFriends}) {
    if (showNewFriends && _selectedFriendRequest != null) {
      return FriendRequestAuditPage(
        key: ValueKey(_selectedFriendRequest!.identityKey),
        record: _selectedFriendRequest!,
        embedded: true,
        onFinished: () {
          setState(() => _selectedFriendRequest = null);
          unawaited(FriendRequestNoticeService.instance.refreshPendingCount());
        },
      );
    }
    return _savedProfilePane();
  }

  Widget _buildDirectoryColumn(TUITheme theme) {
    if (isShowSearch) {
      return Search(
        onTapConversation: (conversation, anchor) {
          widget.onNavigateToChat(conversation, anchor);
          setState(() => isShowSearch = false);
        },
        isAutoFocus: true,
        onBack: () => setState(() => isShowSearch = false),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Container(
        color: theme.wideBackgroundColor,
        child: Column(
          children: [
            SearchEntry(
              conversationController: _conversationController,
              plusType: PlusType.add,
              directToChat: (conversation) =>
                  widget.onNavigateToChat(conversation),
              onClickSearch: () {
                if (kIsWeb || PlatformUtils().isWeb) {
                  ToastUtils.toast(AppI18n.of(context).t(
                    zhHans: '网页端暂不支持消息搜索',
                    zhHant: '網頁端暫不支援訊息搜尋',
                    en: 'Message search is not available on Web',
                    ja: 'Webではメッセージ検索に対応していません',
                    ko: '웹에서는 메시지 검색을 지원하지 않습니다',
                  ));
                  return;
                }
                setState(() => isShowSearch = true);
              },
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              child: TabBar(
                isScrollable: true,
                labelColor: theme.primaryColor,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                unselectedLabelColor:
                    theme.weakTextColor ?? hexToColor('62626b'),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.normal),
                indicatorSize: TabBarIndicatorSize.label,
                indicatorColor: theme.primaryColor ?? hexToColor('62626b'),
                tabs: const [
                  Padding(
                    padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Text('\u901a\u8baf\u5f55'),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Text('\u7fa4\u804a'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Contact(
                    onTapItem: (userID) {
                      setState(() => selectedItem = userID);
                    },
                  ),
                  GroupList(
                    onTapItem: (
                      V2TimGroupInfo groupInfo,
                      V2TimConversation conversation,
                    ) {
                      widget.onNavigateToChat(conversation);
                    },
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    return ValueListenableBuilder<DesktopContactSubpage?>(
      valueListenable: DesktopContactSubpageHost.pageNotifier,
      builder: (context, subpage, _) {
        if (subpage == DesktopContactSubpage.groupNotice) {
          return AllGroupApplicationListPage(
            contactsColumnEmbedded: true,
            onClose: DesktopContactSubpageHost.close,
            idleDetail: _savedProfilePane(),
            onOpenConversation: (conversation) {
              widget.onNavigateToChat(conversation);
            },
          );
        }

        final showNewFriends = subpage == DesktopContactSubpage.newFriends;
        return Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300, maxWidth: 300),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TickerMode(
                    enabled: !showNewFriends,
                    child: Offstage(
                      offstage: showNewFriends,
                      child: _buildDirectoryColumn(theme),
                    ),
                  ),
                  if (showNewFriends)
                    NewContact(
                      columnEmbedded: true,
                      onClose: DesktopContactSubpageHost.close,
                      onSelectRecord: (record) {
                        setState(() => _selectedFriendRequest = record);
                      },
                      onOpenConversation: (conversation) {
                        widget.onNavigateToChat(conversation);
                      },
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 1,
              child: Container(color: theme.weakDividerColor),
            ),
            Expanded(
              child: _buildRightPane(showNewFriends: showNewFriends),
            ),
          ],
        );
      },
    );
  }
}
