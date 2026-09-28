import 'dart:convert';
import 'package:dio/dio.dart';
import 'recovery_log_buffer.dart';
import 'recovery_log_file_stub.dart'
    if (dart.library.io) 'recovery_log_file.dart';

/// Release-safe, bounded failure metadata. Never stores request/response bodies.
class ApiFailureDiagnostics {
  ApiFailureDiagnostics({DateTime Function()? now, this.write})
      : now = now ?? DateTime.now;
  final DateTime Function() now;
  final void Function(String)? write;
  static final _file =
      RecoveryLogFile(maxBytes: 64 * 1024, folderName: 'api_failures');
  static final _buffer = RecoveryLogBuffer(
      write: _file.append,
      capacity: 100,
      batchSize: 20,
      flushDelay: const Duration(seconds: 30),
      retryDelay: const Duration(minutes: 1));
  static final instance = ApiFailureDiagnostics(write: _buffer.add);
  final _rows = <String, Map<String, Object>>{};
  DateTime? _window;
  int _emitted = 0;
  int suppressed = 0;

  // Unknown segments (including user-provided slugs) are hidden by default.
  static const _segments = <String>{
    'api',
    'v1',
    'v2',
    'auth',
    'login',
    'logout',
    'register',
    'sms',
    'password',
    'verify',
    'reset',
    'token',
    'refresh',
    'me',
    'users',
    'user',
    'profile',
    'avatar',
    'nickname',
    'groups',
    'group',
    'members',
    'member',
    'join',
    'leave',
    'owner',
    'admin',
    'mute',
    'contacts',
    'contact',
    'friends',
    'friend',
    'requests',
    'request',
    'accept',
    'reject',
    'messages',
    'message',
    'history',
    'latest',
    'read',
    'recall',
    'delete',
    'send',
    'chat',
    'conversations',
    'conversation',
    'sync',
    'batch',
    'start',
    'complete',
    'upload',
    'download',
    'attachments',
    'attachment',
    'chat-attachments',
    'wallet',
    'balance',
    'transfer',
    'transfers',
    'red-packet',
    'red-packets',
    'claim',
    'detail',
    'status',
    'card-orders',
    'withdraw',
    'deposit',
    'records',
    'list',
    'feedback',
    'platform',
    'config',
    'settings',
    'customer-service',
    'splash',
    'version',
    'sticker',
    'stickers',
    'packs',
    'favorites',
    'search',
    'notifications',
    'device',
    'devices',
    'push',
    'heartbeat',
    'presence',
    'online',
    'agent',
    'rebate',
    'orders',
    'order',
    'payment',
    'payments',
    'create',
    'update',
  };
  static String route(String path) {
    final parsed = Uri.tryParse(path);
    return '/${(parsed?.path ?? '').split('/').where((s) => s.isNotEmpty).take(12).map((s) => _segments.contains(s) ? s : ':id').join('/')}';
  }

  static String code(dynamic value) {
    final text = value is String || value is num ? value.toString() : '';
    return RegExp(r'^(?:[0-9]{1,6}|[A-Z][A-Z0-9_]{1,63})$').hasMatch(text)
        ? text
        : '';
  }

  void record(RequestOptions request,
      {Response? response, String kind = 'http'}) {
    try {
      final status = response?.statusCode ?? 0;
      final body = response?.data;
      final business = body is Map
          ? code(body['code'] ?? body['errorCode'] ?? body['errCode'])
          : '';
      final path = route(request.path);
      final method = const {
        'GET',
        'POST',
        'PUT',
        'DELETE',
        'PATCH',
        'HEAD',
        'OPTIONS'
      }.contains(request.method)
          ? request.method
          : 'OTHER';
      final key = '$method $path $status $kind $business';
      final time = now().toUtc();
      final previous = _rows[key];
      if (previous != null) {
        previous['count'] = (previous['count'] as int) + 1;
        previous['last'] = time.toIso8601String();
        if (time.difference(DateTime.parse(previous['written'] as String)) <
            const Duration(minutes: 1)) {
          suppressed++;
          return;
        }
      }
      if (_window == null ||
          time.difference(_window!) >= const Duration(minutes: 1)) {
        _window = time;
        _emitted = 0;
      }
      if (_emitted >= 20) {
        suppressed++;
        return;
      }
      _emitted++;
      final watch = request.extra['failureDiagnosticsClock'];
      final row = previous ??
          <String, Object>{
            'first': time.toIso8601String(),
            'count': 1,
            'method': method,
            'route': path,
            'status': status,
            'kind': kind,
            if (business.isNotEmpty) 'code': business,
          };
      row['last'] = time.toIso8601String();
      row['written'] = time.toIso8601String();
      if (watch is Stopwatch) row['elapsedMs'] = watch.elapsedMilliseconds;
      final requestId = response?.headers.value('x-request-id') ??
          response?.headers.value('x-trace-id');
      if (requestId != null &&
          RegExp(r'^[a-zA-Z0-9_-]{8,64}$').hasMatch(requestId)) {
        row['requestId'] = requestId;
      } else {
        row.remove('requestId');
      }
      _rows.remove(key);
      _rows[key] = row;
      while (_rows.length > 100) {
        _rows.remove(_rows.keys.first);
      }
      write?.call(jsonEncode(row));
    } catch (_) {/* Diagnostics must never affect network requests. */}
  }

  String snapshot() =>
      'suppressed=$suppressed\n${_rows.values.map(jsonEncode).join('\n')}';
  static Future<String> export() async {
    var saved = '';
    try {
      await _buffer.flush().timeout(const Duration(seconds: 2));
      saved = await _file.read().timeout(const Duration(seconds: 2));
    } catch (_) {
      saved = '[Local file unavailable]';
    }
    return '--- API failures (saved samples; may overlap current session) ---\n$saved\n'
        '--- API failures (current session aggregate) ---\n${instance.snapshot()}\n';
  }
}

class ApiFailureInterceptor extends Interceptor {
  ApiFailureInterceptor({ApiFailureDiagnostics? diagnostics})
      : diagnostics = diagnostics ?? ApiFailureDiagnostics.instance;
  final ApiFailureDiagnostics diagnostics;
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['failureDiagnosticsClock'] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final raw = response.data;
      final value =
          raw is Map ? raw['code'] ?? raw['errorCode'] ?? raw['errCode'] : null;
      final failed = value != null &&
          !const {'', '0', '200', '201', 'OK', 'SUCCESS'}
              .contains(value.toString().toUpperCase());
      if ((response.statusCode ?? 0) >= 400 ||
          failed ||
          (raw is Map && raw['success'] == false)) {
        diagnostics.record(response.requestOptions,
            response: response, kind: failed ? 'business' : 'http');
      }
    } catch (_) {/* No change to the response. */}
    handler.next(response);
  }

  @override
  void onError(DioError err, ErrorInterceptorHandler handler) {
    if (err.type != DioErrorType.cancel) {
      diagnostics.record(err.requestOptions,
          response: err.response, kind: err.type.name);
    }
    handler.next(err);
  }
}
