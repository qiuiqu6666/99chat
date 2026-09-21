import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/call_record_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_bubble_insert_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_enrichment_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_repository.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';

Map<String, dynamic> _recent(String id,
        {String? status, String media = 'audio'}) =>
    {
      'callId': id,
      'callerUserId': 'call-owner',
      'calleeUserId': 'peer',
      'peerUserId': 'peer',
      'direction': 'outgoing',
      'mediaType': media,
      'result': 'missed',
      if (status != null) 'status': status,
      'occurredAt': 1789600000000,
    };

void _ringing(String id) {
  CallResultRepository.instance.save(CallResultRecord.fromSignaling(
    callId: id,
    action: 'invite',
    callerUserId: 'call-owner',
    calleeUserId: 'peer',
    peerUserId: 'peer',
    conversationId: 'c2c_peer',
    isOutgoing: true,
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = CallResultRepository.instance;
  final pending = <(RequestOptions, RequestInterceptorHandler)>[];
  final paths = <String>[];
  late List<Interceptor> originalInterceptors;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.saveToken('test-token', userId: 'call-owner');
  });
  setUp(() async {
    await repository.clearForOwner('call-owner');
    paths.clear();
    pending.clear();
    final dio = ApiClient.instance.dio;
    originalInterceptors = dio.interceptors.toList();
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        paths.add(options.path);
        if (options.path == '/calls/recent') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'items': [_recent('recent-active')]
            },
          ));
        } else if (options.path.startsWith('/calls/livekit/status/')) {
          pending.add((options, handler));
        } else {
          handler.reject(
              DioError(requestOptions: options, error: 'unexpected API'));
        }
      }));
  });
  tearDown(() async {
    for (final (options, handler) in pending) {
      handler.reject(DioError(requestOptions: options, error: 'test end'));
    }
    pending.clear();
    await Future<void>.delayed(Duration.zero);
    ApiClient.instance.dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
  });

  Future<void> waitForStatusRequest() async {
    for (var i = 0; i < 100 && pending.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(pending, hasLength(1));
  }

  Future<void> respond(String id, String status) async {
    final (options, handler) = pending.removeAt(0);
    handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
      'callId': id,
      'status': status,
      'callerUserId': 'call-owner',
      'mediaType': 'audio',
    }));
    final expected = CallSessionStatusCodec.parse(status);
    for (var i = 0; i < 100; i++) {
      final record = repository.get(id);
      if (record?.effectiveStatus == expected &&
          record?.source == CallResultSource.server) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail('Status response was not applied');
  }

  for (final media in ['audio', 'video']) {
    test('$media ringing snapshot never renders a premature missed bubble', () {
      final record = CallRecordItem.fromJson(
        _recent('ringing-$media', status: 'RINGING', media: media),
      ).toCallResultRecord()!;
      expect(record.effectiveStatus, CallSessionStatus.ringing);
      expect(record.protocolType, CallProtocolType.send);
      expect(record.endedAtMs, 0);
      repository.save(record);
      final message =
          CallBubbleInsertService.buildTerminalBubbleMessage(record)!;
      final provider = CallingMessageDataProvider(message);
      expect(provider.protocolType, CallProtocolType.send);
      expect(provider.shouldDisplayInHistory, isFalse);
      expect(provider.content, 'Waiting for answer');
    });
  }

  test('answered live status overrides the unfinished result field', () {
    final record = CallRecordItem.fromJson(
      _recent('answered', status: 'ANSWERED'),
    ).toCallResultRecord()!;
    expect(record.protocolType, CallProtocolType.accept);
    expect(record.effectiveStatus, CallSessionStatus.answered);
    expect(record.endedAtMs, 0);
  });

  test('legacy completed missed record remains a terminal result', () {
    final record =
        CallRecordItem.fromJson(_recent('old-call')).toCallResultRecord()!;
    expect(record.protocolType, CallProtocolType.timeout);
    expect(record.effectiveStatus, CallSessionStatus.missed);
    expect(record.endedAtMs, greaterThan(0));
  });

  test('recent missed result is withheld until session actually times out',
      () async {
    const id = 'active';
    _ringing(id);
    final item = CallRecordItem.fromJson(_recent(id));
    CallResultEnrichmentService.instance.ingestServerItem(item);
    await waitForStatusRequest();
    expect(repository.get(id)!.protocolType, CallProtocolType.send);
    await respond(id, 'RINGING');
    expect(repository.get(id)!.protocolType, CallProtocolType.send);
    CallResultEnrichmentService.instance.ingestServerItem(item);
    await waitForStatusRequest();
    await respond(id, 'MISSED');
    expect(repository.get(id)!.protocolType, CallProtocolType.timeout);
  });

  test('server ringing cache is refreshed through status, not final result API',
      () async {
    const id = 'refresh-active';
    repository.save(CallRecordItem.fromJson(
      _recent(id, status: 'RINGING'),
    ).toCallResultRecord()!);
    final result = CallResultEnrichmentService.instance.ensureServerResult(id);
    await waitForStatusRequest();
    await respond(id, 'ANSWERED');
    expect((await result)!.protocolType, CallProtocolType.accept);
    expect(paths, ['/calls/livekit/status/$id']);
  });

  test('recent list refresh uses the same ongoing-call validation', () async {
    _ringing('recent-active');
    await CallRecordApi.instance.fetchRecent();
    await waitForStatusRequest();
    expect(
        repository.get('recent-active')!.protocolType, CallProtocolType.send);
    await respond('recent-active', 'RINGING');
    expect(
        repository.get('recent-active')!.protocolType, CallProtocolType.send);
  });
}
