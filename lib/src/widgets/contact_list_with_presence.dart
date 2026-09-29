import 'contact_projection_merge.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';

import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_activity.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/starred_friend_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_list_pressable.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/presence_subtitle.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/user_display_profile.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';

class ContactListWithPresence extends StatefulWidget {
  /// Optional explicit projection supplied by a local data source. When set,
  /// the UIKit friendship list is not used to build contact rows.
  final List<V2TimFriendInfo>? friends;
  final void Function(V2TimFriendInfo item)? onTapItem;
  final void Function(V2TimFriendInfo item)? onLongPressItem;
  final List<TopListItem>? topList;
  final Widget? Function(TopListItem item)? topListItemBuilder;
  final Widget Function(BuildContext context)? emptyBuilder;
  final bool isShowOnlineStatus;
  final bool Function(V2TimFriendInfo item)? filterItem;

  /// Stable caller-owned key/version for filter state. Avoids comparing the
  /// predicate closure while still invalidating projection when its captures
  /// change.
  final Object? filterKey;
  final int filterRevision;
  final bool showContactCount;
  final String? footerLabel;

  const ContactListWithPresence({
    Key? key,
    this.friends,
    this.onTapItem,
    this.onLongPressItem,
    this.topList,
    this.topListItemBuilder,
    this.emptyBuilder,
    this.isShowOnlineStatus = true,
    this.filterItem,
    this.filterKey,
    this.filterRevision = 0,
    this.showContactCount = false,
    this.footerLabel,
  }) : super(key: key);

  @override
  State<ContactListWithPresence> createState() =>
      _ContactListWithPresenceState();
}

class _ContactListWithPresenceState extends State<ContactListWithPresence> {
  final TUIFriendShipViewModel _friendShipModel =
      serviceLocator<TUIFriendShipViewModel>();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  static const int _presenceBufferRows = 4;
  static const int _firstScreenPrefetch = 12;
  static const Duration _presenceDebounce = Duration(milliseconds: 200);

  Timer? _presenceDebounceTimer;
  Timer? _projectionSettleTimer;
  bool _scrolling = false;
  bool _projectionPending = false;
  bool _workEnabled = true;
  bool _workGateResolved = false;
  String? _lastPresenceEnsureKey;
  List<ISuspensionBeanImpl>? _cachedShowList;
  List<ISuspensionBeanImpl> _effectiveList = const [];
  List<V2TimFriendInfo> _filteredFriends = const [];
  List<V2TimFriendInfo>? _friendSource;
  int _friendListRevision = -1;
  List<V2TimUserStatus>? _statusSource;
  Map<String, V2TimUserStatus> _statusByUserId = const {};
  final Map<String, _ContactProjectionMeta> _projectionMetaCache = {};
  final Map<String, _ContactRowCacheEntry> _contactRowCache = {};
  final Set<String> _materializedIds = <String>{};
  final List<V2TimFriendInfo> _directoryFriends = <V2TimFriendInfo>[];
  bool _directoryPumping = false;
  bool _directoryNeedsPump = false;
  List<String> _projectionIds = const [];
  int _projectionCursor = 0;
  int _projectionRevision = -1;
  SessionIdentity? _projectionIdentity;
  final List<V2TimFriendInfo> _projectionPendingRows = [];
  final Map<String, int> _directoryRowIndex = {};

  static const double _nameStatusGap = DirectoryListStyle.textGap;
  static const double _textBlockNudgeUp = 0;
  static const BorderRadius _contactAvatarBorderRadius =
      BorderRadius.all(Radius.circular(999));

  bool _useDesktopListMetrics(BuildContext context) =>
      kIsWeb || TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;

  double _avatarSize({required bool isDesktop}) =>
      DirectoryListStyle.avatarSize(isDesktop);

  double _avatarTextGap({required bool isDesktop}) =>
      DirectoryListStyle.avatarTextGap;

  double _rowVerticalPadding({required bool isDesktop}) =>
      DirectoryListStyle.verticalPadding;

  double _itemMinHeight({required bool isDesktop}) =>
      DirectoryListStyle.rowHeight(context, desktop: isDesktop);

  double _dividerInset({required bool isDesktop}) =>
      16.0 +
      _avatarSize(isDesktop: isDesktop) +
      _avatarTextGap(isDesktop: isDesktop);

  @override
  void initState() {
    super.initState();
    _friendShipModel.addListener(_onFriendshipModelChanged);
    StarredFriendProvider.shared.addListener(_onStarredChanged);
    PeerProfileRefreshBus.instance.revision.addListener(_onPeerProfileRefresh);
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
    if (widget.friends == null) {
      ImSdkRelationshipDirectory.instance.addListener(_onDirectoryChange);
    }
    _refreshContactProjection(notify: false);
    if (widget.friends == null &&
        ImSdkRelationshipDirectory.instance.hasCompleteFriendSnapshot) {
      unawaited(_pumpDirectoryProjection(notifyFirstBatch: false));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Joins home-tab enter via FriendRequestNoticeService single-flight.
      unawaited(
        FriendRequestNoticeService.instance.enterContactDataSource(
          reason: 'contact_list_widget',
        ),
      );
      if (widget.friends == null) {
        unawaited(
          ImSdkRelationshipReconcileService.instance.requestFirstSnapshot(
            reason: 'enter_contacts',
          ),
        );
      }
      unawaited(StarredFriendProvider.shared.refresh(force: false));
      final presence = Provider.of<PresenceProvider>(context, listen: false);
      unawaited(presence.hydrateFromLocalCache());
      _prefetchFirstScreenPresence();
      _ensureVisibleProfiles();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep compatibility with the project's declared Flutter >=3.19 floor.
    // ignore: deprecated_member_use
    final tabActive = HomeTabActivity.isActiveOf(context);
    final tickerEnabled = TickerMode.of(context);
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final enabled = tabActive && tickerEnabled && routeCurrent;
    final changed = !_workGateResolved || enabled != _workEnabled;
    _workGateResolved = true;
    _workEnabled = enabled;
    if (!changed) return;
    if (!enabled) {
      _presenceDebounceTimer?.cancel();
      _projectionSettleTimer?.cancel();
      _scrolling = false;
      _lastPresenceEnsureKey = null;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_workEnabled) return;
      _flushPendingDirectoryProjection();
      _prefetchFirstScreenPresence();
    });
  }

  void _flushPendingDirectoryProjection() {
    if (!_workEnabled || _scrolling) return;
    final refresh = _projectionPending;
    final pump = _directoryNeedsPump || _shouldPumpDirectory();
    _projectionPending = false;
    _directoryNeedsPump = false;
    // Rebuild from the updated materialized rows before appending new friends.
    // Otherwise a deletion made under another route stays in the cached AZ rows.
    if (refresh) _refreshContactProjection(force: true);
    if (pump) unawaited(_pumpDirectoryProjection());
  }

  @override
  void dispose() {
    _presenceDebounceTimer?.cancel();
    _projectionSettleTimer?.cancel();
    _friendShipModel.removeListener(_onFriendshipModelChanged);
    ImSdkRelationshipDirectory.instance.removeListener(_onDirectoryChange);
    StarredFriendProvider.shared.removeListener(_onStarredChanged);
    PeerProfileRefreshBus.instance.revision
        .removeListener(_onPeerProfileRefresh);
    _itemPositionsListener.itemPositions
        .removeListener(_onItemPositionsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ContactListWithPresence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.friends, widget.friends)) {
      _projectionRevision = -1;
      _projectionIds = const [];
      _projectionCursor = 0;
    }
    // Do not compare or rebuild from a freshly-created predicate on every
    // parent build. Search callers should provide a new friends projection;
    // presence and ordinary parent rebuilds must not enter this path.
    if (!identical(oldWidget.friends, widget.friends) ||
        oldWidget.filterKey != widget.filterKey ||
        oldWidget.filterRevision != widget.filterRevision) {
      _refreshContactProjection(force: true);
    } else if (oldWidget.topList != widget.topList ||
        oldWidget.showContactCount != widget.showContactCount ||
        oldWidget.footerLabel != widget.footerLabel) {
      _composeContactEntries();
    }
  }

  void _onPeerProfileRefresh() {
    if (!mounted) return;
    if (!_workEnabled) {
      _projectionPending = true;
      return;
    }
    // 昵称变化会改变通讯录首字母分组，必须在监听阶段重建结构投影。
    _refreshContactProjection(force: true);
  }

  void _onStarredChanged() {
    if (!mounted) return;
    if (!_workEnabled) {
      _projectionPending = true;
      return;
    }
    _refreshContactProjection(force: true);
  }

  void _onDirectoryChange(RelationshipDirectoryChange change) {
    if (!mounted || widget.friends != null) {
      return;
    }
    if (change.kind != RelationshipListKind.friends) {
      return;
    }
    if (!_workEnabled || _scrolling) {
      _applyDirectoryIncremental(change, deferProjection: true);
      _projectionPending = true;
      if (change.snapshotCompleted || change.addedIds.isNotEmpty) {
        _directoryNeedsPump = true;
      }
      return;
    }
    if (change.snapshotCompleted) {
      unawaited(_pumpDirectoryProjection());
      return;
    }
    _applyDirectoryIncremental(change);
  }

  bool get _usesDirectoryProjection =>
      widget.friends == null &&
      (ImSdkRelationshipDirectory.instance.hasCompleteFriendSnapshot ||
          _directoryFriends.isNotEmpty);

  bool _shouldPumpDirectory() {
    return widget.friends == null &&
        ImSdkRelationshipDirectory.instance.hasCompleteFriendSnapshot &&
        _directoryFriends.isEmpty &&
        !_directoryPumping;
  }

  Future<void> _pumpDirectoryProjection({bool notifyFirstBatch = true}) async {
    if (_directoryPumping) {
      _directoryNeedsPump = true;
      return;
    }
    if (!_workGateResolved || !_workEnabled || _scrolling) {
      _directoryNeedsPump = true;
      return;
    }
    _directoryPumping = true;
    var firstBatch = true;
    try {
      final directory = ImSdkRelationshipDirectory.instance;
      while (mounted && widget.friends == null) {
        if (!_workEnabled || _scrolling) {
          _directoryNeedsPump = true;
          return;
        }
        final identity = SessionIdentityService.instance.capture();
        if (_projectionIdentity != identity) {
          _projectionIdentity = identity;
          _projectionRevision = -1;
          _materializedIds.clear();
          _directoryFriends.clear();
          _directoryRowIndex.clear();
          _projectionPendingRows.clear();
          _cachedShowList = null;
          _filteredFriends = const [];
          _effectiveList = const [];
          _composeContactEntries();
          if (notifyFirstBatch && mounted) setState(() {});
        }
        if (_projectionRevision != directory.friendRevision) {
          // One immutable ID snapshot per revision; never rescan the whole
          // already-materialized prefix for each small construction slice.
          for (final row in _projectionPendingRows) {
            _materializedIds.remove(row.userID);
          }
          _projectionPendingRows.clear();
          _projectionIds = directory.friendOrderedIds;
          _projectionCursor = 0;
          _projectionRevision = directory.friendRevision;
        }
        final target = contactProjectionPublishSize(_directoryFriends.length,
            firstScreen: ImSdkRelationshipPerf.firstScreenCount);
        var processed = 0;
        while (_projectionCursor < _projectionIds.length &&
            processed < 80 &&
            _projectionPendingRows.length < target) {
          final id = _projectionIds[_projectionCursor++];
          processed++;
          if (!_materializedIds.add(id)) continue;
          if (PlatformOfficialAccountService.shouldHideFromContactAndPickers(
              id)) continue;
          final entry = directory.friend(id);
          if (entry == null) continue;
          final info = entry.toV2TimFriendInfo();
          _projectionMeta(info);
          _projectionPendingRows.add(info);
        }
        final exhausted = _projectionCursor >= _projectionIds.length;
        if (_projectionPendingRows.isNotEmpty &&
            (_projectionPendingRows.length >= target || exhausted)) {
          final added = List<V2TimFriendInfo>.of(_projectionPendingRows);
          _projectionPendingRows.clear();
          for (final row in added) {
            _directoryRowIndex[row.userID] = _directoryFriends.length;
            _directoryFriends.add(row);
          }
          final notify = !firstBatch || notifyFirstBatch;
          firstBatch = false;
          _appendFriendsToAz(added, notify: notify);
        }
        if (exhausted) break;
        await Future<void>.delayed(ImSdkRelationshipPerf.stageYield);
      }
    } finally {
      _directoryPumping = false;
      if (_workEnabled && !_scrolling) _ensureVisibleProfiles();
      if (_directoryNeedsPump && mounted && _workEnabled && !_scrolling) {
        _directoryNeedsPump = false;
        unawaited(_pumpDirectoryProjection());
      }
    }
  }

  void _applyDirectoryIncremental(
    RelationshipDirectoryChange change, {
    bool deferProjection = false,
  }) {
    final directory = ImSdkRelationshipDirectory.instance;
    var mutated = false;
    if (change.removedIds.isNotEmpty) {
      final removed = change.removedIds.toSet();
      _materializedIds.removeAll(removed);
      _directoryFriends.removeWhere((row) => removed.contains(row.userID));
      _projectionPendingRows.removeWhere((row) => removed.contains(row.userID));
      _directoryRowIndex.clear();
      for (var i = 0; i < _directoryFriends.length; i++) {
        _directoryRowIndex[_directoryFriends[i].userID] = i;
      }
      for (final id in removed) {
        _projectionMetaCache.remove(id);
        _contactRowCache.remove(id);
      }
      mutated = true;
    }
    final changed = {...change.metadataChangedIds, ...change.sortKeyChangedIds};
    for (final id in changed) {
      final index = _directoryRowIndex[id];
      final entry = directory.friend(id);
      if (index == null || entry == null) continue;
      _directoryFriends[index] = entry.toV2TimFriendInfo();
      mutated = true;
    }
    if (deferProjection) return;
    if (mutated && _cachedShowList != null)
      _refreshContactProjection(force: true);
    if (change.addedIds.isNotEmpty || change.snapshotCompleted) {
      unawaited(_pumpDirectoryProjection());
    }
  }

  int _compareContactRows(ISuspensionBeanImpl a, ISuspensionBeanImpl b) {
    final left = a.memberInfo as V2TimFriendInfo;
    final right = b.memberInfo as V2TimFriendInfo;
    if (a.tagIndex != b.tagIndex) {
      if (a.tagIndex == '★' || b.tagIndex == '#') return -1;
      if (b.tagIndex == '★' || a.tagIndex == '#') return 1;
      return a.tagIndex.compareTo(b.tagIndex);
    }
    if (a.tagIndex == '★') {
      final ta = StarredFriendProvider.shared.starredAtOf(left.userID);
      final tb = StarredFriendProvider.shared.starredAtOf(right.userID);
      if (ta != null && tb != null && ta != tb) return tb.compareTo(ta);
      if (ta == null && tb != null) return 1;
      if (tb == null && ta != null) return -1;
    }
    final directory = ImSdkRelationshipDirectory.instance;
    final byKey = (directory.friend(left.userID)?.sortKey ?? left.userID)
        .compareTo(directory.friend(right.userID)?.sortKey ?? right.userID);
    return byKey != 0 ? byKey : left.userID.compareTo(right.userID);
  }

  void _appendFriendsToAz(List<V2TimFriendInfo> added, {bool notify = true}) {
    if (added.isEmpty) return;
    final current = (_cachedShowList ?? const <ISuspensionBeanImpl>[])
        .where((row) => row.memberInfo is V2TimFriendInfo)
        .toList();
    final accepted =
        added.where((row) => widget.filterItem?.call(row) ?? true).toList();
    final next = [
      for (final row in accepted)
        ISuspensionBeanImpl(
            memberInfo: row,
            tagIndex: StarredFriendProvider.shared.isStarred(row.userID)
                ? '★'
                : _projectionMeta(row).indexTag)
    ];
    _cachedShowList =
        mergeContactProjection(current, next, _compareContactRows);
    _filteredFriends = [..._filteredFriends, ...accepted];
    _composeContactEntries();
    if (notify && mounted) setState(() {});
  }

  void _onFriendshipModelChanged() {
    if (!mounted || widget.friends != null) return;
    if (_usesDirectoryProjection) {
      final statuses = _friendShipModel.userStatusList;
      if (identical(statuses, _statusSource) ||
          (statuses.isEmpty && (_statusSource?.isEmpty ?? true))) {
        return;
      }
      if (!_workEnabled) {
        _projectionPending = true;
        return;
      }
      _rebuildStatusIndex(statuses);
      setState(() {});
      return;
    }
    // userStatusList 也由该模型通知，但在线状态不应触发联系人全量重算。
    final friends = _friendShipModel.friendList ?? const <V2TimFriendInfo>[];
    final revision = _friendShipModel.friendListRevision;
    if (revision == _friendListRevision && identical(friends, _friendSource)) {
      final statuses = _friendShipModel.userStatusList;
      if (identical(statuses, _statusSource) ||
          (statuses.isEmpty && (_statusSource?.isEmpty ?? true))) {
        return;
      }
      if (!_workEnabled) {
        _projectionPending = true;
        return;
      }
      _rebuildStatusIndex(statuses);
      // Row caching makes this cheap: unchanged users return the identical row
      // widget, while status changes invalidate only the matching signatures.
      setState(() {});
      return;
    }
    if (!_workEnabled) {
      _projectionPending = true;
      return;
    }
    _refreshContactProjection(force: true);
  }

  void _refreshContactProjection({bool force = false, bool notify = true}) {
    if (!_workEnabled && _cachedShowList != null) {
      _projectionPending = true;
      return;
    }
    if (_scrolling && _cachedShowList != null) {
      _projectionPending = true;
      return;
    }
    final source = widget.friends ??
        (_usesDirectoryProjection
            ? _directoryFriends
            : _friendShipModel.friendList) ??
        const <V2TimFriendInfo>[];
    if (!force && identical(source, _friendSource) && _cachedShowList != null) {
      return;
    }
    final allFriends = source
        .where((item) =>
            !PlatformOfficialAccountService.shouldHideFromContactAndPickers(
                item.userID))
        .toList(growable: false);
    final filtered = widget.filterItem == null
        ? allFriends
        : allFriends.where(widget.filterItem!).toList(growable: false);
    _filteredFriends = filtered;
    _friendSource = source;
    _friendListRevision = widget.friends == null
        ? _friendShipModel.friendListRevision
        : _friendListRevision;
    _cachedShowList = _buildShowList(filtered, StarredFriendProvider.shared);
    if (_usesDirectoryProjection) _cachedShowList!.sort(_compareContactRows);
    final activeIds = source.map((item) => item.userID).toSet();
    _projectionMetaCache.removeWhere(
      (userId, _) => !activeIds.contains(userId),
    );
    _contactRowCache.removeWhere(
      (userId, _) => !activeIds.contains(userId),
    );
    _composeContactEntries();
    _lastPresenceEnsureKey = null;
    if (notify && mounted) setState(() {});
  }

  void _composeContactEntries() {
    // Entry titles/icons/callbacks can change without any friend changing.
    // Reuse the existing sorted member rows instead of resolving every name.
    final members = (_cachedShowList ?? const <ISuspensionBeanImpl>[])
        .where((row) => row.memberInfo is! TopListItem);
    _cachedShowList = List<ISuspensionBeanImpl>.unmodifiable(members);
    if (widget.topList != null && widget.topList!.isNotEmpty) {
      final tops = widget.topList!
          .map((e) => ISuspensionBeanImpl(memberInfo: e, tagIndex: '@'))
          .toList(growable: false);
      _cachedShowList = List<ISuspensionBeanImpl>.unmodifiable(
        [...tops, ..._cachedShowList!],
      );
    }
    _effectiveList = widget.showContactCount
        ? List<ISuspensionBeanImpl>.unmodifiable([
            ..._cachedShowList!,
            ISuspensionBeanImpl(
                memberInfo: '__contact_count_footer__', tagIndex: ''),
          ])
        : _cachedShowList!;
  }

  void _onItemPositionsChanged() {
    if (!_workEnabled) {
      return;
    }
    _presenceDebounceTimer?.cancel();
    _presenceDebounceTimer = Timer(_presenceDebounce, () {
      if (!mounted) {
        return;
      }
      _ensureVisibleProfiles();
      if (widget.isShowOnlineStatus) {
        _ensureVisiblePresence();
      }
    });
  }

  void _prefetchFirstScreenPresence() {
    if (!_workEnabled || !widget.isShowOnlineStatus) {
      return;
    }
    final ids = _friendIdsFromEffectiveRange(
      start: 0,
      endExclusive: _firstScreenPrefetch,
    );
    _ensurePresenceIds(ids);
  }

  void _ensureVisiblePresence() {
    if (!_workEnabled || !widget.isShowOnlineStatus || _effectiveList.isEmpty) {
      return;
    }
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      _prefetchFirstScreenPresence();
      return;
    }
    int? minIndex;
    int? maxIndex;
    for (final position in positions) {
      if (position.itemTrailingEdge <= 0 || position.itemLeadingEdge >= 1) {
        continue;
      }
      minIndex = minIndex == null
          ? position.index
          : math.min(minIndex, position.index);
      maxIndex = maxIndex == null
          ? position.index
          : math.max(maxIndex, position.index);
    }
    if (minIndex == null || maxIndex == null) return;
    final start = math.max(0, minIndex - _presenceBufferRows);
    final end = math.min(
      _effectiveList.length,
      maxIndex + _presenceBufferRows + 1,
    );
    final visibleIds = _friendIdsFromEffectiveRange(
      start: minIndex,
      endExclusive: maxIndex + 1,
    );
    final bufferedIds = _friendIdsFromEffectiveRange(
      start: start,
      endExclusive: end,
    );
    // Preserve insertion order so the provider publishes truly visible rows
    // before the small prefetch margin.
    _ensurePresenceIds(<String>{...visibleIds, ...bufferedIds}.toList());
  }

  void _ensureVisibleProfiles() {
    if (!mounted || widget.friends != null) {
      return;
    }
    final positions = _itemPositionsListener.itemPositions.value;
    List<String> ids;
    if (positions.isEmpty) {
      ids = _friendIdsFromEffectiveRange(
        start: 0,
        endExclusive: ImSdkRelationshipPerf.firstScreenCount,
      );
    } else {
      int? minIndex;
      int? maxIndex;
      for (final position in positions) {
        if (position.itemTrailingEdge <= 0 || position.itemLeadingEdge >= 1) {
          continue;
        }
        minIndex = minIndex == null
            ? position.index
            : math.min(minIndex, position.index);
        maxIndex = maxIndex == null
            ? position.index
            : math.max(maxIndex, position.index);
      }
      if (minIndex == null || maxIndex == null) {
        return;
      }
      ids = _friendIdsFromEffectiveRange(
        start: math.max(0, minIndex - _presenceBufferRows),
        endExclusive: math.min(
          _effectiveList.length,
          maxIndex + _presenceBufferRows + 1,
        ),
      );
    }
    if (ids.isEmpty) {
      return;
    }
    unawaited(
      ImSdkRelationshipReconcileService.instance.hydrateViewportFriendDisplay(
        ids,
      ),
    );
  }

  List<String> _friendIdsFromEffectiveRange({
    required int start,
    required int endExclusive,
  }) {
    if (_effectiveList.isEmpty) {
      return const [];
    }
    final lo = start.clamp(0, _effectiveList.length);
    final hi = endExclusive.clamp(0, _effectiveList.length);
    if (lo >= hi) {
      return const [];
    }
    final ids = <String>[];
    for (var i = lo; i < hi; i++) {
      final info = _effectiveList[i].memberInfo;
      if (info is V2TimFriendInfo) {
        final id = info.userID.trim();
        if (id.isNotEmpty) {
          ids.add(id);
        }
      }
    }
    return ids;
  }

  void _ensurePresenceIds(List<String> userIds) {
    if (!_workEnabled ||
        !widget.isShowOnlineStatus ||
        userIds.isEmpty ||
        !mounted) {
      return;
    }
    final ttlMs = PresenceProvider.softFetchTtl.inMilliseconds;
    final bucket =
        ttlMs <= 0 ? 0 : DateTime.now().millisecondsSinceEpoch ~/ ttlMs;
    final idsKey = userIds.length <= 3
        ? userIds.join('|')
        : '${userIds.length}:${userIds.first}:${userIds.last}:${userIds[userIds.length ~/ 2]}';
    final key = '$idsKey@$bucket';
    if (_lastPresenceEnsureKey == key) {
      return;
    }
    _lastPresenceEnsureKey = key;
    final presence = Provider.of<PresenceProvider>(context, listen: false);
    presence.refresh(userIds);
  }

  String _showName(V2TimFriendInfo item) {
    return UserDisplayProfile.nameOfFriend(item);
  }

  _ContactProjectionMeta _projectionMeta(V2TimFriendInfo item) {
    final name = _showName(item);
    final id = item.userID;
    final cached = _projectionMetaCache[id];
    if (cached != null && cached.displayName == name) return cached;
    final meta = _ContactProjectionMeta(
      displayName: name,
      indexTag: memberSuspensionIndexTag(name),
    );
    _projectionMetaCache[id] = meta;
    return meta;
  }

  String _faceUrl(V2TimFriendInfo item) {
    return UserDisplayProfile.avatarOfFriend(item);
  }

  List<ISuspensionBeanImpl> _buildShowList(
    List<V2TimFriendInfo> list,
    StarredFriendProvider starred,
  ) {
    final starredFriends = <V2TimFriendInfo>[];
    final others = <V2TimFriendInfo>[];
    for (final item in list) {
      if (starred.isStarred(item.userID)) {
        starredFriends.add(item);
      } else {
        others.add(item);
      }
    }
    starredFriends.sort((a, b) {
      final ta = starred.starredAtOf(a.userID);
      final tb = starred.starredAtOf(b.userID);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    final out = <ISuspensionBeanImpl>[];
    for (final item in starredFriends) {
      out.add(ISuspensionBeanImpl(memberInfo: item, tagIndex: '★'));
    }
    final otherBeans = <ISuspensionBeanImpl>[];
    for (final item in others) {
      final meta = _projectionMeta(item);
      otherBeans.add(
        ISuspensionBeanImpl(
          memberInfo: item,
          tagIndex: meta.indexTag,
        ),
      );
    }
    SuspensionUtil.sortListBySuspensionTag(otherBeans);
    out.addAll(otherBeans);
    return out;
  }

  V2TimUserStatus? _statusOf(String userId) {
    if (!widget.isShowOnlineStatus) return null;
    final list = _friendShipModel.userStatusList;
    if (!identical(list, _statusSource)) {
      _rebuildStatusIndex(list);
    }
    return _statusByUserId[userId];
  }

  void _rebuildStatusIndex(List<V2TimUserStatus> source) {
    _statusSource = source;
    final next = <String, V2TimUserStatus>{};
    for (final status in source) {
      final userId = status.userID?.trim() ?? '';
      if (userId.isNotEmpty) {
        next[userId] = status;
      }
    }
    _statusByUserId = next;
  }

  Widget _buildTopItem(TopListItem info) {
    final isDesktop = _useDesktopListMetrics(context);
    final custom = widget.topListItemBuilder?.call(info);
    if (custom != null) return custom;
    final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
    final itemBackgroundColor = theme.conversationItemBgColor ??
        theme.weakBackgroundColor ??
        Colors.white;
    final avatarSize = _avatarSize(isDesktop: isDesktop);
    final avatarTextGap = _avatarTextGap(isDesktop: isDesktop);
    final rowPad = _rowVerticalPadding(isDesktop: isDesktop);
    final dividerInset = _dividerInset(isDesktop: isDesktop);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppListPressable(
          color: itemBackgroundColor,
          onTap: info.onTap,
          child: SizedBox(
            width: double.infinity,
            height: _itemMinHeight(isDesktop: isDesktop) - 0.6,
            child: Padding(
              padding: EdgeInsets.only(
                top: rowPad,
                left: 16,
                right: 16,
                bottom: rowPad,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    height: avatarSize,
                    width: avatarSize,
                    margin: EdgeInsets.only(right: avatarTextGap),
                    child: info.icon,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text(info.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.darkTextColor ?? Colors.black,
                                  fontSize: DirectoryListStyle.titleSize,
                                  fontWeight: FontWeight.w500,
                                  height: DirectoryListStyle.lineHeight,
                                ))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: dividerInset),
          child: Container(
            height: 0.6,
            color: DirectoryListStyle.dividerColor(context),
          ),
        ),
      ],
    );
  }

  Widget _buildContactItem(
    TUITheme theme,
    V2TimFriendInfo item,
    PresenceProvider presence,
    StarredFriendProvider starred,
  ) {
    final isDesktop = _useDesktopListMetrics(context);
    final showName = _showName(item);
    final faceUrl = _faceUrl(item);
    final localProfile =
        UserProfileLocalService.instance.readCached(item.userID);
    final isMutualFriend = friendCanMessage(_friendShipModel, item.userID);
    final isStarred = starred.isStarred(item.userID);
    final imStatus = _statusOf(item.userID);
    final itemBackgroundColor = theme.conversationItemBgColor ??
        theme.weakBackgroundColor ??
        Colors.white;
    final avatarSize = _avatarSize(isDesktop: isDesktop);
    final avatarTextGap = _avatarTextGap(isDesktop: isDesktop);
    final rowPad = _rowVerticalPadding(isDesktop: isDesktop);
    final dividerInset = _dividerInset(isDesktop: isDesktop);

    // ScrollablePositionedList may ask for the same visible row repeatedly
    // while reporting positions. Return the identical widget when its visual
    // inputs are unchanged; the nested presence selectors remain live and can
    // still update just the avatar/subtitle for this user.
    final rowSignature = Object.hashAll(<Object?>[
      identityHashCode(item),
      identityHashCode(presence),
      identityHashCode(widget.onTapItem),
      identityHashCode(widget.onLongPressItem),
      showName,
      faceUrl,
      localProfile?.avatarVersion,
      isMutualFriend,
      isStarred,
      widget.isShowOnlineStatus,
      imStatus?.statusType,
      isDesktop,
      MediaQuery.textScalerOf(context).scale(1),
      Theme.of(context).brightness,
      itemBackgroundColor,
      theme.darkTextColor,
      theme.weakTextColor,
      avatarSize,
      avatarTextGap,
      rowPad,
      dividerInset,
    ]);
    final cached = _contactRowCache[item.userID];
    if (cached != null && cached.signature == rowSignature) {
      return cached.widget;
    }

    final row = RepaintBoundary(
      key: ValueKey<String>('contact_row_${item.userID}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppListPressable(
            color: itemBackgroundColor,
            onTap: () => widget.onTapItem?.call(item),
            onLongPress: () => widget.onLongPressItem?.call(item),
            child: SizedBox(
              width: double.infinity,
              height: _itemMinHeight(isDesktop: isDesktop) - 0.6,
              child: Padding(
                padding: EdgeInsets.only(
                  top: rowPad,
                  left: 16,
                  right: 16,
                  bottom: rowPad,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: avatarSize,
                      width: avatarSize,
                      margin: EdgeInsets.only(right: avatarTextGap),
                      child: widget.isShowOnlineStatus
                          ? _ContactPresenceAvatar(
                              presence: presence,
                              userId: item.userID,
                              faceUrl: faceUrl,
                              showName: showName,
                              imStatus: imStatus,
                              isMutualFriend: isMutualFriend,
                            )
                          : Avatar(
                              faceUrl: faceUrl,
                              showName: showName,
                              borderRadius: _contactAvatarBorderRadius,
                            ),
                    ),
                    Expanded(
                      child: Transform.translate(
                        offset: const Offset(0, -_textBlockNudgeUp),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              showName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.darkTextColor ?? Colors.black,
                                fontSize: DirectoryListStyle.titleSize,
                                fontWeight: FontWeight.w500,
                                height: DirectoryListStyle.lineHeight,
                              ),
                            ),
                            if (widget.isShowOnlineStatus) ...[
                              const SizedBox(height: _nameStatusGap),
                              _ContactPresenceSubtitle(
                                presence: presence,
                                userId: item.userID,
                                imStatus: imStatus,
                                isMutualFriend: isMutualFriend,
                                isDesktop: isDesktop,
                                weakTextColor: theme.weakTextColor,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (isStarred)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.star,
                          size: 18,
                          color: Color(0xFFF4B400),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: dividerInset),
            child: Container(
              height: 0.6,
              color: DirectoryListStyle.dividerColor(context),
            ),
          ),
        ],
      ),
    );
    _contactRowCache[item.userID] = _ContactRowCacheEntry(
      signature: rowSignature,
      widget: row,
    );
    return row;
  }

  @override
  Widget build(BuildContext context) {
    // Preserve the scrollable's owner; work/presence listeners are gated in
    // didChangeDependencies, independently of this low-frequency theme source.
    return Selector<DefaultThemeData, TUITheme>(
      selector: (_, model) => model.theme,
      builder: (context, theme, _) => _buildWithTheme(context, theme),
    );
  }

  Widget _buildWithTheme(BuildContext context, TUITheme theme) {
    final starred = StarredFriendProvider.shared;
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: _friendShipModel)],
      builder: (context, _) {
        final presence = Provider.of<PresenceProvider>(context, listen: false);
        final friends = _filteredFriends;
        final showList = _cachedShowList ?? const <ISuspensionBeanImpl>[];

        if (friends.isEmpty) {
          _effectiveList = showList;
          return Column(
            children: [
              ...showList.map((e) {
                final info = e.memberInfo;
                if (info is TopListItem) return _buildTopItem(info);
                return const SizedBox.shrink();
              }),
              Expanded(
                child: widget.emptyBuilder != null
                    ? widget.emptyBuilder!(context)
                    : Center(child: Text(TIM_t("无联系人"))),
              ),
            ],
          );
        }

        final isDesktop = _useDesktopListMetrics(context);
        final effectiveList = _effectiveList;
        _effectiveList = effectiveList;

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth != 0) return false;
            if (notification is ScrollStartNotification) {
              _projectionSettleTimer?.cancel();
              _scrolling = true;
            } else if (notification is ScrollEndNotification) {
              _projectionSettleTimer?.cancel();
              _projectionSettleTimer =
                  Timer(const Duration(milliseconds: 120), () {
                if (!mounted) return;
                _scrolling = false;
                _flushPendingDirectoryProjection();
              });
            }
            return false;
          },
          child: AZListViewContainer(
            subduedStyle: true,
            itemIdentity: (row) {
              final item = row.memberInfo;
              if (item is V2TimFriendInfo) return 'friend:${item.userID}';
              if (item is TopListItem) return 'entry:${item.id}';
              return 'footer:$item';
            },
            memberList: effectiveList,
            itemPositionsListener: _itemPositionsListener,
            itemBuilder: (context, index) {
              final info = effectiveList[index].memberInfo;
              if (info is String && info == '__contact_count_footer__') {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Center(
                    child: Text(
                      widget.footerLabel ??
                          TIM_t_para(
                              "{{option1}}位联系人", "${friends.length}位联系人")(
                            option1: friends.length.toString(),
                          ),
                      style: TextStyle(
                        color: theme.weakTextColor ?? hexToColor("999999"),
                        fontSize: isDesktop ? 12 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }
              if (info is TopListItem) return _buildTopItem(info);
              return _buildContactItem(
                theme,
                info as V2TimFriendInfo,
                presence,
                starred,
              );
            },
          ),
        );
      },
    );
  }
}

class _ContactProjectionMeta {
  const _ContactProjectionMeta({
    required this.displayName,
    required this.indexTag,
  });

  final String displayName;
  final String indexTag;
}

class _ContactRowCacheEntry {
  const _ContactRowCacheEntry({
    required this.signature,
    required this.widget,
  });

  final int signature;
  final Widget widget;
}

/// 行内头像在线点：仅随 Presence 刷新，不触发通讯录整表重建。
class _ContactPresenceAvatar extends StatelessWidget {
  const _ContactPresenceAvatar({
    required this.presence,
    required this.userId,
    required this.faceUrl,
    required this.showName,
    required this.imStatus,
    required this.isMutualFriend,
  });

  final PresenceProvider presence;
  final String userId;
  final String faceUrl;
  final String showName;
  final V2TimUserStatus? imStatus;
  final bool isMutualFriend;

  @override
  Widget build(BuildContext context) {
    Widget buildAvatar() {
      final onlineStatus = presence.resolveAvatarOnlineStatus(
        userId,
        imStatus,
        isMutualFriend: isMutualFriend,
      );
      return Avatar(
        onlineStatus: onlineStatus,
        faceUrl: faceUrl,
        showName: showName,
        borderRadius: _ContactListWithPresenceState._contactAvatarBorderRadius,
      );
    }

    // Hidden IndexedStack tabs remain mounted. Do not keep a Provider
    // subscription alive there; TickerMode notifies this widget once when the
    // tab becomes active again and the fine-grained selector is restored.
    // ignore: deprecated_member_use
    final tabActive = HomeTabActivity.isActiveOf(context);
    final tickerEnabled = TickerMode.of(context);
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final workEnabled = tabActive && tickerEnabled && routeCurrent;
    if (!workEnabled) {
      return buildAvatar();
    }
    return Selector<PresenceProvider, int>(
      selector: (_, provider) => provider.revisionFor(userId),
      builder: (context, _, __) => buildAvatar(),
    );
  }
}

/// 行内在线文案：仅随 Presence 刷新。
class _ContactPresenceSubtitle extends StatelessWidget {
  const _ContactPresenceSubtitle({
    required this.presence,
    required this.userId,
    required this.imStatus,
    required this.isMutualFriend,
    required this.isDesktop,
    required this.weakTextColor,
  });

  final PresenceProvider presence;
  final String userId;
  final V2TimUserStatus? imStatus;
  final bool isMutualFriend;
  final bool isDesktop;
  final Color? weakTextColor;

  @override
  Widget build(BuildContext context) {
    Widget buildSubtitle() {
      final imOnline = presence.resolveOnline(
        userId: userId,
        imOnline: imStatus?.statusType == 1,
      );
      final loading = presence.isLastSeenLoading(
        userId: userId,
        imOnline: imOnline,
        isMutualFriend: isMutualFriend,
      );
      final label = loading
          ? ''
          : presence.listLabelFor(
              userId: userId,
              imOnline: imOnline,
              isMutualFriend: isMutualFriend,
            );
      return PresenceSubtitle(
        label: label,
        loading: loading,
        imOnline: false,
        fontSize: DirectoryListStyle.subtitleSize,
        height: DirectoryListStyle.lineHeight,
        offlineColor: weakTextColor ?? hexToColor("999999"),
        skeletonColor: weakTextColor,
      );
    }

    // ignore: deprecated_member_use
    final tabActive = HomeTabActivity.isActiveOf(context);
    final tickerEnabled = TickerMode.of(context);
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final workEnabled = tabActive && tickerEnabled && routeCurrent;
    if (!workEnabled) {
      return buildSubtitle();
    }
    return Selector<PresenceProvider, int>(
      selector: (_, provider) => provider.revisionFor(userId),
      builder: (context, _, __) => buildSubtitle(),
    );
  }
}
