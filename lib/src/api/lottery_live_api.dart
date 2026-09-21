import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'api_client.dart';
import 'group_query_endpoint.dart';
import 'lottery_number_mappings.dart';
import 'lottery_statistics.dart';

// Debug-only, bounded diagnostics: never dump headers or whole response bodies.
void _lotteryHttpLog(String event,
    {Uri? uri, Response? response, Object? error}) {
  if (!kDebugMode) return;
  final body = response?.data;
  String safe(Object? value) => '$value'
      .replaceAll(
          RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer [redacted]')
      .replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
          '[JWT redacted]')
      .replaceAll(RegExp(r'[\r\n]'), ' ');
  final summary = body is Map
      ? 'code=${safe(body['code'])} message=${safe(body['message'] ?? body['msg'])}'
      : 'bodyType=${body.runtimeType}';
  final address =
      uri == null ? '' : '${uri.scheme}://${uri.authority}${uri.path}';
  final failure = error is DioError
      ? ' type=${error.type}'
      : error == null
          ? ''
          : ' type=${error.runtimeType} reason=${safe(error)}';
  final line =
      '[LotteryHTTP] $event GET $address status=${response?.statusCode} $summary$failure';
  debugPrint(line.length > 1200 ? '${line.substring(0, 1200)}…' : line);
}

/// Public lottery API. Deliberately does not use the authenticated group client.
class LotteryLiveApi {
  LotteryLiveApi({Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
              baseUrl: GroupQueryEndpoint.baseUrl.isEmpty
                  ? ApiClient.resolveBaseUrl()
                  : GroupQueryEndpoint.baseUrl,
              connectTimeout: 10000,
              receiveTimeout: 10000,
            ));
  final Dio dio;
  static const path = '/api/v1/lotteries/mark-six-demo';
  Future<Map<String, dynamic>> get(String resource, String machine,
      {int window = 40, Map<String, dynamic> query = const {}}) async {
    if (machine.trim().isEmpty) throw ArgumentError('机器码不能为空');
    final uri = Uri.parse(dio.options.baseUrl).resolve('$path/$resource');
    _lotteryHttpLog('request_start', uri: uri);
    Response? response;
    try {
      response = await dio.get('$path/$resource', queryParameters: {
        'machineCode': machine,
        if (resource == 'draws' || resource == 'predictions') 'limit': 100,
        if (resource == 'predictions') 'window': window,
        ...query,
      });
      _lotteryHttpLog('response', uri: response.realUri, response: response);
      final envelope = Map<String, dynamic>.from(response.data as Map);
      if (envelope['code'] != 'OK') throw const FormatException('开奖接口返回失败');
      validateEnvelope(envelope);
      return envelope;
    } catch (error) {
      _lotteryHttpLog('request_failed',
          uri: error is DioError ? error.requestOptions.uri : uri,
          response: error is DioError ? error.response : response,
          error: error);
      rethrow;
    }
  }

  static void validateEnvelope(Map<String, dynamic> message) {
    if (message['groupUid'] is! String ||
        (message['groupUid'] as String).isEmpty ||
        message['serverTime'] is! int) {
      throw const FormatException('开奖接口上下文或时间格式错误');
    }
  }

  Uri socketUri(String machine, int window) {
    final base = Uri.parse(dio.options.baseUrl);
    return base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '$path/ws',
        queryParameters: {
          'machineCode': machine,
          'window': '$window',
          'limit': '100',
        },
        fragment: '');
  }

  WebSocketChannel connect(String machine, int window) =>
      WebSocketChannel.connect(socketUri(machine, window));
}

LotteryLiveApi lotteryLiveApi = LotteryLiveApi();
final _sessions = <Object, LotteryLiveSession>{};
LotteryLiveSession lotteryLiveSession(String machine) {
  final key = (
    lotteryLiveApi,
    lotteryLiveApi.dio.options.baseUrl,
    ApiClient.instance.authenticatedUserId,
    ApiClient.instance.token,
    machine
  );
  if (_sessions.length > 16) {
    _sessions.removeWhere((_, value) => !value.active);
  }
  return _sessions.putIfAbsent(
      key, () => LotteryLiveSession(lotteryLiveApi, machine));
}

/// Shared between preview and full screen; stops network work with no viewers.
class LotteryLiveSession extends ChangeNotifier with WidgetsBindingObserver {
  LotteryLiveSession(this.api, this.machine);
  final LotteryLiveApi api;
  final String machine;
  Map<String, dynamic>? config;
  LotteryNumberMappings? mappings;
  List<Map<String, dynamic>> draws = [];
  List<Map<String, dynamic>> predictions = [];
  final statistics = <String, LotteryStatistics>{};
  String? statisticsError;
  String? _statisticsAttribute;
  int _statisticsGeneration = 0;
  bool statisticsLoading = false;

  Future<void> loadStatistics(String attribute, {bool force = false}) async {
    _statisticsAttribute = attribute;
    if (!active ||
        groupUid == null ||
        (!force && statistics.containsKey(attribute))) {
      return;
    }
    final generation = ++_statisticsGeneration;
    final epoch = _epoch;
    final requestedWindow = window;
    statisticsLoading = true;
    statisticsError = null;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final overview = await api.get('overview', machine);
          if (overview['groupUid'] != groupUid) {
            throw const FormatException('统计实例不匹配');
          }
          final snapshot = overview['data']['snapshotId'];
          if (snapshot is! String || snapshot.isEmpty) {
            throw const FormatException('统计快照缺失');
          }
          final response = await api.get('statistics', machine, query: {
            'window': requestedWindow,
            'attribute': attribute,
            'snapshotId': snapshot,
          });
          if (response['groupUid'] != groupUid) {
            throw const FormatException('统计实例不匹配');
          }
          final parsed = LotteryStatistics.parse(
              response['data'], attribute, requestedWindow);
          if (parsed.snapshotId != snapshot) {
            throw const FormatException('统计快照不匹配');
          }
          if (epoch != _epoch ||
              generation != _statisticsGeneration ||
              !active) {
            return;
          }
          statistics[attribute] = parsed;
          return;
        } on DioError catch (e) {
          if (attempt == 0 &&
              e.response?.statusCode == 409 &&
              e.response?.data is Map &&
              e.response?.data['code'] == 'SNAPSHOT_EXPIRED') {
            continue;
          }
          rethrow;
        }
      }
    } catch (_) {
      if (epoch == _epoch && generation == _statisticsGeneration && active) {
        statisticsError = '统计加载失败，请重试';
      }
    } finally {
      if (epoch == _epoch && generation == _statisticsGeneration && active) {
        statisticsLoading = false;
        notifyListeners();
      }
    }
  }

  String predictionMode = 'published';
  String? groupUid;
  String? error;
  bool loading = false;
  bool connected = false;
  int window = 40;
  int _users = 0;
  int _epoch = 0;
  int _serverTime = 0;
  final _clock = Stopwatch();
  final _heartbeat = Stopwatch();
  Timer? _fallback;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool get active => _users > 0;
  bool get ready => config != null;
  static bool _zonesReady = false;
  DateTime timeAt(int timestamp) {
    if (!_zonesReady) {
      tzdata.initializeTimeZones();
      _zonesReady = true;
    }
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.getLocation(config!['timezone'] as String), timestamp);
  }

  DateTime now() => timeAt(_serverTime + _clock.elapsedMilliseconds);
  String formatTime(int timestamp) {
    final t = timeAt(timestamp);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  void attach() {
    if (++_users != 1) return;
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  void detach() {
    if (--_users > 0) return;
    _users = 0;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
  }

  void _stop() {
    _statisticsGeneration++;
    statisticsLoading = false;
    _epoch++;
    loading = false;
    connected = false;
    _fallback?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && active) {
      refresh();
    } else if (state != AppLifecycleState.resumed) {
      _stop();
    }
  }

  void selectWindow(int value) {
    if (window == value) return;
    window = value;
    predictions = [];
    statistics.clear();
    statisticsError = null;
    _stop();
    refresh();
  }

  static List<Map<String, dynamic>> items(dynamic data) {
    if (data is! Map || data['items'] is! List) {
      throw const FormatException('开奖列表格式错误');
    }
    return (data['items'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  LotteryNumberMappings _parseConfig(Map<String, dynamic> data) {
    if (data['lotteryId'] != 'mark-six-demo' || data['timezone'] is! String) {
      throw const FormatException('彩种配置错误');
    }
    if (!_zonesReady) {
      tzdata.initializeTimeZones();
      _zonesReady = true;
    }
    tz.getLocation(data['timezone'] as String);
    return LotteryNumberMappings.parse({
      'code': 0,
      'data': {
        ...data,
        'machineCode': machine,
        'databaseGeneration': data['ruleVersion'],
      }
    }, machine);
  }

  List<Map<String, dynamic>> _parseDraws(dynamic data) {
    final result = items(data);
    for (final row in result) {
      if (row['issue'] is! String ||
          row['sequence'] is! int ||
          !['open', 'closed', 'drawn'].contains(row['status'])) {
        throw const FormatException('开奖期次格式错误');
      }
      for (final key in [
        'openAt',
        'closeAt',
        'closedAt',
        'drawAt',
        'updatedAt'
      ]) {
        if (row[key] != null && row[key] is! int) {
          throw const FormatException('时间须为毫秒时间戳');
        }
      }
      if (row['status'] == 'drawn') {
        final a = row['attributes'];
        if (row['drawAt'] is! int ||
            a is! Map ||
            !RegExp(r'^(0[1-9]|[1-4][0-9])$').hasMatch('${a['special']}') ||
            !['红', '蓝', '绿'].contains(a['wave']) ||
            [
              'zodiac',
              'parity',
              'size',
              'head',
              'tail',
              'sumParity',
              'fiveElement'
            ].any((key) => a[key] is! String)) {
          throw const FormatException('已开奖属性不完整');
        }
      }
    }
    result
        .sort((a, b) => (b['sequence'] as int).compareTo(a['sequence'] as int));
    final seen = <String>{};
    return result
        .where((row) => seen.add(row['issue'] as String))
        .take(100)
        .toList();
  }

  void _syncClock(Map<String, dynamic> envelope) {
    _serverTime = envelope['serverTime'] as int;
    _clock
      ..reset()
      ..start();
  }

  List<Map<String, dynamic>> _parsePredictions(dynamic data) {
    final rows = items(data);
    for (final row in rows) {
      if (row['issue'] is! String ||
          row['items'] is! List ||
          (row['actual'] != null && row['actual'] is! Map)) {
        throw const FormatException('预测结构错误');
      }
      for (final key in ['generatedAt', 'publishedAt']) {
        if (row[key] != null && row[key] is! int) {
          throw const FormatException('预测时间须为毫秒时间戳');
        }
      }
      for (final item in row['items'] as List) {
        if (item is! Map ||
            item['attribute'] is! String ||
            item['values'] is! List ||
            (item['values'] as List).any((v) => v is! String)) {
          throw const FormatException('预测候选格式错误');
        }
      }
    }
    return rows.take(100).toList();
  }

  bool get statisticsComplete {
    final sample =
        draws.where((r) => r['status'] == 'drawn').take(window).toList();
    for (var i = 1; i < sample.length; i++) {
      if ((sample[i - 1]['sequence'] as int) - (sample[i]['sequence'] as int) !=
          1) {
        return false;
      }
    }
    return true;
  }

  Future<void> refresh() async {
    if (!active || loading) return;
    loading = true;
    final epoch = ++_epoch;
    // HTTP and socket must never race to overwrite each other.
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    connected = false;
    notifyListeners();
    try {
      final responses = await Future.wait([
        api.get('config', machine),
        api.get('draws', machine),
        api.get('predictions', machine, window: window),
      ]);
      if (epoch != _epoch || !active) return;
      final group = responses.first['groupUid'] as String;
      if (responses.any((r) => r['groupUid'] != group)) {
        throw const FormatException('接口返回的实例不一致');
      }
      final newConfig = Map<String, dynamic>.from(responses[0]['data'] as Map);
      final newMappings = _parseConfig(newConfig);
      final newDraws = _parseDraws(responses[1]['data']);
      final predictionData = responses[2]['data'] as Map;
      if (predictionData['window'] != window) {
        throw const FormatException('预测窗口不一致');
      }
      final newPredictions = _parsePredictions(predictionData);
      config = newConfig;
      mappings = newMappings;
      draws = newDraws;
      predictions = newPredictions;
      predictionMode = '${predictionData['mode']}';
      groupUid = group;
      error = null;
      _syncClock(responses.last);
      _connect(epoch);
      if (_statisticsAttribute != null) {
        unawaited(loadStatistics(_statisticsAttribute!, force: true));
      }
    } catch (e) {
      if (epoch != _epoch || !active) return;
      error = '开奖数据加载失败，请重试';
      if (e is DioError && [401, 403, 404].contains(e.response?.statusCode)) {
        config = null;
        mappings = null;
        draws = [];
        predictions = [];
        statistics.clear();
        groupUid = null;
      }
    } finally {
      if (epoch == _epoch && active) {
        loading = false;
        _fallback?.cancel();
        _fallback = Timer.periodic(const Duration(seconds: 15), (_) {
          if (!connected || _heartbeat.elapsed > const Duration(seconds: 45)) {
            refresh();
          }
        });
        notifyListeners();
      }
    }
  }

  void _connect(int epoch) {
    try {
      final channel = api.connect(machine, window);
      _channel = channel;
      channel.ready.then((_) {
        if (epoch != _epoch || !active) return;
        connected = true;
        _heartbeat
          ..reset()
          ..start();
        notifyListeners();
      }, onError: (Object e) => _disconnected(epoch));
      _subscription = channel.stream.listen((raw) {
        if (epoch != _epoch || !active) return;
        try {
          final message =
              Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
          LotteryLiveApi.validateEnvelope(message);
          if (message['groupUid'] != groupUid) {
            throw const FormatException('推送实例不匹配');
          }
          _heartbeat
            ..reset()
            ..start();
          _syncClock(message);
          switch (message['eventType']) {
            case 'config':
              final data = Map<String, dynamic>.from(message['data'] as Map);
              final parsed = _parseConfig(data);
              config = data;
              mappings = parsed;
            case 'draws':
              draws = _parseDraws(message['data']);
            case 'predictions':
              final data = message['data'] as Map;
              if (data['window'] != window) return;
              predictions = _parsePredictions(data);
              predictionMode = '${data['mode']}';
            case 'statistics':
              final data = message['data'] as Map;
              if (data['window'] != window) return;
              final all = data['attributes'] as Map;
              final next = <String, LotteryStatistics>{};
              for (final key in LotteryStatistics.candidateCounts.keys) {
                final parsed = LotteryStatistics.parse(all[key], key, window);
                if (parsed.snapshotId != data['snapshotId']) {
                  throw const FormatException('统计快照不匹配');
                }
                next[key] = parsed;
              }
              _statisticsGeneration++;
              statisticsLoading = false;
              statisticsError = null;
              statistics
                ..clear()
                ..addAll(next);
            case 'heartbeat':
              return;
            default:
              return;
          }
          error = null;
          notifyListeners();
        } catch (_) {
          _disconnected(epoch);
        }
      },
          onError: (Object e) => _disconnected(epoch),
          onDone: () => _disconnected(epoch));
    } catch (_) {
      _disconnected(epoch);
    }
  }

  void _disconnected(int epoch) {
    if (epoch != _epoch || !active) return;
    connected = false;
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    error = '实时连接中断，正在自动重连';
    notifyListeners();
  }
}
