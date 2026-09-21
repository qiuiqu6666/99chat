// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:convert';

import 'package:tencent_cloud_chat_uikit/business_logic/controllers/conversation_text_search_controller.dart';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_search_param.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/self_hosted_friendship_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/search_display_resolvers.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/picker_user_filter.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/history_proof.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/history_search_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/search_account_owner.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/user_display_profile.dart';

enum KeywordListMatchType {
  V2TIM_KEYWORD_LIST_MATCH_TYPE_OR,
  V2TIM_KEYWORD_LIST_MATCH_TYPE_AND
}

class TUISearchViewModel extends ChangeNotifier {
  final FriendshipServices _friendshipServices =
      serviceLocator<FriendshipServices>();
  final MessageService _messageService = serviceLocator<MessageService>();
  late final Im06MessageSearchCoordinator _im06MessageSearchCoordinator =
      Im06MessageSearchCoordinator(
    adapter: TUIKitIm06MessageSearchAdapter(_messageService),
  );
  final ConversationService _conversationService =
      serviceLocator<ConversationService>();
  final GroupServices _groupServices = serviceLocator<GroupServices>();

  List<V2TimFriendInfoResult>? friendList = [];

  List<V2TimMessageSearchResultItem>? msgList = [];
  int msgPage = 0;
  int totalMsgCount = 0;
  String _globalMessageSearchCursor = '';
  int _globalMessageLocalPage = 0;
  bool _globalMessageLocalHasMore = false;
  bool _globalMessageLocalLoadingMore = false;
  bool _globalMessageCloudHasMore = false;
  bool _globalMessageCloudLoadingMore = false;
  static const int _globalMessagePageSize = 5;
  bool get hasMoreGlobalMessageResults =>
      _globalMessageLocalHasMore || _globalMessageCloudHasMore;

  late final ConversationTextSearchController conversationTextSearch =
      ConversationTextSearchController(
    read: ({required cloud, required param}) => _searchMessagesThroughIm06(
      source: cloud ? ImHistorySource.cloud : ImHistorySource.local,
      searchParam: param,
    ),
    ownerId: _currentLoginUserId,
    accountGeneration: () => SessionIdentityService.instance.generation,
    onChanged: notifyListeners,
    onTrace: (event, fields) {
      debugPrint('[ConversationSearch] event=$event ${jsonEncode(fields)}');
    },
  );
  int get totalMsgInConversationCount => conversationTextSearch.totalCount;
  List<V2TimMessage> get currentMsgListForConversation =>
      conversationTextSearch.messages;
  bool get hasMoreConversationTextResults => conversationTextSearch.hasMore;

  /// 会话内图片/文件消息（用于文件名关键词搜索）。
  List<V2TimMessage> mediaFileMsgListForConversation = [];
  bool mediaFileHasMore = true;
  bool mediaFileLoading = false;
  String? _mediaFileLastMsgID;
  String _mediaFileCloudCursor = '';
  bool _mediaFileCloudEnabled = true;
  String _mediaFileContextKey = '';
  int _mediaFileGeneration = 0;

  /// 媒体/文件专用浏览页数据。
  List<V2TimMessage> conversationMediaMessages = [];
  List<V2TimMessage> conversationFileMessages = [];
  bool conversationAssetLoading = false;
  bool conversationAssetHasMore = true;
  String? _conversationAssetLastMsgID;
  String _conversationAssetCloudCursor = '';
  bool _conversationAssetCloudEnabled = true;
  String _conversationAssetContextKey = '';
  int _conversationAssetGeneration = 0;

  List<V2TimGroupInfo>? groupList = [];

  List<V2TimConversation?> conversationList = [];

  bool friendSearchLoading = false;
  bool groupSearchLoading = false;
  bool messageLocalLoading = false;
  bool messageCloudLoading = false;
  bool friendFirstRoundComplete = false;
  bool groupFirstRoundComplete = false;
  bool messageLocalFirstRoundComplete = false;
  bool messageCloudFirstRoundComplete = false;
  bool get globalSearchLoading =>
      friendSearchLoading || groupSearchLoading || messageLocalLoading;
  String _completedGlobalSearchKey = '';
  String _activeGlobalSearchKey = '';
  Set<String>? _joinedGroupIdsForSearch;

  /// 绑定当前 IM 登录用户；切号后与此不一致则强制丢弃搜索上下文，避免串号。
  String _boundLoginUserId = '';

  /// 最近一次已完成的全局搜索关键词；与输入框一致时才可展示「无结果」空状态。
  String get completedGlobalSearchKey => _completedGlobalSearchKey;

  Timer? _globalSearchDebounce;
  int _globalSearchGeneration = 0;
  int get globalSearchGeneration => _globalSearchGeneration;
  Future<void> Function(List<String> conversationIds)? appSearchDisplayHydrator;
  static const Duration _globalSearchDebounceDuration =
      Duration(milliseconds: 100);

  Timer? _conversationMediaSearchDebounce;
  int _conversationMediaSearchGeneration = 0;
  static const Duration _conversationMediaSearchDebounceDuration =
      Duration(milliseconds: 500);

  Future<List<V2TimConversation?>?> initConversationMsg() async {
    _syncSearchAccountScope(forceReloadContext: false);
    try {
      final fromLocal = await ConversationLocalStore.instance.loadUiWindow();
      if (fromLocal.isNotEmpty) {
        conversationList = fromLocal
            .where((item) => !shouldHideConversationFromPickers(item))
            .map((item) => item as V2TimConversation?)
            .toList(growable: false);
        return conversationList;
      }
    } catch (_) {}

    final cached = serviceLocator<TUIConversationViewModel>().conversationList;
    if (cached.isNotEmpty) {
      conversationList = cached
          .where((item) => !shouldHideConversationFromPickers(item))
          .toList(growable: false);
      return conversationList;
    }

    final conversationResult = await _conversationService.getConversationList(
        nextSeq: "0", count: 500);
    final conversationListData = conversationResult?.conversationList;
    conversationList = (conversationListData ?? [])
        .where((item) => !shouldHideConversationFromPickers(item))
        .toList(growable: false);
    return conversationListData;
  }

  void _mergeConversationsIntoSearchContext(
    Iterable<V2TimConversation> incoming,
  ) {
    final byId = <String, V2TimConversation>{};
    for (final item in conversationList) {
      if (item == null) {
        continue;
      }
      final id = item.conversationID.trim();
      if (id.isNotEmpty) {
        byId[id] = item;
      }
    }
    for (final item in incoming) {
      if (shouldHideConversationFromPickers(item)) {
        continue;
      }
      final id = item.conversationID.trim();
      if (id.isEmpty) {
        continue;
      }
      byId[id] = item;
    }
    conversationList = byId.values
        .map((item) => item as V2TimConversation?)
        .toList(growable: false);
  }

  Future<List<V2TimConversation>> _localConversationsMatchingKeyword(
    String keyword, {
    int? generation,
    void Function(List<V2TimConversation> batch)? onBatch,
  }) async {
    final q = keyword.trim();
    if (q.isEmpty) {
      return const [];
    }
    try {
      final hits =
          await ConversationLocalStore.instance.searchConversationsAllPages(
        keyword: q,
        shouldCancel: generation == null
            ? null
            : () => generation != _globalSearchGeneration,
        onBatch: (batch, _) {
          _mergeConversationsIntoSearchContext(batch);
          onBatch?.call(batch);
        },
      );
      _mergeConversationsIntoSearchContext(hits);
      return hits;
    } catch (_) {
      return const [];
    }
  }

  void _applyLocalC2cMatchesToFriendMap(
    Map<String, V2TimFriendInfoResult> byUserId,
    Iterable<V2TimConversation> localMatches, {
    required bool Function(String userId) keepUser,
  }) {
    for (final conversation in localMatches) {
      if (isGroupConversation(conversation)) {
        continue;
      }
      final friendInfo = friendInfoFromC2cConversation(conversation);
      final userId = friendInfo.userID.trim();
      if (userId.isEmpty || byUserId.containsKey(userId)) {
        continue;
      }
      if (!keepUser(userId)) {
        continue;
      }
      upsertFriendSearchResult(
        byUserId,
        _friendResultWithDisplay(friendInfo),
      );
    }
  }

  void _applyLocalGroupMatchesToGroupMap(
    Map<String, V2TimGroupInfo> byGroupId,
    Iterable<V2TimConversation> localMatches,
  ) {
    for (final conversation in localMatches) {
      if (shouldHideConversationFromPickers(conversation)) {
        continue;
      }
      if (!isGroupConversation(conversation)) {
        continue;
      }
      final groupInfo = groupInfoFromGroupConversation(conversation);
      final groupId = groupInfo.groupID.trim();
      if (groupId.isEmpty || byGroupId.containsKey(groupId)) {
        continue;
      }
      if (!_keepExternalGroupSearchHit(groupId)) {
        continue;
      }
      byGroupId[groupId] = groupInfo;
    }
  }

  /// 群名变更后轻量修补搜索会话缓存，避免全局搜索仍显示旧 showName。
  void patchGroupShowNameLocally({
    required String groupId,
    required String showName,
  }) {
    final id = groupId.trim();
    final name = showName.trim();
    if (id.isEmpty || name.isEmpty || conversationList.isEmpty) {
      return;
    }
    var changed = false;
    for (final item in conversationList) {
      if (item == null) {
        continue;
      }
      final gid = item.groupID?.trim() ?? '';
      final fromCid = groupIdFromConversationId(item.conversationID) ?? '';
      final hit = searchGroupIdsEquivalent(gid, id) ||
          searchGroupIdsEquivalent(fromCid, id);
      if (!hit) {
        continue;
      }
      if ((item.showName?.trim() ?? '') == name) {
        continue;
      }
      item.showName = name;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  String _currentLoginUserId() {
    String coreUserId = '';
    bool coreLoginSucceeded = false;
    try {
      final core = serviceLocator<CoreServicesImpl>();
      coreUserId = core.loginInfo.userID;
      coreLoginSucceeded = core.isLoginSuccess;
    } catch (_) {}
    return resolveSearchAccountOwner(
      session: SessionManager.instance.state,
      authenticatedUserId: ApiClient.instance.authenticatedUserId,
      coreUserId: coreUserId,
      coreLoginSucceeded: coreLoginSucceeded,
    );
  }

  /// 登录用户变化时丢弃全局搜索上下文，防止复用上一账号会话/群缓存。
  bool _syncSearchAccountScope({required bool forceReloadContext}) {
    final current = _currentLoginUserId();
    final changed = _boundLoginUserId.isNotEmpty &&
        current.isNotEmpty &&
        _boundLoginUserId != current;
    final missingBinding = _boundLoginUserId.isEmpty && current.isNotEmpty;
    if (forceReloadContext || changed || missingBinding) {
      if (changed || forceReloadContext) {
        conversationList = [];
        _joinedGroupIdsForSearch = null;
        friendList = [];
        groupList = [];
        _resetGlobalMessageLaneState();
        _resetGlobalSearchProgress(keepCompletedKey: false);
        conversationTextSearch.clear(notify: false);
        _resetConversationFilterState();
      }
      if (current.isNotEmpty) {
        _boundLoginUserId = current;
      } else if (forceReloadContext) {
        _boundLoginUserId = '';
      }
      return true;
    }
    if (current.isNotEmpty) {
      _boundLoginUserId = current;
    }
    return false;
  }

  /// 消息搜索前：当前 IM 用户必须已绑定且可用。
  bool _canSearchLocalMessagesForCurrentUser() {
    final current = _currentLoginUserId();
    if (current.isEmpty) {
      return false;
    }
    if (_boundLoginUserId.isNotEmpty && _boundLoginUserId != current) {
      _syncSearchAccountScope(forceReloadContext: true);
    }
    _boundLoginUserId = current;
    return true;
  }

  Future<V2TimValueCallback<V2TimMessageSearchResult>>
      _searchMessagesThroughIm06({
    required ImHistorySource source,
    required V2TimMessageSearchParam searchParam,
  }) async {
    final response = await _im06MessageSearchCoordinator.search(
      platform: kIsWeb ? ImPlatform.web : ImPlatform.android,
      requestedSource: source,
      searchParam: searchParam,
    );
    return response.result ??
        V2TimValueCallback<V2TimMessageSearchResult>(
          code: -1,
          desc: response.errorDescription ?? 'IM-06 message search unavailable',
        );
  }

  String _messageSearchIdentity(V2TimMessage message) {
    return searchMessageStableId(message);
  }

  List<V2TimMessage> _mergeMessageLists(
    Iterable<V2TimMessage> current,
    Iterable<V2TimMessage> incoming,
  ) {
    return mergeSearchHitMessages(current, incoming);
  }

  List<V2TimMessageSearchResultItem> _mergeSearchResultItems(
    Iterable<V2TimMessageSearchResultItem> current,
    Iterable<V2TimMessageSearchResultItem> incoming,
  ) {
    return mergeGlobalMessageSearchResults(current, incoming);
  }

  void _resetGlobalMessageLaneState() {
    msgList = [];
    totalMsgCount = 0;
    msgPage = 0;
    _globalMessageSearchCursor = '';
    _globalMessageLocalPage = 0;
    _globalMessageLocalHasMore = false;
    _globalMessageLocalLoadingMore = false;
    _globalMessageCloudHasMore = false;
    _globalMessageCloudLoadingMore = false;
    messageLocalLoading = false;
    messageCloudLoading = false;
    messageLocalFirstRoundComplete = false;
    messageCloudFirstRoundComplete = false;
  }

  void _resetGlobalSearchProgress({required bool keepCompletedKey}) {
    friendSearchLoading = false;
    groupSearchLoading = false;
    friendFirstRoundComplete = false;
    groupFirstRoundComplete = false;
    if (!keepCompletedKey) {
      _completedGlobalSearchKey = '';
      _activeGlobalSearchKey = '';
    }
  }

  void _maybeMarkGlobalSearchComplete(String searchKey, int generation) {
    if (!_isCurrentGeneration(generation, searchKey)) {
      return;
    }
    if (!friendFirstRoundComplete ||
        !groupFirstRoundComplete ||
        !messageLocalFirstRoundComplete ||
        !messageCloudFirstRoundComplete) {
      return;
    }
    _completedGlobalSearchKey = searchKey;
  }

  bool _isCurrentGeneration(int generation, [String? keyword]) {
    if (generation != _globalSearchGeneration) {
      return false;
    }
    if (keyword != null && keyword != _activeGlobalSearchKey) {
      return false;
    }
    return true;
  }

  void initSearch({bool notify = true}) {
    _globalSearchDebounce?.cancel();
    _conversationMediaSearchDebounce?.cancel();
    _globalSearchGeneration++;
    _conversationMediaSearchGeneration++;
    friendList = [];
    _resetGlobalMessageLaneState();
    groupList = [];
    conversationTextSearch.clear(notify: false);
    _resetConversationFilterState();
    mediaFileMsgListForConversation = [];
    mediaFileLoading = false;
    mediaFileHasMore = true;
    _mediaFileLastMsgID = null;
    _mediaFileCloudCursor = '';
    _mediaFileCloudEnabled = true;
    _mediaFileContextKey = '';
    _mediaFileGeneration++;
    conversationMediaMessages = [];
    conversationFileMessages = [];
    conversationAssetLoading = false;
    conversationAssetHasMore = true;
    _conversationAssetLastMsgID = null;
    _conversationAssetCloudCursor = '';
    _conversationAssetCloudEnabled = true;
    _conversationAssetContextKey = '';
    _conversationAssetGeneration++;
    _resetGlobalSearchProgress(keepCompletedKey: false);
    _joinedGroupIdsForSearch = null;
    // 必须清会话缓存：否则切号后仍复用上一账号 conversationList。
    conversationList = [];
    _syncSearchAccountScope(forceReloadContext: false);
    if (notify) {
      notifyListeners();
    }
  }

  /// 登出 / 切号时清空全部全局搜索态（含会话上下文）。
  void clearSession({bool notify = false}) {
    _globalSearchDebounce?.cancel();
    _conversationMediaSearchDebounce?.cancel();
    _globalSearchGeneration++;
    _conversationMediaSearchGeneration++;
    friendList = [];
    groupList = [];
    conversationList = [];
    _resetGlobalMessageLaneState();
    conversationTextSearch.clear(notify: false);
    _resetConversationFilterState();
    mediaFileMsgListForConversation = [];
    mediaFileLoading = false;
    mediaFileHasMore = true;
    _mediaFileLastMsgID = null;
    _mediaFileCloudCursor = '';
    _mediaFileCloudEnabled = true;
    _mediaFileContextKey = '';
    _mediaFileGeneration++;
    conversationMediaMessages = [];
    conversationFileMessages = [];
    conversationAssetLoading = false;
    conversationAssetHasMore = true;
    _conversationAssetLastMsgID = null;
    _conversationAssetCloudCursor = '';
    _conversationAssetCloudEnabled = true;
    _conversationAssetContextKey = '';
    _conversationAssetGeneration++;
    _resetGlobalSearchProgress(keepCompletedKey: false);
    _joinedGroupIdsForSearch = null;
    _boundLoginUserId = '';
    if (notify) {
      notifyListeners();
    }
  }

  /// 进入全局搜索页时预热会话/群/通讯录缓存，缩短首次输入后的首屏等待。
  Future<void> warmGlobalSearchContext() async {
    _syncSearchAccountScope(forceReloadContext: false);
    final friendshipModel = serviceLocator<TUIFriendShipViewModel>();
    final contactWarm = (friendshipModel.friendList == null ||
            friendshipModel.friendList!.isEmpty)
        ? friendshipModel.loadContactListData()
        : Future<void>.value();
    await Future.wait<void>([
      initConversationMsg().then((_) => null),
      _ensureJoinedGroupIdsForSearch(),
      contactWarm,
    ]);
  }

  Future<void> _ensureJoinedGroupIdsForSearch() async {
    _joinedGroupIdsForSearch = await _loadJoinedGroupIdsForSearch();
  }

  Future<void> _ensureGlobalSearchContext(int generation) async {
    final scopeChanged = _syncSearchAccountScope(forceReloadContext: false);
    final futures = <Future<void>>[
      _ensureJoinedGroupIdsForSearch(),
    ];
    if (scopeChanged || conversationList.isEmpty) {
      futures.add(initConversationMsg().then((_) => null));
    }
    await Future.wait<void>(futures);
    if (generation != _globalSearchGeneration) {
      return;
    }
  }

  /// 自托管模式下刷新并返回当前已加入群 ID 集合；非自托管返回 null（跳过过滤）。
  /// 读库失败返回 null；成功且 0 群返回空集合。禁止用 ViewModel.groupList。
  Future<Set<String>?> _loadJoinedGroupIdsForSearch() async {
    if (!SelfHostedGroupBridge.enabled) {
      return null;
    }
    return GroupLocalStore.instance.readJoinedGroupIdsForSearch();
  }

  List<V2TimMessageSearchResultItem>? _filterMsgListForJoinedGroups(
    List<V2TimMessageSearchResultItem>? items,
  ) {
    final joinedIds = _joinedGroupIdsForSearch;
    if (joinedIds == null || items == null) {
      return items;
    }
    return filterMessageSearchResultsByJoinedGroups(items, joinedIds)
        .cast<V2TimMessageSearchResultItem>();
  }

  ({String? userID, String? groupID})? _conversationTargets(
      String conversationId) {
    if (conversationId.startsWith('c2c_')) {
      final userID = conversationId.substring(4).trim();
      return userID.isEmpty ? null : (userID: userID, groupID: null);
    }
    if (conversationId.startsWith('group_')) {
      final groupID = conversationId.substring(6).trim();
      return groupID.isEmpty ? null : (userID: null, groupID: groupID);
    }
    return null;
  }

  ({String? userID, String? groupID})? _resolveConversationTargets({
    required String conversationId,
    String? groupID,
    String? userID,
  }) {
    final parsed = _conversationTargets(conversationId);
    if (parsed != null) {
      return parsed;
    }
    final resolvedGroupId = groupID?.trim() ?? '';
    if (resolvedGroupId.isNotEmpty) {
      return (userID: null, groupID: resolvedGroupId);
    }
    final resolvedUserId = userID?.trim() ?? '';
    if (resolvedUserId.isNotEmpty) {
      return (userID: resolvedUserId, groupID: null);
    }
    return null;
  }

  bool _messageMatchesSenderFilter(
      V2TimMessage message, Set<String> senderSet) {
    final sender = (message.sender ?? message.userID ?? '').trim();
    final senderAlt = (message.userID ?? message.sender ?? '').trim();
    if (senderSet.contains(sender) || senderSet.contains(senderAlt)) {
      return true;
    }
    if (message.isSelf == true) {
      final loginUserId = _currentLoginUserId();
      if (loginUserId.isNotEmpty && senderSet.contains(loginUserId)) {
        return true;
      }
    }
    return false;
  }

  bool _isImageOrFileMessage(V2TimMessage message) {
    final type = message.elemType;
    return type == MessageElemType.V2TIM_ELEM_TYPE_IMAGE ||
        type == MessageElemType.V2TIM_ELEM_TYPE_FILE;
  }

  Future<List<V2TimMessage>> _loadConversationHistoryBatch({
    required String? userID,
    required String? groupID,
    required int count,
    String? lastMsgID,
  }) async {
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final localResult = await globalModel.getHistoryMessageListThroughIm06(
      userID: userID,
      groupID: groupID,
      count: count,
      lastMsgID: lastMsgID,
      getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    );
    final localBatch = localResult?.messageList ?? const <V2TimMessage>[];
    if (localBatch.isNotEmpty) {
      return localBatch;
    }
    final cloudResult = await globalModel.getHistoryMessageListThroughIm06(
      userID: userID,
      groupID: groupID,
      count: count,
      lastMsgID: lastMsgID,
      getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
    );
    return cloudResult?.messageList ?? const <V2TimMessage>[];
  }

  bool _mediaFileMatchesKeyword(V2TimMessage message, String keyword) {
    if (keyword.isEmpty) {
      return true;
    }
    final lower = keyword.toLowerCase();
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_FILE) {
      final name = message.fileElem?.fileName?.toLowerCase() ?? '';
      return name.contains(lower);
    }
    return false;
  }

  Future<void> loadMediaAndFileForConversation(
    String conversationId, {
    required bool reset,
    String keyword = '',
  }) async {
    if (reset) {
      _mediaFileGeneration++;
      mediaFileLoading = false;
      mediaFileMsgListForConversation = [];
      mediaFileHasMore = true;
      _mediaFileLastMsgID = null;
      _mediaFileCloudCursor = '';
      _mediaFileCloudEnabled = true;
      _mediaFileContextKey = '$conversationId|${keyword.trim()}';
    } else if (_mediaFileContextKey != '$conversationId|${keyword.trim()}') {
      return;
    }
    if (mediaFileLoading) {
      return;
    }
    if (!mediaFileHasMore) {
      return;
    }
    final targets = _conversationTargets(conversationId);
    if (targets == null) {
      mediaFileHasMore = false;
      notifyListeners();
      return;
    }

    mediaFileLoading = true;
    final generation = _mediaFileGeneration;
    notifyListeners();
    try {
      if (_mediaFileCloudEnabled && _canSearchLocalMessagesForCurrentUser()) {
        try {
          final result = await _searchMessagesThroughIm06(
            source: ImHistorySource.cloud,
            searchParam: V2TimMessageSearchParam(
              conversationID: conversationId,
              keywordList: keyword.trim().isEmpty ? const [] : [keyword.trim()],
              messageTypeList: const [
                MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
                MessageElemType.V2TIM_ELEM_TYPE_FILE,
              ],
              searchCount: 30,
              searchCursor: _mediaFileCloudCursor,
              type: KeywordListMatchType.V2TIM_KEYWORD_LIST_MATCH_TYPE_OR.index,
            ),
          );
          if (generation != _mediaFileGeneration) return;
          if (result.code == 0 && result.data != null) {
            final item =
                result.data!.messageSearchResultItems?.firstWhereOrNull(
                      (element) => element.conversationID == conversationId,
                    ) ??
                    (result.data!.messageSearchResultItems?.length == 1
                        ? result.data!.messageSearchResultItems!.first
                        : null);
            mediaFileMsgListForConversation = _mergeMessageLists(
              mediaFileMsgListForConversation,
              (item?.messageList ?? const []).where(
                (message) =>
                    _isImageOrFileMessage(message) &&
                    _mediaFileMatchesKeyword(message, keyword),
              ),
            );
            _mediaFileCloudCursor = result.data!.searchCursor ?? '';
            mediaFileHasMore = _mediaFileCloudCursor.isNotEmpty;
            return;
          }
          _mediaFileCloudEnabled = false;
        } catch (_) {
          _mediaFileCloudEnabled = false;
        }
      }

      final seen = mediaFileMsgListForConversation
          .map((m) => m.msgID ?? m.id ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      var appendedCount = 0;
      var keepLoading = true;
      while (keepLoading && mediaFileHasMore) {
        final batch = await _loadConversationHistoryBatch(
          userID: targets.userID,
          groupID: targets.groupID,
          count: 50,
          lastMsgID: _mediaFileLastMsgID,
        );
        if (generation != _mediaFileGeneration) return;
        if (batch.isEmpty) {
          mediaFileHasMore = false;
          break;
        }
        final nextLastMsgId = batch.last.msgID;
        if (nextLastMsgId == null ||
            nextLastMsgId.isEmpty ||
            nextLastMsgId == _mediaFileLastMsgID) {
          mediaFileHasMore = false;
          break;
        }
        _mediaFileLastMsgID = nextLastMsgId;
        if (batch.length < 50) {
          mediaFileHasMore = false;
        }

        for (final message in batch) {
          if (!_isImageOrFileMessage(message)) {
            continue;
          }
          if (!_mediaFileMatchesKeyword(message, keyword)) {
            continue;
          }
          final id = message.msgID ?? message.id ?? '';
          if (id.isNotEmpty && seen.contains(id)) {
            continue;
          }
          if (id.isNotEmpty) {
            seen.add(id);
          }
          mediaFileMsgListForConversation.add(message);
          appendedCount++;
        }
        keepLoading = appendedCount == 0;
      }
    } finally {
      if (generation == _mediaFileGeneration) {
        mediaFileLoading = false;
        notifyListeners();
      }
    }
  }

  List<V2TimMessage> mergedConversationSearchResults(
      {required String keyword}) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final seen = <String>{};
    final merged = <V2TimMessage>[];
    void addMessage(V2TimMessage message) {
      final id = message.msgID ?? message.id ?? '';
      if (id.isNotEmpty && seen.contains(id)) {
        return;
      }
      if (id.isNotEmpty) {
        seen.add(id);
      }
      merged.add(message);
    }

    for (final message in currentMsgListForConversation) {
      addMessage(message);
    }
    for (final message in mediaFileMsgListForConversation) {
      if (_mediaFileMatchesKeyword(message, trimmed)) {
        addMessage(message);
      }
    }
    merged.sort(
      (a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0),
    );
    return merged;
  }

  bool _isMediaMessage(V2TimMessage message) {
    final type = message.elemType;
    return type == MessageElemType.V2TIM_ELEM_TYPE_IMAGE ||
        type == MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
  }

  bool _isFileMessage(V2TimMessage message) {
    return message.elemType == MessageElemType.V2TIM_ELEM_TYPE_FILE;
  }

  Future<void> loadConversationAssets(
    String conversationId, {
    required bool reset,
    String? userID,
    String? groupID,
  }) async {
    if (reset) {
      _conversationAssetGeneration++;
      conversationAssetLoading = false;
      conversationMediaMessages = [];
      conversationFileMessages = [];
      conversationAssetHasMore = true;
      _conversationAssetLastMsgID = null;
      _conversationAssetCloudCursor = '';
      _conversationAssetCloudEnabled = true;
      _conversationAssetContextKey = conversationId;
    } else if (_conversationAssetContextKey != conversationId) {
      return;
    }
    if (conversationAssetLoading) {
      return;
    }
    if (!conversationAssetHasMore) {
      return;
    }
    final targets = _resolveConversationTargets(
      conversationId: conversationId,
      userID: userID,
      groupID: groupID,
    );
    if (targets == null) {
      conversationAssetHasMore = false;
      notifyListeners();
      return;
    }

    conversationAssetLoading = true;
    final generation = _conversationAssetGeneration;
    notifyListeners();
    try {
      if (_conversationAssetCloudEnabled &&
          _canSearchLocalMessagesForCurrentUser()) {
        try {
          final result = await _searchMessagesThroughIm06(
            source: ImHistorySource.cloud,
            searchParam: V2TimMessageSearchParam(
              conversationID: conversationId,
              keywordList: const [],
              messageTypeList: _conversationAssetSearchMessageTypes,
              searchCount: 50,
              searchCursor: _conversationAssetCloudCursor,
              type: KeywordListMatchType.V2TIM_KEYWORD_LIST_MATCH_TYPE_OR.index,
            ),
          );
          if (generation != _conversationAssetGeneration) return;
          if (result.code == 0 && result.data != null) {
            final item =
                result.data!.messageSearchResultItems?.firstWhereOrNull(
                      (element) => element.conversationID == conversationId,
                    ) ??
                    (result.data!.messageSearchResultItems?.length == 1
                        ? result.data!.messageSearchResultItems!.first
                        : null);
            final page = item?.messageList ?? const <V2TimMessage>[];
            conversationMediaMessages = _mergeMessageLists(
              conversationMediaMessages,
              page.where(_isMediaMessage),
            );
            conversationFileMessages = _mergeMessageLists(
              conversationFileMessages,
              page.where(_isFileMessage),
            );
            _conversationAssetCloudCursor = result.data!.searchCursor ?? '';
            conversationAssetHasMore = _conversationAssetCloudCursor.isNotEmpty;
            return;
          }
          _conversationAssetCloudEnabled = false;
        } catch (_) {
          _conversationAssetCloudEnabled = false;
        }
      }

      final seenMedia = conversationMediaMessages
          .map((m) => m.msgID ?? m.id ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final seenFile = conversationFileMessages
          .map((m) => m.msgID ?? m.id ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      var appendedCount = 0;
      var keepLoading = true;
      while (keepLoading && conversationAssetHasMore) {
        final batch = await _loadConversationHistoryBatch(
          userID: targets.userID,
          groupID: targets.groupID,
          count: 50,
          lastMsgID: _conversationAssetLastMsgID,
        );
        if (generation != _conversationAssetGeneration) return;
        if (batch.isEmpty) {
          conversationAssetHasMore = false;
          break;
        }
        final nextLastMsgId = batch.last.msgID;
        if (nextLastMsgId == null ||
            nextLastMsgId.isEmpty ||
            nextLastMsgId == _conversationAssetLastMsgID) {
          conversationAssetHasMore = false;
          break;
        }
        _conversationAssetLastMsgID = nextLastMsgId;
        if (batch.length < 50) {
          conversationAssetHasMore = false;
        }

        for (final message in batch) {
          final id = message.msgID ?? message.id ?? '';
          if (_isMediaMessage(message)) {
            if (id.isEmpty || !seenMedia.contains(id)) {
              if (id.isNotEmpty) {
                seenMedia.add(id);
              }
              conversationMediaMessages.add(message);
              appendedCount++;
            }
          }
          if (_isFileMessage(message)) {
            if (id.isEmpty || !seenFile.contains(id)) {
              if (id.isNotEmpty) {
                seenFile.add(id);
              }
              conversationFileMessages.add(message);
              appendedCount++;
            }
          }
        }
        keepLoading = appendedCount == 0;
      }
    } finally {
      if (generation == _conversationAssetGeneration) {
        conversationAssetLoading = false;
        notifyListeners();
      }
    }
  }

  void searchFriendByKey(String searchKey) async {
    final keyword = searchKey.trim();
    if (keyword.isEmpty) {
      friendList = [];
      notifyListeners();
      return;
    }
    try {
      final searchResult = await _friendshipServices.searchFriends(
        searchParam: _buildFriendSearchParam(keyword),
      );
      friendList = await _mergeFriendSearchResults(
        keyword,
        filterFriendSearchResultsForPickers(searchResult),
      );
    } catch (_) {
      friendList = await _mergeFriendSearchResults(
        keyword,
        const <V2TimFriendInfoResult>[],
      );
    }
    notifyListeners();
  }

  V2TimFriendSearchParam _buildFriendSearchParam(String keyword) {
    final keywordList = <String>[keyword];
    for (final needle in ChatIdFormat.searchKeywordNeedles(keyword)) {
      if (needle.isNotEmpty && !keywordList.contains(needle)) {
        keywordList.add(needle);
      }
    }
    return V2TimFriendSearchParam(
      keywordList: keywordList,
      isSearchUserID: true,
      isSearchNickName: true,
      isSearchRemark: true,
    );
  }

  V2TimGroupSearchParam _buildGroupSearchParam(String keyword) {
    final keywordList = <String>[keyword];
    for (final needle in ChatIdFormat.searchKeywordNeedles(keyword)) {
      if (needle.isNotEmpty && !keywordList.contains(needle)) {
        keywordList.add(needle);
      }
    }
    return V2TimGroupSearchParam(
      keywordList: keywordList,
      isSearchGroupID: true,
      isSearchGroupName: true,
    );
  }

  /// 好友删除后会话列表可能仍缓存 C2C，需清空以便下次搜索重新拉取。
  void invalidateGlobalSearchContext() {
    conversationList = [];
    _joinedGroupIdsForSearch = null;
    _syncSearchAccountScope(forceReloadContext: false);
  }

  bool _directoryHasFriend(String userId) {
    final directory = ImSdkRelationshipDirectory.instance;
    final id = userId.trim();
    if (id.isEmpty) {
      return false;
    }
    if (directory.friend(id) != null) {
      return true;
    }
    final raw = ChatIdFormat.rawUserUid(id);
    return raw.isNotEmpty && directory.friend(raw) != null;
  }

  bool _keepDirectoryFriend(String userId) {
    final directory = ImSdkRelationshipDirectory.instance;
    return keepSearchFriendByDirectoryMembership(
      userId: userId,
      containsFriend: _directoryHasFriend,
      snapshotComplete: directory.hasCompleteFriendSnapshot,
      friendCount: directory.friendCount,
    );
  }

  /// IM / 残留会话不是成员身份源。自托管下白名单未就绪时也不把它们当成仍在群。
  /// 「我的群聊」Directory 里有的群视为仍在群，避免 Store 白名单 ID 形态不一致被丢掉。
  bool _keepExternalGroupSearchHit(String groupId) {
    if (!SelfHostedGroupBridge.enabled) {
      return true;
    }
    if (_directoryHasGroup(groupId)) {
      return true;
    }
    final joinedIds = _joinedGroupIdsForSearch;
    if (joinedIds == null) {
      return false;
    }
    return searchJoinedGroupIdSetContains(joinedIds, groupId);
  }

  bool _directoryHasGroup(String groupId) {
    final directory = ImSdkRelationshipDirectory.instance;
    final id = groupId.trim();
    if (id.isEmpty) {
      return false;
    }
    if (directory.group(id) != null) {
      return true;
    }
    final normalized = ChatIdFormat.normalizeGroupId(id);
    if (normalized.isNotEmpty &&
        normalized != id &&
        directory.group(normalized) != null) {
      return true;
    }
    final token = ChatIdFormat.groupEquivalenceToken(id);
    if (token != null &&
        token.isNotEmpty &&
        token != id &&
        token != normalized &&
        directory.group(token) != null) {
      return true;
    }
    return false;
  }

  V2TimFriendInfoResult _friendResultWithDisplay(V2TimFriendInfo friend) {
    final display = UserDisplayProfile.name(
      userId: friend.userID,
      imRemark: friend.friendRemark,
      imNickName: friend.userProfile?.nickName,
    ).trim();
    if (display.isNotEmpty) {
      friend.friendRemark = display;
    }
    return V2TimFriendInfoResult(
      resultCode: 0,
      resultInfo: '',
      relation: 0,
      friendInfo: friend,
    );
  }

  bool _groupMatchesSearchDisplay(V2TimGroupInfo group, String keyword) {
    if (groupInfoMatchesSearchKeyword(group, keyword)) {
      return true;
    }
    if (keywordMatchesText(
      lookupSearchGroupStoreName(group.groupID),
      keyword,
    )) {
      return true;
    }
    return keywordMatchesText(
      lookupSearchGroupLocalName(group.groupID),
      keyword,
    );
  }

  void _publishFriendMap(
    Map<String, V2TimFriendInfoResult> byUserId, {
    required int generation,
    required String keyword,
    required void Function() notifyIfCurrent,
  }) {
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    friendList = byUserId.values.toList(growable: false);
    notifyIfCurrent();
  }

  void _publishGroupMap(
    Map<String, V2TimGroupInfo> byGroupId, {
    required int generation,
    required String keyword,
    required void Function() notifyIfCurrent,
  }) {
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    groupList = byGroupId.values.toList(growable: false);
    notifyIfCurrent();
  }

  Future<void> _addIndexedLocalFriendHits(
    String keyword,
    Map<String, V2TimFriendInfoResult> byUserId,
    int generation,
  ) async {
    if (!SelfHostedFriendshipBridge.localSearchEnabled) {
      return;
    }
    final page = await SelfHostedFriendshipBridge.searchFriendsLocal(
      keyword: keyword,
      limit: 80,
    );
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    final ids = <String>[
      for (final id in page.ids)
        if (_keepDirectoryFriend(id)) id,
    ];
    if (ids.isEmpty) {
      return;
    }
    final hydrated = await SelfHostedFriendshipBridge.hydrateFriends(ids);
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    for (final friend in filterFriendListForPickers(hydrated)) {
      final userId = friend.userID.trim();
      if (userId.isEmpty || byUserId.containsKey(userId)) {
        continue;
      }
      if (!_keepDirectoryFriend(userId)) {
        continue;
      }
      upsertFriendSearchResult(byUserId, _friendResultWithDisplay(friend));
    }
  }

  void _addDirectoryGroupHits(
    String keyword,
    Map<String, V2TimGroupInfo> byGroupId,
  ) {
    for (final entry in ImSdkRelationshipDirectory.instance.groupEntries) {
      if (!groupDirectoryMatchesSearchKeyword(
        groupName: entry.groupName,
        groupId: entry.groupId,
        keyword: keyword,
      )) {
        continue;
      }
      upsertGroupSearchResult(byGroupId, entry.toV2TimGroupInfo());
    }
  }

  Future<void> _addIndexedLocalGroupHits(
    String keyword,
    Map<String, V2TimGroupInfo> byGroupId,
    int generation,
  ) async {
    _addDirectoryGroupHits(keyword, byGroupId);
    if (!SelfHostedGroupBridge.localSearchEnabled) {
      return;
    }
    final page = await SelfHostedGroupBridge.searchGroupsLocal(
      keyword: keyword,
      limit: 80,
    );
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    final hydrated = await SelfHostedGroupBridge.hydrateGroups(page.ids);
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    for (final group in hydrated) {
      upsertGroupSearchResult(byGroupId, group);
    }
  }

  Future<List<V2TimFriendInfoResult>> _mergeFriendSearchResults(
    String keyword,
    List<V2TimFriendInfoResult>? apiResults, {
    int? generation,
    void Function()? notifyIfCurrent,
    Map<String, V2TimFriendInfoResult>? seed,
  }) async {
    final byUserId = <String, V2TimFriendInfoResult>{
      if (seed != null) ...seed,
    };
    if (generation != null && !_isCurrentGeneration(generation, keyword)) {
      return byUserId.values.toList(growable: false);
    }
    await _addIndexedLocalFriendHits(
      keyword,
      byUserId,
      generation ?? _globalSearchGeneration,
    );
    if (generation != null && !_isCurrentGeneration(generation, keyword)) {
      return byUserId.values.toList(growable: false);
    }
    for (final item in apiResults ?? const <V2TimFriendInfoResult>[]) {
      final friend = item.friendInfo;
      final userId = friend?.userID.trim() ?? '';
      if (friend == null || userId.isEmpty || !_keepDirectoryFriend(userId)) {
        continue;
      }
      upsertFriendSearchResult(byUserId, _friendResultWithDisplay(friend));
    }

    if (conversationList.isEmpty) {
      await initConversationMsg();
    }
    if (generation != null && !_isCurrentGeneration(generation, keyword)) {
      return byUserId.values.toList(growable: false);
    }
    await _localConversationsMatchingKeyword(
      keyword,
      generation: generation,
      onBatch: (batch) {
        if (generation != null && !_isCurrentGeneration(generation, keyword)) {
          return;
        }
        _applyLocalC2cMatchesToFriendMap(
          byUserId,
          batch,
          keepUser: _keepDirectoryFriend,
        );
        if (notifyIfCurrent != null) {
          _publishFriendMap(
            byUserId,
            generation: generation ?? _globalSearchGeneration,
            keyword: keyword,
            notifyIfCurrent: notifyIfCurrent,
          );
        }
      },
    );

    return byUserId.values.toList(growable: false);
  }

  Future<List<V2TimGroupInfo>> _mergeGroupSearchResults(
    String keyword,
    List<V2TimGroupInfo> apiResults, {
    int? generation,
    void Function()? notifyIfCurrent,
    Map<String, V2TimGroupInfo>? seed,
  }) async {
    final byGroupId = <String, V2TimGroupInfo>{
      if (seed != null) ...seed,
    };
    if (generation != null && !_isCurrentGeneration(generation, keyword)) {
      return byGroupId.values.toList(growable: false);
    }
    await _addIndexedLocalGroupHits(
      keyword,
      byGroupId,
      generation ?? _globalSearchGeneration,
    );
    if (generation != null && !_isCurrentGeneration(generation, keyword)) {
      return byGroupId.values.toList(growable: false);
    }
    await _ensureJoinedGroupIdsForSearch();
    if (generation != null && !_isCurrentGeneration(generation, keyword)) {
      return byGroupId.values.toList(growable: false);
    }
    for (final group in apiResults) {
      if (!_groupMatchesSearchDisplay(group, keyword) &&
          !groupInfoMatchesSearchKeyword(group, keyword)) {
        continue;
      }
      if (!_keepExternalGroupSearchHit(group.groupID)) {
        continue;
      }
      upsertGroupSearchResult(byGroupId, group);
    }

    if (conversationList.isEmpty) {
      await initConversationMsg();
    }
    if (generation != null && !_isCurrentGeneration(generation, keyword)) {
      return byGroupId.values.toList(growable: false);
    }
    await _localConversationsMatchingKeyword(
      keyword,
      generation: generation,
      onBatch: (batch) {
        if (generation != null && !_isCurrentGeneration(generation, keyword)) {
          return;
        }
        _applyLocalGroupMatchesToGroupMap(byGroupId, batch);
        if (notifyIfCurrent != null) {
          _publishGroupMap(
            byGroupId,
            generation: generation ?? _globalSearchGeneration,
            keyword: keyword,
            notifyIfCurrent: notifyIfCurrent,
          );
        }
      },
    );

    return byGroupId.values.toList(growable: false);
  }

  Future<void> _searchFriendByKeyQuiet(
    String searchKey, {
    required int generation,
    required void Function() notifyIfCurrent,
    void Function(List<V2TimFriendInfoResult> apiResults)? onApiResults,
  }) async {
    final keyword = searchKey.trim();
    if (keyword.isEmpty) {
      friendList = [];
      if (_isCurrentGeneration(generation, searchKey)) {
        friendSearchLoading = false;
        friendFirstRoundComplete = true;
        _maybeMarkGlobalSearchComplete(searchKey, generation);
      }
      return;
    }
    final byUserId = <String, V2TimFriendInfoResult>{};
    await _addIndexedLocalFriendHits(keyword, byUserId, generation);
    _publishFriendMap(
      byUserId,
      generation: generation,
      keyword: keyword,
      notifyIfCurrent: notifyIfCurrent,
    );

    var apiResults = const <V2TimFriendInfoResult>[];
    try {
      final searchResult = await _friendshipServices.searchFriends(
        searchParam: _buildFriendSearchParam(keyword),
      );
      if (!_isCurrentGeneration(generation, keyword)) {
        return;
      }
      apiResults =
          filterFriendSearchResultsForPickers(searchResult) ?? const [];
      onApiResults?.call(apiResults);
    } catch (_) {
      if (!_isCurrentGeneration(generation, keyword)) {
        return;
      }
      apiResults = const [];
    }

    friendList = await _mergeFriendSearchResults(
      keyword,
      apiResults,
      generation: generation,
      notifyIfCurrent: notifyIfCurrent,
      seed: byUserId,
    );
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    friendSearchLoading = false;
    friendFirstRoundComplete = true;
    _maybeMarkGlobalSearchComplete(keyword, generation);
    notifyIfCurrent();
  }

  void searchGroupByKey(String searchKey) async {
    final keyword = searchKey.trim();
    if (keyword.isEmpty) {
      groupList = [];
      notifyListeners();
      return;
    }
    try {
      final searchResult = await _groupServices.searchGroups(
        searchParam: _buildGroupSearchParam(keyword),
      );
      groupList = await _mergeGroupSearchResults(
        keyword,
        searchResult.data ?? const [],
      );
    } catch (_) {
      groupList = await _mergeGroupSearchResults(
        keyword,
        const <V2TimGroupInfo>[],
      );
    }
    notifyListeners();
  }

  Future<void> _searchGroupByKeyQuiet(
    String searchKey, {
    required int generation,
    required void Function() notifyIfCurrent,
    void Function(List<V2TimGroupInfo> apiResults)? onApiResults,
  }) async {
    final keyword = searchKey.trim();
    if (keyword.isEmpty) {
      groupList = [];
      if (_isCurrentGeneration(generation, searchKey)) {
        groupSearchLoading = false;
        groupFirstRoundComplete = true;
        _maybeMarkGlobalSearchComplete(searchKey, generation);
      }
      return;
    }
    final byGroupId = <String, V2TimGroupInfo>{};
    await _addIndexedLocalGroupHits(keyword, byGroupId, generation);
    await _ensureJoinedGroupIdsForSearch();
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    _publishGroupMap(
      byGroupId,
      generation: generation,
      keyword: keyword,
      notifyIfCurrent: notifyIfCurrent,
    );

    var apiResults = const <V2TimGroupInfo>[];
    try {
      final searchResult = await _groupServices.searchGroups(
        searchParam: _buildGroupSearchParam(keyword),
      );
      if (!_isCurrentGeneration(generation, keyword)) {
        return;
      }
      apiResults = searchResult.data ?? const <V2TimGroupInfo>[];
      onApiResults?.call(apiResults);
    } catch (_) {
      if (!_isCurrentGeneration(generation, keyword)) {
        return;
      }
      apiResults = const <V2TimGroupInfo>[];
    }

    groupList = await _mergeGroupSearchResults(
      keyword,
      apiResults,
      generation: generation,
      notifyIfCurrent: notifyIfCurrent,
      seed: byGroupId,
    );
    if (!_isCurrentGeneration(generation, keyword)) {
      return;
    }
    groupSearchLoading = false;
    groupFirstRoundComplete = true;
    _maybeMarkGlobalSearchComplete(keyword, generation);
    notifyIfCurrent();
  }

  void clearConversationTextResults() {
    conversationTextSearch.clear();
  }

  List<V2TimMessage> conversationFilterMessages = [];
  bool conversationFilterLoading = false;
  bool conversationFilterHasMore = true;
  String? _conversationFilterLastMsgID;
  int _conversationFilterSearchPageIndex = 0;
  String _conversationFilterCloudCursor = '';
  bool _conversationFilterCloudEnabled = true;
  String _conversationFilterContextKey = '';
  int _conversationFilterGeneration = 0;

  /// Once local search fails (e.g. non-premium), stick to history scan for
  /// this filter session so "load more" stays consistent.
  bool _conversationFilterPreferHistoryScan = false;

  static const List<int> _conversationAssetSearchMessageTypes = [
    MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
    MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
    MessageElemType.V2TIM_ELEM_TYPE_FILE,
  ];

  String _conversationFilterKey({
    required String conversationId,
    required int searchTimePosition,
    required int searchTimePeriod,
    required List<String> senderList,
  }) {
    return '$conversationId|$searchTimePosition|$searchTimePeriod|'
        '${senderList.join(',')}';
  }

  void clearConversationFilterResults() {
    _resetConversationFilterState();
    notifyListeners();
  }

  void _resetConversationFilterState() {
    conversationFilterMessages = [];
    conversationFilterLoading = false;
    conversationFilterHasMore = true;
    _conversationFilterLastMsgID = null;
    _conversationFilterSearchPageIndex = 0;
    _conversationFilterCloudCursor = '';
    _conversationFilterCloudEnabled = true;
    _conversationFilterContextKey = '';
    _conversationFilterGeneration++;
    _conversationFilterPreferHistoryScan = false;
  }

  /// Searchable elem types so date-only queries may omit keywords
  /// (IM requires keyword when both sender and type lists are empty).
  static const List<int> _conversationFilterSearchMessageTypes = [
    MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
    MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
    MessageElemType.V2TIM_ELEM_TYPE_SOUND,
    MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
    MessageElemType.V2TIM_ELEM_TYPE_FILE,
    MessageElemType.V2TIM_ELEM_TYPE_LOCATION,
    MessageElemType.V2TIM_ELEM_TYPE_MERGER,
  ];

  Future<void> searchConversationWithFilter({
    required String conversationId,
    required bool reset,
    int searchTimePosition = 0,
    int searchTimePeriod = 0,
    List<String>? userIDList,
    String? groupID,
    String? userID,
  }) async {
    if (reset) {
      conversationFilterMessages = [];
      conversationFilterHasMore = true;
      _conversationFilterLastMsgID = null;
      _conversationFilterSearchPageIndex = 0;
      _conversationFilterPreferHistoryScan = false;
    }
    if (!conversationFilterHasMore || conversationFilterLoading) {
      return;
    }

    final targets = _resolveConversationTargets(
      conversationId: conversationId,
      groupID: groupID,
      userID: userID,
    );
    if (targets == null) {
      conversationFilterHasMore = false;
      notifyListeners();
      return;
    }

    final senderList = (userIDList ?? const [])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final hasDateFilter = searchTimePosition > 0 && searchTimePeriod > 0;
    final hasSenderFilter = senderList.isNotEmpty;
    if (!hasDateFilter && !hasSenderFilter) {
      conversationFilterHasMore = false;
      notifyListeners();
      return;
    }

    final contextKey = _conversationFilterKey(
      conversationId: conversationId,
      searchTimePosition: searchTimePosition,
      searchTimePeriod: searchTimePeriod,
      senderList: senderList,
    );
    if (reset || contextKey != _conversationFilterContextKey) {
      _conversationFilterGeneration++;
      _conversationFilterContextKey = contextKey;
      _conversationFilterCloudCursor = '';
      _conversationFilterCloudEnabled = true;
      _conversationFilterPreferHistoryScan = false;
    }
    final generation = _conversationFilterGeneration;

    conversationFilterLoading = true;
    notifyListeners();
    try {
      final useLocalSearch = !_conversationFilterPreferHistoryScan &&
          _canSearchLocalMessagesForCurrentUser();
      if (_conversationFilterCloudEnabled &&
          _canSearchLocalMessagesForCurrentUser()) {
        final cloudHandled = await _searchConversationFilterViaCloudMessages(
          conversationId: conversationId,
          searchTimePosition: hasDateFilter ? searchTimePosition : 0,
          searchTimePeriod: hasDateFilter ? searchTimePeriod : 0,
          senderList: senderList,
          generation: generation,
        );
        if (generation != _conversationFilterGeneration) return;
        if (cloudHandled) return;
      }
      if (useLocalSearch && generation == _conversationFilterGeneration) {
        final ok = await _searchConversationFilterViaLocalMessages(
          conversationId: conversationId,
          searchTimePosition: hasDateFilter ? searchTimePosition : 0,
          searchTimePeriod: hasDateFilter ? searchTimePeriod : 0,
          senderList: senderList,
        );
        if (ok) {
          return;
        }
        // Premium/API failure → history scan for the rest of this session.
        _conversationFilterPreferHistoryScan = true;
        if (reset) {
          conversationFilterMessages = [];
          _conversationFilterLastMsgID = null;
          conversationFilterHasMore = true;
        }
      }

      await _searchConversationFilterViaHistoryScan(
        targets: targets,
        searchTimePosition: searchTimePosition,
        searchTimePeriod: searchTimePeriod,
        senderList: senderList,
        reset: reset,
      );
    } finally {
      conversationFilterLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _searchConversationFilterViaCloudMessages({
    required String conversationId,
    required int searchTimePosition,
    required int searchTimePeriod,
    required List<String> senderList,
    required int generation,
  }) async {
    try {
      final result = await _searchMessagesThroughIm06(
        source: ImHistorySource.cloud,
        searchParam: V2TimMessageSearchParam(
          conversationID: conversationId,
          keywordList: const <String>[],
          userIDList: senderList,
          messageTypeList: senderList.isEmpty
              ? _conversationFilterSearchMessageTypes
              : const <int>[],
          searchTimePosition: searchTimePosition,
          searchTimePeriod: searchTimePeriod,
          searchCount: 30,
          searchCursor: _conversationFilterCloudCursor,
          type: KeywordListMatchType.V2TIM_KEYWORD_LIST_MATCH_TYPE_OR.index,
        ),
      );
      if (generation != _conversationFilterGeneration) {
        return false;
      }
      if (result.code != 0) {
        _conversationFilterCloudEnabled = false;
        return false;
      }
      final item = result.data?.messageSearchResultItems?.firstWhereOrNull(
            (element) => element.conversationID == conversationId,
          ) ??
          (result.data?.messageSearchResultItems?.length == 1
              ? result.data!.messageSearchResultItems!.first
              : null);
      final incoming = item?.messageList ?? const <V2TimMessage>[];
      final seen =
          conversationFilterMessages.map(_messageSearchIdentity).toSet();
      for (final message in incoming) {
        final identity = _messageSearchIdentity(message);
        if (seen.add(identity)) {
          conversationFilterMessages.add(message);
        }
      }
      _conversationFilterCloudCursor = result.data?.searchCursor ?? '';
      conversationFilterHasMore = _conversationFilterCloudCursor.isNotEmpty;
      return true;
    } catch (_) {
      _conversationFilterCloudEnabled = false;
      return false;
    }
  }

  /// Returns true when SDK local search handled the page (including empty).
  Future<bool> _searchConversationFilterViaLocalMessages({
    required String conversationId,
    required int searchTimePosition,
    required int searchTimePeriod,
    required List<String> senderList,
  }) async {
    const pageSize = 30;
    final pageIndex = _conversationFilterSearchPageIndex;
    try {
      final searchResult = await _searchMessagesThroughIm06(
        source: ImHistorySource.local,
        searchParam: V2TimMessageSearchParam(
          conversationID: conversationId,
          // Empty keywords allowed when sender and/or messageTypeList is set.
          keywordList: const <String>[],
          userIDList: senderList,
          messageTypeList: senderList.isEmpty
              ? _conversationFilterSearchMessageTypes
              : const <int>[],
          searchTimePosition: searchTimePosition,
          searchTimePeriod: searchTimePeriod,
          pageIndex: pageIndex,
          pageSize: pageSize,
          type: KeywordListMatchType.V2TIM_KEYWORD_LIST_MATCH_TYPE_OR.index,
        ),
      );
      if (!_canSearchLocalMessagesForCurrentUser()) {
        return false;
      }
      if (searchResult.code != 0 || searchResult.data == null) {
        return false;
      }

      final items = searchResult.data!.messageSearchResultItems;
      final matched = items?.firstWhereOrNull(
            (element) => element.conversationID == conversationId,
          ) ??
          (items != null && items.length == 1 ? items.first : null);
      final pageMessages = matched?.messageList ?? const <V2TimMessage>[];
      final totalCount = matched?.messageCount ?? 0;

      final seen = conversationFilterMessages
          .map((m) => m.msgID ?? m.id ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final message in pageMessages) {
        final id = message.msgID ?? message.id ?? '';
        if (id.isNotEmpty && seen.contains(id)) {
          continue;
        }
        if (id.isNotEmpty) {
          seen.add(id);
        }
        conversationFilterMessages.add(message);
      }

      _conversationFilterSearchPageIndex = pageIndex + 1;
      if (pageMessages.isEmpty) {
        conversationFilterHasMore = false;
      } else if (totalCount > 0) {
        conversationFilterHasMore =
            conversationFilterMessages.length < totalCount;
      } else {
        conversationFilterHasMore = pageMessages.length >= pageSize;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _searchConversationFilterViaHistoryScan({
    required ({String? userID, String? groupID}) targets,
    required int searchTimePosition,
    required int searchTimePeriod,
    required List<String> senderList,
    required bool reset,
  }) async {
    final dateRange = timestampRangeFromSearchParams(
      searchTimePosition: searchTimePosition,
      searchTimePeriod: searchTimePeriod,
    );
    final hasDateFilter = dateRange.startTs > 0 && dateRange.endTs > 0;
    final senderSet = senderList.toSet();
    final hasSenderFilter = senderSet.isNotEmpty;

    const targetBatchSize = 30;
    const fetchCount = 50;
    final seen = conversationFilterMessages
        .map((m) => m.msgID ?? m.id ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final initialCount = conversationFilterMessages.length;
    var reachedBeforeRange = false;
    var lastMsgID = reset ? null : _conversationFilterLastMsgID;

    while (conversationFilterMessages.length - initialCount < targetBatchSize &&
        !reachedBeforeRange &&
        conversationFilterHasMore) {
      final historyResult = await serviceLocator<TUIChatGlobalModel>()
          .getHistoryMessageListThroughIm06(
        userID: targets.userID,
        groupID: targets.groupID,
        count: fetchCount,
        lastMsgID: lastMsgID,
        getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
      );
      final batch = historyResult?.messageList ?? const <V2TimMessage>[];
      if (batch.isEmpty) {
        conversationFilterHasMore = false;
        break;
      }

      lastMsgID = batch.last.msgID;
      if (batch.length < fetchCount) {
        conversationFilterHasMore = false;
      }

      for (final message in batch) {
        final ts = message.timestamp ?? 0;
        if (hasDateFilter) {
          if (ts > dateRange.endTs) {
            continue;
          }
          if (ts < dateRange.startTs) {
            reachedBeforeRange = true;
            conversationFilterHasMore = false;
            break;
          }
        }
        if (hasSenderFilter &&
            !_messageMatchesSenderFilter(message, senderSet)) {
          continue;
        }

        final id = message.msgID ?? message.id ?? '';
        if (id.isNotEmpty && seen.contains(id)) {
          continue;
        }
        if (id.isNotEmpty) {
          seen.add(id);
        }
        conversationFilterMessages.add(message);
      }
    }

    _conversationFilterLastMsgID = lastMsgID;
  }

  Future<void> getMsgForConversation(
      String keyword, String conversationId, int page) {
    if (page == 0 ||
        conversationTextSearch.keyword != keyword.trim() ||
        conversationTextSearch.conversationId != conversationId.trim()) {
      return conversationTextSearch.search(keyword, conversationId);
    }
    return conversationTextSearch.loadMore();
  }

  void scheduleConversationTextSearch({
    required String keyword,
    required String conversationId,
    required int page,
    bool reset = true,
  }) {
    if (reset) {
      conversationTextSearch.schedule(keyword, conversationId);
    } else {
      unawaited(getMsgForConversation(keyword, conversationId, page));
    }
  }

  void scheduleConversationMediaFileSearch({
    required String conversationId,
    required bool reset,
    String keyword = '',
  }) {
    _conversationMediaSearchDebounce?.cancel();
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      _conversationMediaSearchGeneration++;
      _mediaFileGeneration++;
      mediaFileLoading = false;
      mediaFileMsgListForConversation = [];
      mediaFileHasMore = true;
      _mediaFileLastMsgID = null;
      notifyListeners();
      return;
    }
    final generation = ++_conversationMediaSearchGeneration;
    _conversationMediaSearchDebounce = Timer(
      _conversationMediaSearchDebounceDuration,
      () {
        if (generation != _conversationMediaSearchGeneration) {
          return;
        }
        unawaited(
          loadMediaAndFileForConversation(
            conversationId,
            reset: reset,
            keyword: trimmed,
          ),
        );
      },
    );
  }

  void searchMsgByKey(String searchKey, bool isFirst) {
    if (isFirst) {
      return;
    }
    loadMoreGlobalMessageSearch(searchKey);
  }

  void loadMoreGlobalMessageSearch(String searchKey) {
    final keyword = searchKey.trim();
    if (keyword.isEmpty || keyword != _activeGlobalSearchKey) {
      return;
    }
    final generation = _globalSearchGeneration;
    if (messageLocalFirstRoundComplete &&
        _globalMessageLocalHasMore &&
        !_globalMessageLocalLoadingMore) {
      unawaited(_searchGlobalMessagesLane(
        keyword,
        generation: generation,
        cloud: false,
        isFirstRound: false,
      ));
    }
    if (messageCloudFirstRoundComplete &&
        _globalMessageCloudHasMore &&
        !_globalMessageCloudLoadingMore) {
      unawaited(_searchGlobalMessagesLane(
        keyword,
        generation: generation,
        cloud: true,
        isFirstRound: false,
      ));
    }
  }

  Future<void> _enqueueMessageDisplayHydration(int generation) async {
    final hydrator = appSearchDisplayHydrator;
    if (hydrator == null) {
      return;
    }
    final ids = collectSearchMessageConversationIds(msgList);
    await runSearchMessageDisplayHydration(
      generation: generation,
      currentGeneration: () => _globalSearchGeneration,
      conversationIds: ids,
      hydrator: hydrator,
      onCurrent: notifyListeners,
    );
  }

  Future<void> _applyGlobalMessageSearchPage({
    required int generation,
    required List<V2TimMessageSearchResultItem> incoming,
    required int totalCount,
  }) async {
    if (generation != _globalSearchGeneration) {
      return;
    }
    final merged = _mergeSearchResultItems(
      msgList ?? const [],
      incoming,
    );
    final filtered = _filterMsgListForJoinedGroups(merged) ?? merged;
    msgList = sortGlobalMessageSearchResults(filtered);
    if (totalCount > totalMsgCount) {
      totalMsgCount = totalCount;
    }
    notifyListeners();
    unawaited(_enqueueMessageDisplayHydration(generation));
  }

  void _finishGlobalMessageLane({
    required int generation,
    required String searchKey,
    required bool cloud,
    required bool isFirstRound,
  }) {
    if (generation != _globalSearchGeneration) {
      return;
    }
    if (cloud) {
      _globalMessageCloudLoadingMore = false;
      if (isFirstRound) {
        messageCloudLoading = false;
        messageCloudFirstRoundComplete = true;
      }
    } else {
      _globalMessageLocalLoadingMore = false;
      if (isFirstRound) {
        messageLocalLoading = false;
        messageLocalFirstRoundComplete = true;
      }
    }
    _maybeMarkGlobalSearchComplete(searchKey, generation);
    notifyListeners();
  }

  Future<void> _searchGlobalMessagesLane(
    String searchKey, {
    required int generation,
    required bool cloud,
    required bool isFirstRound,
  }) async {
    if (generation != _globalSearchGeneration) {
      return;
    }
    if (cloud) {
      if (_globalMessageCloudLoadingMore) {
        return;
      }
      _globalMessageCloudLoadingMore = true;
      if (isFirstRound) {
        messageCloudLoading = true;
      }
    } else {
      if (_globalMessageLocalLoadingMore) {
        return;
      }
      _globalMessageLocalLoadingMore = true;
      if (isFirstRound) {
        messageLocalLoading = true;
      }
    }

    try {
      if (!cloud) {
        if (kIsWeb || !_canSearchLocalMessagesForCurrentUser()) {
          _globalMessageLocalHasMore = false;
          return;
        }
      }

      final requestCursor = _globalMessageSearchCursor;
      final pageIndex = _globalMessageLocalPage;
      late V2TimValueCallback<V2TimMessageSearchResult> searchResult;
      try {
        searchResult = await _searchMessagesThroughIm06(
          source: cloud ? ImHistorySource.cloud : ImHistorySource.local,
          searchParam: V2TimMessageSearchParam(
            keywordList: [searchKey],
            pageSize: _globalMessagePageSize,
            pageIndex: cloud ? null : pageIndex,
            searchCount: _globalMessagePageSize,
            searchTimePeriod: 0,
            searchTimePosition: 0,
            searchCursor: cloud ? requestCursor : '',
            type: KeywordListMatchType.V2TIM_KEYWORD_LIST_MATCH_TYPE_OR.index,
          ),
        );
      } catch (_) {
        if (generation != _globalSearchGeneration) {
          return;
        }
        if (cloud) {
          _globalMessageCloudHasMore = false;
        } else {
          _globalMessageLocalHasMore = false;
        }
        return;
      }
      if (generation != _globalSearchGeneration) {
        return;
      }
      if (searchResult.code != 0 || searchResult.data == null) {
        if (cloud) {
          _globalMessageCloudHasMore = false;
        } else {
          _globalMessageLocalHasMore = false;
        }
        return;
      }

      final incoming =
          searchResult.data!.messageSearchResultItems ?? const [];
      final totalCount = searchResult.data!.totalCount ?? 0;
      await _applyGlobalMessageSearchPage(
        generation: generation,
        incoming: incoming,
        totalCount: totalCount,
      );
      if (generation != _globalSearchGeneration) {
        return;
      }

      final incomingCount = incoming
          .where((item) => (item.conversationID?.trim() ?? '').isNotEmpty)
          .length;
      if (cloud) {
        final next = searchResult.data!.searchCursor?.trim() ?? '';
        _globalMessageSearchCursor = next;
        _globalMessageCloudHasMore =
            next.isNotEmpty && next != requestCursor;
      } else {
        _globalMessageLocalPage = pageIndex + 1;
        msgPage = _globalMessageLocalPage;
        if (incomingCount == 0) {
          _globalMessageLocalHasMore = false;
        } else if (totalCount > 0) {
          _globalMessageLocalHasMore =
              (msgList?.length ?? 0) < totalCount;
        } else {
          _globalMessageLocalHasMore =
              incomingCount >= _globalMessagePageSize;
        }
      }
    } finally {
      _finishGlobalMessageLane(
        generation: generation,
        searchKey: searchKey,
        cloud: cloud,
        isFirstRound: isFirstRound,
      );
    }
  }

  Future<void> _refreshGlobalSearchWithContext(
    String searchKey, {
    required int generation,
    required List<V2TimFriendInfoResult> friendApiResults,
    required List<V2TimGroupInfo> groupApiResults,
    required void Function() notifyIfCurrent,
  }) async {
    if (!_isCurrentGeneration(generation, searchKey)) {
      return;
    }
    var changed = false;
    if (friendApiResults.isNotEmpty || searchKey.trim().isNotEmpty) {
      final seed = <String, V2TimFriendInfoResult>{};
      for (final item in friendList ?? const <V2TimFriendInfoResult>[]) {
        upsertFriendSearchResult(seed, item);
      }
      friendList = await _mergeFriendSearchResults(
        searchKey,
        friendApiResults,
        generation: generation,
        notifyIfCurrent: notifyIfCurrent,
        seed: seed,
      );
      changed = true;
    }
    if (!_isCurrentGeneration(generation, searchKey)) {
      return;
    }
    if (groupApiResults.isNotEmpty || searchKey.trim().isNotEmpty) {
      final seed = <String, V2TimGroupInfo>{};
      for (final group in groupList ?? const <V2TimGroupInfo>[]) {
        upsertGroupSearchResult(seed, group);
      }
      groupList = await _mergeGroupSearchResults(
        searchKey,
        groupApiResults,
        generation: generation,
        notifyIfCurrent: notifyIfCurrent,
        seed: seed,
      );
      changed = true;
    }
    if (!_isCurrentGeneration(generation, searchKey)) {
      return;
    }
    final currentMessages = msgList;
    if (currentMessages != null && currentMessages.isNotEmpty) {
      msgList = sortGlobalMessageSearchResults(
        _filterMsgListForJoinedGroups(currentMessages) ?? currentMessages,
      );
      changed = true;
    }
    if (changed) {
      notifyIfCurrent();
    }
  }

  Future<void> _runGlobalSearch(String searchKey) async {
    final generation = ++_globalSearchGeneration;
    _activeGlobalSearchKey = searchKey;
    friendList = [];
    groupList = [];
    _resetGlobalMessageLaneState();
    friendSearchLoading = true;
    groupSearchLoading = true;
    messageLocalLoading = true;
    messageCloudLoading = true;
    friendFirstRoundComplete = false;
    groupFirstRoundComplete = false;
    _completedGlobalSearchKey = '';
    notifyListeners();

    void notifyIfCurrent() {
      if (_isCurrentGeneration(generation, searchKey)) {
        notifyListeners();
      }
    }

    var friendApiResults = const <V2TimFriendInfoResult>[];
    var groupApiResults = const <V2TimGroupInfo>[];

    unawaited(
      _ensureGlobalSearchContext(generation).then((_) async {
        await _refreshGlobalSearchWithContext(
          searchKey,
          generation: generation,
          friendApiResults: friendApiResults,
          groupApiResults: groupApiResults,
          notifyIfCurrent: notifyIfCurrent,
        );
      }),
    );
    unawaited(_searchFriendByKeyQuiet(
      searchKey,
      generation: generation,
      notifyIfCurrent: notifyIfCurrent,
      onApiResults: (results) => friendApiResults = results,
    ));
    unawaited(_searchGroupByKeyQuiet(
      searchKey,
      generation: generation,
      notifyIfCurrent: notifyIfCurrent,
      onApiResults: (results) => groupApiResults = results,
    ));
    unawaited(_searchGlobalMessagesLane(
      searchKey,
      generation: generation,
      cloud: false,
      isFirstRound: true,
    ));
    unawaited(_searchGlobalMessagesLane(
      searchKey,
      generation: generation,
      cloud: true,
      isFirstRound: true,
    ));
  }

  void searchByKey(String? searchKey) {
    _globalSearchDebounce?.cancel();
    final trimmed = searchKey?.trim() ?? '';
    if (trimmed.isEmpty) {
      _globalSearchGeneration++;
      friendList = [];
      groupList = [];
      _resetGlobalMessageLaneState();
      _resetGlobalSearchProgress(keepCompletedKey: false);
      notifyListeners();
      return;
    }
    _globalSearchDebounce = Timer(_globalSearchDebounceDuration, () {
      unawaited(_runGlobalSearch(trimmed));
    });
  }
}
