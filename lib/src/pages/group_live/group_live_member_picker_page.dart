import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_member.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_style_search_bar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/presence_subtitle.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';

import 'group_live_member_loader.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';

class GroupLiveMemberPickerPage extends StatefulWidget {
  const GroupLiveMemberPickerPage({super.key, required this.loadPage});
  final GroupLiveMemberPageLoader loadPage;

  @override
  State<GroupLiveMemberPickerPage> createState() =>
      _GroupLiveMemberPickerPageState();
}

class _GroupLiveMemberPickerPageState extends State<GroupLiveMemberPickerPage> {
  late final GroupLiveMemberLoader _loader;
  final _search = TextEditingController();
  final _presenceRequested = <String>{};
  final _presencePending = <String>{};
  final _online = <String, bool>{};
  bool _presenceScheduled = false;

  @override
  void initState() {
    super.initState();
    _loader = GroupLiveMemberLoader(widget.loadPage)..addListener(_changed);
    unawaited(_loader.load());
  }

  void _queueVisiblePresence(String id) {
    if (id.isEmpty || _presenceRequested.contains(id)) return;
    _presencePending.add(id);
    if (_presenceScheduled) return;
    _presenceScheduled = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_loadVisiblePresence()));
  }

  Future<void> _loadVisiblePresence() async {
    try {
      while (mounted && _presencePending.isNotEmpty) {
        final ids = _presencePending.take(40).toList();
        _presencePending.removeAll(ids);
        _presenceRequested.addAll(ids);
        try {
          context.read<PresenceProvider>().ensure(ids);
        } catch (_) {}
        try {
          final statuses = await serviceLocator<FriendshipServices>()
              .getUserStatus(userIDList: ids);
          if (!mounted) return;
          setState(() {
            for (final status in statuses) {
              final id = status.userID;
              if (id != null) _online[id] = status.statusType == 1;
            }
          });
        } catch (_) {}
      }
    } finally {
      _presenceScheduled = false;
    }
  }

  bool _isMutualFriend(String userId) {
    try {
      return friendCanMessage(serviceLocator<TUIFriendShipViewModel>(), userId);
    } catch (_) {
      return false;
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _loader.removeListener(_changed);
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final keyword = _search.text.trim().toLowerCase();
    final members = _loader.members
        .where((member) =>
            member.name.toLowerCase().contains(keyword) ||
            member.userId.toLowerCase().contains(keyword))
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: Text(i18n.t(
            zhHans: '选择主播',
            zhHant: '選擇主播',
            en: 'Select anchor',
            ja: 'アンカーを選択',
            ko: '앵커 선택',
          ))),
      body: Column(children: [
        ContactStyleSearchBar(
          controller: _search,
          onChanged: (_) => setState(() {}),
          hint: i18n.t(
              zhHans: _loader.complete ? '搜索成员' : '搜索已加载的成员',
              zhHant: _loader.complete ? '搜尋成員' : '搜尋已載入的成員',
              en: _loader.complete ? 'Search members' : 'Search loaded members',
              ja: 'メンバーを検索',
              ko: '멤버 검색'),
          showCancel: false,
        ),
        if (_loader.loading) ...[
          const LinearProgressIndicator(),
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text(i18n.t(
                zhHans: '正在加载群成员…',
                zhHant: '正在載入群成員…',
                en: 'Loading group members…',
                ja: 'メンバーを読み込み中…',
                ko: '멤버 로딩 중…',
              ))),
        ],
        if (_loader.failed)
          TextButton.icon(
            onPressed: () => unawaited(_loader.load()),
            icon: const Icon(Icons.refresh),
            label: Text(i18n.t(
              zhHans: '成员未加载完整，点击重试',
              zhHant: '成員未載入完整，點擊重試',
              en: 'Member list incomplete. Tap to retry',
              ja: '読み込みが未完了です。再試行',
              ko: '멤버 로드 미완료. 다시 시도',
            )),
          ),
        if (!_loader.complete && !_loader.loading && !_loader.failed)
          TextButton(
              onPressed: () => unawaited(_loader.load()),
              child: Text(i18n.t(
                  zhHans: '加载更多成员',
                  zhHant: '載入更多成員',
                  en: 'Load more members'))),
        Expanded(
            child: members.isEmpty
                ? Center(
                    child: Text(_loader.complete
                        ? i18n.t(
                            zhHans: '未找到相关成员',
                            zhHant: '未找到相關成員',
                            en: 'No matching members',
                            ja: '該当するメンバーがいません',
                            ko: '일치하는 멤버 없음',
                          )
                        : ''))
                : ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      _queueVisiblePresence(member.userId);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: AppUserAvatar(
                                faceUrl: member.avatar,
                                showName: member.name,
                                ownerId: member.userId,
                                preferRasterPlaceholder: true,
                                size: 42),
                            title: Text(member.name),
                            subtitle: _ContactStylePresenceSubtitle(
                              userId: member.userId,
                              imOnline: _online[member.userId] == true,
                              isMutualFriend: _isMutualFriend(member.userId),
                            ),
                            onTap: () => Navigator.of(context)
                                .pop<RedPacketMember>(member),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 74),
                            child: Container(
                              height: DirectoryListStyle.dividerThickness,
                              color: DirectoryListStyle.dividerColor(context),
                            ),
                          ),
                        ],
                      );
                    },
                  )),
      ]),
    );
  }
}

class _ContactStylePresenceSubtitle extends StatelessWidget {
  const _ContactStylePresenceSubtitle({
    required this.userId,
    required this.imOnline,
    required this.isMutualFriend,
  });

  final String userId;
  final bool imOnline;
  final bool isMutualFriend;

  @override
  Widget build(BuildContext context) {
    PresenceProvider? presence;
    try {
      presence = Provider.of<PresenceProvider>(context, listen: false);
    } on ProviderNotFoundException {
      presence = null;
    }
    if (presence == null) {
      return PresenceSubtitle(
        label: '',
        loading: false,
        imOnline: false,
        fontSize: DirectoryListStyle.subtitleSize,
        height: DirectoryListStyle.lineHeight,
        offlineColor: hexToColor('999999'),
      );
    }
    return Selector<PresenceProvider, int>(
      selector: (_, provider) => provider.revisionFor(userId),
      builder: (context, _, __) {
        final current = context.read<PresenceProvider>();
        final resolvedOnline = current.resolveOnline(
          userId: userId,
          imOnline: imOnline,
        );
        final loading = current.isLastSeenLoading(
          userId: userId,
          imOnline: resolvedOnline,
          isMutualFriend: isMutualFriend,
        );
        return PresenceSubtitle(
          label: loading
              ? ''
              : current.listLabelFor(
                  userId: userId,
                  imOnline: resolvedOnline,
                  isMutualFriend: isMutualFriend,
                ),
          loading: loading,
          imOnline: false,
          fontSize: DirectoryListStyle.subtitleSize,
          height: DirectoryListStyle.lineHeight,
          offlineColor: hexToColor('999999'),
          skeletonColor: hexToColor('999999'),
        );
      },
    );
  }
}
