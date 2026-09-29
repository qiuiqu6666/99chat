import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/chat_header_state_controller.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_face_url.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_responsive.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_group_title_color.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/official_account_name_label.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/presence_subtitle.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_group_avatar.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';

/// 聊天页 AppBar 标题（名称优先本地资料；头像由 Chat 统一解析）。
class ChatHeaderTitle extends StatefulWidget {
  final String? peerUserId;
  final String conversationID;
  final String? conversationFaceUrl;
  final String title;
  final ChatHeaderStateController? headerState;
  final ConvType convType;

  /// 群聊时用于超级大群红字/火焰；C2C 可空。
  final String? groupType;

  /// 为 null 时不可点（如认证号不允许进聊天设置）。
  final VoidCallback? onTap;
  final TUITheme theme;

  const ChatHeaderTitle({
    super.key,
    required this.peerUserId,
    required this.conversationID,
    required this.conversationFaceUrl,
    required this.title,
    this.headerState,
    required this.convType,
    this.groupType,
    this.onTap,
    required this.theme,
  });

  @override
  State<ChatHeaderTitle> createState() => _ChatHeaderTitleState();
}

typedef _HeaderView = ({
  String showName,
  String faceUrl,
  int? statusType,
  String label,
  bool loading,
  bool online,
  bool showPresenceRow,
  int? memberCount,
});

class _ChatHeaderTitleState extends State<ChatHeaderTitle>
    with WidgetsBindingObserver {
  UserProfileRecord? _localProfile;
  String? _presenceScheduledUserId;
  bool _presenceLoadScheduled = false;
  PresenceProvider? _presence;
  LocalSetting? _settings;
  final _friendship = serviceLocator<TUIFriendShipViewModel>();
  bool _visible = false;
  bool _foreground = true;
  bool _listening = false;
  int _profileGeneration = 0;
  int? _friendRevision;
  String? _friendUserId;
  bool _mutual = false;
  String _face = '';
  int? _imStatus;
  _HeaderView? _view;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unbind();
    _presence = context.read<PresenceProvider>();
    _settings = context.read<LocalSetting>();
    _visible = RouteVisibility.isRouteVisible(context) &&
        TickerMode.valuesOf(context).enabled;
    _bind();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _unbind();
    _bind();
  }

  void _bind() {
    if (!_visible || !_foreground || _presence == null) return;
    _listening = true;
    _presence!.addListener(_refreshView);
    _settings!.addListener(_refreshView);
    _friendship.addListener(_onFriendshipChanged);
    widget.headerState?.addListener(_onIdentityChanged);
    PeerProfileRefreshBus.instance.revision.addListener(_onProfileRefresh);
    _friendRevision = null;
    _onFriendshipChanged();
    _loadLocalProfile();
    _schedulePresenceLoad();
  }

  void _unbind() {
    ++_profileGeneration;
    if (!_listening) return;
    _listening = false;
    _presence?.removeListener(_refreshView);
    _settings?.removeListener(_refreshView);
    _friendship.removeListener(_onFriendshipChanged);
    widget.headerState?.removeListener(_onIdentityChanged);
    PeerProfileRefreshBus.instance.revision.removeListener(_onProfileRefresh);
  }

  void _onFriendshipChanged() {
    final id = widget.peerUserId?.trim() ?? '';
    _imStatus = _statusFor(_friendship, id)?.statusType;
    if (_friendRevision != _friendship.friendListRevision ||
        _friendUserId != id) {
      _friendRevision = _friendship.friendListRevision;
      _friendUserId = id;
      _mutual =
          widget.convType == ConvType.c2c && friendCanMessage(_friendship, id);
      _face = _resolveFaceUrl(_friendship);
    }
    _refreshView();
  }

  void _onIdentityChanged() {
    _face = _resolveFaceUrl(_friendship);
    _refreshView();
  }

  void _refreshView() {
    if (!mounted || !_listening) return;
    _schedulePresenceLoad();
    final next = _project();
    if (next == _view) return;
    setState(() => _view = next);
  }

  _HeaderView _project() {
    final id = widget.peerUserId?.trim() ?? '';
    final presence = _presence!;
    final show = _settings!.isShowOnlineStatus;
    final status = _imStatus == null
        ? null
        : V2TimUserStatus(userID: id, statusType: _imStatus);
    final imOnline = _imStatus == 1;
    return (
      showName: _resolveShowName(),
      faceUrl: _face,
      statusType: show
          ? presence
              .resolveAvatarOnlineStatus(id, status, isMutualFriend: _mutual)
              ?.statusType
          : null,
      label: _presenceLabel(presence, _friendship, status, id,
          showOnlineStatus: show),
      loading: show &&
          widget.convType == ConvType.c2c &&
          id.isNotEmpty &&
          presence.isLastSeenLoading(
              userId: id,
              imOnline: imOnline,
              forChatHeader: true,
              isMutualFriend: _mutual),
      online: show &&
          presence.canViewPreciseLastActive(id, isMutualFriend: _mutual) &&
          presence.resolveOnline(userId: id, imOnline: imOnline),
      showPresenceRow: show && widget.convType == ConvType.c2c && id.isNotEmpty,
      memberCount:
          widget.convType == ConvType.group ? widget.headerState?.memberCount : null,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(covariant ChatHeaderTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_listening && oldWidget.headerState != widget.headerState) {
      oldWidget.headerState?.removeListener(_onIdentityChanged);
      widget.headerState?.addListener(_onIdentityChanged);
    }
    if (oldWidget.peerUserId != widget.peerUserId ||
        oldWidget.convType != widget.convType) {
      ++_profileGeneration;
      _localProfile = null;
      _presenceScheduledUserId = null;
      _loadLocalProfile();
      _schedulePresenceLoad();
    }
    _friendRevision = null;
    _onFriendshipChanged();
    _onIdentityChanged();
  }

  @override
  void dispose() {
    _unbind();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onProfileRefresh() {
    final id = widget.peerUserId?.trim() ?? '';
    if (id.isEmpty || !PeerProfileRefreshBus.instance.matches(id)) {
      return;
    }
    _loadLocalProfile();
  }

  Future<void> _loadLocalProfile() async {
    final id = widget.peerUserId?.trim() ?? '';
    if (id.isEmpty || widget.convType != ConvType.c2c) {
      return;
    }
    if (!_listening) return;
    final generation = ++_profileGeneration;
    final record = await UserProfileLocalService.instance.read(id);
    if (!mounted || !_listening || generation != _profileGeneration) {
      return;
    }
    if (widget.peerUserId?.trim() != id || widget.convType != ConvType.c2c) {
      return;
    }
    _localProfile = record;
    _onIdentityChanged();
  }

  void _schedulePresenceLoad() {
    final userId = widget.peerUserId?.trim() ?? '';
    if (widget.convType != ConvType.c2c || userId.isEmpty) {
      return;
    }
    if (_presenceLoadScheduled || _presenceScheduledUserId == userId) {
      return;
    }
    _presenceLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presenceLoadScheduled = false;
      if (!mounted || !_listening) {
        return;
      }
      final id = widget.peerUserId?.trim() ?? '';
      if (id.isEmpty || id != userId) {
        _schedulePresenceLoad();
        return;
      }
      if (_presenceScheduledUserId == id) return;
      final localSetting = Provider.of<LocalSetting>(context, listen: false);
      if (!localSetting.isShowOnlineStatus) {
        return;
      }
      if (PlatformOfficialAccountService.showsVerifiedBadge(id)) {
        return;
      }
      _presenceScheduledUserId = userId;
      final presence = Provider.of<PresenceProvider>(context, listen: false);
      presence.ensure([id]);
      presence.refresh([id], urgent: true);
    });
  }

  V2TimUserStatus? _statusFor(
    TUIFriendShipViewModel friendship,
    String userId,
  ) {
    if (widget.convType != ConvType.c2c || userId.isEmpty) {
      return null;
    }
    if (PlatformOfficialAccountService.showsVerifiedBadge(userId)) {
      return V2TimUserStatus(userID: userId, statusType: 1);
    }
    for (final status in friendship.userStatusList) {
      if (status.userID == userId) {
        return status;
      }
    }
    return null;
  }

  String _resolveShowName() {
    final userId = widget.peerUserId?.trim() ?? '';
    final title = _effectiveTitle();
    if (widget.convType != ConvType.c2c || userId.isEmpty) {
      final fallback = title.trim();
      return fallback.isNotEmpty ? fallback : 'Chat';
    }

    return FriendDisplayName.resolveLocalFirst(
      localProfile: _localProfile,
      userId: userId,
      conversationShowName: title,
      friendList: _friendship.friendList,
    );
  }

  String _effectiveTitle() {
    final stateTitle = widget.headerState?.titleText?.trim() ?? '';
    return stateTitle.isNotEmpty ? stateTitle : widget.title;
  }

  String? _effectiveConversationFaceUrl() {
    return widget.headerState?.conversationFaceUrl ??
        widget.conversationFaceUrl;
  }

  Widget _buildHeaderName(String showName, String userId) {
    final fallbackColor = widget.theme.chatHeaderTitleTextColor ??
        widget.theme.appbarTextColor ??
        Colors.black;
    final isDesktop = AppResponsive.isDesktop(context);
    final desktopFont = AppTokens.desktopUiFontFamily;
    final style = TextStyle(
      inherit: false,
      color: conversationGroupTitleColor(
        fallback: fallbackColor,
        groupType: widget.groupType,
      ),
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: isDesktop ? 1.25 : 1.1,
      fontFamily: isDesktop ? desktopFont : null,
      fontFamilyFallback:
          isDesktop && desktopFont != null
              ? AppTokens.desktopUiFontFamilyFallback
              : null,
      leadingDistribution: TextLeadingDistribution.even,
    );
    if (widget.convType == ConvType.group) {
      return buildGroupTitleWithOptionalFlame(
        name: showName,
        groupType: widget.groupType,
        flameSize: 16,
        style: style,
      );
    }
    return OfficialAccountNameLabelForUser(
      userId: userId,
      name: showName,
      maxLines: 1,
      badgeSize: 18,
      style: style,
    );
  }

  String _resolveFaceUrl(TUIFriendShipViewModel friendship) {
    final userId = widget.peerUserId?.trim() ?? '';
    final official = PlatformOfficialAccountService.resolveFaceUrl(
      userId: userId,
      conversationFaceUrl: _effectiveConversationFaceUrl(),
    );
    if (widget.convType == ConvType.group) {
      // Avatar only selects its group placeholder when faceUrl is empty.
      // Normalize whitespace, placeholder markers, and unusable relative values
      // here so an unset group avatar cannot become a blank network image.
      return UserAvatarHelper.usableAvatarOrEmpty(official);
    }
    if (widget.convType != ConvType.c2c || userId.isEmpty) {
      return official;
    }

    final fromFriendList = ConversationFaceUrl.resolve(
      userId: userId,
      conversationFaceUrl: _effectiveConversationFaceUrl(),
      friendList: friendship.friendList,
    );
    // Chat owns the resolved conversation avatar. Once it has a usable value,
    // do not let this child switch to a second async profile source.
    final stableImFace = fromFriendList.isNotEmpty
        ? fromFriendList
        : (_effectiveConversationFaceUrl() ?? '');
    if (UserAvatarHelper.usableAvatarOrEmpty(stableImFace).isNotEmpty) {
      return stableImFace;
    }
    return UserAvatarHelper.pickBestPreferBackend(
      imFaceUrl: stableImFace,
      backendAvatarUrl: _localProfile?.avatarUrl,
    );
  }

  String _presenceLabel(
    PresenceProvider presence,
    TUIFriendShipViewModel friendship,
    V2TimUserStatus? status,
    String userId, {
    required bool showOnlineStatus,
  }) {
    if (widget.convType != ConvType.c2c ||
        userId.isEmpty ||
        !showOnlineStatus) {
      return '';
    }
    if (PlatformOfficialAccountService.showsVerifiedBadge(userId)) {
      return TIM_t('在线');
    }
    final imOnline = status?.statusType == 1;
    return presence.chatHeaderLabelFor(
      userId: userId,
      imOnline: imOnline,
      isMutualFriend: _mutual,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.peerUserId?.trim() ?? '';
    final view = _view ?? _project();
    final showName = view.showName;
    final faceUrl = view.faceUrl;
    final presenceStatus = view.statusType == null
        ? null
        : V2TimUserStatus(userID: userId, statusType: view.statusType);
    final presenceLabel = view.label;
    final showPresenceRow = view.showPresenceRow;
    final presenceLoading = view.loading;
    final effectiveOnline = view.online;
    final headerBody = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (!TUIKitScreenUtils.isWideLayout(context)) ...[
            SizedBox(
              width: 40,
              height: 40,
              child: RepaintBoundary(
                child: widget.convType == ConvType.group
                    ? AppGroupAvatar(
                        key: ValueKey(
                          'chat_header_avatar_group_${widget.conversationID}',
                        ),
                        groupId: widget.conversationID,
                        faceUrl: faceUrl,
                        showName: showName,
                        size: 40,
                      )
                    : Avatar(
                        key: ValueKey('chat_header_avatar_c2c_$userId'),
                        faceUrl: faceUrl,
                        showName: showName,
                        onlineStatus: presenceStatus,
                        type: 1,
                        borderRadius: BorderRadius.circular(999),
                      ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderName(showName, userId),
                if (widget.convType == ConvType.group) ...[
                  const SizedBox(height: 2),
                  if ((view.memberCount ?? 0) > 0)
                    Text(
                      AppI18n.of(context).format(
                        zhHans: '{option1}位成员',
                        zhHant: '{option1}位成員',
                        en: '{option1} members',
                        ja: 'メンバー{option1}人',
                        ko: '멤버 {option1}명',
                        vars: {'option1': '${view.memberCount}'},
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: AppResponsive.isDesktop(context) ? 1.3 : 1.1,
                        color: widget.theme.weakTextColor,
                      ),
                    )
                  else
                    SizedBox(
                      height: AppResponsive.isDesktop(context) ? 16 : 13.2,
                    ),
                ],
                if (showPresenceRow) ...[
                  const SizedBox(height: 2),
                  PresenceSubtitle(
                    label: presenceLabel,
                    loading: presenceLoading,
                    imOnline: effectiveOnline,
                    fontSize: 12,
                    height: AppResponsive.isDesktop(context) ? 1.3 : 1.1,
                    lineHeight: AppResponsive.isDesktop(context) ? 16 : 13.2,
                    onlineColor:
                        widget.theme.primaryColor ?? const Color(0xFF1E90FF),
                    skeletonColor: widget.theme.weakTextColor,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.onTap == null) {
      return headerBody;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: headerBody,
      ),
    );
  }
}
