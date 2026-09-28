import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/feedback_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dio = ApiClient.instance.dio;
  late List<Interceptor> original;
  late FormData form;
  var accepts = true;
  setUp(() {
    original = dio.interceptors.toList();
    dio.interceptors.clear();
    accepts = true;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      form = o.data as FormData;
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {
        'code': 0,
        'data': {'id': 42, 'diagnosticsAttached': accepts}
      }));
    }));
  });
  tearDown(() {
    dio.interceptors.clear();
    dio.interceptors.addAll(original);
  });
  Future<FeedbackSubmitResult> submit([Uint8List? report]) =>
      FeedbackApi.instance.submit(
          type: FeedbackType.bug,
          content: 'scroll issue',
          clientVersion: 'test',
          diagnostics: report);
  test('plain feedback sends no report or consent', () async {
    expect((await submit()).id, 42);
    expect(form.files, isEmpty);
    expect(form.fields.any((f) => f.key == 'diagnosticsConsent'), isFalse);
  });
  test('report travels with explicit consent in the feedback request',
      () async {
    final bytes =
        Uint8List.fromList(utf8.encode('Chat recovery report v1\n测试'));
    await submit(bytes);
    expect(form.files.single.key, 'diagnostics');
    expect(form.files.single.value.filename, 'chat-recovery.txt');
    expect(form.files.single.value.length, bytes.length);
    expect(
        form.fields
            .any((f) => f.key == 'diagnosticsConsent' && f.value == 'true'),
        isTrue);
  });
  test('legacy backend cannot silently acknowledge a discarded report',
      () async {
    accepts = false;
    await expectLater(submit(Uint8List.fromList([1])),
        throwsA(isA<FeedbackDiagnosticsNotAccepted>()));
  });
  test('oversized report never reaches transport', () async {
    await expectLater(
        submit(Uint8List(2 * 1024 * 1024 + 1)), throwsArgumentError);
  });
}
