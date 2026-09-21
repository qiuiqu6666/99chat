import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/presence_subtitle.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_style_search_bar.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';
import 'red_packet_member.dart';
import 'red_packet_controller.dart';

class RecipientMemberPage {
  const RecipientMemberPage(this.members, this.cursor);
  final List<RedPacketMember> members;
  final String? cursor;
}

typedef RecipientPageLoader = Future<RecipientMemberPage> Function(
    String keyword, String cursor);

/// One request per scroll/button action. Search resets its cursor, and late
/// responses from the previous query cannot overwrite the new results.
class RecipientMemberPager extends ChangeNotifier {
  RecipientMemberPager(this.loadPage);
  final RecipientPageLoader loadPage;
  final Map<String, RedPacketMember> _members = {};
  final Set<String> _visited = {};
  List<RedPacketMember> get members => _members.values.toList(growable: false);
  String keyword = '';
  String? cursor = '';
  bool loading = false;
  bool failed = false;
  int _generation = 0;
  bool _disposed = false;

  Future<void> search(String value) {
    _generation++;
    keyword = value.trim();
    cursor = '';
    loading = false;
    failed = false;
    _members.clear();
    _visited.clear();
    return load();
  }

  Future<void> load() async {
    if (_disposed || loading || cursor == null) return;
    final generation = _generation;
    final requested = cursor!;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final page = await loadPage(keyword, requested);
      if (_disposed || generation != _generation) return;
      if (page.cursor != null &&
          (page.cursor == requested || _visited.contains(page.cursor))) {
        throw StateError('Member cursor did not advance');
      }
      for (final member in page.members) {
        if (member.userId.trim().isNotEmpty) _members[member.userId] = member;
      }
      _visited.add(requested);
      cursor = page.cursor;
    } catch (_) {
      if (!_disposed && generation == _generation) failed = true;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

RecipientPageLoader recipientPageLoader(String rawGroupId,
    {required bool hideMemberIds}) {
  final groupId = ChatIdFormat.normalizeGroupId(rawGroupId);
  final identity = SessionIdentityService.instance.capture();
  return (keyword, cursor) async {
    void checkAccount() {
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        throw StateError('Account changed');
      }
    }

    bool matches(RedPacketMember member) =>
        !RedPacketController.isSelfUserId(member.userId) &&
        (keyword.isEmpty ||
            member.name.toLowerCase().contains(keyword.toLowerCase()) ||
            (!hideMemberIds &&
                member.userId.toLowerCase().contains(keyword.toLowerCase())));
    checkAccount();
    if (keyword.isNotEmpty &&
        !cursor.startsWith('scan:') &&
        !cursor.startsWith('db:')) {
      final page = await GroupMemberCloudSearch.searchPage(
          groupId: groupId, keyword: keyword, cursor: cursor);
      checkAccount();
      if (page.usedCloud) {
        return RecipientMemberPage(
            page.members
                .map(RedPacketMember.fromGroupMember)
                .where(matches)
                .toList(),
            page.isFinished ? null : page.nextCursor);
      }
    }
    if (keyword.isNotEmpty && !cursor.startsWith('scan:')) {
      final complete = await GroupMemberLocalStore.instance
          .readCompleteSnapshotCount(
              groupId: groupId, ownerUserId: identity.ownerUserId);
      checkAccount();
      if (complete != null) {
        final offset = int.tryParse(cursor.replaceFirst('db:', '')) ?? 0;
        final records = await GroupMemberLocalStore.instance.readWindow(
            groupId: groupId,
            ownerUserId: identity.ownerUserId,
            keyword: keyword,
            offset: offset,
            limit: 100);
        checkAccount();
        return RecipientMemberPage(
            records
                .map((r) => RedPacketMember(
                      userId: r.userId,
                      name: r.friendRemark.trim().isNotEmpty
                          ? r.friendRemark
                          : r.displayName,
                      publicName: r.nickname,
                      avatar: r.avatarUrl,
                    ))
                .where(matches)
                .toList(),
            records.length < 100 ? null : 'db:${offset + 100}');
      }
    }
    final sourceCursor =
        cursor.startsWith('scan:') ? cursor.substring(5) : cursor;
    final response = await GroupMembershipSyncService.instance
        .loadGroupMemberPage(
            groupID: groupId,
            count: 100,
            nextSeq: sourceCursor.isEmpty ? '0' : sourceCursor);
    checkAccount();
    if (response.code != 0 || response.data == null) {
      throw StateError('Unable to load members');
    }
    final next = response.data!.nextSeq?.trim() ?? '0';
    return RecipientMemberPage(
      (response.data!.memberInfoList ?? [])
          .map(RedPacketMember.fromGroupMember)
          .where(matches)
          .toList(),
      next.isEmpty || next == '0'
          ? null
          : keyword.isEmpty
              ? next
              : 'scan:$next',
    );
  };
}

class PagedGroupRecipientPicker extends StatefulWidget {
  const PagedGroupRecipientPicker(
      {super.key,
      required this.groupId,
      this.hideMemberIds = false,
      this.title});
  final String groupId;
  final bool hideMemberIds;
  final String? title;
  @override
  State<PagedGroupRecipientPicker> createState() =>
      _PagedGroupRecipientPickerState();
}

class _PagedGroupRecipientPickerState extends State<PagedGroupRecipientPicker> {
  late final RecipientMemberPager _pager;
  final _search = TextEditingController();
  Timer? _debounce;
  final _presenceRequested = <String>{};
  final _presencePending = <String>{};
  final _online = <String, bool>{};
  bool _presenceScheduled = false;

  void _queueVisiblePresence(String id) {
    if (_presenceRequested.contains(id)) return;
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
        context.read<PresenceProvider>().ensure(ids);
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

  @override
  void initState() {
    super.initState();
    _pager = RecipientMemberPager(recipientPageLoader(widget.groupId,
        hideMemberIds: widget.hideMemberIds))
      ..addListener(_changed);
    unawaited(_pager.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pager.removeListener(_changed);
    _pager.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final members = _pager.members;
    final canLoad = _pager.cursor != null;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.title ??
              i18n.t(
                  zhHans: '选择接收人',
                  zhHant: '選擇接收人',
                  en: 'Select recipient',
                  ja: '受取人を選択',
                  ko: '수령인 선택'))),
      body: Column(children: [
        ContactStyleSearchBar(
            controller: _search,
            showCancel: false,
            hint: i18n.t(
                zhHans: '搜索成员',
                zhHant: '搜尋成員',
                en: 'Search members',
                ja: 'メンバーを検索',
                ko: '멤버 검색'),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300),
                  () => unawaited(_pager.search(value)));
            }),
        if (_pager.loading) const LinearProgressIndicator(),
        Expanded(
            child: NotificationListener<ScrollNotification>(
          onNotification: (event) {
            if (event is ScrollUpdateNotification &&
                event.metrics.extentAfter < 250 &&
                !_pager.failed &&
                _debounce?.isActive != true) {
              unawaited(_pager.load());
            }
            return false;
          },
          child: ListView.builder(
              itemCount: members.length + 1,
              itemBuilder: (_, index) {
                if (index == members.length) {
                  if (_pager.loading) return const SizedBox(height: 48);
                  if (canLoad) {
                    return TextButton(
                        onPressed: () => unawaited(_pager.load()),
                        child: Text(_pager.failed
                            ? i18n.t(
                                zhHans: '加载失败，点击重试',
                                zhHant: '載入失敗，點擊重試',
                                en: 'Retry',
                                ja: '再試行',
                                ko: '다시 시도')
                            : i18n.t(
                                zhHans: '加载更多成员',
                                zhHant: '載入更多成員',
                                en: 'Load more members',
                                ja: 'さらに読み込む',
                                ko: '더 불러오기')));
                  }
                  return members.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                              child: Text(i18n.t(
                                  zhHans: '未找到相关成员',
                                  zhHant: '未找到相關成員',
                                  en: 'No matching members',
                                  ja: '該当するメンバーがいません',
                                  ko: '일치하는 멤버 없음'))))
                      : const SizedBox.shrink();
                }
                final member = members[index];
                _queueVisiblePresence(member.userId);
                return ListTile(
                  leading: AppUserAvatar(
                      faceUrl: member.avatar,
                      showName: member.name,
                      ownerId: member.userId,
                      preferRasterPlaceholder: true,
                      size: 42),
                  title: Text(member.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Selector<PresenceProvider, int>(
                    selector: (_, presence) =>
                        presence.revisionFor(member.userId),
                    builder: (context, _, __) {
                      final presence = context.read<PresenceProvider>();
                      final online = _online[member.userId] == true;
                      final mutual = friendCanMessage(
                          serviceLocator<TUIFriendShipViewModel>(),
                          member.userId);
                      return PresenceSubtitle(
                        label: presence.onlineLabelFor(
                            userId: member.userId,
                            imOnline: online,
                            isMutualFriend: mutual),
                        loading: presence.isLastSeenLoading(
                            userId: member.userId, imOnline: online),
                        imOnline: online,
                        fontSize: 13,
                        height: 1.2,
                        onlineColor: Theme.of(context).colorScheme.primary,
                        offlineColor:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      );
                    },
                  ),
                  onTap: () => Navigator.of(context).pop(member),
                );
              }),
        )),
      ]),
    );
  }
}
