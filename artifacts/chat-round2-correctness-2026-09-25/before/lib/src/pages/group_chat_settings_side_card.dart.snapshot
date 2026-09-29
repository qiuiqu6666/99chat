import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/group_info_detail.dart';
import 'package:tencent_cloud_chat_demo/src/group_manage_page.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_column_scope.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_launcher.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/presence_subtitle.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_role_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/native_desktop_text_selection.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_asset_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/tim_uikit_conversation_media_file_page.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';

class GroupChatSettingsSideCard extends StatefulWidget {
  const GroupChatSettingsSideCard({
    super.key,
    required this.conversation,
    required this.groupInfo,
    required this.onClose,
    required this.onOpenMembers,
    required this.onAddMember,
    required this.onOpenUser,
    this.onJumpConversation,
  });

  final V2TimConversation conversation;
  final V2TimGroupInfo groupInfo;
  final VoidCallback onClose;
  final void Function(
    TUIGroupProfileModel model,
    List<V2TimGroupMemberFullInfo?> members,
  ) onOpenMembers;
  final Future<void> Function(TUIGroupProfileModel model) onAddMember;
  final void Function(String userID) onOpenUser;
  final void Function(V2TimConversation conversation, MessageAnchor? anchor)?
      onJumpConversation;

  @override
  State<GroupChatSettingsSideCard> createState() =>
      _GroupChatSettingsSideCardState();
}

class _GroupChatSettingsSideCardState extends State<GroupChatSettingsSideCard> {
  final MessageService _messageService = serviceLocator<MessageService>();
  bool _memberPageRequested = false;
  int _imageCount = 0;
  int _videoCount = 0;
  int _fileCount = 0;

  String get _conversationId {
    final id = widget.conversation.conversationID.trim();
    if (id.isNotEmpty) {
      return id;
    }
    final groupId = widget.groupInfo.groupID.trim();
    return groupId.isEmpty ? '' : 'group_$groupId';
  }

  @override
  void initState() {
    super.initState();
    GroupLocalStore.instance.commitListenable.addListener(_onGroupStoreCommit);
    unawaited(_loadCounts());
  }

  @override
  void dispose() {
    GroupLocalStore.instance.commitListenable
        .removeListener(_onGroupStoreCommit);
    super.dispose();
  }

  void _onGroupStoreCommit() {
    if (!mounted) {
      return;
    }
    final groupId = widget.groupInfo.groupID;
    final commit = GroupLocalStore.instance.commitListenable.value;
    if (commit.kind != GroupStoreMutationKind.reset &&
        commit.upserted.isNotEmpty &&
        !commit.upserted.any(
          (record) => ChatIdFormat.groupIdsEquivalent(record.groupId, groupId),
        )) {
      return;
    }
    setState(() {});
  }

  int _resolveMemberCount({
    required String groupId,
    required int? sdkCount,
    required int listedCount,
  }) {
    final local =
        GroupLocalStore.instance.readCached(groupId: groupId)?.memberCount ?? 0;
    if (local > 0) {
      return local;
    }
    if (sdkCount != null && sdkCount > 0) {
      return sdkCount;
    }
    return listedCount;
  }

  void _ensureMemberWindow(TUIGroupProfileModel model) {
    if (_memberPageRequested) {
      return;
    }
    _memberPageRequested = true;
    unawaited(model.loadRemainingMemberPages());
    if (!model.hasLoadedManagementMembers &&
        !model.isManagementMemberListLoading) {
      unawaited(model.loadManagementMembers());
    }
  }

  int _sideCardMemberRole(
    TUIGroupProfileModel model,
    V2TimGroupMemberFullInfo member,
  ) {
    final id = ChatIdFormat.rawUserUid(member.userID);
    final backend = model.backendRoleForMember(id);
    if (backend != null) {
      return backend;
    }
    for (final preview in model.localManagementPreview) {
      if (ChatIdFormat.rawUserUid(preview.userID) == id) {
        return preview.role ??
            GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
      }
    }
    return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
  }

  void _maybeLoadMoreMembers(
    TUIGroupProfileModel model,
    ScrollNotification notification,
  ) {
    if (notification.metrics.extentAfter > 240) {
      return;
    }
    if (!model.hasMoreGroupMembers || model.isGroupMemberListLoadingMore) {
      return;
    }
    unawaited(model.loadMoreGroupMembers());
  }

  Future<void> _loadCounts() async {
    final conversationId = _conversationId;
    final results = await Future.wait<int>([
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
    setState(() {
      _imageCount = results[0];
      _videoCount = results[1];
      _fileCount = results[2];
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

  Future<void> _openMedia({
    ConversationAssetTab tab = ConversationAssetTab.media,
  }) async {
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
        conversation: widget.conversation,
        initialTab: tab,
        embedded: true,
        onTapMessage: (conversation, message) {
          widget.onJumpConversation?.call(conversation, null);
        },
      ),
    );
  }

  Future<void> _openGroupDetail(TUIGroupProfileModel model) async {
    final i18n = AppI18n.of(context);
    await DesktopSideColumnScope.push<void>(
      context,
      title: i18n.t(
        zhHans: '群详情',
        zhHant: '群詳情',
        en: 'Group Info',
        ja: 'グループ情報',
        ko: '그룹 정보',
      ),
      page: GroupInfoDetailPage(
        groupInfo: widget.groupInfo,
        model: model,
      ),
    );
  }

  Future<void> _openManage(TUIGroupProfileModel model) async {
    final i18n = AppI18n.of(context);
    await DesktopSideColumnScope.push<void>(
      context,
      title: i18n.t(
        zhHans: '群管理',
        zhHant: '群管理',
        en: 'Group Manage',
        ja: 'グループ管理',
        ko: '그룹 관리',
      ),
      page: GroupManagePage(
        model: model,
        groupID: widget.groupInfo.groupID,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final i18n = AppI18n.of(context);
    return Consumer<TUIGroupProfileModel>(
      builder: (context, model, _) {
        return _buildCard(context, theme, i18n, model);
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    TUITheme theme,
    AppI18n i18n,
    TUIGroupProfileModel model,
  ) {
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
    final name = (model.groupInfo?.groupName ??
            widget.groupInfo.groupName ??
            widget.conversation.showName ??
            '')
        .trim();
    final face = (model.groupInfo?.faceUrl ??
            widget.groupInfo.faceUrl ??
            widget.conversation.faceUrl ??
            '')
        .trim();
    _ensureMemberWindow(model);
    final members = model
        .membersWithBackendRoles(model.groupMemberList)
        .whereType<V2TimGroupMemberFullInfo>()
        .toList()
      ..sort(
        (a, b) => GroupRolePolicy.memberSortRank(a.role)
            .compareTo(GroupRolePolicy.memberSortRank(b.role)),
      );
    final memberCount = _resolveMemberCount(
      groupId: widget.groupInfo.groupID,
      sdkCount: model.groupInfo?.memberCount ?? widget.groupInfo.memberCount,
      listedCount: members.length,
    );
    final isMuted = (model.conversation?.recvOpt ??
            widget.conversation.recvOpt ??
            0) !=
        0;
    final presence = Provider.of<PresenceProvider>(context);
    final friendship = serviceLocator<TUIFriendShipViewModel>();
    final showOnlineStatus =
        Provider.of<LocalSetting>(context).isShowOnlineStatus;
    final memberIds = members
        .map((item) => item.userID.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (showOnlineStatus) {
      presence.ensure(memberIds, includeVisibility: false);
    }
    final anyoneOnline = showOnlineStatus &&
        members.any((member) {
          final id = member.userID.trim();
          if (id.isEmpty) {
            return false;
          }
          final mutual = friendCanMessage(friendship, id);
          return presence.shouldShowPresence(
                id,
                isMutualFriend: mutual,
              ) &&
              presence.resolveOnline(
                userId: id,
                imOnline: member.isOnline == true,
              );
        });

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

    Widget iconRow({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 16, 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: ink),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 16, color: ink),
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
                    InkWell(
                      onTap: () => unawaited(_openGroupDetail(model)),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Avatar(
                              faceUrl: face,
                              showName: name,
                              type: 2,
                              borderRadius: BorderRadius.circular(36),
                            ),
                            if (anyoneOnline)
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF34C759),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: headerBg,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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
                    const SizedBox(height: 2),
                    Text(
                      i18n.format(
                        zhHans: '{option1}位成员',
                        zhHant: '{option1}位成員',
                        en: '{option1} members',
                        ja: 'メンバー{option1}人',
                        ko: '멤버 {option1}명',
                        vars: {'option1': '$memberCount'},
                      ),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        actionChip(
                          icon: isMuted
                              ? Icons.notifications_off_outlined
                              : Icons.notifications_none_rounded,
                          label: i18n.t(
                            zhHans: '静音',
                            zhHant: '靜音',
                            en: 'Mute',
                            ja: 'ミュート',
                            ko: '음소거',
                          ),
                          onTap: () =>
                              unawaited(model.setMessageDisturb(!isMuted)),
                        ),
                        actionChip(
                          icon: Icons.tune_rounded,
                          label: i18n.t(
                            zhHans: '管理',
                            zhHant: '管理',
                            en: 'Manage',
                            ja: '管理',
                            ko: '관리',
                          ),
                          onTap: () => unawaited(_openManage(model)),
                        ),
                        actionChip(
                          icon: Icons.graphic_eq_rounded,
                          label: i18n.t(
                            zhHans: '视频聊天',
                            zhHant: '視頻聊天',
                            en: 'Video Chat',
                            ja: 'ビデオ通話',
                            ko: '영상 채팅',
                          ),
                          onTap: () => unawaited(
                            CallLauncher.startGroup(
                              context,
                              groupId: widget.groupInfo.groupID,
                              userIds: memberIds,
                              video: true,
                            ),
                          ),
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
          iconRow(
            icon: Icons.image_outlined,
            label: i18n.format(
              zhHans: '{option1}张图片',
              zhHant: '{option1}張圖片',
              en: '{option1} photos',
              ja: '写真{option1}件',
              ko: '사진 {option1}장',
              vars: {'option1': '$_imageCount'},
            ),
            onTap: _openMedia,
          ),
          iconRow(
            icon: Icons.videocam_outlined,
            label: i18n.format(
              zhHans: '{option1}个视频',
              zhHant: '{option1}個視頻',
              en: '{option1} videos',
              ja: '動画{option1}件',
              ko: '동영상 {option1}개',
              vars: {'option1': '$_videoCount'},
            ),
            onTap: _openMedia,
          ),
          iconRow(
            icon: Icons.insert_drive_file_outlined,
            label: i18n.format(
              zhHans: '{option1}个文件',
              zhHant: '{option1}個檔案',
              en: '{option1} files',
              ja: 'ファイル{option1}件',
              ko: '파일 {option1}개',
              vars: {'option1': '$_fileCount'},
            ),
            onTap: () => unawaited(
              _openMedia(tab: ConversationAssetTab.file),
            ),
          ),
          Divider(height: 8, thickness: 6, color: sectionGap),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 8, 8),
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 22, color: ink),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onOpenMembers(
                      model,
                      model.groupMemberList,
                    ),
                    child: Text(
                      i18n.format(
                        zhHans: '{option1}位成员',
                        zhHant: '{option1}位成員',
                        en: '{option1} members',
                        ja: 'メンバー{option1}人',
                        ko: '멤버 {option1}명',
                        vars: {'option1': '$memberCount'},
                      ),
                      style: TextStyle(fontSize: 16, color: ink),
                    ),
                  ),
                ),
                if (model.canInviteMember())
                  IconButton(
                    onPressed: () => unawaited(widget.onAddMember(model)),
                    icon: Icon(Icons.person_add_alt_1_outlined, color: ink),
                  ),
              ],
            ),
          ),
          for (final member in members)
            _memberRow(
              member: member,
              model: model,
              theme: theme,
              pageBg: listBg,
              ink: ink,
              muted: muted,
              presence: presence,
              friendship: friendship,
              showOnlineStatus: showOnlineStatus,
              i18n: i18n,
            ),
          if (model.isGroupMemberListLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
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
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _maybeLoadMoreMembers(model, notification);
          return false;
        },
        child: listView,
      ),
    );
  }

  Widget _memberRow({
    required V2TimGroupMemberFullInfo member,
    required TUIGroupProfileModel model,
    required TUITheme theme,
    required Color pageBg,
    required Color ink,
    required Color muted,
    required PresenceProvider presence,
    required TUIFriendShipViewModel friendship,
    required bool showOnlineStatus,
    required AppI18n i18n,
  }) {
    final userId = member.userID.trim();
    final display = (member.nameCard?.trim().isNotEmpty == true
            ? member.nameCard
            : (member.nickName?.trim().isNotEmpty == true
                ? member.nickName
                : userId)) ??
        userId;
    final mutual = friendCanMessage(friendship, userId);
    final imOnline = member.isOnline == true;
    final online = showOnlineStatus &&
        presence.shouldShowPresence(
          userId,
          isMutualFriend: mutual,
        ) &&
        presence.resolveOnline(userId: userId, imOnline: imOnline);
    final status = showOnlineStatus
        ? presence.onlineLabelFor(
            userId: userId,
            imOnline: imOnline,
            isMutualFriend: mutual,
          )
        : '';
    final loading = showOnlineStatus &&
        presence.isLastSeenLoading(
          userId: userId,
          imOnline: imOnline,
          isMutualFriend: mutual,
        );
    final badgeKey = GroupRolePolicy.roleBadgeKey(
      _sideCardMemberRole(model, member),
    );

    return InkWell(
      onTap: userId.isEmpty ? null : () => widget.onOpenUser(userId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 16, 10),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Avatar(
                    faceUrl: member.faceUrl ?? '',
                    showName: display,
                    type: 1,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  if (online)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759),
                          shape: BoxShape.circle,
                          border: Border.all(color: pageBg, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: ink),
                  ),
                  if (showOnlineStatus) ...[
                    const SizedBox(height: 2),
                    PresenceSubtitle(
                      label: status,
                      loading: loading,
                      imOnline: online,
                      fontSize: 13,
                      offlineColor: muted,
                      skeletonColor: muted.withValues(alpha: 0.28),
                    ),
                  ],
                ],
              ),
            ),
            if (badgeKey != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeKey == 'owner'
                      ? (theme.primaryColor ?? const Color(0xFF1E90FF))
                          .withValues(alpha: 0.12)
                      : const Color(0xFFB86E00).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  badgeKey == 'owner'
                      ? i18n.t(
                          zhHans: '群主',
                          zhHant: '群主',
                          en: 'Owner',
                          ja: 'オーナー',
                          ko: '그룹장',
                        )
                      : i18n.t(
                          zhHans: '管理员',
                          zhHant: '管理員',
                          en: 'Admin',
                          ja: '管理者',
                          ko: '관리자',
                        ),
                  style: TextStyle(
                    fontSize: 11,
                    color: badgeKey == 'owner'
                        ? (theme.primaryColor ?? const Color(0xFF1E90FF))
                        : const Color(0xFFB86E00),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
