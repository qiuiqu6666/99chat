import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

/// A request/page belongs to the account session that created it, including
/// when the same account logs out and back in with the same token.
class AgentSessionSnapshot {
  AgentSessionSnapshot()
      : _session = SessionIdentityService.instance.generation,
        _credentials = ApiClient.instance.credentialGeneration;

  final int _session;
  final int _credentials;

  bool get isCurrent =>
      !ApiClient.instance.isLogoutInProgress &&
      SessionIdentityService.instance.isGenerationCurrent(_session) &&
      ApiClient.instance.credentialGeneration == _credentials;

  static bool get canRequest =>
      !ApiClient.instance.isLogoutInProgress &&
      ApiClient.isValidJwt(ApiClient.instance.token);
}

/// Reject stale results before downstream interceptors can mutate account
/// state (for example clearing a tenant after an old tenant-not-found error).
class AgentSessionInterceptor extends Interceptor {
  AgentSessionInterceptor({this.allRequests = false});

  final bool allRequests;
  static const _snapshotKey = 'agentAccountSession';

  bool _handles(RequestOptions options) {
    if (allRequests) return true;
    final path = options.uri.path;
    return path.startsWith('/me/agent/') ||
        path.startsWith('/me/rebate/') ||
        path.startsWith('/me/robot/groups');
  }

  static DioError _cancel(RequestOptions options) => DioError(
        requestOptions: options,
        type: DioErrorType.cancel,
        error: '账号会话已变化，请重新进入群聊',
      );

  static bool _isStale(RequestOptions options) {
    final snapshot = options.extra[_snapshotKey];
    return snapshot is AgentSessionSnapshot && !snapshot.isCurrent;
  }

  /// Recheck at the credential injection boundary too: Dio runs request
  /// interceptors asynchronously, so an account switch can occur between them.
  static bool rejectStaleRequest(
      RequestOptions options, RequestInterceptorHandler handler) {
    if (!_isStale(options)) return false;
    handler.reject(_cancel(options));
    return true;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_handles(options)) {
      if (rejectStaleRequest(options, handler)) return;
      if (!AgentSessionSnapshot.canRequest) {
        handler.reject(_cancel(options));
        return;
      }
      options.extra[_snapshotKey] = AgentSessionSnapshot();
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_isStale(response.requestOptions)) {
      handler.reject(_cancel(response.requestOptions));
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioError err, ErrorInterceptorHandler handler) {
    if (_isStale(err.requestOptions)) {
      handler.reject(_cancel(err.requestOptions));
      return;
    }
    handler.next(err);
  }
}
