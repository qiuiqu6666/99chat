import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/wallet_api.dart';

class _LedgerAdapter implements HttpClientAdapter {
  _LedgerAdapter(this.requests);

  final List<RequestOptions> requests;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<dynamic>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'message': 'ok',
        'data': {
          'content': [
            for (final id in ['101', '102'])
              {
                'id': id,
                'ledgerType': 'GROUP_CREATE',
                'source': 'PLATFORM',
                'refType': 'COMMUNITY_CREATE',
                'refId': '',
                'currency': '99',
                'amount': -100,
                'direction': 'OUT',
                'status': 'SUCCESS',
                'remark': 'Community creation: @TGS#_P$id',
                'createdAt': '2026-09-25T04:00:00Z',
              },
          ],
          'page': 0,
          'size': 100,
          'totalElements': 2,
          'totalPages': 1,
        },
      }),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('history includes GROUP_CREATE debits from the unfiltered ledger',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dio = ApiClient.instance.dio;
    final previousAdapter = dio.httpClientAdapter;
    final requests = <RequestOptions>[];
    dio.httpClientAdapter = _LedgerAdapter(requests);
    try {
      final records = await WalletApi.instance.getHistoryRecords();

      expect(records.map((record) => record.id), containsAll(['101', '102']));
      expect(
        records.every((record) =>
            record.title == '超级大群创建费' ||
            record.title == 'Super group creation fee'),
        isTrue,
      );
      expect(records.every((record) => !record.income), isTrue);
      expect(records.every((record) => record.amount == '1.00'), isTrue);
      expect(requests, hasLength(1));
      expect(requests.single.path, '/wallet/ledger');
      expect(requests.single.queryParameters.containsKey('ledgerType'), isFalse);
    } finally {
      dio.httpClientAdapter = previousAdapter;
    }
  });
}
