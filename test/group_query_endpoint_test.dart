import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_query_endpoint.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';

void main() {
  test('all lottery feature routes switch through one client base', () async {
    for (final base in ['http://47.242.90.129', 'https://test.example']) {
      final client = GroupQueryEndpoint.createClient(base: base);
      client.interceptors.insert(0,
          InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.uri.origin, base);
        expect(options.uri.path, isNot(contains('/sangong')));
        handler.resolve(Response(requestOptions: options, data: {}));
      }));
      for (final path in [
        '/me/robot/groups/a%23b',
        '/me/agent/player',
        '/me/agent/descendants',
        '/me/agent/first-level-agents',
        '/me/agent/descendants/user',
        '/me/agent/descendants/history',
        '/me/agent/rebate/current',
        '/me/agent/rebate/apply',
        '/me/agent/rebate/history',
        '/me/agent/rebate/personal-history',
        '/me/agent/rebate/history/export/task/download',
        '/api/admin/robot-desk/number-mappings',
      ]) {
        await client.get(path);
      }
      client.close();
    }
  });
  test('default queries use main service without a direct endpoint', () {
    expect(GroupQueryEndpoint.baseUrl, isEmpty);
    expect(GroupQueryEndpoint.resolve('/me/agent/descendants'),
        '/me/agent/descendants');
    expect(GroupQueryEndpoint.resolve('/api/v1/me/users/a%23b/parent'),
        '/api/v1/me/users/a%23b/parent');
    final client = GroupQueryEndpoint.createClient();
    final lottery = LotteryLiveApi();
    final main = Uri.parse(ApiClient.resolveBaseUrl());
    expect(client.options.baseUrl, ApiClient.resolveBaseUrl());
    expect(lottery.dio.options.baseUrl, ApiClient.resolveBaseUrl());
    final socket = lottery.socketUri('BDEP-T685-JSWQ', 40);
    expect(socket.host, main.host);
    expect(socket.port, main.port);
    expect(socket.scheme, main.scheme == 'https' ? 'wss' : 'ws');
    expect(socket.queryParameters['machineCode'], 'BDEP-T685-JSWQ');
    client.close();
    lottery.dio.close();
  });
  test('production fallback and explicit override preserve paths', () {
    expect(GroupQueryEndpoint.resolve('/me/agent/descendants', base: ''),
        '/me/agent/descendants');
    expect(
        GroupQueryEndpoint.resolve('/api/v1/lotteries/demo/overview',
            base: 'http://47.242.90.129/'),
        'http://47.242.90.129/api/v1/lotteries/demo/overview');
  });
}
