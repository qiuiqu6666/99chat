// 一次性诊断工具：跨页面跟踪"点击会话 → 首帧可见"全链路时延。
// 仅用于性能诊断，不参与业务逻辑。默认关闭控制台输出。
import 'package:flutter/foundation.dart';

class ChatPipelineClock {
  static final ChatPipelineClock instance = ChatPipelineClock._();
  ChatPipelineClock._();

  static const bool enabled = false;

  final Map<String, Stopwatch> _clocks = <String, Stopwatch>{};

  /// 把任意形式的会话 ID 归一化成 Stopwatch 主键（c2c_xxx / group_xxx）。
  /// 优先 groupID / userID（来自 V2TimConversation），其次回退到 raw conversationID。
  /// 若 raw 已经带 c2c_/group_ 前缀则直接返回；否则按 ChatIdFormat 推断类型补前缀。
  static String normalizeKey({
    String? rawConversationId,
    String? userId,
    String? groupId,
  }) {
    final g = groupId?.trim() ?? '';
    if (g.isNotEmpty) {
      if (g.startsWith('group_')) return g;
      if (g.startsWith('@TGS#')) return g;
      return 'group_$g';
    }
    final u = userId?.trim() ?? '';
    if (u.isNotEmpty) {
      if (u.startsWith('c2c_')) return u;
      return 'c2c_$u';
    }
    final r = rawConversationId?.trim() ?? '';
    if (r.isEmpty) return '';
    if (r.startsWith('c2c_') || r.startsWith('group_')) return r;
    if (r.startsWith('@TGS#')) return r;
    return r;
  }

  /// 在 conv_item_tap 内调用，建立 t0 锚点。
  void start(String convId) {
    final sw = _clocks.putIfAbsent(convId, () => Stopwatch());
    sw
      ..reset()
      ..start();
  }

  /// 取从 start 起算的总偏移（毫秒）。未 start 返回 -1。
  /// 兼容 `group_xxx` / 裸 `xxx`、`c2c_xxx` / 裸 userId。
  int offsetMs(String convId) {
    final sw = _runningClock(convId);
    if (sw == null) return -1;
    return sw.elapsedMilliseconds;
  }

  /// 取从 start 起算的总偏移（微秒）。未 start 返回 -1。
  int offsetMicros(String convId) {
    final sw = _runningClock(convId);
    if (sw == null) return -1;
    return sw.elapsedMicroseconds;
  }

  /// 取得 sw 用于逐段 delta 计算。
  Stopwatch? stopwatch(String convId) => _runningClock(convId);

  Stopwatch? _runningClock(String convId) {
    for (final key in _aliasKeys(convId)) {
      final sw = _clocks[key];
      if (sw != null && sw.isRunning) {
        return sw;
      }
    }
    return null;
  }

  Iterable<String> _aliasKeys(String convId) sync* {
    final raw = convId.trim();
    if (raw.isEmpty) {
      return;
    }
    yield raw;
    final normalized = normalizeKey(rawConversationId: raw);
    if (normalized.isNotEmpty && normalized != raw) {
      yield normalized;
    }
    if (raw.startsWith('group_') && raw.length > 6) {
      yield raw.substring(6);
    } else if (raw.startsWith('c2c_') && raw.length > 4) {
      yield raw.substring(4);
    } else if (!raw.startsWith('group_') && !raw.startsWith('c2c_')) {
      yield 'group_$raw';
      yield 'c2c_$raw';
    }
  }

  /// 在 pipeline 末端释放资源。
  void clear(String convId) {
    _clocks.remove(convId);
  }

  /// 统一格式输出。
  void trace(
    String convId,
    String stage, {
    int? elapsedMs,
    Map<String, Object?>? extras,
  }) {
    if (!enabled) {
      return;
    }
    final offset = offsetMs(convId);
    final buf = StringBuffer()
      ..write('[Pipeline] stage=')
      ..write(stage)
      ..write(' conv=')
      ..write(convId)
      ..write(' offset=')
      ..write(offset)
      ..write('ms');
    if (elapsedMs != null) {
      buf
        ..write(' elapsed=')
        ..write(elapsedMs)
        ..write('ms');
    }
    if (extras != null && extras.isNotEmpty) {
      buf
        ..write(' ')
        ..write(extras.entries.map((e) => '${e.key}=${e.value}').join(' '));
    }
    // ignore: avoid_print
    debugPrint(buf.toString());
  }
}
