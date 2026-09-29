import 'package:dio/dio.dart';

class AuthFailurePolicy {
  static const versionPaths = {
    '/auth/register',
    '/auth/login/sms',
    '/auth/login/password',
    '/auth/login/password/verify',
    '/auth/password/reset',
  };
  static bool requiresVersion(String path) =>
      versionPaths.contains(Uri.tryParse(path)?.path);

  static String? passwordLockMessage(Response? response) {
    final data = response?.data;
    if (response?.statusCode != 429 ||
        response?.requestOptions.method != 'POST' ||
        Uri.tryParse(response!.requestOptions.path)?.path !=
            '/auth/login/password' ||
        data is! Map ||
        data['code'] != 'LOGIN_RATE_LIMITED') {
      return null;
    }
    return data['message'] is String ? data['message'] as String : '尝试过多，请稍后再试';
  }

  static AuthVersionFailure? versionFailure(Response? response) {
    final data = response?.data;
    if (response?.statusCode != 403 ||
        response?.requestOptions.method != 'POST' ||
        !requiresVersion(response!.requestOptions.path) ||
        data is! Map ||
        !const {'CLIENT_VERSION_REQUIRED', 'CLIENT_VERSION_TOO_LOW'}
            .contains(data['code'])) {
      return null;
    }
    return AuthVersionFailure(
      message:
          data['message'] is String ? data['message'] as String : '请升级后再登录',
      downloadUrl:
          data['downloadUrl'] is String ? data['downloadUrl'] as String : '',
      changelog: data['changelog'] is String ? data['changelog'] as String : '',
    );
  }
}

class AuthVersionFailure {
  const AuthVersionFailure(
      {required this.message,
      required this.downloadUrl,
      required this.changelog});
  final String message, downloadUrl, changelog;
  Uri? get downloadUri {
    final uri = Uri.tryParse(downloadUrl.trim());
    return uri != null &&
            const {'https', 'http'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }
}
