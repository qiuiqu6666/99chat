import 'dart:async';
import 'package:flutter/material.dart';
import '../services/startup_perf_log.dart';
import '../services/sqflite_lifecycle_host.dart';

/// Completed steps survive retry; pending native work is never duplicated.
class StartupTasks {
  final Map<String, Future<Object?>> _tasks = {};
  Future<T> run<T>(String key, FutureOr<T> Function() work) {
    final old = _tasks[key];
    if (old != null) return old.then((value) => value as T);
    late final Future<T> operation;
    operation = Future<T>.sync(work).then((value) {
      StartupPerfLog.markTagged('bootstrap_step_ready',
          category: 'startup', details: {'step': key});
      return value;
    }, onError: (Object error, StackTrace stack) {
      if (identical(_tasks[key], operation)) _tasks.remove(key);
      Error.throwWithStackTrace(error, stack);
    });
    _tasks[key] = operation;
    return operation;
  }
}

class RecoverableStartup extends StatefulWidget {
  const RecoverableStartup(
      {super.key,
      required this.bootstrap,
      this.waitBudget = const Duration(seconds: 8)});
  final Future<Widget> Function() bootstrap;
  final Duration waitBudget;
  @override
  State<RecoverableStartup> createState() => _RecoverableStartupState();
}

class _RecoverableStartupState extends State<RecoverableStartup> {
  Future<Widget>? _operation;
  Widget? _ready;
  Timer? _watchdog;
  bool _slow = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _start() {
    if (_operation != null) {
      _armWatchdog();
      return;
    }
    setState(() {
      _slow = false;
      _failed = false;
    });
    final operation = Future<Widget>.sync(widget.bootstrap);
    _operation = operation;
    _armWatchdog();
    unawaited(operation.then<void>((child) {
      if (!mounted || !identical(_operation, operation)) return;
      _watchdog?.cancel();
      setState(() {
        _ready = child;
        _operation = null;
      });
    }, onError: (Object error, StackTrace stack) {
      if (!mounted || !identical(_operation, operation)) return;
      _watchdog?.cancel();
      StartupPerfLog.markTagged('bootstrap_failed',
          category: 'startup',
          details: {'errorType': error.runtimeType.toString()});
      setState(() {
        _failed = true;
        _operation = null;
      });
    }));
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    if (mounted) setState(() => _slow = false);
    _watchdog = Timer(widget.waitBudget, () {
      if (mounted && _operation != null) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready != null) return _ready!;
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            body: SafeArea(
                child: Center(
                    child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('99chat',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            if (!_failed && !_slow) const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
                _failed
                    ? '启动暂未完成，请重试。'
                    : _slow
                        ? '正在等待设备完成准备。你可以继续等待，若长时间没有恢复，请重新打开应用。'
                        : '正在准备…',
                textAlign: TextAlign.center),
            if (_failed || _slow)
              TextButton(
                  onPressed: _start, child: Text(_failed ? '重试' : '继续等待')),
          ]),
        )))));
  }
}

/// A stalled native close leaves the app usable while clearly explaining why
/// local data is unavailable. It does not offer an unsafe forced reopen.
class DatabaseRecoveryNotice extends StatelessWidget {
  const DatabaseRecoveryNotice({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<SqfliteLifecycleStatus>(
        valueListenable: SqfliteLifecycleHost.status,
        builder: (context, status, _) => Stack(children: [
          child,
          if (status == SqfliteLifecycleStatus.degraded)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                  child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xfffff2d6),
                child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('本地数据暂未就绪，部分操作已暂停。若持续未恢复，请重新打开应用。',
                        style:
                            TextStyle(color: Color(0xff5d4512), fontSize: 13))),
              )),
            ),
        ]),
      );
}
