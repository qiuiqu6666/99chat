import 'dart:async' show unawaited;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/all_group_application_list.dart';
import 'package:tencent_cloud_chat_demo/src/chat.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/c2c_chat_settings_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_chat_settings_side_card.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_archive_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_esc_back.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_create_group_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_group_notice_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_profile_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_column_scope.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_column_window.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_confirm_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_settings_shell.dart';
import 'package:tencent_cloud_chat_demo/src/pages/add_friend_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/qr_code_page.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_invite_member_page_meta.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_add_source.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/profile_page_nav.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_add_group_member.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_delete_group_member.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_group_member_list.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_demo/src/create_group.dart';
import 'package:tencent_cloud_chat_demo/src/user_profile.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_deleted_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_profile_pin_bar.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/empty_widget.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/search.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/custom_last_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/group_profile_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/tim_uikit_wide_modal_operation_key.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitProfile/profile_widget.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';

class ConversationAndChat extends StatefulWidget {
  final V2TimConversation? conversation;
  final MessageAnchor? searchJumpAnchor;
  final ConversationListScope listScope;
  /// 是否承接桌面壳内的用户资料（消息 / 群聊 Tab）。
  final bool showDesktopUserProfile;

  const ConversationAndChat({
    Key? key,
    this.conversation,
    this.searchJumpAnchor,
    this.listScope = ConversationListScope.c2c,
    this.showDesktopUserProfile = false,
  }) : super(key: key);

  @override
  State<ConversationAndChat> createState() => _ConversationAndChatState();
}

class _ConversationAndChatState extends State<ConversationAndChat> {
  final TIMUIKitConversationController _conversationController = TIMUIKitConversationController();
  final TUIConversationViewModel _conversationViewModel =
      serviceLocator<TUIConversationViewModel>();

  V2TimConversation? currentConversation;
  MessageAnchor? pendingMessageAnchor;
  V2TimMessage? pendingTargetMessage;
  String? _cachedCurrentConversationFaceUrl;
  bool isShowSearch = false;
  /// 右侧「设置」边栏（群资料 / 单聊资料，形态与群聊一致）
  bool isShowSideProfile = false;
  /// 开列时锁死左栏+聊天的像素宽，关列后清掉，避免中间区域被挤。
  double? _lockedMainWidth;
  /// 最近一次未开栏时的宿主宽，开栏时立刻用，不再多等一帧采集。
  double? _lastHostWidth;
  /// 取消过期的扩/缩窗，避免关后再开时窗口先缩后扩。
  int _sideGeomEpoch = 0;

  @override
  void initState() {
    super.initState();
    DesktopEscBack.register(_onDesktopEscBack);
    currentConversation = widget.conversation;
    pendingMessageAnchor = widget.searchJumpAnchor;
    pendingTargetMessage = null;
    _cachedCurrentConversationFaceUrl = currentConversation?.faceUrl;
    _conversationViewModel.addListener(_onConversationViewModelChanged);
    ConversationDeletedBus.instance.revision
        .addListener(_onConversationsDeletedBus);
    DesktopProfileHost.userIdNotifier.addListener(_onDesktopProfileHostChanged);
    DesktopArchiveHost.scopeNotifier.addListener(_onDesktopArchiveHostChanged);
  }

  @override
  void dispose() {
    DesktopEscBack.unregister(_onDesktopEscBack);
    DesktopArchiveHost.scopeNotifier.removeListener(_onDesktopArchiveHostChanged);
    DesktopProfileHost.userIdNotifier.removeListener(_onDesktopProfileHostChanged);
    ConversationDeletedBus.instance.revision
        .removeListener(_onConversationsDeletedBus);
    _conversationViewModel.removeListener(_onConversationViewModelChanged);
    super.dispose();
  }

  bool _onDesktopEscBack() {
    if (!mounted || !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    if (isShowSearch) {
      setState(() {
        isShowSearch = false;
      });
      return true;
    }
    if (isShowSideProfile) {
      _closeSideProfile();
      return true;
    }
    return false;
  }

  /// 侧栏打开资料时，左侧若卡在「Web 不支持搜索」页，先退回会话列表。
  void _onDesktopProfileHostChanged() {
    if (!mounted || !widget.showDesktopUserProfile) {
      return;
    }
    if (!DesktopProfileHost.isOpen || !isShowSearch) {
      return;
    }
    setState(() {
      isShowSearch = false;
    });
  }

  void _onDesktopArchiveHostChanged() {
    if (!mounted || !widget.showDesktopUserProfile) {
      return;
    }
    if (DesktopArchiveHost.isOpen && isShowSearch) {
      setState(() {
        isShowSearch = false;
      });
    }
  }

  DesktopArchiveScope get _expectArchiveScope =>
      widget.listScope == ConversationListScope.group
          ? DesktopArchiveScope.group
          : DesktopArchiveScope.c2c;

  void _openConversationFromArchive(V2TimConversation conversation) {
    DesktopProfileHost.close();
    DesktopGroupNoticeHost.close();
    DesktopCreateGroupHost.close();
    setState(() {
      currentConversation = conversation;
      pendingMessageAnchor = null;
      pendingTargetMessage = null;
      isShowSearch = false;
    });
  }

  Widget _buildLeftPane() {
    return ValueListenableBuilder<DesktopArchiveScope?>(
      valueListenable: DesktopArchiveHost.scopeNotifier,
      builder: (context, archiveScope, _) {
        final showArchive = widget.showDesktopUserProfile &&
            archiveScope == _expectArchiveScope;
        if (isShowSearch) {
          return Search(
            onTapConversation: (conversation, anchor) {
              DesktopProfileHost.close();
              DesktopGroupNoticeHost.close();
              DesktopArchiveHost.close();
              DesktopCreateGroupHost.close();
              setState(() {
                currentConversation = conversation;
                pendingMessageAnchor = anchor;
                pendingTargetMessage = null;
                isShowSearch = false;
              });
            },
            onTapConversationWithMessage:
                (conversation, anchor, targetMessage) {
              DesktopProfileHost.close();
              DesktopGroupNoticeHost.close();
              DesktopArchiveHost.close();
              DesktopCreateGroupHost.close();
              setState(() {
                currentConversation = conversation;
                pendingMessageAnchor = anchor;
                pendingTargetMessage = null;
                isShowSearch = false;
              });
            },
            isAutoFocus: true,
            onBack: () {
              setState(() {
                isShowSearch = false;
              });
            },
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            TickerMode(
              enabled: !showArchive,
              child: Offstage(
                offstage: showArchive,
                child: Conversation(
                  selectedConversation: currentConversation,
                  listScope: widget.listScope,
                  onConversationChanged: (conversation) {
                    if (conversation == null) {
                      _clearOpenConversationWindow();
                      return;
                    }
                    DesktopProfileHost.close();
                    DesktopGroupNoticeHost.close();
                    DesktopArchiveHost.close();
                    DesktopCreateGroupHost.close();
                    setState(() {
                      currentConversation = conversation;
                      pendingMessageAnchor = null;
                    });
                  },
                  onClickSearch: _openMessageSearch,
                  conversationController: _conversationController,
                ),
              ),
            ),
            if (showArchive)
              ArchivedConversationPage(
                key: ValueKey('desktop_archive_$_expectArchiveScope'),
                controller: _conversationController,
                listScope: widget.listScope,
                shellEmbedded: true,
                onClose: DesktopArchiveHost.close,
                onTapConversation: (conversation) {
                  if (conversation == null) {
                    return;
                  }
                  _openConversationFromArchive(conversation);
                },
                lastMessageAbstractBuilder: conversationListLastMessageAbstract,
              ),
          ],
        );
      },
    );
  }

  void _openMessageSearch() {
    // Web SDK 无全局消息搜索：勿替换列表栏，否则会出现无返回的 NotSupport 页。
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
    setState(() {
      isShowSearch = true;
    });
  }

  void _onConversationsDeletedBus() {
    if (!mounted || currentConversation == null) {
      return;
    }
    final currentId = currentConversation!.conversationID.trim();
    if (currentId.isEmpty) {
      return;
    }
    final hit = ConversationDeletedBus.instance.lastDeletedIds.any(
      (id) => MessageConversationId.sameConversation(id, currentId),
    );
    if (!hit) {
      return;
    }
    _clearOpenConversationWindow();
  }

  void _clearOpenConversationWindow() {
    if (!mounted) {
      return;
    }
    setState(() {
      currentConversation = null;
      _hideSideProfileColumn();
      pendingMessageAnchor = null;
      pendingTargetMessage = null;
      _cachedCurrentConversationFaceUrl = null;
    });
  }

  void _onConversationViewModelChanged() {
    if (!mounted || currentConversation == null) return;
    final conversationID = currentConversation!.conversationID;
    if (conversationID != null && conversationID.isNotEmpty) {
      for (final conv in _conversationViewModel.conversationList) {
        if (conv?.conversationID == conversationID) {
          final latestUrl = conv?.faceUrl ?? '';
          if (latestUrl.isNotEmpty &&
              latestUrl != (currentConversation!.faceUrl ?? '')) {
            currentConversation!.faceUrl = latestUrl;
          }
          break;
        }
      }
    }
    final faceUrl = currentConversation!.faceUrl ?? '';
    if (faceUrl == (_cachedCurrentConversationFaceUrl ?? '')) {
      return;
    }
    _cachedCurrentConversationFaceUrl = faceUrl;
    setState(() {});
  }

  @override
  void didUpdateWidget(ConversationAndChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.conversation;
    final oldIncoming = oldWidget.conversation;
    final incomingId = incoming?.conversationID?.trim() ?? '';
    final oldIncomingId = oldIncoming?.conversationID?.trim() ?? '';
    final conversationPropChanged = incomingId != oldIncomingId;
    final jumpChanged = widget.searchJumpAnchor?.stableKey !=
        oldWidget.searchJumpAnchor?.stableKey;
    if (!conversationPropChanged && !jumpChanged) {
      return;
    }
    setState(() {
      if (conversationPropChanged) {
        currentConversation = incoming;
        _cachedCurrentConversationFaceUrl = incoming?.faceUrl;
      }
      pendingMessageAnchor = widget.searchJumpAnchor;
      pendingTargetMessage = null;
    });
  }

  String _messageJumpKey(MessageAnchor? anchor) => anchor?.stableKey ?? '';

  void _syncSideProfilePaneOpen(bool open) {
    GroupNoticeRefreshBus.instance.setSideProfilePanelOpen(open);
  }

  void _hideSideProfileColumn() {
    final wasShowing = isShowSideProfile;
    isShowSideProfile = false;
    _syncSideProfilePaneOpen(false);
    if (!wasShowing) {
      return;
    }
    final epoch = ++_sideGeomEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _sideGeomEpoch) {
        return;
      }
      DesktopSideColumnWindow.releaseColumn();
    });
  }

  void _openSideProfile() {
    _sideGeomEpoch++;
    final hostWidth = _lastHostWidth ?? context.size?.width;
    setState(() {
      isShowSideProfile = true;
      _lockedMainWidth =
          (hostWidth != null && hostWidth > 0) ? hostWidth : null;
    });
    _syncSideProfilePaneOpen(true);
    final epoch = _sideGeomEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _sideGeomEpoch || !isShowSideProfile) {
        return;
      }
      if (!DesktopSideColumnWindow.isHeld) {
        DesktopSideColumnWindow.tryGrowForColumn(_sideProfileWidth);
      }
      if (!mounted || epoch != _sideGeomEpoch) {
        return;
      }
      if (!DesktopSideColumnWindow.hasExpanded) {
        setState(() {
          _lockedMainWidth = null;
        });
        return;
      }
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _sideGeomEpoch && isShowSideProfile) {
          setState(() {});
        }
      });
    });
  }

  /// 聊天顶栏「更多」：已展开则按关栏路径收掉右栏并缩窗，禁止再走一遍开栏把中间拉开。
  void _toggleSideProfile() {
    if (isShowSideProfile) {
      _closeSideProfile();
      return;
    }
    _openSideProfile();
  }

  void _closeSideProfile() {
    if (!mounted) {
      return;
    }
    setState(() {
      _hideSideProfileColumn();
    });
    final groupId = currentConversation?.groupID?.trim() ?? '';
    if (groupId.isNotEmpty) {
      GroupNoticeRefreshBus.instance.notifyRefresh(groupId);
    }
  }

  /// 群成员点击：仍用轻量浮层名片；会话「设置」走右侧边栏。
  void onClickUserName(Offset? offset, String user) {
    final conversation = currentConversation != null &&
            currentConversation!.userID == user
        ? currentConversation!
        : ConversationPinService.c2cConversationSnapshot(userID: user);
    TUIKitWidePopup.showPopupWindow(
        operationKey: TUIKitWideModalOperationKey.showUserProfileFromChat,
        context: context,
        isDarkBackground: false,
        width: 350,
        offset: offset,
        height: 460,
        child: (closeFunc) => Container(
              padding: const EdgeInsets.only(top: 20, left: 10, right: 10),
              child: TIMUIKitProfile(
                smallCardMode: true,
                profileWidgetBuilder: ProfileWidgetBuilder(
                  pinConversationBar: (isPinned, onChange) {
                    return ConversationProfilePinBar(
                      conversation: conversation,
                      source: 'wide_chat_profile_popup',
                      smallCardMode: true,
                    );
                  },
                ),
                profileWidgetsOrder: const [
                  ProfileWidgetEnum.userInfoCard,
                  ProfileWidgetEnum.operationDivider,
                  ProfileWidgetEnum.remarkBar,
                  ProfileWidgetEnum.genderBar,
                  ProfileWidgetEnum.birthdayBar,
                  ProfileWidgetEnum.operationDivider,
                  ProfileWidgetEnum.addToBlockListBar,
                  ProfileWidgetEnum.pinConversationBar,
                  ProfileWidgetEnum.messageMute,
                ],
                userID: user,
              ),
            ));
  }

  /// 对齐 Telegram Desktop：左右列表固定像素宽，中间聊天吃剩余。
  static const double _leftListMin = 300;
  static const double _leftListMax = 300;
  static const double _sideProfileWidth = 300;

  Future<void> _openSideColumnUser(String userId) async {
    final id = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty) {
      return;
    }
    final ctx = context;
    final i18n = AppI18n.of(ctx);
    if (ProfilePageNav.isFriendInContactList(id) ||
        ProfilePageNav.isSelfUser(id)) {
      await DesktopSideColumnScope.push<void>(
        ctx,
        title: i18n.t(
          zhHans: '详细资料',
          zhHant: '詳細資料',
          en: 'Profile',
          ja: '詳細',
          ko: '상세 정보',
        ),
        page: UserProfile(userID: id),
      );
      return;
    }
    await DesktopSideColumnScope.push<void>(
      ctx,
      title: i18n.t(
        zhHans: '添加好友',
        zhHant: '添加好友',
        en: 'Add Friend',
        ja: '友達を追加',
        ko: '친구 추가',
      ),
      page: AddFriendPage(
        userID: id,
        nickname: id,
        embedded: true,
      ),
    );
  }

  void _pushGroupMemberList(
    BuildContext context,
    TUIGroupProfileModel model,
    List<V2TimGroupMemberFullInfo?> memberList,
  ) {
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    final localSetting = Provider.of<LocalSetting>(context, listen: false);
    final friendship = serviceLocator<TUIFriendShipViewModel>();
    final i18n = AppI18n.of(context);
    final count = memberList.whereType<V2TimGroupMemberFullInfo>().length;
    DesktopSideColumnScope.push<void>(
      context,
      title: i18n.format(
        zhHans: '群成员({option1}人)',
        zhHant: '群成員({option1}人)',
        en: 'Members ({option1})',
        ja: 'メンバー({option1})',
        ko: '멤버({option1})',
        vars: {'option1': '$count'},
      ),
      page: GroupProfileMemberListPage(
        model: model,
        memberList: memberList,
        presenceListenable: presence,
        isShowOnlineStatus: localSetting.isShowOnlineStatus,
        presenceLabelBuilder: (userId, imOnline) => presence.onlineLabelFor(
          userId: userId,
          imOnline: imOnline,
          isMutualFriend: friendCanMessage(friendship, userId),
        ),
        presenceLoadingChecker: (userId, imOnline) =>
            presence.isLastSeenLoading(userId: userId, imOnline: imOnline),
        presenceOnlineResolver: (userId, imOnline) =>
            presence.shouldShowPresence(
              userId,
              isMutualFriend: friendCanMessage(friendship, userId),
            ) &&
            presence.resolveOnline(userId: userId, imOnline: imOnline),
        onMemberListLoaded: (userIds) {
          presence.ensure(userIds, includeVisibility: false);
        },
      ),
    );
  }

  Future<void> _pushAddGroupMember(
    BuildContext context,
    TUIGroupProfileModel model,
  ) async {
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    final friendship = serviceLocator<TUIFriendShipViewModel>();
    final i18n = AppI18n.of(context);
    final pageKey = addGroupMemberKey;
    await DesktopSideColumnScope.push<void>(
      context,
      title: i18n.t(
        zhHans: '添加成员',
        zhHant: '添加成員',
        en: 'Add Members',
        ja: 'メンバーを追加',
        ko: '멤버 추가',
      ),
      page: Column(
        children: [
          Expanded(
            child: AddGroupMemberPage(
              key: pageKey,
              model: model,
              presenceListenable: presence,
              presenceLabelBuilder: (userId, imOnline) =>
                  presence.onlineLabelFor(
                userId: userId,
                imOnline: imOnline,
                isMutualFriend: friendCanMessage(friendship, userId),
              ),
              presenceLoadingChecker: (userId, imOnline) =>
                  presence.isLastSeenLoading(
                userId: userId,
                imOnline: imOnline,
              ),
              onContactListLoaded: (userIds) {
                presence.ensure(userIds);
              },
              inviteNeedsApprovalLoader: () =>
                  GroupInviteMemberPageMeta.inviteNeedsApproval(model.groupID),
              existingMemberUserIdsLoader: (candidateUserIds) =>
                  GroupInviteMemberPageMeta.existingMemberUserIds(
                model.groupID,
                candidateUserIds: candidateUserIds,
              ),
              pendingReviewUserIdsLoader: () =>
                  GroupInviteMemberPageMeta.pendingReviewUserIds(
                model.groupID,
                memberUserIds: model.groupMemberList
                    .map((item) => item?.userID ?? '')
                    .where((id) => id.trim().isNotEmpty)
                    .toSet(),
              ),
            ),
          ),
          _sideColumnDoneBar(
            context,
            onPressed: () {
              pageKey.currentState?.submitAdd();
            },
          ),
        ],
      ),
    );
    if (context.mounted) {
      await model.loadGroupInfo(model.groupID);
    }
  }

  Future<void> _pushDeleteGroupMember(
    BuildContext context,
    TUIGroupProfileModel model,
  ) async {
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    final friendship = serviceLocator<TUIFriendShipViewModel>();
    final i18n = AppI18n.of(context);
    final deleteKey = GlobalKey<DeleteGroupMemberPageState>();
    await DesktopSideColumnScope.push<void>(
      context,
      title: i18n.t(
        zhHans: '删除群成员',
        zhHant: '刪除群成員',
        en: 'Remove Members',
        ja: 'メンバーを削除',
        ko: '멤버 삭제',
      ),
      page: Column(
        children: [
          Expanded(
            child: DeleteGroupMemberPage(
              key: deleteKey,
              model: model,
              presenceListenable: presence,
              presenceLabelBuilder: (userId, imOnline) =>
                  presence.onlineLabelFor(
                userId: userId,
                imOnline: imOnline,
                isMutualFriend: friendCanMessage(friendship, userId),
              ),
              presenceLoadingChecker: (userId, imOnline) =>
                  presence.isLastSeenLoading(
                userId: userId,
                imOnline: imOnline,
              ),
              onMemberListLoaded: (userIds) {
                presence.ensure(userIds, includeVisibility: false);
              },
            ),
          ),
          _sideColumnDoneBar(
            context,
            onPressed: () {
              unawaited(deleteKey.currentState?.submitDelete() ?? Future.value());
            },
          ),
        ],
      ),
    );
    if (context.mounted) {
      await model.loadGroupInfo(model.groupID);
    }
  }

  Widget _sideColumnDoneBar(BuildContext context, {required VoidCallback onPressed}) {
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final i18n = AppI18n.of(context);
    return Material(
      color: theme.wideBackgroundColor ?? Colors.white,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.weakDividerColor ?? const Color(0xFFE8EAED),
              ),
            ),
          ),
          child: Text(
            i18n.t(
              zhHans: '完成',
              zhHant: '完成',
              en: 'Done',
              ja: '完了',
              ko: '완료',
            ),
            style: TextStyle(
              color: theme.primaryColor ?? const Color(0xFF1E90FF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSideButtonArea(
    BuildContext context,
    TUIGroupProfileModel model,
  ) {
    final i18n = AppI18n.of(context);
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final isOwner = model.backendSelfRole ==
        GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER;
    final groupType = model.groupInfo?.groupType ?? '';
    final caution = theme.cautionColor ?? const Color(0xFFE53935);

    Future<void> confirmThen({
      required String title,
      required String message,
      required String confirmText,
      required Future<void> Function() action,
    }) async {
      final ok = await DesktopSideColumnScope.push<bool>(
        context,
        title: title,
        page: DesktopSideConfirmPage(
          title: title,
          message: message,
          confirmText: confirmText,
        ),
      );
      if (ok == true) {
        await action();
      }
    }

    Widget row(String label, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Text(label, style: TextStyle(color: caution, fontSize: 16)),
        ),
      );
    }

    final showClear = true;
    final showQuit = !isOwner ||
        (!SelfHostedGroupBridge.governanceEnabled &&
            groupType == GroupType.Work);
    final showDismiss = isOwner &&
        (SelfHostedGroupBridge.governanceEnabled ||
            groupType != GroupType.Work);

    return Column(
      children: [
        if (showClear)
          row(
            i18n.t(
              zhHans: '清空聊天记录',
              zhHant: '清空聊天記錄',
              en: 'Clear Chat History',
              ja: 'チャット履歴を削除',
              ko: '채팅 기록 삭제',
            ),
            () {
              confirmThen(
                title: i18n.t(
                  zhHans: '清空聊天记录',
                  zhHant: '清空聊天記錄',
                  en: 'Clear Chat History',
                  ja: 'チャット履歴を削除',
                  ko: '채팅 기록 삭제',
                ),
                message: i18n.t(
                  zhHans: '清空后无法恢复，确定清空该群的聊天记录吗？',
                  zhHant: '清空後無法恢復，確定清空該群的聊天記錄嗎？',
                  en: 'This cannot be undone. Clear this group chat history?',
                  ja: '削除後は元に戻せません。このグループの履歴を削除しますか？',
                  ko: '삭제 후 복구할 수 없습니다. 이 그룹 기록을 삭제할까요?',
                ),
                confirmText: i18n.t(
                  zhHans: '清空',
                  zhHant: '清空',
                  en: 'Clear',
                  ja: '削除',
                  ko: '삭제',
                ),
                action: () async {
                  final groupID = model.groupID;
                  ArchiveHistoryProvider.markHistoryClearPending(groupID);
                  await TIMUIKitCore.getSDKInstance()
                      .getMessageManager()
                      .clearGroupHistoryMessage(groupID: groupID);
                  await ArchiveHistoryProvider.completeHistoryClear(
                    isGroup: true,
                    conversationID: groupID,
                  );
                },
              );
            },
          ),
        if (showQuit)
          row(
            i18n.t(
              zhHans: '退出群组',
              zhHant: '退出群組',
              en: 'Leave Group',
              ja: 'グループを退出',
              ko: '그룹 나가기',
            ),
            () {
              confirmThen(
                title: i18n.t(
                  zhHans: '退出群组',
                  zhHant: '退出群組',
                  en: 'Leave Group',
                  ja: 'グループを退出',
                  ko: '그룹 나가기',
                ),
                message: i18n.t(
                  zhHans: '确定退出该群吗？',
                  zhHant: '確定退出該群嗎？',
                  en: 'Leave this group?',
                  ja: 'このグループを退出しますか？',
                  ko: '이 그룹에서 나갈까요?',
                ),
                confirmText: i18n.t(
                  zhHans: '退出',
                  zhHant: '退出',
                  en: 'Leave',
                  ja: '退出',
                  ko: '나가기',
                ),
                action: () async {
                  final groupID = model.groupID;
                  if (SelfHostedGroupBridge.governanceEnabled) {
                    await SelfHostedGroupBridge.leaveGroup(groupID);
                  } else {
                    await TIMUIKitCore.getSDKInstance()
                        .quitGroup(groupID: groupID);
                  }
                  await model.lifeCycle?.didLeaveGroup?.call();
                },
              );
            },
          ),
        if (showDismiss)
          row(
            i18n.t(
              zhHans: '解散群组',
              zhHant: '解散群組',
              en: 'Disband Group',
              ja: 'グループを解散',
              ko: '그룹 해산',
            ),
            () {
              confirmThen(
                title: i18n.t(
                  zhHans: '解散群组',
                  zhHant: '解散群組',
                  en: 'Disband Group',
                  ja: 'グループを解散',
                  ko: '그룹 해산',
                ),
                message: i18n.t(
                  zhHans: '确定解散该群吗？此操作无法撤销。',
                  zhHant: '確定解散該群嗎？此操作無法撤銷。',
                  en: 'Disband this group? This cannot be undone.',
                  ja: 'このグループを解散しますか？元に戻せません。',
                  ko: '이 그룹을 해산할까요? 되돌릴 수 없습니다.',
                ),
                confirmText: i18n.t(
                  zhHans: '解散',
                  zhHant: '解散',
                  en: 'Disband',
                  ja: '解散',
                  ko: '해산',
                ),
                action: () async {
                  final groupID = model.groupID;
                  if (SelfHostedGroupBridge.governanceEnabled) {
                    await SelfHostedGroupBridge.dismissGroup(groupID);
                  } else {
                    await TIMUIKitCore.getSDKInstance()
                        .dismissGroup(groupID: groupID);
                  }
                  await model.lifeCycle?.didLeaveGroup?.call();
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildSideProfileBody() {
    final conversation = currentConversation!;
    final groupId = TencentUtils.checkString(conversation.groupID);
    if (groupId != null) {
      return TIMUIKitGroupProfile(
        groupID: groupId,
        scrollable: false,
        builder: (context, groupInfo, memberList) {
          return GroupChatSettingsSideCard(
            conversation: conversation,
            groupInfo: groupInfo,
            onClose: _closeSideProfile,
            onOpenMembers: (model, members) {
              _pushGroupMemberList(context, model, members);
            },
            onAddMember: (model) => _pushAddGroupMember(context, model),
            onOpenUser: _openSideColumnUser,
            onJumpConversation: (next, anchor) {
              if (!mounted) {
                return;
              }
              setState(() {
                currentConversation = next;
                pendingMessageAnchor = anchor;
                pendingTargetMessage = null;
              });
            },
          );
        },
        lifeCycle: GroupProfileLifeCycle(
          didLeaveGroup: () async {
            if (!mounted) {
              return;
            }
            setState(() {
              _hideSideProfileColumn();
              currentConversation = null;
            });
          },
        ),
        onClickUser: (memberInfo, tapDetails) {
          _openSideColumnUser(memberInfo.userID);
        },
      );
    }

    final userId = conversation.userID?.trim() ?? '';
    if (userId.isEmpty) {
      return const SizedBox.shrink();
    }
    return C2cChatSettingsPage(
      key: ValueKey('c2c_side_${conversation.conversationID}'),
      conversation: conversation,
      embeddedInSidePanel: true,
      onClose: _closeSideProfile,
      onJumpConversation: (next, anchor) {
        if (!mounted) {
          return;
        }
        setState(() {
          currentConversation = next;
          pendingMessageAnchor = anchor;
          pendingTargetMessage = null;
        });
      },
      directToChat: (next) {
        if (!mounted) {
          return;
        }
        setState(() {
          currentConversation = next;
          pendingMessageAnchor = null;
          pendingTargetMessage = null;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final showRight = isShowSideProfile && currentConversation != null;
    final mainPane = Row(
            children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _leftListMin,
            maxWidth: _leftListMax,
          ),
          child: ClipRect(
            child: _buildLeftPane(),
          ),
        ),
        SizedBox(
          width: 1,
          child: Container(
            color: theme.weakDividerColor,
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<DesktopCreateGroupArgs?>(
            valueListenable: DesktopCreateGroupHost.argsNotifier,
            builder: (context, createGroupArgs, _) {
              final expectCreateScope =
                  widget.listScope == ConversationListScope.group
                      ? DesktopCreateGroupScope.group
                      : DesktopCreateGroupScope.c2c;
              final showCreateGroup = widget.showDesktopUserProfile &&
                  createGroupArgs != null &&
                  createGroupArgs.scope == expectCreateScope;
              if (showCreateGroup) {
                return Navigator(
                  key: ValueKey('desktop_create_group_$expectCreateScope'),
                  onGenerateRoute: (settings) {
                    return MaterialPageRoute(
                      settings: settings,
                      builder: (_) => CreateGroup(
                        key: createGroupKey,
                        convType: createGroupArgs.convType,
                        initialSelectedUserIds:
                            createGroupArgs.initialSelectedUserIds,
                        selectGroupTypeAfterMembers:
                            createGroupArgs.selectGroupTypeAfterMembers,
                        onDesktopClose: DesktopCreateGroupHost.close,
                        directToChat: (conversation) {
                          DesktopCreateGroupHost.close();
                          setState(() {
                            currentConversation = conversation;
                            pendingMessageAnchor = null;
                            pendingTargetMessage = null;
                          });
                        },
                      ),
                    );
                  },
                );
              }
              return ValueListenableBuilder<bool>(
                valueListenable: DesktopGroupNoticeHost.openNotifier,
                builder: (context, groupNoticeOpen, _) {
                  final showGroupNotice =
                      widget.showDesktopUserProfile &&
                          widget.listScope == ConversationListScope.group &&
                          groupNoticeOpen;
                  if (showGroupNotice) {
                    return AllGroupApplicationListPage(
                      key: const ValueKey('desktop_group_notice'),
                      shellEmbedded: true,
                      onClose: DesktopGroupNoticeHost.close,
                      onOpenConversation: (conversation) {
                        DesktopGroupNoticeHost.close();
                        setState(() {
                          currentConversation = conversation;
                          pendingMessageAnchor = null;
                          pendingTargetMessage = null;
                        });
                      },
                    );
                  }
                  return ValueListenableBuilder<String?>(
                    valueListenable: DesktopProfileHost.userIdNotifier,
                    builder: (context, profileUserId, _) {
                      final showProfile =
                          widget.showDesktopUserProfile &&
                              (profileUserId?.trim().isNotEmpty ?? false);
                      if (showProfile) {
                        return UserProfile(
                          key: ValueKey('desktop_profile_$profileUserId'),
                          userID: profileUserId!.trim(),
                          groupId: DesktopProfileHost.groupId,
                          onClose: DesktopProfileHost.close,
                          onClickSendMessage: (conversation) {
                            DesktopProfileHost.close();
                            DesktopGroupNoticeHost.close();
                            DesktopArchiveHost.close();
                            DesktopCreateGroupHost.close();
                            setState(() {
                              currentConversation = conversation;
                              pendingMessageAnchor = null;
                              pendingTargetMessage = null;
                            });
                          },
                        );
                      }
                      if (currentConversation == null) {
                        return EmptyWidget(
                          title: TIM_t("99Chat · IM"),
                          description: TIM_t("服务亿级 99Chat 用户的即时通讯技术"),
                        );
                      }
                      return Chat(
                        key: ValueKey(
                          '${currentConversation!.conversationID}_${_messageJumpKey(pendingMessageAnchor)}',
                        ),
                        directToChat: (conversation) {
                          DesktopProfileHost.close();
                          DesktopGroupNoticeHost.close();
                          DesktopArchiveHost.close();
                          DesktopCreateGroupHost.close();
                          setState(() {
                            currentConversation = conversation;
                            pendingMessageAnchor = null;
                            pendingTargetMessage = null;
                          });
                        },
                        selectedConversation: currentConversation!,
                        entryUnreadCount:
                            currentConversation!.unreadCount ?? 0,
                        initFindingMsg: pendingTargetMessage,
                        searchJumpAnchor: pendingMessageAnchor,
                        showGroupProfile: _toggleSideProfile,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
            ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!showRight && constraints.maxWidth.isFinite) {
          _lastHostWidth = constraints.maxWidth;
        }
        final lock = _lockedMainWidth;
        final double mainWidth;
        if (!showRight) {
          mainWidth = constraints.maxWidth;
        } else if (lock != null) {
          mainWidth = lock < constraints.maxWidth
              ? lock
              : constraints.maxWidth;
        } else {
          mainWidth = (constraints.maxWidth - _sideProfileWidth)
              .clamp(0.0, constraints.maxWidth);
        }
        final rightW = showRight
            ? (constraints.maxWidth - mainWidth).clamp(0.0, _sideProfileWidth)
            : 0.0;
        if (!showRight &&
            lock != null &&
            constraints.maxWidth <= lock + 8) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _lockedMainWidth = null;
          });
        }
        final view = MediaQuery.sizeOf(context);
        final chrome = view.width - constraints.maxWidth;
        final mqWidth = lock != null ? lock + chrome : view.width;
        final shell = showRight && rightW > 1
            ? DesktopSideSettingsShell(
                key: ValueKey(
                  'side_${currentConversation!.conversationID}',
                ),
                theme: theme,
                width: _sideProfileWidth,
                title: TIM_t("设置"),
                hideHeader: true,
                onClose: _closeSideProfile,
                child: _buildSideProfileBody(),
              )
            : null;
        return Row(
          children: [
            MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: Size(mqWidth, view.height),
              ),
              child: SizedBox(
                width: mainWidth,
                child: mainPane,
              ),
            ),
            if (shell != null)
              rightW + 0.5 >= _sideProfileWidth
                  ? shell
                  : ClipRect(
                      child: SizedBox(
                        width: rightW,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: _sideProfileWidth,
                          maxWidth: _sideProfileWidth,
                          child: shell,
                        ),
                      ),
                    ),
          ],
        );
      },
    );
  }
}
