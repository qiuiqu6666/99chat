import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_style_search_bar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/presence_subtitle.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

import 'red_packet_member.dart';
import 'paged_group_recipient_picker.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/widgets/wallet_page_colors.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';

Future<RedPacketMember?> pickRedPacketMember(
  BuildContext context, {
  required List<RedPacketMember> members,
  bool hideMemberIds = false,
  String? title,
  bool enablePresence = true,
  String? groupId,
}) {
  return Navigator.of(context).push<RedPacketMember>(
    AppMaterialPageRoute(
      builder: (_) => groupId != null && groupId.trim().isNotEmpty
          ? PagedGroupRecipientPicker(groupId: groupId, hideMemberIds: hideMemberIds, title: title)
          : RedPacketMemberPickerPage(
        members: members,
        hideMemberIds: hideMemberIds,
        title: title,
        enablePresence: enablePresence,
      ),
    ),
  );
}

class RedPacketMemberPickerPage extends StatefulWidget {
  final List<RedPacketMember> members;
  final bool hideMemberIds;
  final String? title;
  final bool enablePresence;

  const RedPacketMemberPickerPage({
    super.key,
    required this.members,
    this.hideMemberIds = false,
    this.title,
    this.enablePresence = true,
  });

  @override
  State<RedPacketMemberPickerPage> createState() =>
      _RedPacketMemberPickerPageState();
}

class _RedPacketMemberPickerPageState extends State<RedPacketMemberPickerPage> {
  final TextEditingController _searchController = TextEditingController();
  final TUIFriendShipViewModel _friendShipModel =
      serviceLocator<TUIFriendShipViewModel>();
  Map<String, V2TimUserStatus> _userStatusById = {};
  PresenceProvider? _presence;

  @override
  void initState() {
    super.initState();
    if (!widget.enablePresence) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _presence = Provider.of<PresenceProvider>(context, listen: false);
      _presence!.addListener(_onPresenceChanged);
      unawaited(_loadPresenceData());
    });
  }

  @override
  void dispose() {
    _presence?.removeListener(_onPresenceChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onPresenceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPresenceData() async {
    final ids = widget.members
        .map((member) => member.userId.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final presence = Provider.of<PresenceProvider>(context, listen: false);
    presence.ensure(ids);

    const chunkSize = 500;
    final merged = <String, V2TimUserStatus>{};
    final friendshipServices = serviceLocator<FriendshipServices>();
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, min(i + chunkSize, ids.length));
      try {
        final statuses =
            await friendshipServices.getUserStatus(userIDList: chunk);
        for (final status in statuses) {
          final id = status.userID?.trim() ?? '';
          if (id.isNotEmpty) {
            merged[id] = status;
          }
        }
      } catch (_) {}
    }

    if (!mounted) {
      return;
    }
    setState(() => _userStatusById = merged);
  }

  bool _isImOnline(String userId) {
    return _userStatusById[userId]?.statusType == 1;
  }

  String _presenceLabel(String userId) {
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    return presence.onlineLabelFor(
      userId: userId,
      imOnline: _isImOnline(userId),
      isMutualFriend: friendCanMessage(_friendShipModel, userId),
    );
  }

  bool _matches(RedPacketMember item, String keyword) {
    if (keyword.isEmpty) return true;
    final k = keyword.toLowerCase();
    if (item.name.toLowerCase().contains(k)) {
      return true;
    }
    // 群隐私保护开启时，禁止用 userId/qq 搜索，避免暴露成员 ID。
    if (widget.hideMemberIds) {
      return false;
    }
    return item.userId.toLowerCase().contains(k) ||
        item.qq.toLowerCase().contains(k);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final colors = WalletPageColors.of(context);
    final keyword = _searchController.text.trim();
    final list =
        widget.members.where((item) => _matches(item, keyword)).toList();

    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: theme.weakBackgroundColor ?? Colors.white,
        appBar: AppBar(
          centerTitle: true,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          backgroundColor: theme.appbarBgColor ?? theme.weakBackgroundColor,
          systemOverlayStyle: walletPageOverlayStyle(context),
          title: Text(
            widget.title ??
                i18n.t(
                  zhHans: '选择接收人',
                  zhHant: '選擇接收人',
                  en: 'Select recipient',
                  ja: '受取人を選択',
                  ko: '수령인 선택',
                ),
            style: TextStyle(
              color: theme.appbarTextColor ?? theme.darkTextColor,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconTheme: IconThemeData(
            color: theme.primaryColor ?? const Color(0xFF1E90FF),
          ),
        ),
        body: Column(
          children: [
            ContactStyleSearchBar(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              hint: i18n.t(
                zhHans: '搜索成员',
                zhHant: '搜尋成員',
                en: 'Search members',
                ja: 'メンバーを検索',
                ko: '멤버 검색',
              ),
              showCancel: false,
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        keyword.isEmpty
                            ? i18n.t(
                                zhHans: '暂无成员',
                                zhHant: '暫無成員',
                                en: 'No members yet',
                                ja: 'メンバーがいません',
                                ko: '멤버가 없습니다',
                              )
                            : i18n.t(
                                zhHans: '未找到相关成员',
                                zhHant: '未找到相關成員',
                                en: 'No matching members',
                                ja: '該当するメンバーが見つかりません',
                                ko: '관련 멤버를 찾을 수 없습니다',
                              ),
                        style: TextStyle(
                          color: theme.weakTextColor ?? Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final item = list[i];
                        if (!widget.enablePresence) {
                          return _SimpleMemberTile(
                            item: item,
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        }
                        final imOnline = _isImOnline(item.userId);
                        final presence = Provider.of<PresenceProvider>(
                          context,
                          listen: false,
                        );
                        final presenceLoading = presence.isLastSeenLoading(
                          userId: item.userId,
                          imOnline: imOnline,
                        );
                        final presenceLabel =
                            presenceLoading ? '' : _presenceLabel(item.userId);
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(item),
                          child: Container(
                            height: 74,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                _MemberPickerAvatar(item: item),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colors.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      PresenceSubtitle(
                                        label: presenceLabel,
                                        loading: presenceLoading,
                                        imOnline: imOnline,
                                        fontSize: 13,
                                        height: 1.2,
                                        onlineColor: theme.primaryColor ??
                                            const Color(0xFF1E90FF),
                                        offlineColor: theme.weakTextColor ??
                                            const Color(0xFF999999),
                                        skeletonColor: theme.weakTextColor,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 22,
                                  color: colors.subText,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberPickerAvatar extends StatelessWidget {
  const _MemberPickerAvatar({required this.item});

  final RedPacketMember item;

  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    final displayName =
        item.name.trim().isNotEmpty ? item.name.trim() : item.userId;
    return AppUserAvatar(
      faceUrl: item.avatar,
      showName: displayName,
      size: _size,
    );
  }
}

class _SimpleMemberTile extends StatelessWidget {
  const _SimpleMemberTile({
    required this.item,
    required this.onTap,
  });

  final RedPacketMember item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _MemberPickerAvatar(item: item),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: colors.subText,
            ),
          ],
        ),
      ),
    );
  }
}
