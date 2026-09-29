import 'package:dio/dio.dart';
import 'agent_rebate_http.dart';
import 'group_query_endpoint.dart';
import 'api_client.dart';

final lotteryNumberMappingsCache = LotteryNumberMappingsCache(
  scope: () => (
    GroupQueryEndpoint.client.options.baseUrl,
    ApiClient.instance.authenticatedUserId,
    ApiClient.instance.token
  ),
);

/// Session-only cache: separate machines, bounded size, coalesced requests.
class LotteryNumberMappingsCache {
  LotteryNumberMappingsCache({
    this.loader = fetchLotteryNumberMappings,
    this.scope,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final Future<LotteryNumberMappings> Function(String) loader;
  final Object Function()? scope;
  final DateTime Function() _now;
  Object? _scope;
  int _generation = 0;
  final _values = <String, (LotteryNumberMappings, DateTime)>{};
  final _pending = <String, Future<LotteryNumberMappings>>{};

  void _checkScope() {
    final current = scope?.call();
    if (current == _scope) return;
    clear();
    _scope = current;
  }

  void clear() {
    _generation++;
    _values.clear();
    _pending.clear();
  }

  LotteryNumberMappings? peek(String machineCode) {
    _checkScope();
    return _values[machineCode]?.$1;
  }

  Future<LotteryNumberMappings> refresh(String machineCode,
      {bool force = false}) {
    _checkScope();
    final pending = _pending[machineCode];
    if (pending != null) return pending;
    final cached = _values[machineCode];
    if (!force &&
        cached != null &&
        _now().difference(cached.$2) < const Duration(seconds: 30)) {
      return Future.value(cached.$1);
    }
    final generation = _generation;
    late final Future<LotteryNumberMappings> request;
    request = Future.sync(() => loader(machineCode)).then((value) {
      _checkScope();
      if (generation == _generation) {
        _values.remove(machineCode);
        _values[machineCode] = (value, _now());
        if (_values.length > 32) _values.remove(_values.keys.first);
      }
      return value;
    }).whenComplete(() {
      if (identical(_pending[machineCode], request)) {
        _pending.remove(machineCode);
      }
    });
    _pending[machineCode] = request;
    return request;
  }
}

class LotteryNumberMappings {
  LotteryNumberMappings._(this.machineCode, this.databaseGeneration,
      this.zodiacs, this.colors, this.elements);
  final String machineCode;
  final String databaseGeneration;
  final Map<int, String> zodiacs;
  final Map<int, String> colors;
  final Map<int, String> elements;

  static Map<int, String> _read(dynamic raw, Set<String> labels) {
    if (raw is! Map) throw const FormatException('号码配置缺失');
    final result = <int, String>{};
    for (final entry in raw.entries) {
      final label = entry.key == '绿色' ? '绿' : entry.key.toString();
      if (!labels.contains(label) || entry.value is! List) {
        throw const FormatException('号码配置分类错误');
      }
      for (final value in entry.value as List) {
        if (value is! int ||
            value < 1 ||
            value > 49 ||
            result.containsKey(value)) {
          throw const FormatException('号码配置包含重复或无效号码');
        }
        result[value] = label;
      }
    }
    if (result.length != 49 || !result.values.toSet().containsAll(labels)) {
      throw const FormatException('号码配置不完整');
    }
    return Map.unmodifiable(result);
  }

  factory LotteryNumberMappings.parse(dynamic raw, String expectedMachineCode) {
    if (raw is! Map) throw const FormatException('号码配置响应格式错误');
    final code = raw['code'] ?? raw['代码'];
    if (code != 0 && code != '0') throw const FormatException('号码配置请求失败');
    final data = raw['data'] ?? raw['数据'];
    if (data is! Map || data['machineCode'] != expectedMachineCode) {
      throw const FormatException('号码配置机器码不匹配');
    }
    final generation = data['databaseGeneration'];
    if (generation is! String || generation.isEmpty) {
      throw const FormatException('号码配置版本缺失');
    }
    return LotteryNumberMappings._(
      expectedMachineCode,
      generation,
      _read(data['zodiacNumbers'],
          {'鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'}),
      _read(data['colorNumbers'], {'红', '蓝', '绿'}),
      _read(
          data['fiveElementNumbers'] ??
              data['fiveElementsNumbers'] ??
              data['五个元素编号s'],
          {'金', '木', '水', '火', '土'}),
    );
  }
}

Future<LotteryNumberMappings> fetchLotteryNumberMappings(String machineCode,
    {Dio? dio}) async {
  final response = await (dio ?? GroupQueryEndpoint.client).get(
    '/api/admin/robot-desk/number-mappings',
    queryParameters: {'machineCode': machineCode},
    options: AgentRebateHttp.options(skipGroup: true),
  );
  return LotteryNumberMappings.parse(response.data, machineCode);
}
