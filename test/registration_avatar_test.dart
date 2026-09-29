import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/registration_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dio = ApiClient.instance.dio;
  late List<Interceptor> previous;
  var requests = 0;
  var validResponse = true;
  late RequestOptions sent;
  setUp(() {
    requests = 0;
    validResponse = true;
    previous = dio.interceptors.toList();
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requests++;
      sent = o;
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {
        'code': 0,
        'data':
            validResponse ? {'avatarUrl': 'https://example.com/avatar.png'} : {}
      }));
    }));
  });
  tearDown(() {
    dio.interceptors.clear();
    dio.interceptors.addAll(previous);
  });
  test('uploads selected bytes only to the existing user avatar endpoint',
      () async {
    await uploadRegistrationAvatar(
        Uint8List.fromList([1, 2, 3]), 'selected.png');
    expect(sent.path, '/me/avatar');
    expect(requests, 1);
    final file = (sent.data as FormData).files.single;
    expect(file.key, 'file');
    expect(file.value.contentType.toString(), 'image/png');
    expect(file.value.filename, 'avatar.png');
  });
  test('empty and oversized avatars are rejected before sending', () async {
    await expectLater(
        uploadRegistrationAvatar(Uint8List(0), 'a.jpg'), throwsArgumentError);
    await expectLater(
        uploadRegistrationAvatar(Uint8List(10 * 1024 * 1024 + 1), 'a.jpg'),
        throwsArgumentError);
    expect(requests, 0);
  });
  test('invalid upload response cannot be reported as a saved avatar',
      () async {
    validResponse = false;
    await expectLater(
        uploadRegistrationAvatar(Uint8List.fromList([1]), 'a.jpg'),
        throwsA(isA<DioError>()));
    expect(requests, 1);
  });
}
