import 'package:dio/dio.dart';
import 'api_client.dart';
import 'agent_session_guard.dart';

/// Shared endpoint for lottery, agent lookup, rebates and history/export.
/// All build modes use the main service unless explicitly configured.
class GroupQueryEndpoint {
  static Dio? _client;

  static Dio get client => _client ??= createClient();

  static Dio createClient({String base = baseUrl}) {
    final dio = Dio(BaseOptions(
      baseUrl: base.isEmpty ? ApiClient.resolveBaseUrl() : base,
      connectTimeout: 15000,
      receiveTimeout: 30000,
      contentType: 'application/json',
    ));
    dio.interceptors.add(AgentSessionInterceptor(allRequests: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (AgentSessionInterceptor.rejectStaleRequest(options, handler)) return;
      options.baseUrl = base.isEmpty ? ApiClient.resolveBaseUrl() : base;
      final token = ApiClient.instance.token;
      if (ApiClient.isValidJwt(token)) {
        options.headers['Authorization'] = 'Bearer $token';
      } else {
        options.headers.remove('Authorization');
      }
      handler.next(options);
    }));
    return dio;
  }

  static const String baseUrl = String.fromEnvironment(
    'GROUP_QUERY_BASE_URL',
    defaultValue: '',
  );

  static String resolve(String path, {String base = baseUrl}) {
    if (base.isEmpty) return path;
    return '${base.replaceAll(RegExp(r'/+$'), '')}/'
        '${path.replaceFirst(RegExp(r'^/+'), '')}';
  }
}
