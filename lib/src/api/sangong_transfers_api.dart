import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_transfer.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

class SangongTransfersApi {
  SangongTransfersApi({Dio? dio}) : _dio = dio;
  final Dio? _dio;

  Future<List<SangongTransfer>> fetch({
    String direction = 'all',
    int limit = 100,
    int? sessionId,
  }) async {
    if (!const ['all', 'out', 'in'].contains(direction)) {
      throw ArgumentError.value(direction, 'direction');
    }
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit');
    }
    if (sessionId != null && sessionId <= 0) {
      throw ArgumentError.value(sessionId, 'sessionId');
    }
    final response = await (_dio ?? SangongGameHttp.client).get(
      '/api/v1/me/transfers',
      queryParameters: {
        'direction': direction,
        'limit': limit,
        if (sessionId != null) 'sessionId': sessionId,
      },
    );
    final envelope = readApiWriteEnvelope(response.data);
    final payload = envelope.payload;
    if (envelope.isBusinessError ||
        (response.data is Map && response.data['ok'] == false) ||
        (payload is Map && payload['ok'] == false)) {
      throw DioError(
        requestOptions: response.requestOptions,
        response: response,
        type: DioErrorType.response,
      );
    }
    if (payload is! Map || payload['transfers'] is! List) {
      throw const FormatException('Invalid transfers response');
    }
    final records = (payload['transfers'] as List).map((item) {
      if (item is! Map) throw const FormatException('Invalid transfer');
      return SangongTransfer.fromJson(Map<String, dynamic>.from(item));
    }).toList();
    records.sort((a, b) => b.id.compareTo(a.id));
    return records;
  }
}
