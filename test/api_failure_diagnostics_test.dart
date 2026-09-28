import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/api_failure_diagnostics.dart';

void main() {
  test('redacts URL parameters, dynamic IDs and payloads', () {
    final log = ApiFailureDiagnostics();
    final request = RequestOptions(
        path:
            'https://private.host/users/alice@example.com/orders/123?token=secret',
        method: 'POST',
        data: {'password': 'sensitive'},
        headers: {'Authorization': 'Bearer secret'});
    log.record(request,
        response: Response(
            requestOptions: request,
            statusCode: 500,
            data: {'code': 'SERVER_ERROR', 'message': 'private response text'},
            headers: Headers.fromMap({
              'x-request-id': ['trace_12345']
            })));
    final report = log.snapshot();
    expect(report, contains('/users/:id/orders/:id'));
    expect(report, contains('SERVER_ERROR'));
    expect(report, contains('trace_12345'));
    for (final secret in [
      'alice',
      'private.host',
      'token',
      'sensitive',
      'Bearer',
      'private response text'
    ]) {
      expect(report, isNot(contains(secret)));
    }
  });
  test('repeated failures aggregate and obey global rate and memory limits',
      () {
    var time = DateTime.utc(2026);
    final written = <String>[];
    final log = ApiFailureDiagnostics(now: () => time, write: written.add);
    final request = RequestOptions(path: '/wallet/balance');
    for (var i = 0; i < 1000; i++) {
      log.record(request, kind: 'receiveTimeout');
    }
    expect(written.length, 1);
    expect(log.snapshot(), contains('"count":1000'));
    time = time.add(const Duration(minutes: 1));
    for (var i = 400; i < 500; i++) {
      log.record(request,
          response: Response(requestOptions: request, statusCode: i));
    }
    expect(written.length, 21);
    for (var i = 0; i < 200; i++) {
      time = time.add(const Duration(minutes: 1));
      log.record(request,
          response: Response(requestOptions: request, statusCode: 500 + i));
    }
    expect(log.snapshot().split('\n').length, 101);
  });
  test(
      'interceptor preserves responses, ignores success and cancellation, records business errors',
      () async {
    final log = ApiFailureDiagnostics();
    final dio = Dio()
      ..interceptors.add(ApiFailureInterceptor(diagnostics: log));
    var mode = 'success';
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (mode == 'cancel') {
        h.reject(DioError(requestOptions: o, type: DioErrorType.cancel));
        return;
      }
      if (mode == 'timeout') {
        h.reject(DioError(requestOptions: o, type: DioErrorType.receiveTimeout),
            true);
        return;
      }
      h.resolve(
          Response(
              requestOptions: o,
              statusCode: 200,
              data: {'code': mode == 'success' ? 0 : 'PAYMENT_FAILED'}),
          true);
    }));
    await dio.get('/wallet/balance');
    expect(log.snapshot(), 'suppressed=0\n');
    mode = 'cancel';
    await expectLater(dio.get('/wallet/balance'), throwsA(isA<DioError>()));
    expect(log.snapshot(), 'suppressed=0\n');
    mode = 'business';
    expect((await dio.get('/wallet/balance')).data['code'], 'PAYMENT_FAILED');
    expect(log.snapshot(), contains('PAYMENT_FAILED'));
    mode = 'timeout';
    await expectLater(dio.get('/wallet/balance'), throwsA(isA<DioError>()));
    expect(log.snapshot(), contains('receiveTimeout'));
    dio.close();
  });
  test('broken diagnostics storage cannot change the request result', () {
    final log =
        ApiFailureDiagnostics(write: (_) => throw StateError('disk full'));
    expect(
        () => log.record(RequestOptions(path: '/feedback')), returnsNormally);
    expect(jsonDecode(log.snapshot().split('\n').last)['route'], '/feedback');
  });
}
