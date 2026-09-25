import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_app_payload.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_gallery_worker.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_image_normalizer.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_web_login_payload.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_zxing2_decode.dart';

class QrGalleryCancellation {
  bool _cancelled = false;
  final _listeners = <VoidCallback>{};
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }
}

class QrGalleryScanResult {
  const QrGalleryScanResult(this.values, this.status, this.diagnostics);
  final List<String> values;
  // ok, no_code, cancelled, timeout, invalid_image, too_large, error
  final String status;
  final Map<String, Object?> diagnostics;
}

/// Owns the deadline and cancellation on the UI isolate. All bitmap work and
/// synchronous FFI calls run in a disposable worker, including on desktop.
class QrGalleryDecoder {
  QrGalleryDecoder._();
  static const Duration _totalTimeout = Duration(seconds: 8);

  static Future<String?> decodeFromPath(
    String path, {
    @Deprecated('Gallery path no longer uses ML Kit analyzeImage')
    MobileScannerController? mlKitScanner,
  }) async =>
      pickPreferred(await scanAll(path));

  static Future<List<String>> scanAll(String path) async =>
      (await scan(path)).values;

  static Future<QrGalleryScanResult> scan(
    String path, {
    QrGalleryCancellation? cancellation,
    Duration timeout = _totalTimeout,
    bool collectDiagnostics = false,
  }) async {
    final cancel = cancellation ?? QrGalleryCancellation();
    final clock = Stopwatch()..start();
    NormalizedQrImage? normalized;
    Timer? memorySampler;
    int? rssBefore;
    int? rssPeak;
    var normalizeMs = 0;
    if (collectDiagnostics && !kIsWeb) {
      int? readRss() {
        try {
          return ProcessInfo.currentRss;
        } catch (_) {
          return null;
        }
      }

      rssBefore = readRss();
      rssPeak = rssBefore;
      memorySampler = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final rss = readRss();
        if (rss != null) rssPeak = math.max(rssPeak ?? rss, rss);
      });
    }
    QrGalleryScanResult result(Map<String, Object?> raw) {
      final values = (raw['values'] as List?)?.cast<String>() ?? <String>[];
      final status = raw['status'] as String? ?? 'error';
      final metrics = <String, Object?>{
        ...(Map<String, Object?>.from(raw)..remove('values')),
        'elapsedMs': clock.elapsedMilliseconds,
        'normalizeMs': normalizeMs,
        if (rssBefore != null && rssPeak != null)
          'sampledProcessRssDeltaBytes': rssPeak! - rssBefore,
      };
      if (kDebugMode || collectDiagnostics) {
        // Never log the image path or decoded login/address/personal payload.
        debugPrint(
            '[QrGallery] ${jsonEncode({...metrics, 'codes': values.length})}');
      }
      return QrGalleryScanResult(List.unmodifiable(values), status, metrics);
    }

    try {
      if (cancel.isCancelled) return result({'status': 'cancelled'});
      if (kIsWeb || path.trim().isEmpty) {
        return result({'status': 'invalid_image'});
      }
      if (timeout <= Duration.zero) return result({'status': 'timeout'});
      var normalizeExpired = false;
      final normalizeBudget = timeout < const Duration(milliseconds: 800)
          ? timeout
          : const Duration(milliseconds: 800);
      normalized = await QrImageNormalizer.normalize(path).then((value) async {
        if (normalizeExpired) await value.disposeTemporary();
        return value;
      }).timeout(normalizeBudget, onTimeout: () {
        normalizeExpired = true;
        return NormalizedQrImage(
            path: path, width: 0, height: 0, isTemporary: false);
      });
      normalizeMs = clock.elapsedMilliseconds;
      if (cancel.isCancelled) return result({'status': 'cancelled'});
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) return result({'status': 'timeout'});
      return result(await _runWorker(normalized.path, remaining, cancel));
    } catch (_) {
      return result({'status': cancel.isCancelled ? 'cancelled' : 'error'});
    } finally {
      memorySampler?.cancel();
      await normalized?.disposeTemporary();
    }
  }

  static Future<Map<String, Object?>> _runWorker(
    String path,
    Duration budget,
    QrGalleryCancellation cancel,
  ) {
    final completion = Completer<Map<String, Object?>>();
    final replies = ReceivePort();
    Isolate? worker;
    Timer? deadline;
    late VoidCallback onCancel;
    void finish(Map<String, Object?> value) {
      if (completion.isCompleted) return;
      deadline?.cancel();
      cancel._listeners.remove(onCancel);
      replies.close();
      // A native call already running can finish before the isolate exits;
      // its late result is discarded and no more passes are scheduled.
      worker?.kill(priority: Isolate.immediate);
      completion.complete(value);
    }

    onCancel = () => finish({'status': 'cancelled'});
    replies.listen((message) {
      if (message is Map) {
        finish(Map<String, Object?>.from(message));
      } else {
        finish({'status': 'error'});
      }
    });
    cancel._listeners.add(onCancel);
    if (cancel.isCancelled) {
      onCancel();
      return completion.future;
    }
    deadline = Timer(budget, () => finish({'status': 'timeout'}));
    unawaited(Isolate.spawn(
      decodeQrGalleryWorker,
      (
        replies.sendPort,
        path,
        budget.inMilliseconds,
        (Platform.isAndroid || Platform.isIOS) &&
            !Platform.environment.containsKey('FLUTTER_TEST')
      ),
      onError: replies.sendPort,
      onExit: replies.sendPort,
      errorsAreFatal: true,
      debugName: 'qr-gallery',
    ).then((isolate) {
      worker = isolate;
      if (completion.isCompleted) isolate.kill(priority: Isolate.immediate);
    }, onError: (Object _, StackTrace __) {
      finish({'status': 'error'});
    }));
    return completion.future;
  }

  /// A single app target wins over unrelated codes. Ambiguous targets are
  /// returned to the UI for explicit selection, never silently chosen.
  static List<String> preferredCandidates(List<String> values,
      {bool preferAppCodes = true}) {
    final all = <String, String>{};
    final business = <String, String>{};
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final app = QrAppPayload.tryParse(value);
      final login = QrWebLoginPayload.tryParse(value);
      final key = app != null
          ? jsonEncode([app.type.name, app.id])
          : login != null
              ? 'login:${login.sessionId}'
              : 'raw:$value';
      all.putIfAbsent(key, () => value);
      if (app != null || login != null) business.putIfAbsent(key, () => value);
    }
    return (preferAppCodes && business.isNotEmpty ? business : all)
        .values
        .toList(growable: false);
  }

  @visibleForTesting
  static String? pickPreferred(List<String> values) {
    final candidates = preferredCandidates(values);
    return candidates.length == 1 ? candidates.single : null;
  }

  @visibleForTesting
  static String? decodeZxingFromPathForTest(String path) =>
      pickPreferred(decodeQrWithZxing2FromPath(path));
}
