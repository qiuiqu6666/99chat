import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';

class AuthRepository {
  AuthRepository({AuthApi? api}) : _api = api ?? AuthApi.instance;

  final AuthApi _api;

  Future<UserSigResult> fetchImCredential() async {
    try {
      return await _api.fetchUserSig();
    } on DioError catch (error) {
      if (DioErrorMessage.isAuthFailure(error)) {
        throw const SessionAuthExpiredException();
      }
      rethrow;
    }
  }

  Future<MeResult> fetchMe() async {
    try {
      return await _api.fetchMe();
    } on DioError catch (error) {
      if (DioErrorMessage.isAuthFailure(error)) {
        throw const SessionAuthExpiredException();
      }
      rethrow;
    }
  }
}

class SessionAuthExpiredException implements Exception {
  const SessionAuthExpiredException();
}
