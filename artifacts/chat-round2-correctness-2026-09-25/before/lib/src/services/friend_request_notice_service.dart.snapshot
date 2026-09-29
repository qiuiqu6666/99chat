import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/api/friend_request_api.dart';
import 'package:tencent_cloud_chat_demo/src/friend_application_helper.dart';
import 'package:tencent_cloud_chat_demo/src/models/friend_request_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/archived_conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_recent_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_realtime_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/red_packet_realtime_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/platform/route_handler.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_join_application_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_index_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime_service.dart';
import 'package:tencent_cloud_chat_demo/src/platform/system_message_alert_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/in_app_notification_sound.dart';
import 'package:tencent_cloud_chat_demo/src/services/in_app_notification_vibration.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_system_notification_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/push_msgkey_dedup.dart';
import 'package:tencent_cloud_chat_demo/src/utils/friend_request_poll_gate.dart';
import 'package:tencent_cloud_chat_demo/src/utils/contact_data_source_enter_gate.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

const String friendRequestReadWatermarkStorageKey =
    'friend_request_read_watermark';

class FriendRequestNoticeService {
  FriendRequestNoticeService._();

  static final FriendRequestNoticeService instance =
      FriendRequestNoticeService._();

  static const Duration _pollInterval = Duration(seconds: 60);
  static const int _groupTabIndex = 1;
  static const int _contactTabIndex = 2;
  static const Duration _joinApplicationsResumeDebounce = Duration(seconds: 1);
  static const Duration _dataSourceEnterDebounce = Duration(seconds: 2);

  bool _started = false;
  int _homeTabIndex = 0;
  Timer? _pollTimer;
  DateTime? _lastJoinApplicationsResumeAt;
  DateTime? _lastGroupDataSourceEnterAt;
  String? _pendingContactEnterReason;
  final ContactDataSourceEnterSingleFlight _contactDataSourceEnterFlight =
      ContactDataSourceEnterSingleFlight();
  DateTime? _lastRequestToastAt;
  DateTime? _lastFriendAddedNoticeAt;
  String? _lastFriendAddedNoticeKey;
  final Set<int> _notifiedIncomingIds = <int>{};
  final Set<String> _notifiedIncomingKeys = <String>{};
  List<FriendRequestRecord> _observedIncoming = <FriendRequestRecord>[];
  FriendRequestReadWatermark _readWatermark =
      const FriendRequestReadWatermark.empty();
  bool _watermarkLoaded = false;
  String _watermarkOwner = '';

  final ValueNotifier<int> pendingApplicationCount = ValueNotifier<int>(0);
  int _sessionClearGeneration = 0;

  // ignore: avoid_print
  static void _log(String message) {
    // Verbose notice tracing disabled.
  }

  void start() {
    ensureRunning();
  }

  void ensureRunning() {
    final restarting = _started;
    _started = true;

    FriendRealtimeService.instance.onEvent = _handleRealtimeEvent;
    FriendRealtimeService.instance.addAuthOkListener(_onRealtimeAuthOk);
    FriendRealtimeService.instance.start();

    unawaited(FriendSyncService.instance.restoreSyncStateForCurrentOwner());

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!shouldPollFriendRequests(
        realtimeReady: FriendRealtimeService.instance.isRealtimeReady,
      )) {
        return;
      }
      unawaited(_pollIncomingRequests());
    });

    _log(
      'ensureRunning restarting=$restarting poll=${_pollInterval.inSeconds}s',
    );

    unawaited(_bootstrapUnread());
    if (_pendingContactEnterReason != null ||
        _homeTabIndex == _contactTabIndex) {
      final reason = _pendingContactEnterReason ?? 'contact_tab_replay';
      _pendingContactEnterReason = null;
      unawaited(enterContactDataSource(reason: reason));
    }
  }

  /// 首页底部 Tab 切换：通讯录/群聊 Tab 走「先本地再拉一次」。
  void onHomeTabChanged(int index, {bool skipDataSourceEnter = false}) {
    _homeTabIndex = index;
    if (!_started) {
      if (!skipDataSourceEnter && index == _contactTabIndex) {
        _pendingContactEnterReason = 'contact_tab';
      }
      return;
    }
    if (!skipDataSourceEnter) {
      if (index == _contactTabIndex) {
        unawaited(enterContactDataSource(reason: 'contact_tab'));
      } else if (index == _groupTabIndex) {
        unawaited(enterGroupDataSource(reason: 'group_tab'));
      }
    }
  }

  /// 进入通讯录：好友本以 IM SDK 为准，不再拉自建 Difference。
  /// Concurrent callers (home Tab + list widget) join one in-flight Future.
  Future<void> enterContactDataSource({required String reason}) {
    if (!_started) {
      _pendingContactEnterReason = reason;
      return Future<void>.value();
    }
    return _contactDataSourceEnterFlight.run(
      () => _enterContactDataSourceBody(reason: reason),
    );
  }

  Future<void> _enterContactDataSourceBody({required String reason}) async {
    final identity = SessionIdentityService.instance.capture();
    final clearGeneration = _sessionClearGeneration;
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
    await FriendSyncService.instance.hydrateContactListFromLocal();
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
  }

  /// 进入群聊相关列表：只刷新 SDK 群列表，不再拉 /me/groups/changes。
  Future<void> enterGroupDataSource({required String reason}) async {
    if (!_started) {
      return;
    }
    final now = DateTime.now();
    final last = _lastGroupDataSourceEnterAt;
    if (last != null && now.difference(last) < _dataSourceEnterDebounce) {
      return;
    }
    _lastGroupDataSourceEnterAt = now;
    try {
      await ImSdkRelationshipReconcileService.instance
          .requestFirstSnapshot(reason: 'enter_group_data_source');
    } catch (e) {
      _log('enterGroupDataSource failed reason=$reason: $e');
    }
  }

  Future<void> _bootstrapUnread() async {
    await ensureWatermarkLoaded();
    unawaited(_pollIncomingRequests());
    unawaited(refreshPendingCount(notifyUnseen: true));
  }

  void _onRealtimeAuthOk() {
    unawaited(_pollIncomingRequests());
    unawaited(refreshPendingCount(notifyUnseen: true));
  }

  void onAppLifecycleChanged(AppLifecycleState state) {
    if (!_started) {
      return;
    }
    FriendRealtimeService.instance.onAppLifecycleChanged(state);
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_pollIncomingRequests());
        unawaited(refreshPendingCount(notifyUnseen: true));
        unawaited(GroupNoticeBootstrap.refreshFromNetwork());
        GroupLiveIndexSyncService.instance.onAppResumed();
        _refreshJoinApplicationsOnResume();
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        return;
      case AppLifecycleState.inactive:
        return;
    }
  }

  void _refreshJoinApplicationsOnResume() {
    final now = DateTime.now();
    final last = _lastJoinApplicationsResumeAt;
    if (last != null &&
        now.difference(last) < _joinApplicationsResumeDebounce) {
      return;
    }
    _lastJoinApplicationsResumeAt = now;
    unawaited(
      GroupJoinApplicationService.instance.refresh(
        force: true,
        syncMembership: false,
      ),
    );
  }

  Future<void> stop() async {
    _sessionClearGeneration++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pendingContactEnterReason = null;
    _homeTabIndex = 0;
    _lastGroupDataSourceEnterAt = null;
    if (!_started) {
      _lastRequestToastAt = null;
      _lastFriendAddedNoticeAt = null;
      _lastFriendAddedNoticeKey = null;
      _notifiedIncomingIds.clear();
      _notifiedIncomingKeys.clear();
      _clearMemoryWatermarkState();
      pendingApplicationCount.value = 0;
      return;
    }
    _started = false;
    _lastRequestToastAt = null;
    _lastFriendAddedNoticeAt = null;
    _lastFriendAddedNoticeKey = null;
    _notifiedIncomingIds.clear();
    _notifiedIncomingKeys.clear();
    _clearMemoryWatermarkState();
    pendingApplicationCount.value = 0;
    FriendSyncService.instance.onBecameFriendsCompleted = null;
    FriendRealtimeService.instance.onEvent = null;
    FriendRealtimeService.instance.removeAuthOkListener(_onRealtimeAuthOk);
    await FriendRealtimeService.instance.stop();
  }

  Future<void> _pollIncomingRequests() async {
    if (!_started) {
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    final clearGeneration = _sessionClearGeneration;
    if (identity.ownerUserId.isEmpty) {
      return;
    }
    await ensureWatermarkLoaded();
    if (!_isCurrentRefresh(identity, clearGeneration)) {
      return;
    }
    try {
      final incoming = await FriendRequestApi.instance.fetchIncomingPending();
      if (!_isCurrentRefresh(identity, clearGeneration)) {
        return;
      }
      await _syncIncomingNotifications(
        incoming,
        source: 'poll',
        identity: identity,
        clearGeneration: clearGeneration,
      );
    } catch (e) {
      _log('poll failed $e');
    }
  }

  Future<void> _syncIncomingNotifications(
    List<FriendRequestRecord> incoming, {
    required String source,
    bool notifyUnseen = true,
    SessionIdentity? identity,
    int? clearGeneration,
  }) async {
    if (identity != null &&
        !_isCurrentRefresh(
          identity,
          clearGeneration ?? _sessionClearGeneration,
        )) {
      return;
    }
    await ensureWatermarkLoaded();
    if (identity != null &&
        !_isCurrentRefresh(
          identity,
          clearGeneration ?? _sessionClearGeneration,
        )) {
      return;
    }
    _observedIncoming = List<FriendRequestRecord>.from(incoming);
    final unreadCount = computeFriendRequestUnreadCount(
      pending: incoming,
      watermark: _readWatermark,
    );
    if (pendingApplicationCount.value != unreadCount) {
      pendingApplicationCount.value = unreadCount;
    }
    if (!notifyUnseen || incoming.isEmpty) {
      return;
    }

    final unseen = incoming.where(_isUnseenIncoming).toList();
    if (unseen.isEmpty) {
      return;
    }

    unseen.sort((a, b) => b.displayTimestamp.compareTo(a.displayTimestamp));
    final latest = unseen.first;
    _markIncomingNotified(latest);
    _log(
      'notify unseen source=$source id=${latest.id} from=${latest.userID} '
      'unread=$unreadCount',
    );
    await _notifyFriendRequestReceived(
      userID: latest.userID,
      displayName: latest.nickname,
      faceUrl: latest.faceUrl,
      expectedIdentity: identity,
      expectedClearGeneration: clearGeneration,
    );
  }

  bool _isCurrentRefresh(SessionIdentity identity, int clearGeneration) {
    return _started &&
        clearGeneration == _sessionClearGeneration &&
        SessionIdentityService.instance.isCurrent(identity);
  }

  bool _isUnseenIncoming(FriendRequestRecord record) {
    if (record.hasServerId) {
      return !_notifiedIncomingIds.contains(record.id);
    }
    return !_notifiedIncomingKeys.contains(record.identityKey);
  }

  /// Kept for compatibility. Entry unread is owned by the owner watermark.
  void markLoadedRequestsRead(Iterable<FriendRequestRecord> records) {}

  Future<void> ensureWatermarkLoaded() async {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      _readWatermark = const FriendRequestReadWatermark.empty();
      _watermarkLoaded = false;
      _watermarkOwner = '';
      return;
    }
    if (_watermarkLoaded && _watermarkOwner == identity.ownerUserId) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    _readWatermark = FriendRequestReadWatermark.fromJsonString(
      prefs.getString(_storageKeyForOwner(identity.ownerUserId)),
    );
    _watermarkLoaded = true;
    _watermarkOwner = identity.ownerUserId;
  }

  Future<void> commitObservedAsRead() async {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      return;
    }
    await ensureWatermarkLoaded();
    if (!SessionIdentityService.instance.isCurrent(identity) ||
        _watermarkOwner != identity.ownerUserId) {
      return;
    }
    if (pendingApplicationCount.value > 0 && _observedIncoming.isEmpty) {
      try {
        final incoming = await FriendRequestApi.instance.fetchIncomingPending();
        if (!SessionIdentityService.instance.isCurrent(identity) ||
            _watermarkOwner != identity.ownerUserId) {
          return;
        }
        _observedIncoming = List<FriendRequestRecord>.from(incoming);
      } catch (e) {
        _log('commitObservedAsRead fetch failed $e');
      }
    }
    _readWatermark = watermarkFromObserved(_observedIncoming, _readWatermark);
    pendingApplicationCount.value = 0;
    await _persistReadWatermark(identity);
  }

  Future<void> clearForOwner(String? ownerUserId) async {
    final owner = ChatIdFormat.rawUserUid(ownerUserId);
    _clearMemoryWatermarkState();
    pendingApplicationCount.value = 0;
    if (owner.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKeyForOwner(owner));
  }

  void _clearMemoryWatermarkState() {
    _observedIncoming = <FriendRequestRecord>[];
    _readWatermark = const FriendRequestReadWatermark.empty();
    _watermarkLoaded = false;
    _watermarkOwner = '';
  }

  String _storageKeyForOwner(String userId) {
    final owner = ChatIdFormat.rawUserUid(userId);
    if (owner.isEmpty) {
      return friendRequestReadWatermarkStorageKey;
    }
    return '${friendRequestReadWatermarkStorageKey}_$owner';
  }

  Future<void> _persistReadWatermark(SessionIdentity identity) async {
    if (!SessionIdentityService.instance.isCurrent(identity) ||
        _watermarkOwner != identity.ownerUserId) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!SessionIdentityService.instance.isCurrent(identity) ||
        _watermarkOwner != identity.ownerUserId) {
      return;
    }
    await prefs.setString(
      _storageKeyForOwner(identity.ownerUserId),
      _readWatermark.toJsonString(),
    );
  }

  void _markIncomingNotified(FriendRequestRecord record) {
    if (record.hasServerId) {
      _notifiedIncomingIds.add(record.id!);
      return;
    }
    _notifiedIncomingKeys.add(record.identityKey);
  }

  void _markIncomingNotifiedByEvent(FriendRealtimeEvent event) {
    final requestId = event.requestId;
    if (requestId != null && requestId > 0) {
      _notifiedIncomingIds.add(requestId);
    }
  }

  Future<void> _handleRealtimeEvent(FriendRealtimeEvent event) async {
    final identity = SessionIdentityService.instance.capture();
    final clearGeneration = _sessionClearGeneration;
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
    _log(
      'realtime event=${event.event} from=${event.fromUserId} '
      'to=${event.toUserId} requestId=${event.requestId}',
    );
    final selfId = _selfUserId();

    switch (event.event) {
      case 'friend_request_received':
        if (selfId.isNotEmpty &&
            event.toUserId.trim().isNotEmpty &&
            !_isSameUser(event.toUserId, selfId)) {
          if (kDebugMode) {
            debugPrint(
              'FriendRequestNotice: skip received '
              'target=${event.toUserId} self=$selfId',
            );
          }
          return;
        }
        await _onFriendRequestReceived(event, identity, clearGeneration);
        return;
      case 'friend_request_accepted':
      case 'friend_request_rejected':
        if (selfId.isNotEmpty && !_eventInvolvesSelf(event, selfId)) {
          return;
        }
        if (event.event == 'friend_request_accepted') {
          await _onFriendRequestAccepted(event, identity, clearGeneration);
        } else {
          await _onFriendRequestRejected(event, identity, clearGeneration);
        }
        return;
      case 'friend_request_auto_accepted':
      case 'friend_restored':
        if (selfId.isNotEmpty && !_eventInvolvesSelf(event, selfId)) {
          return;
        }
        await _onFriendRelationshipChanged(event, identity, clearGeneration);
        return;
      case 'friend_list_changed':
        await _onFriendListChanged(event);
        return;
      case 'group_changed':
        await _onGroupChanged(event);
        return;
      case 'call_recent_changed':
        await _onCallRecentChanged(event);
        return;
      case 'presence_changed':
        _onPresenceChanged(event);
        return;
      case 'red_packet_changed':
        await _onRedPacketChanged(event);
        return;
      case 'moment_changed':
        await _onMomentChanged(event);
        return;
      case 'conversation_archive_changed':
        await _onConversationArchiveChanged(event);
        return;
      case 'conversation_folder_changed':
        await _onConversationFolderChanged(event);
        return;
      default:
        return;
    }
  }

  Future<void> _onMomentChanged(FriendRealtimeEvent event) async {
    await MomentsRealtimeSyncService.instance.handleRealtimeEvent(event);
  }

  Future<void> _onConversationArchiveChanged(FriendRealtimeEvent event) async {
    await ArchivedConversationSyncService.instance.handleRealtimeEvent(event);
  }

  Future<void> _onConversationFolderChanged(FriendRealtimeEvent event) async {
    await ConversationFolderSyncService.instance.handleRealtimeEvent(event);
  }

  Future<void> _onFriendListChanged(FriendRealtimeEvent event) async {
    await FriendSyncService.instance.applyListChanged(event);
    await FriendSyncService.instance.refreshUIKitLists(force: true);
  }

  Future<void> _onGroupChanged(FriendRealtimeEvent event) async {
    await GroupSyncService.instance.handleRealtimeEvent(event);
  }

  Future<void> _onCallRecentChanged(FriendRealtimeEvent event) async {
    await CallRecentSyncService.instance.handleRealtimeEvent(event);
  }

  Future<void> _onRedPacketChanged(FriendRealtimeEvent event) async {
    await RedPacketRealtimeSyncService.instance.handleRealtimeEvent(event);
  }

  void _onPresenceChanged(FriendRealtimeEvent event) {
    final peerId = event.peerUserId?.trim() ?? '';
    if (peerId.isEmpty) {
      return;
    }
    PresenceProvider.activeInstance?.applyPresenceChanged(
      peerUserId: peerId,
      lastActiveAt: event.lastActiveAt ?? event.ts,
      lastActiveVisibility: event.lastActiveVisibility,
      online: event.online ?? true,
    );
  }

  Future<void> _onFriendRequestReceived(
    FriendRealtimeEvent event,
    SessionIdentity identity,
    int clearGeneration,
  ) async {
    _markIncomingNotifiedByEvent(event);
    await refreshPendingCount();
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'friend_application_added',
    );
    final userID = event.fromUserId.trim();
    final dedupKey = _friendNoticeKey(
      requestId: event.requestId,
      userId: userID,
    );
    await PushMsgKeyDedup.instance.ensureReady();
    if (PushMsgKeyDedup.instance.wasHandled(dedupKey)) {
      return;
    }
    if (!PushMsgKeyDedup.instance.tryClaim(dedupKey)) {
      return;
    }
    final name = await _resolveDisplayName(userID);
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
    await _notifyFriendRequestReceived(
      userID: userID,
      displayName: name,
      expectedIdentity: identity,
      expectedClearGeneration: clearGeneration,
    );
  }

  String _friendNoticeKey({int? requestId, required String userId}) {
    if (requestId != null && requestId > 0) {
      return 'friend_request:$requestId';
    }
    final id = userId.trim();
    return 'friend_request:user:$id';
  }

  Future<void> _notifyFriendRequestReceived({
    required String userID,
    String? displayName,
    String? faceUrl,
    SessionIdentity? expectedIdentity,
    int? expectedClearGeneration,
  }) async {
    bool isCurrent() =>
        expectedIdentity == null ||
        _isCurrentRefresh(
          expectedIdentity,
          expectedClearGeneration ?? _sessionClearGeneration,
        );
    if (!isCurrent()) return;
    final now = DateTime.now();
    final last = _lastRequestToastAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }

    final id = userID.trim();
    final name = (displayName ?? '').trim().isNotEmpty
        ? displayName!.trim()
        : (id.isNotEmpty ? await _resolveDisplayName(id) : '');
    if (!isCurrent()) return;
    final text = name.isEmpty
        ? AppI18n.current.t(
            zhHans: '收到新的好友申请',
            zhHant: '收到新的好友申請',
            en: 'New friend request received',
            ja: '新しい友達申請が届きました',
            ko: '새 친구 요청을 받았습니다',
          )
        : AppI18n.current.format(
            zhHans: '{name} 请求添加你为好友',
            zhHant: '{name} 請求新增你為好友',
            en: '{name} sent you a friend request',
            ja: '{name} さんから友達申請が届きました',
            ko: '{name}님이 친구 요청을 보냈습니다',
            vars: {'name': name},
          );
    final title = AppI18n.current.t(
      zhHans: '新的好友申请',
      zhHant: '新的好友申請',
      en: 'New friend request',
      ja: '新しい友達申請',
      ko: '새 친구 요청',
    );
    final apiFace = (faceUrl ?? '').trim();
    final resolvedFaceUrl = apiFace.isNotEmpty &&
            UserAvatarHelper.resolveDisplayUrl(apiFace) != null
        ? apiFace
        : (id.isNotEmpty ? await _resolveFaceUrl(id) : '');
    if (!isCurrent()) return;
    final shown = await _showFriendNotice(
      key: 'friend_application_$id',
      title: title,
      body: text,
      faceUrl: resolvedFaceUrl,
      showName: name.isEmpty ? title : name,
      userID: id,
      type: 'friend_request',
      onTap: RouteHandler.openNewContact,
      expectedIdentity: expectedIdentity,
      expectedClearGeneration: expectedClearGeneration,
    );
    if (shown) {
      _lastRequestToastAt = DateTime.now();
    }
  }

  Future<void> _onFriendRequestAccepted(
    FriendRealtimeEvent event,
    SessionIdentity identity,
    int clearGeneration,
  ) async {
    final peerUserId = _peerUserIdFromEvent(event);
    await FriendSyncService.instance.onBecameFriends(
      peerUserId: peerUserId,
      nickname: event.peerNickname,
      avatarUrl: event.peerAvatarUrl,
      remark: event.remark ?? '',
      reason: 'friend_request_accepted',
    );
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
    await refreshPendingCount();
    await _showFriendOutcomeNotice(
      peerUserId: peerUserId,
      title: AppI18n.current.t(
        zhHans: '好友申请已通过',
        zhHant: '好友申請已通過',
        en: 'Friend request accepted',
        ja: '友達申請が承認されました',
        ko: '친구 요청이 수락되었습니다',
      ),
      bodyBuilder: (name) => name.isEmpty
          ? AppI18n.current.t(
              zhHans: '对方已同意你的好友申请',
              zhHant: '對方已同意你的好友申請',
              en: 'Your friend request was accepted',
              ja: '友達申請が承認されました',
              ko: '친구 요청이 수락되었습니다',
            )
          : AppI18n.current.format(
              zhHans: '{name} 已同意你的好友申请',
              zhHant: '{name} 已同意你的好友申請',
              en: '{name} accepted your friend request',
              ja: '{name} さんが友達申請を承認しました',
              ko: '{name}님이 친구 요청을 수락했습니다',
              vars: {'name': name},
            ),
      noticeType: 'friend_request_accepted',
      openConversation: true,
      expectedIdentity: identity,
      expectedClearGeneration: clearGeneration,
    );
  }

  Future<void> _onFriendRequestRejected(
    FriendRealtimeEvent event,
    SessionIdentity identity,
    int clearGeneration,
  ) async {
    await refreshPendingCount();
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'friend_application_refresh',
    );
    final peerUserId = _peerUserIdFromEvent(event);
    await _showFriendOutcomeNotice(
      peerUserId: peerUserId,
      title: AppI18n.current.t(
        zhHans: '好友申请未通过',
        zhHant: '好友申請未通過',
        en: 'Friend request declined',
        ja: '友達申請は承認されませんでした',
        ko: '친구 요청이 거절되었습니다',
      ),
      bodyBuilder: (name) => name.isEmpty
          ? AppI18n.current.t(
              zhHans: '对方拒绝了你的好友申请',
              zhHant: '對方拒絕了你的好友申請',
              en: 'Your friend request was declined',
              ja: '友達申請は拒否されました',
              ko: '친구 요청이 거절되었습니다',
            )
          : AppI18n.current.format(
              zhHans: '{name} 拒绝了你的好友申请',
              zhHant: '{name} 拒絕了你的好友申請',
              en: '{name} declined your friend request',
              ja: '{name} さんが友達申請を拒否しました',
              ko: '{name}님이 친구 요청을 거절했습니다',
              vars: {'name': name},
            ),
      noticeType: 'friend_request_rejected',
      openConversation: false,
      onTap: RouteHandler.openNewContact,
      expectedIdentity: identity,
      expectedClearGeneration: clearGeneration,
    );
  }

  Future<void> _onFriendRelationshipChanged(
    FriendRealtimeEvent event,
    SessionIdentity identity,
    int clearGeneration,
  ) async {
    final selfId = _selfUserId();
    final peerUserId = _isSameUser(event.fromUserId, selfId)
        ? event.toUserId.trim()
        : event.fromUserId.trim();
    final resolvedPeer =
        peerUserId.isNotEmpty ? peerUserId : _peerUserIdFromEvent(event);
    await FriendSyncService.instance.onBecameFriends(
      peerUserId: resolvedPeer,
      nickname: event.peerNickname,
      avatarUrl: event.peerAvatarUrl,
      remark: event.remark ?? '',
      reason: event.event,
    );
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
    if (resolvedPeer.isNotEmpty && event.event != 'friend_restored') {
      // friend_restored 不进「新的朋友」历史；自动通过写入已处理。
      final direction = _isSameUser(event.toUserId, selfId)
          ? FriendRequestDirection.incoming
          : FriendRequestDirection.outgoing;
      unawaited(
        FriendApplicationHelper.recordBecameFriendsHistory(
          userID: resolvedPeer,
          nickname: event.peerNickname ?? '',
          faceUrl: event.peerAvatarUrl ?? '',
          addSource: 'auto',
          direction: direction,
        ),
      );
    }
    await refreshPendingCount();
    if (event.event == 'friend_restored') {
      return;
    }

    if (resolvedPeer.isEmpty) {
      return;
    }

    await _showFriendOutcomeNotice(
      peerUserId: resolvedPeer,
      title: AppI18n.current.t(
        zhHans: '已成为好友',
        zhHant: '已成為好友',
        en: 'You are now friends',
        ja: '友達になりました',
        ko: '친구가 되었습니다',
      ),
      bodyBuilder: (name) => name.isEmpty
          ? AppI18n.current.t(
              zhHans: '你们已成为好友',
              zhHant: '你們已成為好友',
              en: 'You are now friends',
              ja: '友達になりました',
              ko: '친구가 되었습니다',
            )
          : AppI18n.current.format(
              zhHans: '你与 {name} 已成为好友',
              zhHant: '你與 {name} 已成為好友',
              en: 'You and {name} are now friends',
              ja: '{name} さんと友達になりました',
              ko: '{name}님과 친구가 되었습니다',
              vars: {'name': name},
            ),
      noticeType: event.event,
      openConversation: true,
      expectedIdentity: identity,
      expectedClearGeneration: clearGeneration,
    );
  }

  Future<void> _showFriendOutcomeNotice({
    required String peerUserId,
    required String title,
    required String Function(String name) bodyBuilder,
    required String noticeType,
    required bool openConversation,
    FutureOr<void> Function()? onTap,
    SessionIdentity? expectedIdentity,
    int? expectedClearGeneration,
  }) async {
    bool isCurrent() =>
        expectedIdentity == null ||
        _isCurrentRefresh(
          expectedIdentity,
          expectedClearGeneration ?? _sessionClearGeneration,
        );
    if (!isCurrent()) return;
    if (peerUserId.isEmpty) {
      return;
    }

    final dedupKey = 'friend_outcome:${noticeType}_$peerUserId';
    await PushMsgKeyDedup.instance.ensureReady();
    if (PushMsgKeyDedup.instance.wasHandled(dedupKey)) {
      return;
    }
    if (!PushMsgKeyDedup.instance.tryClaim(dedupKey)) {
      return;
    }

    final now = DateTime.now();
    final last = _lastFriendAddedNoticeAt;
    if (_lastFriendAddedNoticeKey == peerUserId &&
        last != null &&
        now.difference(last) < const Duration(seconds: 2)) {
      return;
    }

    final name = await _resolveDisplayName(peerUserId);
    if (!isCurrent()) return;
    final faceUrl = await _resolveFaceUrl(peerUserId);
    if (!isCurrent()) return;
    final shown = await _showFriendNotice(
      key: '${noticeType}_$peerUserId',
      title: title,
      body: bodyBuilder(name),
      showName: name.isEmpty ? title : name,
      faceUrl: faceUrl,
      userID: peerUserId,
      type: noticeType,
      conversationID: openConversation ? 'c2c_$peerUserId' : null,
      onTap: onTap ??
          (openConversation
              ? () => RouteHandler.openConversation('c2c_$peerUserId')
              : RouteHandler.openNewContact),
      expectedIdentity: expectedIdentity,
      expectedClearGeneration: expectedClearGeneration,
    );
    if (shown) {
      _lastFriendAddedNoticeAt = DateTime.now();
      _lastFriendAddedNoticeKey = peerUserId;
    }
  }

  Future<bool> _showFriendNotice({
    required String key,
    required String title,
    required String body,
    required String userID,
    required String type,
    required FutureOr<void> Function() onTap,
    String? conversationID,
    String faceUrl = '',
    String showName = '',
    SessionIdentity? expectedIdentity,
    int? expectedClearGeneration,
  }) async {
    if (expectedIdentity != null &&
        !_isCurrentRefresh(
          expectedIdentity,
          expectedClearGeneration ?? _sessionClearGeneration,
        )) {
      return false;
    }
    // 进程内前台/后台/锁屏走本策略。杀进程远程 APNS 音震取决于服务端载荷。
    final decision = SystemMessageAlertPolicy.decide(
      SystemMessageAlertPolicy.currentSettings(),
    );
    if (!decision.postNotice) {
      return false;
    }
    final playSound = decision.playSound;
    final playVibration = decision.playVibration;

    final systemShown =
        await LocalSystemNotificationService.instance.showChatMessage(
      title: title,
      body: body,
      conversationID: conversationID ?? '',
      ext: jsonEncode(<String, dynamic>{
        'type': type,
        'userID': userID,
        'conversationID': conversationID ?? '',
      }),
      avatarUrl: faceUrl.isNotEmpty ? faceUrl : null,
      playSound: playSound,
      playVibration: playVibration,
      useSystemMessageChannel: true,
    );
    if (expectedIdentity != null &&
        !_isCurrentRefresh(
          expectedIdentity,
          expectedClearGeneration ?? _sessionClearGeneration,
        )) {
      return false;
    }
    if (systemShown) {
      // iOS 系统通知震动绑在默认音上；只震不响时进程内补应用内振动。
      if (playVibration &&
          !playSound &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        unawaited(InAppNotificationVibration.playMessageReceived());
      }
      if (kDebugMode) {
        debugPrint('FriendRequestNotice: system notification shown type=$type');
      }
      return true;
    }

    if (playSound) {
      unawaited(InAppNotificationSound.playMessageReceived());
    }
    if (playVibration) {
      unawaited(InAppNotificationVibration.playMessageReceived());
    }
    final noticeShown = AppDialog.showNotice(
      title: title,
      message: body.isNotEmpty ? body : title,
      duration: const Duration(seconds: 3),
      onTap: onTap,
      enableReminderHaptic: playVibration,
    );
    if (noticeShown) {
      if (kDebugMode) {
        debugPrint('FriendRequestNotice: app notice shown type=$type');
      }
      return true;
    }
    return false;
  }

  /// 离线 Push / 前台补推时刷新待处理申请并尝试弹出提示。
  Future<void> handlePushFriendRequest({
    String? fromUserId,
    String? displayName,
    int? requestId,
  }) async {
    await refreshPendingCount(notifyUnseen: true);
    final id = fromUserId?.trim() ?? '';
    if (id.isEmpty) {
      return;
    }
    final dedupKey = _friendNoticeKey(requestId: requestId, userId: id);
    await PushMsgKeyDedup.instance.ensureReady();
    if (PushMsgKeyDedup.instance.wasHandled(dedupKey)) {
      return;
    }
    if (!PushMsgKeyDedup.instance.tryClaim(dedupKey)) {
      return;
    }
    await _notifyFriendRequestReceived(userID: id, displayName: displayName);
  }

  Future<void> handlePushFriendList(Map<String, dynamic> data) async {
    await FriendSyncService.instance.handlePushFriendList(data);
  }

  Future<void> handlePushGroupChanged(Map<String, dynamic> data) async {
    await GroupSyncService.instance.handlePushGroupChanged(data);
  }

  Future<void> refreshPendingCount({
    bool markRead = false,
    bool notifyUnseen = false,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    final clearGeneration = _sessionClearGeneration;
    if (identity.ownerUserId.isEmpty ||
        !_isCurrentRefresh(identity, clearGeneration)) {
      return;
    }
    try {
      if (markRead) {
        final incoming = await FriendRequestApi.instance.fetchIncomingPending();
        if (!_isCurrentRefresh(identity, clearGeneration)) {
          return;
        }
        _observedIncoming = List<FriendRequestRecord>.from(incoming);
        await commitObservedAsRead();
        return;
      }
      await ensureWatermarkLoaded();
      if (!_isCurrentRefresh(identity, clearGeneration)) {
        return;
      }
      final incoming = await FriendRequestApi.instance.fetchIncomingPending();
      if (!_isCurrentRefresh(identity, clearGeneration)) {
        return;
      }
      await _syncIncomingNotifications(
        incoming,
        source: 'refresh',
        notifyUnseen: notifyUnseen,
        identity: identity,
        clearGeneration: clearGeneration,
      );
    } catch (e) {
      _log('refreshPendingCount failed $e');
    }
  }

  String _selfUserId() {
    final authoritative = ChatIdFormat.rawUserUid(
      ContactSocialCacheStore.safeLoginUserId(),
    );
    if (authoritative.isNotEmpty) return authoritative;
    try {
      final fromCore = ChatIdFormat.rawUserUid(
        TIMUIKitCore.getInstance().loginInfo.userID,
      );
      if (fromCore.isNotEmpty) {
        return fromCore;
      }
    } catch (_) {}
    return ChatIdFormat.rawUserUid(
      serviceLocator<TUISelfInfoViewModel>().loginInfo?.userID,
    );
  }

  bool _eventInvolvesSelf(FriendRealtimeEvent event, String selfId) {
    return _isSameUser(event.fromUserId, selfId) ||
        _isSameUser(event.toUserId, selfId);
  }

  String _peerUserIdFromEvent(FriendRealtimeEvent event) {
    final selfId = _selfUserId();
    if (selfId.isNotEmpty && _isSameUser(event.fromUserId, selfId)) {
      return event.toUserId.trim();
    }
    if (selfId.isNotEmpty && _isSameUser(event.toUserId, selfId)) {
      return event.fromUserId.trim();
    }
    return event.toUserId.trim().isNotEmpty
        ? event.toUserId.trim()
        : event.fromUserId.trim();
  }

  bool _isSameUser(String? a, String? b) {
    final left = ChatIdFormat.rawUserUid(a);
    final right = ChatIdFormat.rawUserUid(b);
    return left.isNotEmpty && right.isNotEmpty && left == right;
  }

  Future<String> _resolveDisplayName(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) {
      return '';
    }
    try {
      final res = await TIMUIKitCore.getSDKInstance().getUsersInfo(
        userIDList: [id],
      );
      if (res.code == 0 && res.data != null && res.data!.isNotEmpty) {
        final nick = res.data!.first.nickName?.trim() ?? '';
        if (nick.isNotEmpty) {
          return nick;
        }
      }
    } catch (_) {}
    return id;
  }

  Future<String> _resolveFaceUrl(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) {
      return '';
    }
    try {
      final res = await TIMUIKitCore.getSDKInstance().getUsersInfo(
        userIDList: [id],
      );
      if (res.code == 0 && res.data != null && res.data!.isNotEmpty) {
        return res.data!.first.faceUrl?.trim() ?? '';
      }
    } catch (_) {}
    return '';
  }
}

/// Future: replace createdAt with a server revision/sequence when the API
/// provides one. Comparison stays in [isFriendRequestAfterReadWatermark].
class FriendRequestReadWatermark {
  const FriendRequestReadWatermark({
    required this.createdAtMs,
    required this.idsAtCreatedAt,
  });

  const FriendRequestReadWatermark.empty()
      : createdAtMs = 0,
        idsAtCreatedAt = const <String>{};

  final int createdAtMs;
  final Set<String> idsAtCreatedAt;

  String toJsonString() {
    final ids = idsAtCreatedAt.toList()..sort();
    return jsonEncode({
      'createdAt': createdAtMs,
      'ids': ids,
    });
  }

  static FriendRequestReadWatermark fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const FriendRequestReadWatermark.empty();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const FriendRequestReadWatermark.empty();
      }
      final map = Map<String, dynamic>.from(decoded);
      final createdAt = _watermarkInt(map['createdAt']);
      final ids = <String>{};
      final idsRaw = map['ids'];
      if (idsRaw is List) {
        for (final item in idsRaw) {
          final id = item.toString().trim();
          if (id.isNotEmpty) {
            ids.add(id);
          }
        }
      }
      return FriendRequestReadWatermark(
        createdAtMs: createdAt,
        idsAtCreatedAt: ids,
      );
    } catch (_) {
      return const FriendRequestReadWatermark.empty();
    }
  }
}

int _watermarkInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String friendRequestUnreadIdentity(FriendRequestRecord record) {
  if (record.hasServerId) {
    return '${record.id}';
  }
  return record.identityKey;
}

bool isFriendRequestAfterReadWatermark(
  FriendRequestRecord record,
  FriendRequestReadWatermark watermark,
) {
  final createdAt = record.addTime;
  if (createdAt > watermark.createdAtMs) {
    return true;
  }
  if (createdAt < watermark.createdAtMs) {
    return false;
  }
  return !watermark.idsAtCreatedAt
      .contains(friendRequestUnreadIdentity(record));
}

int computeFriendRequestUnreadCount({
  required List<FriendRequestRecord> pending,
  required FriendRequestReadWatermark watermark,
}) {
  return pending.where((record) {
    return record.isIncoming &&
        record.isPending &&
        isFriendRequestAfterReadWatermark(record, watermark);
  }).length;
}

FriendRequestReadWatermark watermarkFromObserved(
  List<FriendRequestRecord> observed,
  FriendRequestReadWatermark previous,
) {
  var maxCreatedAt = 0;
  for (final record in observed) {
    if (!record.isIncoming || !record.isPending) {
      continue;
    }
    if (record.addTime > maxCreatedAt) {
      maxCreatedAt = record.addTime;
    }
  }
  if (maxCreatedAt < previous.createdAtMs) {
    return previous;
  }
  final ids = <String>{};
  if (maxCreatedAt == previous.createdAtMs) {
    ids.addAll(previous.idsAtCreatedAt);
  }
  for (final record in observed) {
    if (!record.isIncoming || !record.isPending) {
      continue;
    }
    if (record.addTime == maxCreatedAt) {
      ids.add(friendRequestUnreadIdentity(record));
    }
  }
  if (maxCreatedAt == 0 && ids.isEmpty) {
    return previous;
  }
  return FriendRequestReadWatermark(
    createdAtMs: maxCreatedAt,
    idsAtCreatedAt: ids,
  );
}
