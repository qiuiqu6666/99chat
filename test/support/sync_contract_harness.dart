import 'dart:async';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_api.dart';

class SyncHarness {
  SyncHarness() {
    api = SyncApi.withDio(dio, deviceId: 'device-a');
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests.add(request);
      try {
        final body = await respond(request);
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'code': 0, 'message': 'ok', 'data': body}));
      } on DioError catch (error) {
        handler.reject(error);
      } catch (error) {
        handler.reject(DioError(requestOptions: request, error: error));
      }
    }));
  }
  final Dio dio = Dio();
  late final SyncApi api;
  final List<RequestOptions> requests = [];
  late FutureOr<Object> Function(RequestOptions) respond;
  List<RequestOptions> at(String suffix) =>
      requests.where((request) => request.path.endsWith(suffix)).toList();
}

DioError contractError(RequestOptions request, String code,
        {int status = 409}) =>
    DioError(
        requestOptions: request,
        type: DioErrorType.response,
        response: Response(requestOptions: request, statusCode: status, data: {
          'code': code,
          'message': code,
          if (status == 409) 'ok': false
        }));

DioError lostResponse(RequestOptions request) =>
    DioError(requestOptions: request, type: DioErrorType.receiveTimeout);
