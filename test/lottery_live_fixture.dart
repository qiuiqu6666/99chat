import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'lottery_number_mappings_test.dart' show fixture;

Map<String, dynamic> liveFixture(String path, {int window = 40}) => {
      'code': 'OK',
      'groupUid': 'resolved-player-group',
      'serverTime': 1790005751631,
      'data': path.endsWith('/config')
          ? {
              ...fixture('game1')['data'] as Map,
              'lotteryId': 'mark-six-demo',
              'ruleVersion': 'rules-1',
              'timezone': 'Asia/Shanghai',
              'windowOptions': [6, 12, 20, 30, 40],
              'defaultWindow': 40,
            }
          : path.endsWith('/draws')
              ? {
                  'items': [
                    {
                      'issue': '20260921004',
                      'issueLabel': '004',
                      'sequence': 5,
                      'status': 'closed',
                      'drawAt': null,
                      'attributes': null
                    },
                    {
                      'issue': '20260921003',
                      'issueLabel': '003',
                      'sequence': 4,
                      'status': 'drawn',
                      'drawAt': 1790005751631,
                      'attributes': {
                        'special': '03',
                        'zodiac': '兔',
                        'parity': '单',
                        'size': '小',
                        'head': '0',
                        'tail': '3',
                        'sumParity': '单',
                        'fiveElement': '金',
                        'wave': '蓝'
                      }
                    },
                  ]
                }
              : {
                  'window': window,
                  'mode': 'published',
                  'items': [
                    {
                      'issue': '20260921004',
                      'issueLabel': '004',
                      'predictionState': 'insufficient_sample',
                      'drawState': 'pending',
                      'actual': null,
                      'items': [
                        {
                          'attribute': 'special',
                          'values': <String>[],
                          'result': 'insufficient_sample'
                        }
                      ]
                    },
                  ]
                },
    };

class FakeLotteryApi extends LotteryLiveApi {
  FakeLotteryApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://example.test')));
  final sockets = <FakeLotterySocket>[];
  @override
  WebSocketChannel connect(String machine, int window) {
    final socket = FakeLotterySocket();
    sockets.add(socket);
    return socket;
  }
}

class FakeLotterySocket implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  late final _sink = FakeLotterySink(() {
    if (!incoming.isClosed) incoming.close();
  });
  void send(String event, Map<String, dynamic> envelope) =>
      incoming.add(jsonEncode({...envelope, 'eventType': event}));
  @override
  Future<void> get ready async {}
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLotterySink implements WebSocketSink {
  FakeLotterySink(this.onClose);
  final void Function() onClose;
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
