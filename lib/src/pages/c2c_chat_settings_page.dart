import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/create_group.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/user_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/common_group_chats_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/common_group_chats_service.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_create_group_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_column_scope.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_confirm_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/profile_nickname_edit_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/presence_subtitle.dart';
import 'package:tencent_cloud_chat_demo/src/platform/clipboard_guard.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_asset_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/tim_uikit_conversation_media_file_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/add_friend_page.dart';
import 'package:tencent_cloud_chat_demo/src/user_profile.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_receive_opt_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/account_scoped_conversation_key.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/api/conversation_pin_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/pages/chat_background_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/complaint/complaint_reason_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/search.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_launcher.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/ui/utils/desktop_modal_layout.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_add_source.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/profile_page_nav.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/receive_message_opt_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/tim_uikit_wide_modal_operation_key.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/native_desktop_text_selection.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';

/// 单聊「聊天设置」页（头部点头像/标题进入，不再直达用户资料）。
class C2cChatSettingsPage extends StatefulWidget {
  const C2cChatSettingsPage({
    super.key,
    required this.conversation,
    this.directToChat,
    this.onJumpConversation,
    this.onRemarkUpdate,
    this.onClose,

    /// 嵌在宽屏右侧边栏时去掉内层 AppBar，避免与「设置」双标题。
    this.embeddedInSidePanel = false,
  });

  final V2TimConversation conversation;
  final ValueChanged<V2TimConversation>? directToChat;
  final void Function(V2TimConversation conversation, MessageAnchor? anchor)?
      onJumpConversation;
  final void Function(String remark)? onRemarkUpdate;
  final VoidCallback? onClose;
  final bool embeddedInSidePanel;

  @override
  State<C2cChatSettingsPage> createState() => _C2cChatSettingsPageState();
}

class _C2cChatSettingsPageState extends State<C2cChatSettingsPage> {
  final TUIConversationViewModel _conversationModel =
      serviceLocator<TUIConversationViewModel>();
  final MessageService _messageService = serviceLocator<MessageService>();
  final TUIFriendShipViewModel _friendship =
      serviceLocator<TUIFriendShipViewModel>();

  late V2TimConversation _conversation;
  UserProfileRecord? _localProfile;
  bool _busy = false;
  int _imageCount = 0;
  int _videoCount = 0;
  int _fileCount = 0;
  int _commonGroupCount = 0;

  String get _peerId =>
      ChatIdFormat.rawUserUid(widget.conversation.userID ?? '');

  String get _conversationId {
    final id = _conversation.conversationID.trim();
    if (id.isNotEmpty) {
      return id;
    }
    final peer = _peerId;
    return peer.isEmpty ? '' : 'c2c_$peer';
  }

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    PeerProfileRefreshBus.instance.revision.addListener(_onPeerProfileRefresh);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    PeerProfileRefreshBus.instance.revision
        .removeListener(_onPeerProfileRefresh);
    super.dispose();
  }

  void _onPeerProfileRefresh() {
    final peer = _peerId;
    if (peer.isEmpty || !PeerProfileRefreshBus.instance.matches(peer)) {
      return;
    }
    unawaited(_reloadPeerAvatarAfterProfileChange());
  }

  Future<void> _reloadPeerAvatarAfterProfileChange() async {
    await _loadLocalProfile();
    await _resolvePeerFace();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _refreshConversation(),
      _loadLocalProfile(),
    ]);
    if (!mounted) {
      return;
    }
    await _resolvePeerFace();
    if (widget.embeddedInSidePanel) {
      unawaited(_loadSideCardExtras());
    }
  }

  Future<void> _loadLocalProfile() async {
    final peer = _peerId;
    if (peer.isEmpty) {
      return;
    }
    final record = await UserProfileLocalService.instance.read(peer);
    if (!mounted) {
      return;
    }
    setState(() => _localProfile = record);
  }

  Future<void> _loadSideCardExtras() async {
    final peer = _peerId;
    final conversationId = _conversationId;
    final results = await Future.wait<Object?>([
      CommonGroupChatsService.instance.loadCommonGroupsPage(peer, limit: 1),
      if (conversationId.isNotEmpty)
        _countLocalMessages(
          conversationId: conversationId,
          messageTypeList: <int>[MessageElemType.V2TIM_ELEM_TYPE_IMAGE],
        )
      else
        Future<int>.value(0),
      if (conversationId.isNotEmpty)
        _countLocalMessages(
          conversationId: conversationId,
          messageTypeList: <int>[MessageElemType.V2TIM_ELEM_TYPE_VIDEO],
        )
      else
        Future<int>.value(0),
      if (conversationId.isNotEmpty)
        _countLocalMessages(
          conversationId: conversationId,
          messageTypeList: <int>[MessageElemType.V2TIM_ELEM_TYPE_FILE],
        )
      else
        Future<int>.value(0),
    ]);
    if (!mounted) {
      return;
    }
    final groups = results[0] as CommonGroupsPage;
    setState(() {
      _commonGroupCount = groups.total;
      _imageCount = results[1] as int;
      _videoCount = results[2] as int;
      _fileCount = results[3] as int;
    });
  }

  Future<int> _countLocalMessages({
    required String conversationId,
    List<String> keywordList = const <String>[],
    List<int> messageTypeList = const <int>[],
  }) async {
    try {
      final res = await _messageService.searchLocalMessages(
        searchParam: V2TimMessageSearchParam(
          conversationID: conversationId,
          keywordList: keywordList,
          messageTypeList: messageTypeList,
          pageIndex: 0,
          pageSize: 1,
          type: 0,
        ),
      );
      if (res.code != 0) {
        return 0;
      }
      return res.data?.totalCount ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _refreshConversation() async {
    final id = _conversationId;
    if (id.isEmpty) {
      return;
    }
    final previousFace =
        UserAvatarHelper.usableAvatarOrEmpty(_conversation.faceUrl);
    try {
      final latest = await TIMUIKitCore.getSDKInstance()
          .getConversationManager()
          .getConversation(conversationID: id);
      if (!mounted || latest.code != 0 || latest.data == null) {
        return;
      }
      final next = latest.data!;
      next.isPinned =
          ConversationPinSyncService.instance.isPinnedConversationId(id);
      final nextFace = UserAvatarHelper.usableAvatarOrEmpty(next.faceUrl);
      if (nextFace.isEmpty && previousFace.isNotEmpty) {
        next.faceUrl = previousFace;
      }
      setState(() => _conversation = next);
    } catch (_) {}
  }

  Future<void> _resolvePeerFace() async {
    final peer = _peerId;
    if (peer.isEmpty) {
      return;
    }
    final resolved = await UserAvatarHelper.resolveChatPeerFaceUrl(
      peerUserId: peer,
      conversationFaceUrl: _conversation.faceUrl,
      preferLiveProfile: true,
    );
    if (!mounted) {
      return;
    }
    final usable = UserAvatarHelper.usableAvatarOrEmpty(resolved);
    if (usable.isEmpty) {
      return;
    }
    if (UserAvatarHelper.usableAvatarOrEmpty(_conversation.faceUrl) == usable) {
      return;
    }
    setState(() {
      _conversation.faceUrl = usable;
    });
  }

  String _displayName() {
    return FriendDisplayName.resolveLocalFirst(
      localProfile: _localProfile,
      userId: _peerId,
      conversationShowName: _conversation.showName,
      friendList: _friendship.friendList,
    );
  }

  String _faceUrl() {
    final fromList = ConversationFaceUrl.resolve(
      userId: _peerId,
      conversationFaceUrl: _conversation.faceUrl,
      friendList: _friendship.friendList,
    );
    return UserAvatarHelper.pickBestPreferBackend(
      imFaceUrl: fromList,
      backendAvatarUrl: _localProfile?.avatarUrl,
    );
  }

  bool get _isPinned => ConversationPinSyncService.instance
      .isPinnedConversationId(_conversationId);

  bool get _isMuted => (_conversation.recvOpt ?? 0) != 0;

  Future<void> _openPeerProfile() async {
    final peer = _peerId;
    if (peer.isEmpty) {
      return;
    }
    if (widget.embeddedInSidePanel) {
      final i18n = AppI18n.of(context);
      if (ProfilePageNav.isFriendInContactList(peer) ||
          ProfilePageNav.isSelfUser(peer)) {
        await DesktopSideColumnScope.push<void>(
          context,
          title: i18n.t(
            zhHans: '详细资料',
            zhHant: '詳細資料',
            en: 'Profile',
            ja: '詳細',
            ko: '상세 정보',
          ),
          page: UserProfile(
            userID: peer,
            onRemarkUpdate: widget.onRemarkUpdate,
          ),
        );
      } else {
        await DesktopSideColumnScope.push<void>(
          context,
          title: i18n.t(
            zhHans: '添加好友',
            zhHant: '添加好友',
            en: 'Add Friend',
            ja: '友達を追加',
            ko: '친구 추가',
          ),
          page: AddFriendPage(
            userID: peer,
            nickname: _displayName(),
            addSource: FriendAddSource.chat,
            embedded: true,
          ),
        );
      }
    } else {
      await ProfilePageNav.openUserProfileOrAddFriend(
        context,
        userID: peer,
        addSource: FriendAddSource.chat,
        onRemarkUpdate: widget.onRemarkUpdate,
      );
    }
    if (mounted) {
      unawaited(_loadLocalProfile());
      unawaited(_resolvePeerFace());
    }
  }

  Future<void> _openCreateGroup() async {
    final peerId = _peerId;
    if (widget.embeddedInSidePanel) {
      final i18n = AppI18n.of(context);
      await DesktopSideColumnScope.push<void>(
        context,
        title: i18n.t(
          zhHans: '选择联系人',
          zhHant: '選擇聯絡人',
          en: 'Select Contacts',
          ja: '連絡先を選択',
          ko: '연락처 선택',
        ),
        page: CreateGroup(
          convType: GroupTypeForUIKit.work,
          selectGroupTypeAfterMembers: true,
          initialSelectedUserIds: peerId.isEmpty ? null : <String>[peerId],
          embeddedInSideColumn: true,
          directToChat: (conversation) {
            if (widget.directToChat != null) {
              widget.directToChat!(conversation);
            }
          },
        ),
      );
      return;
    }
    if (DesktopModalLayout.isDesktop(context)) {
      DesktopCreateGroupHost.open(
        scope: DesktopCreateGroupScope.c2c,
        convType: GroupTypeForUIKit.work,
        selectGroupTypeAfterMembers: true,
        initialSelectedUserIds: peerId.isEmpty ? null : <String>[peerId],
      );
      return;
    }
    await Navigator.of(context).push(
      AppMaterialPageRoute(
        builder: (_) => CreateGroup(
          // convType 仅作选人上限占位；真正类型在选完好友后进通用选择页决定。
          convType: GroupTypeForUIKit.work,
          selectGroupTypeAfterMembers: true,
          initialSelectedUserIds: peerId.isEmpty ? null : <String>[peerId],
          directToChat: (conversation) {
            if (widget.directToChat != null) {
              widget.directToChat!(conversation);
              return;
            }
            openOrReuseAppChat(context, conversation);
          },
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    // 手机：替换设置页，避免返回栈叠多层聊天。
    // 宽屏边栏：普通 push，关闭搜索后仍回到右侧设置。
    final route = AppMaterialPageRoute(
      settings: const RouteSettings(name: AppRoutes.searchInConversation),
      builder: (context) => Search(
        conversation: _conversation,
        onTapConversation:
            (V2TimConversation conversation, MessageAnchor? anchor) {
          openChatWithAnchor(context, conversation, anchor: anchor);
        },
      ),
    );
    if (widget.embeddedInSidePanel) {
      final i18n = AppI18n.of(context);
      await DesktopSideColumnScope.push<void>(
        context,
        title: i18n.t(
          zhHans: '查找聊天内容',
          zhHant: '查找聊天內容',
          en: 'Search Chat Content',
          ja: 'チャット内容を検索',
          ko: '채팅 내용 검색',
        ),
        page: Search(
          conversation: _conversation,
          onTapConversation:
              (V2TimConversation conversation, MessageAnchor? anchor) {
            widget.onJumpConversation?.call(conversation, anchor);
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      );
      return;
    }
    await Navigator.pushReplacement(context, route);
  }

  Future<void> _setPinned(bool value) async {
    if (_conversationId.isEmpty || _busy) {
      return;
    }
    // 勿先改 conversation.isPinned：PinService 用该字段判 prev==next 会直接空成功，
    // SDK/本地都不写，随后 refresh 又把开关拉回旧值（取消置顶无效果）。
    setState(() => _busy = true);
    try {
      final result = await ConversationPinService.instance.setPinned(
        conversation: _conversation,
        isPinned: value,
        source: 'c2c_chat_settings',
      );
      if (!mounted) {
        return;
      }
      if (!result.applied) {
        setState(() => _busy = false);
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '设置失败',
          zhHant: '設置失敗',
          en: 'Failed to update',
          ja: '設定に失敗しました',
          ko: '설정에 실패했습니다',
        ));
        return;
      }
      setState(() {
        _conversation.isPinned = result.isPinned;
        _busy = false;
      });
    } on ConversationPinLimitExceededException {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '置顶已达上限（最多 100 个）',
        zhHant: '置頂已達上限（最多 100 個）',
        en: 'Pin limit reached (max 100)',
        ja: 'ピン留め上限です（最大100）',
        ko: '고정 한도에 도달했습니다(최대 100)',
      ));
    }
    unawaited(_refreshConversation());
  }

  Future<void> _setMuted(bool value) async {
    final peer = _peerId;
    if (peer.isEmpty || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _conversation.recvOpt = value ? 2 : 0;
    });
    // IM-09 ADR §10.1: c2c 免打扰收敛到 C2cReceiveOptService,
    // 在异步链入口处 capture() 拿到 SessionIdentity,跨账号 fence 生效.
    final captured = SessionIdentityService.instance.capture();
    final key = AccountScopedConversationKey.tryParse(
      ownerUserId: captured.ownerUserId,
      conversationType: ImConversationType.c2c,
      conversationId: peer,
    );
    if (key == null) {
      if (mounted) {
        setState(() {
          _conversation.recvOpt = value ? 0 : 2;
          _busy = false;
        });
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '设置失败',
          zhHant: '設置失敗',
          en: 'Failed to update',
          ja: '設定に失敗しました',
          ko: '설정에 실패했습니다',
        ));
      }
      return;
    }
    final res = await C2cReceiveOptService.setOpt(
      messageService: _messageService,
      key: key,
      opt: value
          ? ReceiveMsgOptEnum.V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE
          : ReceiveMsgOptEnum.V2TIM_RECEIVE_MESSAGE,
      capturedIdentity: captured,
    );
    if (!mounted) {
      return;
    }
    if (res.code != 0) {
      setState(() {
        _conversation.recvOpt = value ? 0 : 2;
        _busy = false;
      });
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '设置失败',
        zhHant: '設置失敗',
        en: 'Failed to update',
        ja: '設定に失敗しました',
        ko: '설정에 실패했습니다',
      ));
      return;
    }
    setState(() => _busy = false);
    unawaited(_friendship.loadContactListData());
    unawaited(_refreshConversation());
  }

  Future<void> _openChatBackground() async {
    final conversationId = _conversationId;
    if (conversationId.isEmpty) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '当前无法设置聊天背景',
        zhHant: '目前無法設定聊天背景',
        en: 'Cannot set chat background now',
        ja: '今は背景を設定できません',
        ko: '지금은 배경 설정 불가',
      ));
      return;
    }
    final page = ChatBackgroundPage(
      conversationId: conversationId,
      conversationName: _displayName(),
      embedded: DesktopModalLayout.isDesktop(context),
    );
    if (widget.embeddedInSidePanel) {
      final i18n = AppI18n.of(context);
      await DesktopSideColumnScope.push<void>(
        context,
        title: i18n.t(
          zhHans: '聊天背景',
          zhHant: '聊天背景',
          en: 'Chat Background',
          ja: 'チャット背景',
          ko: '채팅 배경',
        ),
        page: ChatBackgroundPage(
          conversationId: conversationId,
          conversationName: _displayName(),
          embedded: true,
        ),
      );
      return;
    }
    if (DesktopModalLayout.isDesktop(context)) {
      final size = DesktopModalLayout.dualPane(context);
      await TUIKitWidePopup.showPopupWindow(
        operationKey: TUIKitWideModalOperationKey.custom,
        context: context,
        title: AppI18n.of(context).t(
          zhHans: '聊天背景',
          zhHant: '聊天背景',
          en: 'Chat Background',
          ja: 'チャット背景',
          ko: '채팅 배경',
        ),
        width: size.width,
        height: size.height,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: (_) => page,
      );
      return;
    }
    await Navigator.push(
      context,
      AppMaterialPageRoute(builder: (context) => page),
    );
  }

  Future<void> _confirmAndClearHistory() async {
    final peer = _peerId;
    if (peer.isEmpty) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '当前无法清空聊天记录',
        zhHant: '目前無法清空聊天記錄',
        en: 'Cannot clear chat history now',
        ja: '今は履歴を削除できません',
        ko: '지금은 채팅 기록을 삭제할 수 없습니다',
      ));
      return;
    }
    final confirmTitle = AppI18n.of(context).t(
      zhHans: '清空聊天记录',
      zhHant: '清空聊天記錄',
      en: 'Clear Chat History',
      ja: 'チャット履歴を削除',
      ko: '채팅 기록 삭제',
    );
    final confirmMessage = AppI18n.of(context).t(
      zhHans: '清空后无法恢复，该会话将从消息列表移除。确定继续吗？',
      zhHant: '清空後無法恢復，該會話將從訊息列表移除。確定繼續嗎？',
      en: 'This cannot be undone. The conversation will also be removed from your message list. Continue?',
      ja: '削除後は元に戻せません。会話はメッセージ一覧からも削除されます。続行しますか？',
      ko: '삭제 후 복구할 수 없습니다. 대화가 메시지 목록에서도 제거됩니다. 계속할까요?',
    );
    final confirmAction = AppI18n.of(context).t(
      zhHans: '清空',
      zhHant: '清空',
      en: 'Clear',
      ja: '削除',
      ko: '삭제',
    );
    final bool confirmed;
    if (widget.embeddedInSidePanel) {
      confirmed = await DesktopSideColumnScope.push<bool>(
            context,
            title: confirmTitle,
            page: DesktopSideConfirmPage(
              title: confirmTitle,
              message: confirmMessage,
              confirmText: confirmAction,
            ),
          ) ==
          true;
    } else {
      confirmed = await AppDialog.confirm(
        title: confirmTitle,
        message: confirmMessage,
        confirmText: confirmAction,
        destructive: true,
      );
    }
    if (!confirmed || !mounted) {
      return;
    }

    unawaited(AppDialog.showLoading(
      text: AppI18n.of(context).t(
        zhHans: '正在清空...',
        zhHant: '正在清空...',
        en: 'Clearing...',
        ja: '削除中...',
        ko: '삭제 중...',
      ),
    ));
    // 等 loading 路由挂上，避免清空极快返回时 hideLoading 误 pop 设置页。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final result = await _conversationModel.clearHistoryMessage(
        convID: peer,
        convType: 1,
      );
      if (result?.code == 0) {
        final convId = _conversationId;
        if (convId.isNotEmpty) {
          await ConversationSyncService.instance.onConversationHistoryCleared(
            conversationID: convId,
            snapshot: _conversation,
          );
        }
        widget.conversation.lastMessage = null;
        _conversation.lastMessage = null;
        if (mounted) {
          ToastUtils.toast(AppI18n.of(context).t(
            zhHans: '聊天记录已清空',
            zhHant: '聊天記錄已清空',
            en: 'Chat history cleared',
            ja: 'チャット履歴を削除しました',
            ko: '채팅 기록을 삭제했습니다',
          ));
        }
        return;
      }
      if (mounted) {
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '清空聊天记录失败',
          zhHant: '清空聊天記錄失敗',
          en: 'Failed to clear chat history',
          ja: 'チャット履歴の削除に失敗しました',
          ko: '채팅 기록 삭제에 실패했습니다',
        ));
      }
    } catch (_) {
      if (mounted) {
        ToastUtils.toast(AppI18n.of(context).t(
          zhHans: '清空聊天记录失败',
          zhHant: '清空聊天記錄失敗',
          en: 'Failed to clear chat history',
          ja: 'チャット履歴の削除に失敗しました',
          ko: '채팅 기록 삭제에 실패했습니다',
        ));
      }
    } finally {
      AppDialog.hideLoading();
    }
  }

  Future<void> _openComplaint() async {
    final peer = _peerId;
    if (peer.isEmpty || ProfilePageNav.isSelfUser(peer)) {
      ToastUtils.toast(AppI18n.of(context).t(
        zhHans: '不能投诉自己',
        zhHant: '不能投訴自己',
        en: 'You cannot report yourself.',
        ja: '自分自身を通報できません。',
        ko: '자신을 신고할 수 없습니다.',
      ));
      return;
    }
    if (widget.embeddedInSidePanel) {
      final i18n = AppI18n.of(context);
      await DesktopSideColumnScope.push<void>(
        context,
        title: i18n.t(
          zhHans: '投诉原因',
          zhHant: '投訴原因',
          en: 'Complaint Reason',
          ja: '通報理由',
          ko: '신고 사유',
        ),
        page: ComplaintReasonPage(
          reportedUserId: peer,
          reportedUserName: _displayName(),
        ),
      );
      return;
    }
    await ComplaintReasonPage.openC2c(
      context,
      reportedUserId: peer,
      reportedUserName: _displayName(),
    );
  }

  Widget _sectionGap(Color pageBg) {
    return Container(height: 10, color: pageBg);
  }

  Widget _sectionCard(TUITheme theme, Color cardBg, List<Widget> children) {
    return Container(
      color: cardBg,
      child: Column(
        children: List.generate(children.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              height: 0.6,
              thickness: 0.6,
              indent: 16,
              color: theme.weakDividerColor ?? const Color(0xFFE5E5E5),
            );
          }
          return children[index ~/ 2];
        }),
      ),
    );
  }

  Widget _memberCard(TUITheme theme, Color cardBg) {
    final name = _displayName();
    final face = _faceUrl();
    final weak = theme.weakTextColor ?? const Color(0xFF999999);
    return Container(
      width: double.infinity,
      color: cardBg,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        children: [
          InkWell(
            onTap: _openPeerProfile,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 54,
              child: Column(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Avatar(
                      faceUrl: face,
                      showName: name,
                      type: 1,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: weak),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: _openCreateGroup,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 54,
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: weak.withValues(alpha: 0.45)),
                    ),
                    child: Icon(Icons.add, color: weak, size: 28),
                  ),
                  const SizedBox(height: 6),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow({
    required TUITheme theme,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final titleColor = theme.darkTextColor ?? Colors.black;
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 16, color: titleColor),
              ),
            ),
            Transform.scale(
              scale: 0.9,
              child: CupertinoSwitch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: theme.primaryColor ?? const Color(0xFF1E90FF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _arrowRow({
    required TUITheme theme,
    required String title,
    VoidCallback? onTap,
    Widget? trailing,
    bool showArrow = true,
  }) {
    final titleColor = theme.darkTextColor ?? Colors.black;
    final weak = theme.weakTextColor ?? const Color(0xFF999999);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16, color: titleColor),
                ),
              ),
              if (trailing != null) ...[
                trailing,
                const SizedBox(width: 6),
              ],
              if (showArrow)
                Icon(Icons.chevron_right_rounded, color: weak, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  String _usernameLabel() {
    final id = ChatIdFormat.display(_peerId);
    if (id.isEmpty) {
      return '';
    }
    return id.startsWith('@') ? id : '@$id';
  }

  Future<void> _copyUsername() async {
    final username = _usernameLabel();
    if (username.isEmpty) {
      return;
    }
    await ClipboardGuard.copy(username);
    if (!mounted) {
      return;
    }
    ToastUtils.toast(AppI18n.of(context).t(
      zhHans: '已复制',
      zhHant: '已複製',
      en: 'Copied',
      ja: 'コピーしました',
      ko: '복사됨',
    ));
  }

  Future<void> _openMediaAssets({
    ConversationAssetTab tab = ConversationAssetTab.media,
  }) async {
    if (!widget.embeddedInSidePanel) {
      return;
    }
    final i18n = AppI18n.of(context);
    final isFile = tab == ConversationAssetTab.file;
    await DesktopSideColumnScope.push<void>(
      context,
      title: i18n.t(
        zhHans: isFile ? '文件' : '图片和视频',
        zhHant: isFile ? '檔案' : '圖片和視頻',
        en: isFile ? 'Files' : 'Photos & Videos',
        ja: isFile ? 'ファイル' : '写真と動画',
        ko: isFile ? '파일' : '사진 및 동영상',
      ),
      page: TIMUIKitConversationMediaFilePage(
        conversation: _conversation,
        initialTab: tab,
        embedded: true,
        onTapMessage: (conversation, message) {
          widget.onJumpConversation?.call(conversation, null);
        },
      ),
    );
  }

  Future<void> _openCommonGroups() async {
    final peer = _peerId;
    if (peer.isEmpty) {
      return;
    }
    final i18n = AppI18n.of(context);
    await DesktopSideColumnScope.push<void>(
      context,
      title: i18n.t(
        zhHans: '共同加入的群组',
        zhHant: '共同加入的群組',
        en: 'Groups in Common',
        ja: '共通のグループ',
        ko: '공통 그룹',
      ),
      page: CommonGroupChatsPage(
        peerUserId: peer,
        peerDisplayName: _displayName(),
        embedded: true,
      ),
    );
  }

  Future<void> _editContact() async {
    final peer = _peerId;
    if (peer.isEmpty) {
      return;
    }
    await ProfileNicknameEditPage.pushFriendRemark(
      context,
      initialRemark: _localProfile?.friendRemark ?? '',
      hintBaseline: _displayName(),
      avatarFaceUrl: _faceUrl(),
      avatarShowName: _displayName(),
      onSave: (remark) async {
        final res = await TIMUIKitCore.getSDKInstance()
            .getFriendshipManager()
            .setFriendInfo(userID: peer, friendRemark: remark.trim());
        if (res.code != 0) {
          if (mounted) {
            ToastUtils.toast(AppI18n.of(context).t(
              zhHans: '保存失败',
              zhHant: '儲存失敗',
              en: 'Save failed',
              ja: '保存に失敗',
              ko: '저장 실패',
            ));
          }
          return false;
        }
        widget.onRemarkUpdate?.call(remark.trim());
        await _loadLocalProfile();
        return true;
      },
    );
  }

  Future<void> _deleteContact() async {
    final peer = _peerId;
    if (peer.isEmpty) {
      return;
    }
    final i18n = AppI18n.of(context);
    final title = i18n.t(
      zhHans: '删除联系人',
      zhHant: '刪除聯絡人',
      en: 'Delete Contact',
      ja: '連絡先を削除',
      ko: '연락처 삭제',
    );
    final confirmed = await DesktopSideColumnScope.push<bool>(
          context,
          title: title,
          page: DesktopSideConfirmPage(
            title: title,
            message: i18n.t(
              zhHans: '删除后将从通讯录移除，确定继续吗？',
              zhHant: '刪除後將從通訊錄移除，確定繼續嗎？',
              en: 'This contact will be removed. Continue?',
              ja: '連絡先が削除されます。続行しますか？',
              ko: '연락처가 삭제됩니다. 계속할까요?',
            ),
            confirmText: i18n.t(
              zhHans: '删除',
              zhHant: '刪除',
              en: 'Delete',
              ja: '削除',
              ko: '삭제',
            ),
          ),
        ) ==
        true;
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await MeFriendApi.instance.deleteFriend(peer);
      ToastUtils.toast(i18n.t(
        zhHans: '已删除联系人',
        zhHant: '已刪除聯絡人',
        en: 'Contact deleted',
        ja: '連絡先を削除しました',
        ko: '연락처가 삭제됨',
      ));
      widget.onClose?.call();
    } catch (_) {
      ToastUtils.toast(i18n.t(
        zhHans: '删除失败',
        zhHant: '刪除失敗',
        en: 'Delete failed',
        ja: '削除に失敗',
        ko: '삭제 실패',
      ));
    }
  }

  Future<void> _startCall({required bool video}) async {
    final peer = _peerId;
    if (peer.isEmpty) {
      return;
    }
    await CallLauncher.startBridgeC2C(
      context,
      userId: peer,
      video: video,
      conversationId: _conversationId,
    );
  }

  Future<void> _shareContact() async {
    final i18n = AppI18n.of(context);
    final lines = <String>[
      _displayName(),
      if (_usernameLabel().isNotEmpty) _usernameLabel(),
    ].where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      return;
    }
    await ClipboardGuard.copy(lines.join('\n'));
    if (!mounted) {
      return;
    }
    ToastUtils.toast(i18n.t(
      zhHans: '已复制联系方式',
      zhHant: '已複製聯絡方式',
      en: 'Contact copied',
      ja: '連絡先をコピーしました',
      ko: '연락처가 복사됨',
    ));
  }

  bool _peerImOnline() {
    final id = _peerId;
    if (id.isEmpty) {
      return false;
    }
    for (final status in _friendship.userStatusList) {
      if (status.userID == id) {
        return status.statusType == 1;
      }
    }
    return false;
  }

  Widget _buildTelegramSideCard(TUITheme theme, AppI18n i18n) {
    final name = _displayName();
    final face = _faceUrl();
    final username = _usernameLabel();
    final bio = _localProfile?.selfSignature.trim() ?? '';
    final presence = Provider.of<PresenceProvider>(context);
    final showOnlineStatus =
        Provider.of<LocalSetting>(context).isShowOnlineStatus;
    final mutual = friendCanMessage(_friendship, _peerId);
    final imOnline = _peerImOnline();
    if (showOnlineStatus && _peerId.isNotEmpty) {
      presence.ensure(<String>[_peerId]);
    }
    final lastSeen = showOnlineStatus
        ? presence.chatHeaderLabelFor(
            userId: _peerId,
            imOnline: imOnline,
            isMutualFriend: mutual,
          )
        : '';
    final lastSeenLoading = showOnlineStatus &&
        presence.isLastSeenLoading(
          userId: _peerId,
          imOnline: imOnline,
          forChatHeader: true,
          isMutualFriend: mutual,
        );
    final peerOnline = showOnlineStatus &&
        presence.canViewPreciseLastActive(
          _peerId,
          isMutualFriend: mutual,
        ) &&
        presence.resolveOnline(userId: _peerId, imOnline: imOnline);
    final avatarStatus = showOnlineStatus
        ? presence.resolveAvatarOnlineStatus(
            _peerId,
            V2TimUserStatus(
              userID: _peerId,
              statusType: imOnline ? 1 : 0,
            ),
            isMutualFriend: mutual,
          )
        : null;
    final isDark = Provider.of<DefaultThemeData>(context, listen: false)
            .currentThemeType ==
        ThemeType.dark;
    final headerBg = isDark
        ? (theme.weakBackgroundColor ?? const Color(0xFF2C2C2E))
        : const Color(0xFFF2F3F5);
    final listBg = isDark
        ? (theme.wideBackgroundColor ??
            theme.conversationItemBgColor ??
            const Color(0xFF1C1C1E))
        : Colors.white;
    final chipBg = isDark ? listBg : Colors.white;
    final sectionGap = isDark
        ? (theme.weakBackgroundColor ?? const Color(0xFF2C2C2E))
        : const Color(0xFFF2F3F5);
    final ink = theme.darkTextColor ?? const Color(0xFF222222);
    final muted = theme.weakTextColor ?? const Color(0xFF8E8E93);

    Widget actionChip({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: chipBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: ink),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
      );
    }

    Widget infoRow({
      required String title,
      required String subtitle,
      Color? titleColor,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        color: titleColor ?? ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      );
    }

    Widget iconRow({
      required IconData icon,
      required String label,
      Color? color,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 16, 11),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color ?? ink),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 16, color: color ?? ink),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget listView = ListView(
      padding: EdgeInsets.zero,
      children: [
          Stack(
            children: [
              ColoredBox(
                color: headerBg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: Avatar(
                          faceUrl: face,
                          showName: name,
                          type: 1,
                          onlineStatus: avatarStatus,
                          borderRadius: BorderRadius.circular(36),
                        ),
                      ),
                      const SizedBox(height: 8),
                      NativeDesktopSelectableMessageText(
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (showOnlineStatus) ...[
                        const SizedBox(height: 2),
                        PresenceSubtitle(
                          label: lastSeen,
                          loading: lastSeenLoading,
                          imOnline: peerOnline,
                          fontSize: 12,
                          offlineColor: muted,
                          onlineColor: theme.primaryColor ?? ink,
                          skeletonColor: muted.withValues(alpha: 0.28),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          actionChip(
                            icon: Icons.call_outlined,
                            label: i18n.t(
                              zhHans: '语音通话',
                              zhHant: '語音通話',
                              en: 'Voice',
                              ja: '音声',
                              ko: '음성',
                            ),
                            onTap: () => unawaited(_startCall(video: false)),
                          ),
                          actionChip(
                            icon: Icons.videocam_outlined,
                            label: i18n.t(
                              zhHans: '视频通话',
                              zhHant: '視頻通話',
                              en: 'Video',
                              ja: 'ビデオ',
                              ko: '영상',
                            ),
                            onTap: () => unawaited(_startCall(video: true)),
                          ),
                          actionChip(
                            icon: _isMuted
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_none_rounded,
                            label: i18n.t(
                              zhHans: '静音',
                              zhHant: '靜音',
                              en: 'Mute',
                              ja: 'ミュート',
                              ko: '음소거',
                            ),
                            onTap: () => unawaited(_setMuted(!_isMuted)),
                          ),
                          actionChip(
                            icon: _isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            label: i18n.t(
                              zhHans: '置顶',
                              zhHant: '置頂',
                              en: 'Pin',
                              ja: 'ピン留め',
                              ko: '고정',
                            ),
                            onTap: () => unawaited(_setPinned(!_isPinned)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  onPressed: widget.onClose,
                  icon: Icon(Icons.close_rounded, color: muted),
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty)
            infoRow(
              title: bio,
              subtitle: i18n.t(
                zhHans: '个人简介',
                zhHant: '個人簡介',
                en: 'Bio',
                ja: '自己紹介',
                ko: '소개',
              ),
            ),
          if (username.isNotEmpty)
            infoRow(
              title: username,
              titleColor: theme.primaryColor ?? AppColors.primaryBlue,
              subtitle: i18n.t(
                zhHans: '用户名',
                zhHant: '使用者名稱',
                en: 'Username',
                ja: 'ユーザー名',
                ko: '사용자 이름',
              ),
              onTap: _copyUsername,
              trailing: IconButton(
                onPressed: _copyUsername,
                icon: Icon(Icons.copy_all_outlined, size: 20, color: muted),
              ),
            ),
          Divider(height: 8, thickness: 6, color: sectionGap),
          iconRow(
            icon: Icons.image_outlined,
            label: i18n.t(
              zhHans: '$_imageCount张图片',
              zhHant: '$_imageCount張圖片',
              en: '$_imageCount photos',
              ja: '写真$_imageCount件',
              ko: '사진 $_imageCount장',
            ),
            onTap: _openMediaAssets,
          ),
          iconRow(
            icon: Icons.videocam_outlined,
            label: i18n.t(
              zhHans: '$_videoCount个视频',
              zhHant: '$_videoCount個視頻',
              en: '$_videoCount videos',
              ja: '動画$_videoCount件',
              ko: '동영상 $_videoCount개',
            ),
            onTap: _openMediaAssets,
          ),
          iconRow(
            icon: Icons.insert_drive_file_outlined,
            label: i18n.t(
              zhHans: '$_fileCount个文件',
              zhHant: '$_fileCount個檔案',
              en: '$_fileCount files',
              ja: 'ファイル$_fileCount件',
              ko: '파일 $_fileCount개',
            ),
            onTap: () => unawaited(
              _openMediaAssets(tab: ConversationAssetTab.file),
            ),
          ),
          iconRow(
            icon: Icons.person_outline_rounded,
            label: i18n.t(
              zhHans: '$_commonGroupCount个共同加入的群组',
              zhHant: '$_commonGroupCount個共同加入的群組',
              en: '$_commonGroupCount groups in common',
              ja: '共通グループ$_commonGroupCount件',
              ko: '공통 그룹 $_commonGroupCount개',
            ),
            onTap: _openCommonGroups,
          ),
          Divider(height: 8, thickness: 6, color: sectionGap),
          iconRow(
            icon: Icons.ios_share_rounded,
            label: i18n.t(
              zhHans: '分享联系方式',
              zhHant: '分享聯絡方式',
              en: 'Share Contact',
              ja: '連絡先を共有',
              ko: '연락처 공유',
            ),
            onTap: _shareContact,
          ),
          iconRow(
            icon: Icons.edit_outlined,
            label: i18n.t(
              zhHans: '编辑联系人',
              zhHant: '編輯聯絡人',
              en: 'Edit Contact',
              ja: '連絡先を編集',
              ko: '연락처 편집',
            ),
            onTap: _editContact,
          ),
          iconRow(
            icon: Icons.delete_outline_rounded,
            label: i18n.t(
              zhHans: '删除联系人',
              zhHant: '刪除聯絡人',
              en: 'Delete Contact',
              ja: '連絡先を削除',
              ko: '연락처 삭제',
            ),
            onTap: _deleteContact,
          ),
          const SizedBox(height: 24),
        ],
    );
    if (PlatformUtils().isNativeDesktop) {
      final behavior = ScrollConfiguration.of(context);
      listView = ScrollConfiguration(
        behavior: behavior.copyWith(
          dragDevices:
              behavior.dragDevices.difference({PointerDeviceKind.mouse}),
        ),
        child: listView,
      );
    }
    return ColoredBox(
      color: listBg,
      child: listView,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final isDark = Provider.of<DefaultThemeData>(context, listen: false)
            .currentThemeType ==
        ThemeType.dark;
    final i18n = AppI18n.of(context);
    // 浅色强制灰底 + 白卡片，避免 weakBackground 接近白色导致分区糊成一片。
    final pageBg = isDark
        ? (theme.weakBackgroundColor ?? AppColors.background(dark: true))
        : const Color(0xFFF1F1F1);
    final cardBg = isDark
        ? (theme.conversationItemBgColor ??
            theme.wideBackgroundColor ??
            AppColors.card(dark: true))
        : Colors.white;
    final appBarBg = isDark
        ? (theme.appbarBgColor ?? cardBg)
        : (theme.appbarBgColor ?? Colors.white);
    final textColor = theme.darkTextColor ?? AppColors.text(dark: isDark);
    final primary = theme.primaryColor ?? AppColors.primaryBlue;

    final body = ListView(
      children: [
        _memberCard(theme, cardBg),
        _sectionGap(pageBg),
        _sectionCard(theme, cardBg, [
          _arrowRow(
            theme: theme,
            title: i18n.t(
              zhHans: '查找聊天内容',
              zhHant: '查找聊天內容',
              en: 'Search Chat Content',
              ja: 'チャット内容を検索',
              ko: '채팅 내용 검색',
            ),
            onTap: _openSearch,
          ),
        ]),
        _sectionGap(pageBg),
        _sectionCard(theme, cardBg, [
          _switchRow(
            theme: theme,
            title: i18n.t(
              zhHans: '置顶聊天',
              zhHant: '置頂聊天',
              en: 'Pin Chat',
              ja: 'チャットをピン留め',
              ko: '채팅 고정',
            ),
            value: _isPinned,
            onChanged: _setPinned,
          ),
          _switchRow(
            theme: theme,
            title: i18n.t(
              zhHans: '消息免打扰',
              zhHant: '訊息免打擾',
              en: 'Mute Notifications',
              ja: '通知をミュート',
              ko: '알림 끄기',
            ),
            value: _isMuted,
            onChanged: _setMuted,
          ),
        ]),
        _sectionGap(pageBg),
        _sectionCard(theme, cardBg, [
          _arrowRow(
            theme: theme,
            title: i18n.t(
              zhHans: '设置当前聊天背景',
              zhHant: '設定目前聊天背景',
              en: 'Set Chat Background',
              ja: 'チャット背景を設定',
              ko: '채팅 배경 설정',
            ),
            onTap: _openChatBackground,
          ),
        ]),
        _sectionGap(pageBg),
        _sectionCard(theme, cardBg, [
          _arrowRow(
            theme: theme,
            title: i18n.t(
              zhHans: '清空聊天记录',
              zhHant: '清空聊天記錄',
              en: 'Clear Chat History',
              ja: 'チャット履歴を削除',
              ko: '채팅 기록 삭제',
            ),
            showArrow: false,
            onTap: _confirmAndClearHistory,
          ),
        ]),
        _sectionGap(pageBg),
        _sectionCard(theme, cardBg, [
          _arrowRow(
            theme: theme,
            title: i18n.t(
              zhHans: '投诉',
              zhHant: '投訴',
              en: 'Complaint',
              ja: '通報',
              ko: '신고',
            ),
            onTap: _openComplaint,
          ),
        ]),
        const SizedBox(height: 24),
      ],
    );

    if (widget.embeddedInSidePanel) {
      return _buildTelegramSideCard(theme, i18n);
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: appBarBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          i18n.t(
            zhHans: '聊天设置',
            zhHant: '聊天設置',
            en: 'Chat Settings',
            ja: 'チャット設定',
            ko: '채팅 설정',
          ),
          style: TextStyle(
            color: theme.appbarTextColor ?? textColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: body,
    );
  }
}
