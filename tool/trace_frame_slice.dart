// tool/trace_frame_slice.dart
//
// Plan 125 Phase A/B/C 单帧切片工具（只读分析，不改产品代码）。
// 输入：Chrome trace JSON（Flutter DevTools Timeline 导出，顶层含 "traceEvents"）。
// trace 内 ts/dur 单位为微秒；--time 参数也用微秒。
//
// 用法：
//   dart run tool/trace_frame_slice.dart --trace <file> --list-frames
//       列出全部 Flutter Frame 事件（number/build/raster/vsync/时间），用于 Phase 0 漂移核对。
//   dart run tool/trace_frame_slice.dart --trace <file> --frames 5053,4375 [--pad-ms 50] [--tid N] [--md out.md]
//       按帧号锚点切 ±pad 窗口，输出线程概览 + UI 线程调用树（self>1ms 与 inclusive>2ms 双阈值）。
//   dart run tool/trace_frame_slice.dart --trace <file> --time <t0Us>,<t1Us> [--pad-ms 0] [--tid N] [--md out.md]
//       无帧号锚点时按绝对时间窗切（Phase B/C 阶段窗口复用）。
//
// 设计约束（对应 plans/125-single-frame-hotspot-attribution.md）：
// - 输出热点统一 Path/Inclusive/Self/Calls 四列；root callback（self 小、inclusive 大）
//   必须保留：self 阈值滤不掉 inclusive 达标节点。
// - 只描述 trace 内可见事件，不做代码归因。

import 'dart:convert';
import 'dart:io';

const _selfThresholdUs = 1000; // self > 1ms
const _inclThresholdUs = 2000; // inclusive > 2ms

class _Ev {
  final String name;
  final String ph;
  final int pid;
  final int tid;
  final int ts;
  final int dur;
  final Map<String, dynamic> args;
  _Ev(this.name, this.ph, this.pid, this.tid, this.ts, this.dur, this.args);
  int get end => ts + dur;
}

class _Frame {
  final int number;
  final int ts;
  final int dur;
  final int? buildUs;
  final int? rasterUs;
  final int? vsyncUs;
  final int tid;
  _Frame(this.number, this.ts, this.dur, this.buildUs, this.rasterUs, this.vsyncUs, this.tid);
  int get end => ts + dur;
}

class _Node {
  final _Ev ev;
  final List<_Node> children = [];
  _Node(this.ev);
  int get ts => ev.ts;
  int get end => ev.end;
}

int? _pickArg(Map<String, dynamic> args, List<String> keys) {
  for (final k in args.keys) {
    final lk = k.toLowerCase();
    for (final want in keys) {
      if (lk == want || lk.startsWith(want)) {
        final v = args[k];
        if (v is num) return v.round();
      }
    }
  }
  return null;
}

List<_Frame> _findFrames(List<_Ev> events) {
  final frames = <_Frame>[];
  for (final e in events) {
    if (e.name != 'Frame') continue;
    final n = e.args['number'];
    if (n is! num) continue;
    frames.add(_Frame(
      n.round(),
      e.ts,
      e.dur,
      _pickArg(e.args, ['buildtimemicros', 'buildtime', 'buildms', 'build']),
      _pickArg(e.args, ['rastertimemicros', 'rastertime', 'rasterms', 'raster']),
      _pickArg(e.args, ['vsyncoverheadmicros', 'vsyncoverhead', 'vsync']),
      e.tid,
    ));
  }
  frames.sort((a, b) => a.ts.compareTo(b.ts));
  return frames;
}

Map<int, String> _threadNames(List<_Ev> events) {
  final names = <int, String>{};
  for (final e in events) {
    if (e.ph == 'M' && e.name == 'thread_name') {
      final n = e.args['name'];
      final key = e.pid * 100000 + e.tid;
      if (n is String) names[key] = n;
    }
  }
  return names;
}

// 按同线程 ts/dur 嵌套关系建树（Dart Timeline 同线程事件严格嵌套或兄弟）。
List<_Node> _buildForest(List<_Ev> events) {
  final sorted = [...events]..sort((a, b) {
      final c = a.ts.compareTo(b.ts);
      return c != 0 ? c : b.dur.compareTo(a.dur);
    });
  final roots = <_Node>[];
  final stack = <_Node>[];
  for (final e in sorted) {
    while (stack.isNotEmpty && e.ts >= stack.last.end) {
      stack.removeLast();
    }
    final node = _Node(e);
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.children.add(node);
    }
    stack.add(node);
  }
  return roots;
}

int _selfUs(_Node n) {
  var childSum = 0;
  for (final c in n.children) {
    childSum += c.ev.dur;
  }
  final s = n.ev.dur - childSum;
  return s < 0 ? 0 : s;
}

String _fmtMs(int us) => '${(us / 1000).toStringAsFixed(2)}ms';

bool _inclOk(_Node n) => n.ev.dur > _inclThresholdUs;
bool _selfOk(_Node n) => _selfUs(n) > _selfThresholdUs;
bool _anyOk(_Node n) => _inclOk(n) || _selfOk(n);

void _writeTree(StringBuffer b, List<_Node> roots) {
  b.writeln('```');
  void walk(_Node n, int depth) {
    final mark = _inclOk(n) ? '*' : ' ';
    b.writeln('${'  ' * depth}$mark${n.ev.name}  incl=${_fmtMs(n.ev.dur)} self=${_fmtMs(_selfUs(n))} ts=${n.ev.ts}');
    final shown = n.children.where(_anyOk).toList();
    for (final c in shown) {
      walk(c, depth + 1);
    }
    final hidden = n.children.length - shown.length;
    if (hidden > 0) b.writeln('${'  ' * (depth + 1)}… (+$hidden below thresholds)');
  }

  for (final r in roots.where(_anyOk)) {
    walk(r, 0);
  }
  b.writeln('```');
  b.writeln('`*` = inclusive >2ms；未标 `*` 的行仅 self >1ms；未列出 = 双阈值均未达标。');
}

class _Row {
  final String path;
  int calls = 0;
  int inclUs = 0;
  int selfUs = 0;
  _Row(this.path);
}

void _writeAggregate(StringBuffer b, String title, Iterable<_Node> nodes, bool byInclusive) {
  final byPath = <String, _Row>{};
  void collect(_Node n, String parentPath) {
    final path = parentPath.isEmpty ? n.ev.name : '$parentPath > ${n.ev.name}';
    final keep = byInclusive ? _inclOk(n) : _selfOk(n);
    if (keep) {
      final r = byPath.putIfAbsent(path, () => _Row(path));
      r.calls++;
      r.inclUs += n.ev.dur;
      r.selfUs += _selfUs(n);
    }
    for (final c in n.children) {
      collect(c, path);
    }
  }

  for (final root in nodes) {
    collect(root, '');
  }
  final rows = byPath.values.toList()
    ..sort((a, b) => byInclusive ? b.inclUs.compareTo(a.inclUs) : b.selfUs.compareTo(a.selfUs));
  b.writeln('### $title');
  b.writeln('');
  b.writeln('| Path | Inclusive | Self | Calls |');
  b.writeln('| --- | --- | --- | --- |');
  if (rows.isEmpty) {
    b.writeln('| （无达标节点） | | | |');
  }
  for (final r in rows.take(40)) {
    b.writeln('| ${r.path} | ${_fmtMs(r.inclUs)} | ${_fmtMs(r.selfUs)} | ${r.calls} |');
  }
  b.writeln('');
}

void _analyzeWindow(StringBuffer b, List<_Ev> events, Map<int, String> threadNames,
    String title, int t0, int t1, int anchorTid, int anchorPid) {
  b.writeln('## $title');
  b.writeln('');
  b.writeln('窗口：[${t0}us, ${t1}us]（宽 ${_fmtMs(t1 - t0)}），锚定线程 tid=$anchorTid。');
  b.writeln('');
  final inWin = events.where((e) => e.ph == 'X' && e.ts < t1 && e.end > t0).toList();
  b.writeln('### 线程概览（窗口内完整事件）');
  b.writeln('');
  b.writeln('| pid.tid | 线程名 | 事件数 | 事件总时长 |');
  b.writeln('| --- | --- | --- | --- |');
  final byThread = <int, List<_Ev>>{};
  for (final e in inWin) {
    byThread.putIfAbsent(e.pid * 100000 + e.tid, () => []).add(e);
  }
  final tkeys = byThread.keys.toList()..sort();
  for (final k in tkeys) {
    final list = byThread[k]!;
    final total = list.fold<int>(0, (a, e) => a + e.dur);
    b.writeln('| ${k ~/ 100000}.${k % 100000} | ${threadNames[k] ?? '(unnamed)'} | ${list.length} | ${_fmtMs(total)} |');
  }
  b.writeln('');
  final anchorEvents =
      inWin.where((e) => e.pid == anchorPid && e.tid == anchorTid && e.name != 'Frame').toList();
  final forest = _buildForest(anchorEvents);
  b.writeln('### 调用树（锚定线程，标注双阈值）');
  b.writeln('');
  _writeTree(b, forest);
  _writeAggregate(b, '热点（Inclusive >2ms，root callback 保留）', forest, true);
  _writeAggregate(b, '热点（Self >1ms）', forest, false);
}

// ---- DevTools performance snapshot 支持（plans/125 方案 B）----
// snapshot 顶层：{"devToolsSnapshot":true,...,"performance":{"traceBinary":[...],"flutterFrames":[...],...}}
// - --list-frames：读 flutterFrames（与 DevTools/既有程序化分析同源）
// - --extract-binary <out>：流式提取 traceBinary 写出 Perfetto proto（避免整文件 jsonDecode 的内存峰值）

String? _sliceAfter(String text, String key) {
  final i = text.indexOf(key);
  if (i < 0) return null;
  final open = text.indexOf('[', i + key.length);
  if (open < 0) return null;
  var depth = 0;
  var inStr = false;
  for (var j = open; j < text.length; j++) {
    final c = text[j];
    if (inStr) {
      if (c == r'\') {
        j++;
      } else if (c == '"') {
        inStr = false;
      }
      continue;
    }
    if (c == '"') {
      inStr = true;
    } else if (c == '[') {
      depth++;
    } else if (c == ']') {
      depth--;
      if (depth == 0) return text.substring(open + 1, j);
    }
  }
  return null;
}

List<int> _extractTraceBinary(String text) {
  final body = _sliceAfter(text, '"traceBinary":');
  if (body == null) return const [];
  final bytes = <int>[];
  final sb = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    final c = body.codeUnitAt(i);
    if (c >= 0x30 && c <= 0x39) {
      sb.writeCharCode(c);
    } else if (c == 0x2c) {
      if (sb.isNotEmpty) {
        bytes.add(int.parse(sb.toString()));
        sb.clear();
      }
    } else if (c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09) {
      // 空白忽略
    } else {
      stderr.writeln('traceBinary 含非数字字符 0x${c.toRadixString(16)} @ $i，中止');
      exit(2);
    }
  }
  if (sb.isNotEmpty) bytes.add(int.parse(sb.toString()));
  return bytes;
}

void _runSnapshotMode(String text, {required bool listFrames, String? extractTo, String? mdPath}) {
  final b = StringBuffer();
  if (listFrames) {
    final framesBody = _sliceAfter(text, '"flutterFrames":');
    if (framesBody == null) {
      stderr.writeln('snapshot 中未找到 flutterFrames');
      exit(2);
    }
    final frames = (jsonDecode('[$framesBody]') as List).cast<Map<String, dynamic>>();
    stdout.writeln('flutterFrames: ${frames.length} 帧。');
    if (frames.isNotEmpty) {
      stdout.writeln('首帧字段: ${frames.first.keys.toList()}');
    }
    b.writeln('## Frame 清单（flutterFrames，${frames.length} 帧）');
    b.writeln('');
    b.writeln('| number | startTime(us) | 相对起点 | build | raster | vsync | endTime |');
    b.writeln('| --- | --- | --- | --- | --- | --- | --- |');
    final origin = frames.isEmpty ? 0 : (_num(frames.first, ['startTime', 'ts', 'start']).round());
    for (final f in frames) {
      final st = _num(f, ['startTime', 'ts', 'start']);
      final bt = _num(f, ['buildTime', 'build']);
      final rt = _num(f, ['rasterTime', 'raster']);
      final vo = _num(f, ['vsyncOverhead', 'vsync']);
      final et = _num(f, ['endTime', 'end']);
      b.writeln('| ${_num(f, ['number', 'frameNumber']).round()} | ${st.round()} | '
          '${((st - origin) / 1e6).toStringAsFixed(3)}s | ${_fmtMs(bt.round())} | ${_fmtMs(rt.round())} | '
          '${_fmtMs(vo.round())} | ${et.round()} |');
    }
    b.writeln('');
  }
  if (extractTo != null) {
    stdout.writeln('流式提取 traceBinary…');
    final bytes = _extractTraceBinary(text);
    if (bytes.isEmpty) {
      stderr.writeln('traceBinary 为空');
      exit(2);
    }
    File(extractTo).writeAsBytesSync(bytes);
    stdout.writeln('已写出 ${bytes.length} 字节到 $extractTo');
  }
  final out = b.toString();
  if (out.isNotEmpty) stdout.write(out);
  if (mdPath != null && out.isNotEmpty) {
    File(mdPath).writeAsStringSync(out);
    stdout.writeln('已写入 $mdPath');
  }
}

num _num(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is num) return v;
  }
  return 0;
}

void main(List<String> argv) {
  String? tracePath;
  String? framesArg;
  String? timeArg;
  String? mdPath;
  String? extractTo;
  var padMs = 50;
  int? forceTid;
  var listFrames = false;
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (a == '--trace') {
      tracePath = argv[++i];
    } else if (a == '--frames') {
      framesArg = argv[++i];
    } else if (a == '--time') {
      timeArg = argv[++i];
    } else if (a == '--md') {
      mdPath = argv[++i];
    } else if (a == '--extract-binary') {
      extractTo = argv[++i];
    } else if (a == '--pad-ms') {
      padMs = int.parse(argv[++i]);
    } else if (a == '--tid') {
      forceTid = int.parse(argv[++i]);
    } else if (a == '--list-frames') {
      listFrames = true;
    } else {
      stderr.writeln('未知参数: $a');
      exit(2);
    }
  }
  if (tracePath == null) {
    stderr.writeln('用法：dart run tool/trace_frame_slice.dart --trace <file.json> [--list-frames | --frames 5053,4375 | --time t0,t1] [--pad-ms 50] [--tid N] [--md out.md]');
    exit(2);
  }
  final file = File(tracePath);
  if (!file.existsSync()) {
    stderr.writeln('trace 文件不存在: $tracePath');
    exit(2);
  }
  stdout.writeln('读取 $tracePath（大文件可能耗时数十秒）…');
  final text = file.readAsStringSync();
  if (text.contains('"devToolsSnapshot"')) {
    _runSnapshotMode(text, listFrames: listFrames, extractTo: extractTo, mdPath: mdPath);
    return;
  }
  final decoded = jsonDecode(text);
  final rawEvents = decoded is Map ? decoded['traceEvents'] : decoded;
  if (rawEvents is! List) {
    stderr.writeln('未找到 traceEvents 数组；本工具仅支持 Chrome trace JSON。Perfetto proto 需先转换为 JSON。');
    exit(2);
  }
  final events = <_Ev>[];
  for (final r in rawEvents) {
    if (r is! Map) continue;
    final ts = r['ts'];
    final dur = r['dur'];
    final ph = (r['ph'] ?? 'X').toString();
    // Metadata（ph=M）事件无 ts/dur，但 thread_name 需要保留用于线程识别。
    if (ph != 'M' && (ts is! num || dur is! num)) continue;
    final pid = r['pid'];
    final tid = r['tid'];
    final args = r['args'];
    events.add(_Ev(
      (r['name'] ?? '(unnamed)').toString(),
      ph,
      pid is num ? pid.round() : -1,
      tid is num ? tid.round() : -1,
      ts is num ? ts.round() : 0,
      dur is num ? dur.round() : 0,
      args is Map ? args.cast<String, dynamic>() : const <String, dynamic>{},
    ));
  }
  stdout.writeln('共 ${events.length} 条事件。');
  final threadNames = _threadNames(events);
  final b = StringBuffer();
  b.writeln('# trace 切片分析：${file.uri.pathSegments.last}');
  b.writeln('');

  if (listFrames) {
    final frames = _findFrames(events);
    b.writeln('## Frame 清单（${frames.length} 帧）');
    b.writeln('');
    b.writeln('| number | ts(us) | 相对起点 | dur | build | raster | vsync | tid |');
    b.writeln('| --- | --- | --- | --- | --- | --- | --- | --- |');
    final origin = frames.isEmpty ? 0 : frames.first.ts;
    for (final f in frames) {
      b.writeln('| ${f.number} | ${f.ts} | ${((f.ts - origin) / 1e6).toStringAsFixed(3)}s | ${_fmtMs(f.dur)} | '
          '${f.buildUs == null ? '-' : _fmtMs(f.buildUs!)} | ${f.rasterUs == null ? '-' : _fmtMs(f.rasterUs!)} | '
          '${f.vsyncUs == null ? '-' : _fmtMs(f.vsyncUs!)} | ${f.tid} |');
    }
    b.writeln('');
  }

  if (framesArg != null) {
    final want = framesArg.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toSet();
    final frames = _findFrames(events);
    final padUs = padMs * 1000;
    for (final w in want) {
      final f = frames.where((x) => x.number == w).toList();
      if (f.isEmpty) {
        b.writeln('## Frame $w 未找到（trace 内 Frame.number 不含 $w）');
        b.writeln('');
        continue;
      }
      final fr = f.first;
      _analyzeWindow(
          b,
          events,
          threadNames,
          'Frame ${fr.number} @ ${(fr.ts / 1e6).toStringAsFixed(3)}s '
          '(build ${fr.buildUs == null ? '-' : _fmtMs(fr.buildUs!)}, raster ${fr.rasterUs == null ? '-' : _fmtMs(fr.rasterUs!)}, '
          'vsync ${fr.vsyncUs == null ? '-' : _fmtMs(fr.vsyncUs!)})',
          fr.ts - padUs,
          fr.end + padUs,
          forceTid ?? fr.tid,
          fr.tid == -1 ? 0 : _pidOf(events, fr));
    }
  }

  if (timeArg != null) {
    final parts = timeArg.split(',');
    if (parts.length != 2) {
      stderr.writeln('--time 需要 t0Us,t1Us');
      exit(2);
    }
    final t0 = int.parse(parts[0]);
    final t1 = int.parse(parts[1]);
    final anchor = events.firstWhere((e) => e.ph == 'X' && e.ts < t1 && e.end > t0, orElse: () => events.first);
    _analyzeWindow(b, events, threadNames, '时间窗 [${t0}us, ${t1}us]', t0, t1,
        forceTid ?? anchor.tid, anchor.pid);
  }

  final out = b.toString();
  stdout.write(out);
  if (mdPath != null) {
    File(mdPath).writeAsStringSync(out);
    stdout.writeln('已写入 $mdPath');
  }
}

int _pidOf(List<_Ev> events, _Frame f) {
  for (final e in events) {
    if (e.name == 'Frame' && e.ts == f.ts) return e.pid;
  }
  return 0;
}


