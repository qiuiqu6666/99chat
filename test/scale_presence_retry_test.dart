// Read-only diagnostic: all HTTP is intercepted; no production requests.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TIMUIKitCore.getInstance();
  });

  test('fast HTTP 503 backs off instead of retrying every 400ms',
      () async {
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    final elapsed = Stopwatch()..start();
    final starts = <int>[];
    final presence = PresenceProvider();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      starts.add(elapsed.elapsedMilliseconds);
      handler.reject(DioError(
        requestOptions: request,
        type: DioErrorType.response,
        response: Response(requestOptions: request, statusCode: 503),
      ));
    }));
    try {
      presence.ensure(['synthetic_scale_audit_user'], includeVisibility: false);
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      final gaps = [
        for (var i = 1; i < starts.length; i++) starts[i] - starts[i - 1]
      ];
      // This intentionally records the current risky behavior, not an acceptance gate.
      print('SCALE_AUDIT presence_503 requestStartsMs=$starts gapsMs=$gaps');
      expect(starts.length, inInclusiveRange(1, 2));
      expect(gaps.every((gap) => gap >= 950), isTrue);
    } finally {
      presence.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      dio.interceptors.clear();
      dio.interceptors.addAll(saved);
    }
  });
}
