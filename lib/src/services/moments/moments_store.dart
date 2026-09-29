import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/errors/app_error.dart';
import 'package:tencent_cloud_chat_demo/src/api/moments_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/moments/moment_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_error_mapper.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class MomentsSessionChanged implements Exception {
  const MomentsSessionChanged();
}

class MomentsStore {
  MomentsStore._();

  static const String _draftKeyPrefix = 'moments_draft_v1_';
  static String? debugAccountScopeOverride;
  static MomentUserSnapshot? debugSelfSnapshotOverride;

  static String safeLoginUserId() {
    try {
      return TIMUIKitCore.getInstance().loginInfo.userID.trim();
    } catch (_) {
      return '';
    }
  }

  static String accountScope() {
    final override = debugAccountScopeOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    return accountScopeForUserId(safeLoginUserId());
  }

  static String accountScopeForUserId(String? userId) {
    final raw = (userId ?? '').trim();
    if (raw.isEmpty) return '_guest';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static String _draftKey([String? ownerUserId]) =>
      '$_draftKeyPrefix${accountScopeForUserId(ownerUserId ?? accountScope())}';

  static SessionIdentity captureSessionIdentity() {
    final owner = accountScope();
    return SessionIdentityService.instance.capture(ownerUserId: owner);
  }

  static bool isSessionIdentityCurrent(SessionIdentity identity) =>
      SessionIdentityService.instance.isCurrent(
        identity,
        currentOwnerUserId: accountScope(),
      );

  static void _requireCurrent(SessionIdentity identity) {
    if (!isSessionIdentityCurrent(identity)) {
      throw const MomentsSessionChanged();
    }
  }

  /// 注销：删除该账号朋友圈草稿 prefs。
  static Future<void> clearDraftForOwner(String? ownerUserId) async {
    final scope = accountScopeForUserId(ownerUserId);
    if (scope.isEmpty || scope == '_guest') {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_draftKeyPrefix$scope');
  }

  static MomentPostPage _postPageFromApi(MomentsPageResult page) {
    return MomentPostPage(
      items: page.items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      visibleRangeDays: page.visibleRangeDays,
    );
  }

  static List<MomentPost> seedPosts() {
    final self = _selfSnapshot();
    return <MomentPost>[
      MomentPost(
        id: 'seed_1',
        author: const MomentUserSnapshot(
          id: 'friend_1001',
          name: '林远',
          avatarUrl: 'assets/custom_face_resource/4350/yz08@2x.png',
        ),
        text: '周末把项目里朋友圈入口先做出来了，后面再接后端。',
        attachments: const [
          MomentAttachment(
            type: MomentMediaType.image,
            path: 'assets/chat_backgrounds/scenery.png',
          ),
        ],
        likes: [
          MomentReaction(
            id: 'like_1',
            author: const MomentUserSnapshot(
              id: 'friend_1002',
              name: '苏予',
              avatarUrl: 'assets/custom_face_resource/4351/ys04@2x.png',
            ),
            createdAt: DateTime(2026, 6, 25, 18, 12),
          ),
        ],
        comments: [
          MomentComment(
            id: 'comment_1',
            author: const MomentUserSnapshot(
              id: 'friend_1003',
              name: '陈屿',
              avatarUrl: 'assets/custom_face_resource/4352/gcs03@2x.png',
            ),
            text: '这个入口放个人页挺合适。',
            createdAt: DateTime(2026, 6, 25, 18, 20),
          ),
          MomentComment(
            id: 'comment_1_reply',
            author: const MomentUserSnapshot(
              id: 'friend_1002',
              name: '苏予',
              avatarUrl: 'assets/custom_face_resource/4351/ys04@2x.png',
            ),
            replyToCommentId: 'comment_1',
            replyToUser: const MomentUserSnapshot(
              id: 'friend_1003',
              name: '陈屿',
              avatarUrl: 'assets/custom_face_resource/4352/gcs03@2x.png',
            ),
            text: '对，放在关系入口里更自然。',
            createdAt: DateTime(2026, 6, 25, 18, 28),
          ),
        ],
        createdAt: DateTime(2026, 6, 25, 17, 48),
        location: '深圳',
      ),
      MomentPost(
        id: 'seed_2',
        author: const MomentUserSnapshot(
          id: 'friend_1004',
          name: '青禾',
          avatarUrl: 'assets/custom_face_resource/4351/ys11@2x.png',
        ),
        text: '把长列表卡片做得更紧凑一点，信息密度才像聊天产品。',
        attachments: const [
          MomentAttachment(
            type: MomentMediaType.image,
            path: 'assets/icon_wechat_moments.jpg',
          ),
        ],
        likes: [],
        comments: [],
        createdAt: DateTime(2026, 6, 24, 22, 15),
        location: '上海',
      ),
      MomentPost(
        id: 'seed_3',
        author: self,
        text: '今天先把朋友圈前端做成可用版本，后端接口后面补。',
        attachments: const [
          MomentAttachment(
            type: MomentMediaType.image,
            path: 'assets/chat_backgrounds/beauty.png',
          ),
          MomentAttachment(
            type: MomentMediaType.image,
            path: 'assets/chat_backgrounds/scenery.png',
          ),
        ],
        likes: [],
        comments: [
          MomentComment(
            id: 'comment_2',
            author: const MomentUserSnapshot(
              id: 'friend_1005',
              name: '阿澄',
              avatarUrl: 'assets/custom_face_resource/4352/gcs07@2x.png',
            ),
            text: '先把流程跑通很重要。',
            createdAt: DateTime(2026, 6, 26, 10, 1),
          ),
        ],
        createdAt: DateTime(2026, 6, 26, 9, 36),
        location: '杭州',
      ),
    ];
  }

  static MomentUserSnapshot _selfSnapshot() {
    final override = debugSelfSnapshotOverride;
    if (override != null && !override.isEmpty) {
      return override;
    }
    String id = '';
    String name = '';
    String avatar = '';
    try {
      final info = serviceLocator<TUISelfInfoViewModel>().loginInfo;
      id = info?.userID?.trim() ?? '';
      name = info?.nickName?.trim() ?? '';
      avatar = info?.faceUrl?.trim() ?? '';
    } catch (_) {}
    return MomentUserSnapshot(
      id: id.isEmpty ? 'self' : id,
      name: name.isEmpty ? '我' : name,
      avatarUrl: avatar.isEmpty ? 'assets/default_avatar.png' : avatar,
    );
  }

  static Future<List<MomentPost>> loadFeed({SessionIdentity? identity}) async {
    final page = await loadFeedPage(identity: identity);
    return page.items;
  }

  static Future<List<MomentPost>> loadUserMoments(String userId,
      {SessionIdentity? identity}) async {
    final page = await loadUserMomentsPage(userId, identity: identity);
    return page.items;
  }

  static Future<MomentPostPage> loadFeedPage({
    String? cursor,
    int pageSize = 20,
    SessionIdentity? identity,
  }) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    final scope = MomentsLocalStore.feedScope();
    try {
      final page = _postPageFromApi(
        await MomentsApi.instance.fetchFeed(
          cursor: cursor,
          pageSize: pageSize,
        ),
      );
      _requireCurrent(requestIdentity);
      await MomentsLocalStore.instance.savePage(
        ownerUserId: requestIdentity.ownerUserId,
        scope: scope,
        page: page,
        replace: (cursor ?? '').trim().isEmpty,
      );
      _requireCurrent(requestIdentity);
      return page;
    } catch (e) {
      if (e is MomentsSessionChanged) rethrow;
      _requireCurrent(requestIdentity);
      return _cachedPageOrThrow(
        error: e,
        scope: scope,
        allowCache: (cursor ?? '').trim().isEmpty,
        identity: requestIdentity,
      );
    }
  }

  static Future<MomentPostPage> loadUserMomentsPage(
    String userId, {
    String? cursor,
    int pageSize = 20,
    SessionIdentity? identity,
  }) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    final id = userId.trim();
    if (id.isEmpty) return const MomentPostPage(items: [], hasMore: false);
    final scope = MomentsLocalStore.userScope(id);
    try {
      final page = _postPageFromApi(
        await MomentsApi.instance.fetchUserMoments(
          id,
          cursor: cursor,
          pageSize: pageSize,
        ),
      );
      _requireCurrent(requestIdentity);
      await MomentsLocalStore.instance.savePage(
        ownerUserId: requestIdentity.ownerUserId,
        scope: scope,
        page: page,
        replace: (cursor ?? '').trim().isEmpty,
      );
      _requireCurrent(requestIdentity);
      return page;
    } catch (e) {
      if (e is MomentsSessionChanged) rethrow;
      _requireCurrent(requestIdentity);
      return _cachedPageOrThrow(
        error: e,
        scope: scope,
        allowCache: (cursor ?? '').trim().isEmpty,
        identity: requestIdentity,
      );
    }
  }

  static Future<List<MomentPost>> loadLocalFeed() async {
    final owner = accountScope();
    final page = await MomentsLocalStore.instance.loadPage(
      ownerUserId: owner,
      scope: MomentsLocalStore.feedScope(),
    );
    return page.items;
  }

  static Future<void> saveFeed(List<MomentPost> posts) async {
    final owner = accountScope();
    await MomentsLocalStore.instance.savePage(
      ownerUserId: owner,
      scope: MomentsLocalStore.feedScope(),
      page: MomentPostPage(items: posts, hasMore: false),
      replace: true,
    );
  }

  static Future<MomentPostPage> _cachedPageOrThrow({
    required Object error,
    required String scope,
    required bool allowCache,
    required SessionIdentity identity,
  }) async {
    final mapped = MomentsErrorMapper.map(error);
    if (allowCache) {
      _requireCurrent(identity);
      final cached = await MomentsLocalStore.instance.loadPage(
        ownerUserId: identity.ownerUserId,
        scope: scope,
      );
      _requireCurrent(identity);
      if (cached.items.isNotEmpty) {
        return MomentPostPage(
          items: cached.items,
          nextCursor: cached.nextCursor,
          hasMore: false,
          fromCache: true,
          notice: mapped.userMessage,
          visibleRangeDays: cached.visibleRangeDays,
        );
      }
    }
    throw AppException(mapped);
  }

  static Future<MomentDraft?> loadDraft({SessionIdentity? identity}) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    if (!isSessionIdentityCurrent(requestIdentity)) return null;
    final prefs = await SharedPreferences.getInstance();
    if (!isSessionIdentityCurrent(requestIdentity)) return null;
    final raw = prefs.getString(_draftKey(requestIdentity.ownerUserId));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return MomentDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDraft(MomentDraft? draft,
      {SessionIdentity? identity}) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    if (!isSessionIdentityCurrent(requestIdentity)) return;
    final key = _draftKey(requestIdentity.ownerUserId);
    final prefs = await SharedPreferences.getInstance();
    if (!isSessionIdentityCurrent(requestIdentity)) return;
    if (draft == null) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(draft.toJson()));
  }

  static Future<MomentPost?> findPost(String postId,
      {SessionIdentity? identity}) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    try {
      final post = await MomentsApi.instance.fetchDetail(postId);
      _requireCurrent(requestIdentity);
      return post;
    } catch (e) {
      if (e is MomentsSessionChanged) rethrow;
      _requireCurrent(requestIdentity);
      final error = MomentsErrorMapper.map(e);
      if (error.code == 'MOMENT_NOT_FOUND') {
        return null;
      }
      throw AppException(error);
    }
  }

  static Future<List<MomentNotification>> loadNotifications() async {
    final page = await loadNotificationsPage();
    return page.items;
  }

  static Future<MomentsNotificationsResult> loadNotificationsPage({
    String? cursor,
  }) {
    return MomentsApi.instance.fetchNotifications(
      cursor: cursor,
      pageSize: 20,
    );
  }

  static Future<int> fetchNotificationUnreadCount() async {
    try {
      final page = await MomentsApi.instance.fetchNotifications(pageSize: 1);
      return page.unreadCount;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markNotificationsRead({
    List<String> notificationIds = const [],
    bool readAll = false,
  }) {
    return MomentsApi.instance.markNotificationsRead(
      notificationIds: notificationIds,
      readAll: readAll,
    );
  }

  static Future<MomentPost> upsertPost(MomentPost post,
      {SessionIdentity? identity}) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    await MomentsLocalStore.instance.upsertPost(
      ownerUserId: requestIdentity.ownerUserId,
      post: post,
    );
    _requireCurrent(requestIdentity);
    return post;
  }

  static Future<void> deletePost(String postId,
      {SessionIdentity? identity}) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    try {
      await MomentsApi.instance.deletePost(postId);
      _requireCurrent(requestIdentity);
      await MomentsLocalStore.instance.deletePost(
        ownerUserId: requestIdentity.ownerUserId,
        postId: postId,
      );
      _requireCurrent(requestIdentity);
    } catch (e) {
      if (e is MomentsSessionChanged) rethrow;
      throw MomentsErrorMapper.exception(e, action: 'delete');
    }
  }

  static Future<MomentPost> toggleLike(
    String postId, {
    MomentPost? current,
    SessionIdentity? identity,
  }) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    try {
      final selfId = safeLoginUserId();
      final liked = current?.likedBy(selfId) ??
          (await MomentsApi.instance.fetchDetail(postId)).likedBy(selfId);
      _requireCurrent(requestIdentity);
      final updated = liked
          ? await MomentsApi.instance.unlike(postId, current: current)
          : await MomentsApi.instance.like(postId, current: current);
      _requireCurrent(requestIdentity);
      return upsertPost(updated, identity: requestIdentity);
    } catch (e) {
      if (e is MomentsSessionChanged) rethrow;
      throw MomentsErrorMapper.exception(e, action: 'like');
    }
  }

  static Future<MomentPost> addComment(
    String postId,
    String text, {
    MomentUserSnapshot? author,
    String? replyToCommentId,
    SessionIdentity? identity,
  }) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    final content = text.trim();
    if (content.isEmpty) {
      throw ArgumentError.value(text, 'text', 'comment text is empty');
    }
    try {
      final updated = await MomentsApi.instance.addComment(
        postId,
        content,
        replyToCommentId: replyToCommentId,
      );
      _requireCurrent(requestIdentity);
      return upsertPost(updated, identity: requestIdentity);
    } catch (e) {
      if (e is MomentsSessionChanged) rethrow;
      throw MomentsErrorMapper.exception(e, action: 'comment');
    }
  }

  static Future<MomentPost> deleteComment(String postId, String commentId,
      {SessionIdentity? identity}) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    final momentId = postId.trim();
    final id = commentId.trim();
    if (momentId.isEmpty || id.isEmpty) {
      throw ArgumentError('postId and commentId are required');
    }
    try {
      await MomentsApi.instance.deleteComment(momentId, id);
      _requireCurrent(requestIdentity);
      final updated = await MomentsApi.instance.fetchDetail(momentId);
      _requireCurrent(requestIdentity);
      return upsertPost(updated, identity: requestIdentity);
    } catch (e) {
      if (e is MomentsSessionChanged) rethrow;
      throw MomentsErrorMapper.exception(e, action: 'delete');
    }
  }

  static Future<MomentPost> createPost({
    required String text,
    required List<MomentAttachment> attachments,
    String? location,
    MomentPublishPrivacy privacy = const MomentPublishPrivacy(),
    void Function(int completed, int total)? onUploadProgress,
    SessionIdentity? identity,
  }) async {
    final requestIdentity = identity ?? captureSessionIdentity();
    _requireCurrent(requestIdentity);
    try {
      final uploaded = <MomentAttachment>[];
      final total = attachments.length;
      for (var index = 0; index < attachments.length; index++) {
        onUploadProgress?.call(index, total);
        uploaded.add(await MomentsApi.instance.uploadMedia(attachments[index]));
        _requireCurrent(requestIdentity);
      }
      if (total > 0) {
        onUploadProgress?.call(total, total);
      }
      final mediaIds = uploaded
          .map((item) => item.mediaId?.trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final visibleUserIds = privacy.selectedUsers
          .map((user) => user.id.trim())
          .where((id) => id.isNotEmpty)
          .toList();
      final created = await MomentsApi.instance.createPost(
        text: text,
        mediaIds: mediaIds,
        location: location,
        visibility: privacy.mode.apiValue,
        visibleUserIds: visibleUserIds,
      );
      _requireCurrent(requestIdentity);
      final mergedAttachments = <MomentAttachment>[];
      for (var index = 0; index < created.attachments.length; index++) {
        final server = created.attachments[index];
        MomentAttachment? local;
        final serverId = server.mediaId?.trim() ?? '';
        if (serverId.isNotEmpty) {
          for (final candidate in uploaded) {
            if (candidate.mediaId?.trim() == serverId) {
              local = candidate;
              break;
            }
          }
        }
        if (local == null && index < uploaded.length) local = uploaded[index];
        mergedAttachments.add(server.copyWith(
          width: server.width ?? local?.width,
          height: server.height ?? local?.height,
          durationSec: server.durationSec ?? local?.durationSec,
        ));
      }
      return upsertPost(
        created.copyWith(attachments: mergedAttachments),
        identity: requestIdentity,
      );
    } catch (e) {
      if (e is MomentsSessionChanged) rethrow;
      throw MomentsErrorMapper.exception(e, action: 'publish');
    }
  }

  static Future<void> bootstrapDraftFromCurrentText(String text) async {
    final draft = MomentDraft(
      text: text,
      attachments: const [],
      updatedAt: DateTime.now(),
    );
    await saveDraft(draft);
  }
}
