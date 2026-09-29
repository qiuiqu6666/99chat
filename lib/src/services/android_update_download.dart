import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class AndroidUpdateRequest {
  const AndroidUpdateRequest(
      {required this.url,
      required this.version,
      required this.build,
      required this.mandatory,
      this.notes = ''});

  final String url;
  final String version;
  final int build;
  final bool mandatory;
  final String notes;

  String get key =>
      sha256.convert(utf8.encode(jsonEncode([url, version, build]))).toString();

  Map<String, Object> toMap() => {
        'key': key,
        'url': url,
        'version': version,
        'build': build,
        'mandatory': mandatory,
        'notes': notes,
      };

  factory AndroidUpdateRequest.fromMap(Map<Object?, Object?> value) =>
      AndroidUpdateRequest(
          url: value['url'] as String,
          version: value['version'] as String,
          build: (value['build'] as num).toInt(),
          mandatory: value['mandatory'] == true,
          notes: value['notes'] as String? ?? '');
}

@immutable
class AndroidUpdateSnapshot {
  const AndroidUpdateSnapshot(this.state,
      {this.request, this.reason = '', this.received = 0, this.total = 0});
  final String state;
  final AndroidUpdateRequest? request;
  final String reason;
  final int received;
  final int total;
  bool get ready => state == 'ready';
  bool get downloading => const ['queued', 'running', 'paused'].contains(state);

  factory AndroidUpdateSnapshot.fromMap(Map<Object?, Object?> value) =>
      AndroidUpdateSnapshot(value['state'] as String? ?? 'missing',
          request: value['request'] is Map
              ? AndroidUpdateRequest.fromMap(value['request'] as Map)
              : null,
          reason: value['reason']?.toString() ?? '',
          received: (value['received'] as num?)?.toInt() ?? 0,
          total: (value['total'] as num?)?.toInt() ?? 0);
}

abstract interface class AndroidUpdateGateway {
  Future<AndroidUpdateSnapshot> ensure(AndroidUpdateRequest request,
      {required bool retry});
  Future<AndroidUpdateSnapshot> status();
  Future<String> install(String key, {required bool requestPermission});
  Future<void> cancel();
}

class MethodChannelAndroidUpdateGateway implements AndroidUpdateGateway {
  static const _channel = MethodChannel('ninechat/app_update');
  static const _deadline = Duration(seconds: 30);

  @override
  Future<AndroidUpdateSnapshot> ensure(AndroidUpdateRequest request,
          {required bool retry}) async =>
      AndroidUpdateSnapshot.fromMap(await _channel
              .invokeMapMethod<Object?, Object?>('ensure', {
            ...request.toMap(),
            'retry': retry,
            'allowMetered': true
          }).timeout(_deadline) ??
          {});

  @override
  Future<AndroidUpdateSnapshot> status() async =>
      AndroidUpdateSnapshot.fromMap(await _channel
              .invokeMapMethod<Object?, Object?>('status')
              .timeout(_deadline) ??
          {});

  @override
  Future<String> install(String key, {required bool requestPermission}) async =>
      await _channel.invokeMethod<String>('install', {
        'key': key,
        'requestPermission': requestPermission
      }).timeout(_deadline) ??
      'unavailable';

  @override
  Future<void> cancel() =>
      _channel.invokeMethod<void>('cancel').timeout(_deadline);
}

/// DownloadManager owns the transfer. This controller only observes it while
/// the UI is active; no Dart isolate has to survive background suspension.
class AndroidUpdateDownloadController extends ChangeNotifier {
  AndroidUpdateDownloadController(
    this.gateway, {
    this.pollInterval = const Duration(seconds: 3),
    this.operationTimeout = const Duration(seconds: 35),
  });
  final AndroidUpdateGateway gateway;
  final Duration pollInterval;
  final Duration operationTimeout;
  AndroidUpdateSnapshot snapshot = const AndroidUpdateSnapshot('missing');
  Timer? _poll;
  Future<void>? _preparing;
  String? _preparingKey;
  Future<void>? _refreshing;
  Future<String>? _installing;
  int _generation = 0;
  int _queryFailures = 0;
  bool _foreground = true;
  bool _disposed = false;

  Future<void> prepare(AndroidUpdateRequest request, {bool retry = false}) {
    if (_preparingKey == request.key && _preparing != null) return _preparing!;
    final generation = ++_generation;
    _poll?.cancel();
    _queryFailures = 0;
    _preparingKey = request.key;
    // A previous ready APK must not remain actionable while replacing it.
    _publish(AndroidUpdateSnapshot('queued', request: request));
    late final Future<void> task;
    task = () async {
      try {
        final next =
            await Future.sync(() => gateway.ensure(request, retry: retry))
                .timeout(operationTimeout);
        if (!_disposed && generation == _generation) _publish(next);
      } catch (_) {
        if (!_disposed && generation == _generation) {
          _queryFailures++;
          _publish(AndroidUpdateSnapshot('unavailable', request: request));
        }
      } finally {
        if (identical(_preparing, task)) {
          _preparing = null;
          _preparingKey = null;
        }
        if (!_disposed && generation == _generation) _schedule();
      }
    }();
    _preparing = task;
    return task;
  }

  Future<void> refresh() {
    if (_preparing != null) return _preparing!;
    if (_refreshing != null) return _refreshing!;
    final generation = _generation;
    late final Future<void> task;
    task = () async {
      try {
        final next =
            await Future.sync(gateway.status).timeout(operationTimeout);
        if (!_disposed && generation == _generation) {
          _queryFailures = 0;
          _publish(next);
        }
      } catch (_) {
        if (!_disposed && generation == _generation) {
          _queryFailures++;
          _publish(
              AndroidUpdateSnapshot('unavailable', request: snapshot.request));
        }
      } finally {
        if (identical(_refreshing, task)) _refreshing = null;
        if (!_disposed && generation == _generation) _schedule();
      }
    }();
    _refreshing = task;
    return task;
  }

  Future<String> install({bool requestPermission = true}) {
    if (_installing != null) return _installing!;
    final request = snapshot.request;
    if (!snapshot.ready || request == null) return Future.value('not_ready');
    late final Future<String> task;
    task = () async {
      try {
        return await Future.sync(() => gateway.install(request.key,
            requestPermission: requestPermission)).timeout(operationTimeout);
      } catch (_) {
        return 'unavailable';
      } finally {
        if (identical(_installing, task)) _installing = null;
      }
    }();
    _installing = task;
    return task;
  }

  Future<void> cancel() async {
    final generation = ++_generation;
    _preparing = null;
    _preparingKey = null;
    _refreshing = null;
    _poll?.cancel();
    if (!_disposed) _publish(const AndroidUpdateSnapshot('missing'));
    try {
      await gateway.cancel().timeout(operationTimeout);
    } catch (_) {/* next check retries */}
    if (!_disposed && generation == _generation) {
      _publish(const AndroidUpdateSnapshot('missing'));
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    _poll?.cancel();
    if (value && !_disposed) unawaited(refresh());
  }

  void _publish(AndroidUpdateSnapshot value) {
    snapshot = value;
    notifyListeners();
  }

  void _schedule() {
    _poll?.cancel();
    if (_disposed || !_foreground) return;
    if (snapshot.downloading ||
        (snapshot.state == 'unavailable' && _queryFailures < 3)) {
      _poll = Timer(pollInterval, refresh);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _poll?.cancel();
    super.dispose();
  }
}
