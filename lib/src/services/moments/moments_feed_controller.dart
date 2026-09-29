import 'package:tencent_cloud_chat_demo/src/models/moments/moment_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_error_mapper.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

class MomentsFeedController {
  MomentsFeedController({
    String? authorId,
  }) : authorId = authorId?.trim() ?? '';

  final String authorId;

  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  List<MomentPost> posts = const [];
  MomentDraft? draft;
  String? error;
  String? loadMoreError;
  String? _nextCursor;
  int? authorVisibleRangeDays;
  SessionIdentity? _loadedIdentity;
  int _feedRequestGeneration = 0;

  bool get isProfileList => authorId.isNotEmpty;

  void _resetForIdentity(SessionIdentity identity) {
    if (_loadedIdentity == identity) {
      return;
    }
    _loadedIdentity = identity;
    posts = const [];
    draft = null;
    _nextCursor = null;
    hasMore = false;
    loadingMore = false;
    error = null;
    loadMoreError = null;
  }

  void _discardIfSessionChanged(SessionIdentity identity) {
    if (MomentsStore.isSessionIdentityCurrent(identity) ||
        _loadedIdentity != identity) {
      return;
    }
    _loadedIdentity = null;
    posts = const [];
    draft = null;
    _nextCursor = null;
    hasMore = false;
    loading = false;
    loadingMore = false;
    error = null;
    loadMoreError = null;
  }

  Future<void> load({bool showRefreshing = false}) async {
    final identity = MomentsStore.captureSessionIdentity();
    _resetForIdentity(identity);
    final requestGeneration = ++_feedRequestGeneration;
    if (!showRefreshing) {
      loading = true;
      error = null;
      loadMoreError = null;
    }
    try {
      final results = await Future.wait([
        isProfileList
            ? MomentsStore.loadUserMomentsPage(authorId, identity: identity)
            : MomentsStore.loadFeedPage(identity: identity),
        MomentsStore.loadDraft(identity: identity),
      ]);
      if (requestGeneration != _feedRequestGeneration ||
          !MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      final page = results[0] as MomentPostPage;
      posts = page.items;
      _nextCursor = page.nextCursor;
      hasMore = page.hasMore && (page.nextCursor?.trim().isNotEmpty ?? false);
      if (isProfileList) {
        authorVisibleRangeDays = page.visibleRangeDays;
      }
      loadingMore = false;
      loadMoreError = null;
      draft = results[1] as MomentDraft?;
      loading = false;
      error = page.fromCache ? page.notice : null;
    } catch (e) {
      if (e is MomentsSessionChanged ||
          !MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      if (requestGeneration != _feedRequestGeneration) return;
      loading = false;
      loadingMore = false;
      error = MomentsErrorMapper.map(e).userMessage;
    }
  }

  Future<void> loadMore() async {
    final identity = MomentsStore.captureSessionIdentity();
    _resetForIdentity(identity);
    final cursor = _nextCursor?.trim() ?? '';
    if (loadingMore || !hasMore || cursor.isEmpty) {
      return;
    }
    loadingMore = true;
    loadMoreError = null;
    final requestGeneration = ++_feedRequestGeneration;
    try {
      final page = isProfileList
          ? await MomentsStore.loadUserMomentsPage(authorId,
              cursor: cursor, identity: identity)
          : await MomentsStore.loadFeedPage(cursor: cursor, identity: identity);
      if (requestGeneration != _feedRequestGeneration ||
          !MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      posts = _mergePosts(posts, page.items);
      _nextCursor = page.nextCursor;
      hasMore = page.hasMore && (page.nextCursor?.trim().isNotEmpty ?? false);
      loadingMore = false;
    } catch (e) {
      if (e is MomentsSessionChanged ||
          !MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      if (requestGeneration != _feedRequestGeneration) return;
      loadingMore = false;
      loadMoreError = MomentsErrorMapper.map(e).userMessage;
    }
  }

  Future<void> refreshAfterNavigation() async {
    await load(showRefreshing: true);
  }

  Future<void> refreshDraft() async {
    final identity = MomentsStore.captureSessionIdentity();
    _resetForIdentity(identity);
    try {
      final next = await MomentsStore.loadDraft(identity: identity);
      if (MomentsStore.isSessionIdentityCurrent(identity)) {
        draft = next;
      } else {
        _discardIfSessionChanged(identity);
      }
    } catch (e) {
      if (e is MomentsSessionChanged ||
          !MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      rethrow;
    }
  }

  Future<void> toggleLike(MomentPost post) async {
    final identity = MomentsStore.captureSessionIdentity();
    _resetForIdentity(identity);
    if (!posts.any((item) => item.id == post.id)) return;
    try {
      final updated = await MomentsStore.toggleLike(
        post.id,
        current: post,
        identity: identity,
      );
      if (MomentsStore.isSessionIdentityCurrent(identity)) {
        _replacePost(updated);
      } else {
        _discardIfSessionChanged(identity);
      }
    } catch (e) {
      if (e is MomentsSessionChanged ||
          !MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      rethrow;
    }
  }

  Future<void> addComment(
    MomentPost post,
    String text, {
    String? replyToCommentId,
  }) async {
    final identity = MomentsStore.captureSessionIdentity();
    _resetForIdentity(identity);
    if (!posts.any((item) => item.id == post.id)) return;
    try {
      final updated = await MomentsStore.addComment(
        post.id,
        text,
        replyToCommentId: replyToCommentId,
        identity: identity,
      );
      if (MomentsStore.isSessionIdentityCurrent(identity)) {
        _replacePost(updated);
      } else {
        _discardIfSessionChanged(identity);
      }
    } catch (e) {
      if (e is MomentsSessionChanged ||
          !MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      rethrow;
    }
  }

  Future<void> deleteComment(MomentPost post, String commentId) async {
    final identity = MomentsStore.captureSessionIdentity();
    _resetForIdentity(identity);
    if (!posts.any((item) => item.id == post.id)) return;
    try {
      final updated = await MomentsStore.deleteComment(
        post.id,
        commentId,
        identity: identity,
      );
      if (MomentsStore.isSessionIdentityCurrent(identity)) {
        _replacePost(updated);
      } else {
        _discardIfSessionChanged(identity);
      }
    } catch (e) {
      if (e is MomentsSessionChanged ||
          !MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      rethrow;
    }
  }

  Future<void> deletePost(MomentPost post) async {
    final identity = MomentsStore.captureSessionIdentity();
    _resetForIdentity(identity);
    if (!posts.any((item) => item.id == post.id)) return;
    try {
      await MomentsStore.deletePost(post.id, identity: identity);
      if (!MomentsStore.isSessionIdentityCurrent(identity)) {
        _discardIfSessionChanged(identity);
        return;
      }
      await load(showRefreshing: true);
    } catch (_) {
      _discardIfSessionChanged(identity);
    }
  }

  List<MomentPost> _mergePosts(
    List<MomentPost> current,
    List<MomentPost> incoming,
  ) {
    if (incoming.isEmpty) {
      return current;
    }
    final seen = current.map((post) => post.id).toSet();
    final merged = <MomentPost>[...current];
    for (final post in incoming) {
      if (seen.add(post.id)) {
        merged.add(post);
      }
    }
    return merged;
  }

  void _replacePost(MomentPost next) {
    posts = posts
        .map((post) => post.id == next.id ? next : post)
        .toList(growable: false);
  }
}
