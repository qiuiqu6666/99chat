import 'package:tencent_cloud_chat_demo/src/services/chat_history_refresh_bus.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/chat_attachment_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_transfer.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_diagnostics.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:uuid/uuid.dart';

typedef AttachmentMessageDispatch = Future<ExternalMessageSendResult> Function(
    ChatAttachmentTask task);

class ChatAttachmentService extends ChangeNotifier {
  ChatAttachmentService(
      {ChatAttachmentApi? api,
      ChatAttachmentStore? store,
      ChatAttachmentTransfer? transfer,
      String Function()? ownerProvider,
      int Function()? generationProvider,
      bool Function()? platformSupported,
      AttachmentMessageDispatch? dispatch,
      Future<String?> Function(String)? thumbnailBuilder})
      : api = api ?? ChatAttachmentApi(),
        store = store ?? ChatAttachmentStore(),
        _owner =
            ownerProvider ?? (() => ApiClient.instance.authenticatedUserId),
        _generation = generationProvider ??
            (() => ApiClient.instance.credentialGeneration),
        _platformSupported = platformSupported ?? (() => mobileSupported),
        _dispatch = dispatch ?? _dispatchMessage,
        _thumbnailBuilder = thumbnailBuilder ??
            ((path) =>
                buildVideoSnapshotForSend(videoPath: path, maxAttempts: 1)) {
    this.transfer = transfer ?? ChatAttachmentTransfer(api: this.api);
  }
  static final instance = ChatAttachmentService();
  final ChatAttachmentApi api;
  final ChatAttachmentStore store;
  late final ChatAttachmentTransfer transfer;
  final String Function() _owner;
  final int Function() _generation;
  final bool Function() _platformSupported;
  final AttachmentMessageDispatch _dispatch;
  final Future<String?> Function(String) _thumbnailBuilder;
  final Map<String, Future<String?>> _videoThumbnails = {};
  Timer? _nativeStatusTimer;
  bool _checkingNativeStatus = false;
  bool _nativeStatusDisposed = false;

  void _watchNativeStatus() {
    if (_nativeStatusDisposed) return;
    _nativeStatusTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_checkNativeStatuses());
    });
  }

  Future<void> _checkNativeStatuses() async {
    if (_nativeStatusDisposed || _checkingNativeStatus) return;
    final pending = _tasks.values
        .where((t) =>
            t.ownerUserId == _owner() &&
            t.kind == 'video' &&
            t.state == 'outcomeUnknown')
        .toList();
    if (pending.isEmpty) {
      _nativeStatusTimer?.cancel();
      _nativeStatusTimer = null;
      return;
    }
    _checkingNativeStatus = true;
    final generation = _generation();
    try {
      for (final task in pending) {
        try {
          final data = await api.nativeVideoStatus(task.taskId);
          if (_nativeStatusDisposed) return;
          _check(task.ownerUserId, generation);
          final result = nativeVideoResult(task, data);
          if (result.state == ExternalMessageSendState.outcomeUnknown) continue;
          task.state = result.succeeded ? 'sent' : 'failed';
          task.error = result.description;
          await _save(task);
          if (result.succeeded) _refreshNativeHistory(task);
        } catch (_) {
          /* Read-only retry; never reissue a POST after ambiguity. */
        }
      }
    } finally {
      _checkingNativeStatus = false;
    }
  }

  static ExternalMessageSendResult nativeVideoResult(
      ChatAttachmentTask task, Map<String, dynamic> data) {
    if (data['clientOperationId'] != task.taskId ||
        data['attachmentId'] != task.attachmentId ||
        data['referenceId'] != task.referenceId) {
      throw const ChatAttachmentException('INVALID_RESPONSE', '原生视频发送结果不匹配');
    }
    if (data['status'] == 'sent' &&
        data['messageType'] == 'TIMVideoFileElem' &&
        (task.target.isGroup
            ? attachmentInt(data['msgSeq']) > 0
            : attachmentString(data['msgKey']).isNotEmpty)) {
      return const ExternalMessageSendResult(
          state: ExternalMessageSendState.succeeded);
    }
    if (data['status'] == 'failed') {
      return const ExternalMessageSendResult(
          state: ExternalMessageSendState.blocked, description: '原生视频发送失败，请重试');
    }
    return const ExternalMessageSendResult(
        state: ExternalMessageSendState.outcomeUnknown,
        description: '发送结果待确认，请勿重复发送');
  }

  static void _refreshNativeHistory(ChatAttachmentTask task) {
    ChatHistoryRefreshBus.instance.requestRefresh(
        conversationId:
            '${task.target.isGroup ? "group" : "c2c"}_${task.target.id}',
        reason: 'native_video_sent');
  }

  final Map<String, ChatAttachmentTask> _tasks = {};
  final Map<String, CancelToken> _tokens = {};
  final Map<String, Future<void>> _running = {};
  final Map<String, Future<String>> _downloads = {};
  String? _loadedOwner;
  Future<void>? _loading;
  ChatAttachmentPolicy? _policy;
  DateTime? _policyTime;
  int? _policyGeneration;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get mobileSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  ChatAttachmentPolicy get routingPolicy => _policyGeneration == _generation()
      ? _policy ?? const ChatAttachmentPolicy()
      : const ChatAttachmentPolicy();
  bool isRunning(String taskId) => _running.containsKey(taskId);
  List<ChatAttachmentTask> tasksFor(ChatAttachmentTarget target) =>
      _tasks.values
          .where((t) =>
              t.ownerUserId == _owner() &&
              t.target.key == target.key &&
              !t.terminal)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  void _check(String owner, int generation, [CancelToken? token]) {
    if (owner.isEmpty || _owner() != owner || _generation() != generation) {
      token?.cancel('session changed');
      throw const ChatAttachmentException('SESSION_CHANGED', '账号已切换');
    }
    if (token?.isCancelled == true) {
      throw const ChatAttachmentException('CANCELLED', '任务已暂停');
    }
  }

  Future<void> load() {
    final owner = _owner();
    if (owner.isEmpty) return Future<void>.value();
    if (_loadedOwner == owner) return _loading ?? Future<void>.value();
    final generation = _generation();
    _loadedOwner = owner;
    final future = (() async {
      final rows = await store.tasks(owner);
      _check(owner, generation);
      for (final row in rows) {
        final task = ChatAttachmentTask.fromJson(row);
        if (_running.containsKey(task.taskId)) continue;
        // Crossing the IM dispatch boundary is never auto-retried after a crash.
        if (task.state == 'dispatching') task.state = 'outcomeUnknown';
        if (task.state == 'uploading') task.state = 'paused';
        _tasks[task.taskId] = task;
      }
      notifyListeners();
      _watchNativeStatus();
      unawaited(_checkNativeStatuses());
    })();
    _loading = future.catchError((Object error, StackTrace stack) {
      if (_loadedOwner == owner) _loadedOwner = null;
      Error.throwWithStackTrace(error, stack);
    });
    return _loading!;
  }

  /// Also registers receiver device capability. A policy failure cannot enable
  /// uploading; existing ordinary media remains governed by its native route.
  Future<ChatAttachmentPolicy> refreshPolicy({bool force = false}) async {
    final owner = _owner();
    final generation = _generation();
    if (!force &&
        _policyGeneration == generation &&
        _policyTime != null &&
        DateTime.now().difference(_policyTime!) < const Duration(minutes: 1)) {
      return routingPolicy;
    }
    final policy = await api.policy();
    _check(owner, generation);
    _policy = policy;
    _policyTime = DateTime.now();
    _policyGeneration = generation;
    return policy;
  }

  Future<bool> handles(String? path, String nativeKind) async {
    if (path == null || path.isEmpty) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    return routingPolicy.routesToBackend(await file.length(), nativeKind);
  }

  Future<void> start(
      {required String path,
      required ChatAttachmentTarget target,
      required String nativeMessageKind,
      String? name,
      String? snapshotPath,
      int? durationMs,
      int? width,
      int? height}) async {
    if (!_platformSupported()) {
      throw const ChatAttachmentException(
          'ATTACHMENT_DISABLED', '当前平台暂不支持发送大附件');
    }
    final owner = _owner();
    final generation = _generation();
    _check(owner, generation);
    final source = File(path);
    final size = await source.length();
    if (size <= 0) {
      throw const ChatAttachmentException('FILE_TOO_LARGE', '文件大小超限');
    }
    final baseName =
        (name?.trim().isNotEmpty == true ? name!.trim() : p.basename(path));
    final mime = _mimeFor(baseName, nativeMessageKind);
    final posterSize = nativeMessageKind == 'video' &&
            snapshotPath != null &&
            (width == null || height == null)
        ? await probeLocalImageSize(snapshotPath)
        : null;
    _check(owner, generation);
    final task = ChatAttachmentTask(
        taskId: const Uuid().v4(),
        ownerUserId: owner,
        target: target,
        sourcePath: path,
        name: baseName,
        nativeMessageKind: nativeMessageKind,
        kind: nativeMessageKind == 'sound'
            ? 'audio'
            : nativeMessageKind == 'file' && mime.startsWith('audio/')
                ? 'audio'
                : nativeMessageKind,
        mimeType: mime,
        sizeBytes: size,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        snapshotPath: snapshotPath,
        durationMs: durationMs,
        width: width ?? posterSize?.width.round(),
        height: height ?? posterSize?.height.round());
    await load();
    _check(owner, generation);
    _tasks[task.taskId] = task;
    await _save(task);
    ChatAttachmentDiagnostics.event('task_created', {
      'nativeMessageKind': nativeMessageKind,
      'sizeBytes': size,
      'conversationType': target.isGroup ? 'group' : 'c2c',
    });
    await resume(task);
  }

  Future<void> _save(ChatAttachmentTask task) async {
    await store.saveTask(task.ownerUserId, task.taskId, task.toJson());
    if (!_nativeStatusDisposed && task.ownerUserId == _owner())
      notifyListeners();
  }

  Future<void> resume(ChatAttachmentTask task) {
    final active = _running[task.taskId];
    if (active != null) return active;
    if (!task.canResume) return Future<void>.value();
    final token = CancelToken();
    final generation = _generation();
    _tokens[task.taskId] = token;
    late Future<void> future;
    future = _run(task, generation, token).whenComplete(() {
      _running.remove(task.taskId);
      _tokens.remove(task.taskId);
      notifyListeners();
    });
    _running[task.taskId] = future;
    return future;
  }

  Future<void> _run(
      ChatAttachmentTask task, int generation, CancelToken token) async {
    void check() => _check(task.ownerUserId, generation, token);
    final boundaryWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_owner() != task.ownerUserId || _generation() != generation) {
        token.cancel('session changed');
      }
    });
    try {
      check();
      if (!_platformSupported()) {
        throw const ChatAttachmentException('ATTACHMENT_DISABLED', '当前平台未开放');
      }
      // Persist an observable task before policy/network work. A disabled or
      // malformed policy must leave a visible failure instead of an INFO callback.
      final policy = await refreshPolicy(force: true);
      check();
      ChatAttachmentDiagnostics.event('policy_gate', {
        'uploadEnabled': policy.uploadEnabled,
        'sendEnabled': policy.sendEnabled,
        'sizeBytes': task.sizeBytes,
        'nativeMessageKind': task.nativeMessageKind,
      });
      if (!policy.sendEnabled ||
          (task.uploadId == null && !policy.uploadEnabled)) {
        throw const ChatAttachmentException('ATTACHMENT_DISABLED', '功能未开放');
      }
      if (task.kind == 'video' && !policy.nativeVideoMessageEnabled) {
        throw const ChatAttachmentException(
            'NATIVE_VIDEO_NOT_ENABLED', '后端尚未开放原生视频消息');
      }
      if (task.sizeBytes > policy.maxAttachmentBytes) {
        throw const ChatAttachmentException('FILE_TOO_LARGE', '文件大小超限');
      }
      if (!policy.routesToBackend(task.sizeBytes, task.nativeMessageKind)) {
        throw const ChatAttachmentException(
            'NATIVE_CHANNEL_REQUIRED', '请使用普通通道');
      }
      if (task.referenceId == null) {
        task.state = 'preparing';
        task.error = '';
        await _save(task);
        final staged = await store.stageSource(
            task.ownerUserId, task.taskId, task.sourcePath);
        check();
        task.sourcePath = staged.path;
        task.state = 'uploading';
        await _save(task);
        await transfer.upload(task,
            maxParallelParts: policy.maxParallelPartsPerUpload,
            cancelToken: token,
            checkSession: check,
            persist: () => _save(task),
            onProgress: (progress) {
              task.progress = progress.clamp(0, 1).toDouble();
              final now = DateTime.now();
              if (now.difference(_lastProgress).inMilliseconds >= 100) {
                _lastProgress = now;
                if (!_nativeStatusDisposed && task.ownerUserId == _owner())
                  notifyListeners();
              }
            });
        check();
        await store.registerLocal(task.ownerUserId, task.attachmentId!, staged,
            expectedSize: task.sizeBytes);
        await _tryThumbnail(task, token, check);
        check();
        task.referenceId = await api.reference(
            task.attachmentId!, task.target, task.taskId,
            cancelToken: token);
        check();
        task.state = 'ready';
        await _save(task);
      }
      check();
      if (task.expiresAt != null &&
          !task.expiresAt!.isAfter(DateTime.now().toUtc())) {
        throw const ChatAttachmentException('ATTACHMENT_EXPIRED', '附件已过期');
      }
      // Persist before IM: on a crash the task stays pending, never auto-resends.
      task.state = 'dispatching';
      await _save(task);
      check();
      final result = task.kind == 'video'
          ? nativeVideoResult(
              task,
              await api.sendNativeVideo(
                  attachmentId: task.attachmentId!,
                  referenceId: task.referenceId!,
                  operationId: task.taskId,
                  target: task.target,
                  durationMs: task.durationMs,
                  cancelToken: token))
          : await _dispatch(task);
      check();
      // A realtime/history confirmation can arrive before the dispatch future.
      if (task.state == 'sent') return;
      task.state = switch (result.state) {
        ExternalMessageSendState.succeeded => 'sent',
        // The regular failed message bubble owns explicit IM retry from here.
        ExternalMessageSendState.failed => 'handedOff',
        ExternalMessageSendState.outcomeUnknown => 'outcomeUnknown',
        _ => 'failed',
      };
      task.error = result.succeeded ? '' : result.description;
      await _save(task);
      if (task.kind == 'video' && result.succeeded) _refreshNativeHistory(task);
    } catch (error) {
      if (task.state == 'sent') return;
      final known = error is ChatAttachmentException
          ? error
          : error is DioError
              ? ChatAttachmentException(
                  CancelToken.isCancel(error) ? 'CANCELLED' : 'NETWORK_ERROR',
                  '')
              : const ChatAttachmentException('LOCAL_ERROR', '附件操作失败，请重试');
      task.state = task.state == 'dispatching'
          ? 'outcomeUnknown'
          : const {'CANCELLED', 'SESSION_CHANGED'}.contains(known.code)
              ? 'paused'
              : 'failed';
      task.error =
          task.state == 'outcomeUnknown' ? '发送结果待确认，请勿重复发送' : known.userMessage;
      ChatAttachmentDiagnostics.event('task_failed', {
        'state': task.state,
        'code': known.code,
        'errorType': error.runtimeType.toString(),
        'hasUploadSession': task.uploadId != null,
      });
      await _save(task);
    } finally {
      if (task.kind == 'video' && task.state == 'outcomeUnknown') {
        _watchNativeStatus();
      }
      boundaryWatch.cancel();
    }
  }

  Future<void> pause(ChatAttachmentTask task) async {
    if (task.terminal ||
        task.state == 'dispatching' ||
        task.state == 'outcomeUnknown') {
      return;
    }
    _tokens[task.taskId]?.cancel('paused');
    await _running[task.taskId];
    if (task.terminal ||
        task.state == 'dispatching' ||
        task.state == 'outcomeUnknown') {
      return;
    }
    task.state = 'paused';
    await _save(task);
  }

  Future<void> cancel(ChatAttachmentTask task) async {
    final owner = _owner(), generation = _generation();
    _check(task.ownerUserId, generation);
    if (task.terminal ||
        task.state == 'dispatching' ||
        task.state == 'outcomeUnknown') {
      return;
    }
    await pause(task);
    _check(owner, generation);
    if (task.terminal ||
        task.state == 'dispatching' ||
        task.state == 'outcomeUnknown') {
      return;
    }
    if (task.uploadId != null) await api.cancel(task.uploadId!);
    _check(owner, generation);
    task.state = 'cancelled';
    await _save(task);
  }

  Future<void> observeSent(ChatAttachment attachment) async {
    await load();
    for (final task in _tasks.values.toList()) {
      if (task.ownerUserId == _owner() &&
          task.referenceId == attachment.referenceId &&
          (task.state == 'outcomeUnknown' || task.state == 'dispatching')) {
        task.state = 'sent';
        await _save(task);
      }
    }
  }

  Future<void> _tryThumbnail(
      ChatAttachmentTask task, CancelToken token, void Function() check) async {
    if (task.kind != 'video' || task.thumbnailAttachmentId != null) {
      return;
    }
    try {
      if (task.snapshotPath == null ||
          !await File(task.snapshotPath!).exists()) {
        task.snapshotPath = await _thumbnailBuilder(task.sourcePath);
        check();
      }
      if (task.snapshotPath == null) return;
      final source = File(task.snapshotPath!);
      if (!await source.exists()) return;
      final length = await source.length();
      if (length <= 0 || length > 1048576) return;
      check();
      // Keep the sender's cover even when the optional cloud upload fails.
      final dest = await store.downloadFile(
          task.ownerUserId, task.attachmentId!, 'thumbnail.jpg',
          variant: 'thumbnail');
      final temp = await source.copy('${dest.path}.part');
      check();
      final file = await temp.rename(dest.path);
      await store.registerLocal(task.ownerUserId, task.attachmentId!, file,
          expectedSize: length, variant: 'thumbnail');
      check();
      final grant =
          await api.thumbnailUpload(task.uploadId!, cancelToken: token);
      check();
      final headers = ChatAttachmentTransfer.signedHeaders(grant);
      final request = Options(
              method: 'PUT',
              headers: {...headers, 'Content-Length': length},
              followRedirects: false,
              responseType: ResponseType.plain)
          .compose(
              transfer.storage.options, ChatAttachmentTransfer.signedUrl(grant),
              data: source.openRead(), cancelToken: token);
      // Presigned cover PUTs need the exact signed headers, just like originals.
      request.contentType = headers.entries
          .where((entry) => entry.key.toLowerCase() == 'content-type')
          .map((entry) => entry.value?.toString())
          .firstWhere((_) => true, orElse: () => null);
      await transfer.storage.fetch<dynamic>(request);
      check();
      final done =
          await api.thumbnailComplete(task.uploadId!, cancelToken: token);
      check();
      task.thumbnailAttachmentId = attachmentOptionalString(
          done['thumbnailAttachmentId'] ?? grant['thumbnailAttachmentId']);
      if (task.thumbnailAttachmentId != null) {
        await _save(task);
      }
    } catch (error) {
      check(); // An optional cover failure must never suppress a session change.
      ChatAttachmentDiagnostics.event('thumbnail_upload_failed', {
        'errorType': error.runtimeType.toString(),
        'httpStatus': error is DioError ? error.response?.statusCode : null,
      });
    }
  }

  /// Never fetches the original just to display a poster. Coalesce extraction
  /// across rebuilds and persist it in the existing account-scoped cache.
  Future<String?> videoThumbnail(ChatAttachment attachment) async {
    if (attachment.kind != 'video') return null;
    final owner = _owner(), generation = _generation();
    final key = '$owner:$generation:${attachment.attachmentId}';
    final active = _videoThumbnails[key];
    if (active != null) return active;
    final future = _resolveVideoThumbnail(attachment, owner, generation);
    _videoThumbnails[key] = future;
    try {
      return await future;
    } finally {
      _videoThumbnails.remove(key);
    }
  }

  Future<String?> _resolveVideoThumbnail(
      ChatAttachment attachment, String owner, int generation) async {
    final cached = await localPath(attachment, thumbnail: true);
    if (cached != null) return cached;
    final original = await localPath(attachment);
    _check(owner, generation);
    if (original == null) {
      // The parent reference resolves the cover, even for old wire messages
      // lacking the optional thumbnailAttachmentId.
      try {
        return await resolveFile(attachment, thumbnail: true);
      } catch (error) {
        _check(owner, generation);
        ChatAttachmentDiagnostics.event('thumbnail_restore_failed', {
          'errorType': error.runtimeType.toString(),
          'wireThumbnailPresent': attachment.thumbnailAttachmentId != null,
        });
        return null;
      }
    }
    final generated = await _thumbnailBuilder(original);
    _check(owner, generation);
    if (generated == null) return null;
    final source = File(generated);
    if (!await source.exists() || await source.length() == 0) return null;
    final dest = await store.downloadFile(
        owner, attachment.attachmentId, 'thumbnail.jpg',
        variant: 'thumbnail');
    final part = await source.copy('${dest.path}.part');
    _check(owner, generation);
    final file = await part.rename(dest.path);
    await store.registerLocal(owner, attachment.attachmentId, file,
        expectedSize: await file.length(), variant: 'thumbnail');
    _check(owner, generation);
    return file.path;
  }

  Future<String?> localPath(ChatAttachment attachment,
      {bool thumbnail = false}) async {
    final owner = _owner(), generation = _generation();
    final file = await store.localFile(owner, attachment.attachmentId,
        variant: thumbnail ? 'thumbnail' : 'original',
        expectedSize: thumbnail ? null : attachment.sizeBytes);
    _check(owner, generation);
    return file?.path;
  }

  Future<String> resolveFile(ChatAttachment attachment,
      {bool thumbnail = false,
      void Function(double)? onProgress,
      CancelToken? cancelToken}) async {
    final local = await localPath(attachment, thumbnail: thumbnail);
    if (local != null) return local;
    final owner = _owner(), generation = _generation();
    final key =
        '$owner:${attachment.attachmentId}:${thumbnail ? "thumbnail" : "original"}';
    final existing = _downloads[key];
    if (existing != null) return existing;
    final future = _download(
        attachment, owner, generation, thumbnail, onProgress, cancelToken);
    _downloads[key] = future;
    try {
      return await future;
    } finally {
      _downloads.remove(key);
    }
  }

  Future<ChatAttachmentPlayback> playback(ChatAttachment attachment,
      {CancelToken? cancelToken}) async {
    if (cancelToken?.isCancelled == true) {
      throw const ChatAttachmentException('CANCELLED', '任务已暂停');
    }
    final local = await localPath(attachment);
    if (local != null) return ChatAttachmentPlayback(local, local: true);
    final owner = _owner(), generation = _generation();
    final grant =
        await api.access(attachment, 'playback', cancelToken: cancelToken);
    _check(owner, generation, cancelToken);
    return ChatAttachmentPlayback(ChatAttachmentTransfer.signedUrl(grant),
        headers: ChatAttachmentTransfer.signedHeaders(grant)
            .map((key, value) => MapEntry(key, value.toString())));
  }

  Future<String> _download(
      ChatAttachment attachment,
      String owner,
      int generation,
      bool thumbnail,
      void Function(double)? onProgress,
      CancelToken? cancelToken) async {
    final token = cancelToken ?? CancelToken();
    void check() => _check(owner, generation, token);
    final watch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_owner() != owner || _generation() != generation) {
        token.cancel('session changed');
      }
    });
    try {
      check();
      final destination = await store.downloadFile(
          owner,
          attachment.attachmentId,
          thumbnail ? 'thumbnail.jpg' : attachment.name,
          variant: thumbnail ? 'thumbnail' : 'original');
      final temp = File('${destination.path}.part');
      for (var attempt = 0; attempt < 3; attempt++) {
        check();
        var offset = await temp.exists() ? await temp.length() : 0;
        if (offset >= (thumbnail ? 1048576 : attachment.sizeBytes)) {
          await temp.writeAsBytes([]);
          offset = 0;
        }
        final grant = await api.access(
            attachment, thumbnail ? 'thumbnail' : 'download',
            cancelToken: token);
        check();
        try {
          final response = await transfer.storage.get<ResponseBody>(
              ChatAttachmentTransfer.signedUrl(grant),
              cancelToken: token,
              options: Options(
                  responseType: ResponseType.stream,
                  followRedirects: false,
                  headers: {
                    ...ChatAttachmentTransfer.signedHeaders(grant),
                    if (offset > 0) 'Range': 'bytes=$offset-'
                  }));
          check();
          final partial = response.statusCode == 206;
          final body = response.data;
          if (body == null) {
            throw const ChatAttachmentException('INVALID_RESPONSE', '附件响应为空');
          }
          if (partial) {
            final range = response.headers.value('content-range') ?? '';
            final match =
                RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
            if (match == null ||
                int.parse(match[1]!) != offset ||
                (!thumbnail && int.parse(match[3]!) != attachment.sizeBytes)) {
              await body.stream.listen((_) {}).cancel();
              throw const ChatAttachmentException(
                  'INVALID_RESPONSE', '附件续传范围不匹配');
            }
          } else if (response.statusCode == 200) {
            offset = 0;
          } else {
            await body.stream.listen((_) {}).cancel();
            throw const ChatAttachmentException('INVALID_RESPONSE', '附件下载响应无效');
          }
          var received = offset;
          final maxBytes = thumbnail ? 1048576 : attachment.sizeBytes;
          final sink =
              await temp.open(mode: partial ? FileMode.append : FileMode.write);
          try {
            await for (final chunk in body.stream) {
              check();
              received += chunk.length;
              if (received > maxBytes) {
                throw const ChatAttachmentException(
                    'CHECKSUM_MISMATCH', '附件大小不匹配');
              }
              await sink.writeFrom(chunk);
              onProgress?.call((received / maxBytes).clamp(0, 1).toDouble());
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          check();
          final actual = await temp.length();
          if (actual <= 0 || (!thumbnail && actual != attachment.sizeBytes)) {
            throw const ChatAttachmentException('NETWORK_ERROR', '附件下载不完整');
          }
          if (await destination.exists()) await destination.delete();
          final file = await temp.rename(destination.path);
          await store.registerLocal(owner, attachment.attachmentId, file,
              expectedSize: actual,
              variant: thumbnail ? 'thumbnail' : 'original');
          check();
          return file.path;
        } on DioError catch (error) {
          if (CancelToken.isCancel(error)) {
            throw const ChatAttachmentException('CANCELLED', '下载已暂停');
          }
          if (attempt == 2) {
            throw const ChatAttachmentException('NETWORK_ERROR', '下载中断');
          }
          await Future<void>.delayed(
              Duration(milliseconds: 500 * (1 << attempt)));
        }
      }
      throw const ChatAttachmentException('NETWORK_ERROR', '下载中断');
    } finally {
      watch.cancel();
    }
  }

  static Future<ExternalMessageSendResult> _dispatchMessage(
      ChatAttachmentTask task) async {
    if (task.kind == 'video') {
      throw const ChatAttachmentException('INVALID_STATE', '视频必须通过后端发送原生消息');
    }
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId != task.ownerUserId ||
        ApiClient.instance.authenticatedUserId != task.ownerUserId) {
      throw const ChatAttachmentException('SESSION_CHANGED', '账号已切换');
    }
    final created = await serviceLocator<MessageService>()
        .createCustomMessage(data: jsonEncode(task.message.toJson()));
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      throw const ChatAttachmentException('SESSION_CHANGED', '账号已切换');
    }
    if (created?.messageInfo == null || created?.id == null) {
      return const ExternalMessageSendResult(
          state: ExternalMessageSendState.blocked, description: '附件消息创建失败');
    }
    return ChatExternalMessageSender.sendCreatedMessageDetailed(
        messageInfo: created!.messageInfo,
        receiverUserId: task.target.isGroup ? '' : task.target.id,
        groupId: task.target.isGroup ? task.target.id : '',
        reason: 'chat_attachment_sent');
  }

  static String _mimeFor(String name, String nativeKind) {
    final ext = p.extension(name).toLowerCase();
    return const {
          '.jpg': 'image/jpeg',
          '.jpeg': 'image/jpeg',
          '.png': 'image/png',
          '.gif': 'image/gif',
          '.webp': 'image/webp',
          '.heic': 'image/heic',
          '.mp4': 'video/mp4',
          '.mov': 'video/quicktime',
          '.mkv': 'video/x-matroska',
          '.mp3': 'audio/mpeg',
          '.m4a': 'audio/mp4',
          '.aac': 'audio/aac',
          '.wav': 'audio/wav',
          '.ogg': 'audio/ogg',
          '.amr': 'audio/amr',
          '.flac': 'audio/flac',
          '.pdf': 'application/pdf'
        }[ext] ??
        (nativeKind == 'sound' ? 'audio/aac' : 'application/octet-stream');
  }

  @override
  void dispose() {
    _nativeStatusDisposed = true;
    _nativeStatusTimer?.cancel();
    _nativeStatusTimer = null;
    super.dispose();
  }
}
