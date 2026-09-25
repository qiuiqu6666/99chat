import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_send_perf.dart';

void main() {
  test('placeholder and SDK identifiers share one trace and release together',
      () async {
    final trace = MediaSendPerf.begin('placeholder');
    trace.bind('sdk-id');
    expect(MediaSendPerf.begin('sdk-id'), same(trace));
    trace.record('sizeOriginal', 20000000);
    await trace.measure('compress', () async => 'sendFile');
    expect(trace.metrics['compressMs'], greaterThanOrEqualTo(0));
    trace.finish('success');
    expect(MediaSendPerf.lookup('placeholder'), isNull);
    expect(MediaSendPerf.lookup('sdk-id'), isNull);
    expect(trace.metrics['sizeOriginal'], 20000000);
    expect(trace.metrics['totalMs'], greaterThanOrEqualTo(0));
  });

  test('failed stages retain timing and do not hide the failure', () async {
    final trace = MediaSendPerf.begin('failed');
    await expectLater(
        trace.measure('upload', () async => throw StateError('network')),
        throwsStateError);
    expect(trace.metrics['uploadMs'], greaterThanOrEqualTo(0));
    trace.finish('failed');
    final metrics = Map.of(trace.metrics);
    trace.finish('success');
    expect(trace.metrics, metrics);
    expect(MediaSendPerf.lookup('failed'), isNull);
  });

  test('SDK timeline binds native message identity and keeps one time origin',
      () async {
    final trace = MediaSendPerf.begin('local-only');
    await Future<void>.delayed(const Duration(milliseconds: 15));
    trace.markSdkEnter(connectionState: 'connecting', handshakePending: true);
    trace.bind('native-msg-id'); // onSyncMsgID runs before native progress.
    final progressTrace = MediaSendPerf.lookup('native-msg-id')!;
    progressTrace.observeUploadProgress(0);
    expect(trace.metrics, isNot(contains('uploadFirstProgressMs')));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    progressTrace.observeUploadProgress(20);
    progressTrace.observeUploadProgress(100);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    trace.markSdkReturn(connectionState: 'connected');
    final sdkReturn = trace.metrics['sdkReturnMs']!;
    progressTrace.observeUploadProgress(100); // Ignore callbacks after return.
    trace.finish('success');
    final event = MediaSendPerf.recentEvents.last;
    expect(event['timingOrigin'], 'media_start');
    expect(event['imConnectionStateAtSend'], 'connecting');
    expect(event['imConnectionStateAtReturn'], 'connected');
    expect(event['imHandshakePendingAtSend'], isTrue);
    expect(trace.metrics['uploadProgressCallbackCount'], 3);
    final sdkEnter = trace.metrics['sdkEnterMs']!;
    final first = trace.metrics['uploadFirstProgressMs']!;
    final uploaded = trace.metrics['upload100Ms']!;
    expect(sdkEnter, greaterThan(0));
    expect(first, greaterThanOrEqualTo(sdkEnter));
    expect(uploaded, greaterThanOrEqualTo(first));
    expect(sdkReturn, greaterThanOrEqualTo(uploaded));
    expect(trace.metrics['upload100ToSdkReturnMs'], sdkReturn - uploaded);
    expect(MediaSendPerf.lookup('native-msg-id'), isNull);
    expect(MediaSendPerf.lookup('local-only'), isNull);
    expect(event.toString(), isNot(contains('native-msg-id')));
  });

  test('missing upload callbacks remain distinguishable from instant upload',
      () {
    final trace = MediaSendPerf.begin('no-progress');
    trace.markSdkEnter(connectionState: 'connected', handshakePending: false);
    trace.markSdkReturn(connectionState: 'connected');
    trace.finish('success');
    final event = MediaSendPerf.recentEvents.last;
    expect(event['uploadProgressCallbackCount'], 0);
    expect(event, isNot(contains('uploadFirstProgressMs')));
    expect(event, isNot(contains('upload100Ms')));
    expect(event, contains('sdkEnterMs'));
    expect(event, contains('sdkReturnMs'));
  });

  test('a stalled stage reports once without completing or repeating work', () {
    fakeAsync((async) {
      final trace = MediaSendPerf.begin('stalled');
      final gate = Completer<int>();
      var calls = 0;
      int? result;
      trace.measure('sdkCreateImage', () {
        calls++;
        return gate.future;
      }).then((value) => result = value);
      async.elapse(const Duration(seconds: 20));
      final events = MediaSendPerf.recentEvents
          .where((event) => event['mediaId'] == trace.mediaId);
      expect(events.length, 1);
      expect(events.single['stage'], 'sdkCreateImage');
      expect(events.single['event'], 'slow_stage');
      expect(calls, 1);
      expect(result, isNull);
      gate.complete(42);
      async.flushMicrotasks();
      expect(result, 42);
      trace.finish('success');
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('upload progress is monotonic and 100 percent is not a send result', () {
    fakeAsync((async) {
      final trace = MediaSendPerf.begin('upload');
      final gate = Completer<void>();
      var completed = false;
      trace.observeUploadProgress(100); // No SDK dispatch has started yet.
      expect(trace.metrics, isEmpty);
      trace
          .measure('sdkUploadAndSend', () => gate.future)
          .then((_) => completed = true);
      trace.observeUploadProgress(10);
      trace.observeUploadProgress(100);
      trace.observeUploadProgress(20); // Late, out-of-order callback.
      async.flushMicrotasks();
      expect(trace.metrics['uploadProgressPercent'], 100);
      expect(trace.metrics, contains('uploadFirstProgressMs'));
      expect(trace.metrics, contains('uploadCompleteProgressMs'));
      expect(completed, isFalse);
      expect(MediaSendPerf.lookup('upload'), same(trace));
      gate.complete();
      async.flushMicrotasks();
      expect(completed, isTrue);
      trace.finish('success');
    });
  });

  test('finish cancels pending diagnostics and ignores late stage completion',
      () {
    fakeAsync((async) {
      final trace = MediaSendPerf.begin('finished');
      final gate = Completer<void>();
      trace.measure('snapshot', () => gate.future);
      trace.finish('session_changed');
      final before = Map.of(trace.metrics);
      async.elapse(const Duration(seconds: 10));
      expect(
          MediaSendPerf.recentEvents
              .where((event) => event['mediaId'] == trace.mediaId)
              .length,
          1);
      gate.complete();
      async.flushMicrotasks();
      expect(trace.metrics, before);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('diagnostic output failure cannot fail a media operation', () {
    final previous = debugPrint;
    debugPrint = (String? _, {int? wrapWidth}) => throw StateError('log sink');
    try {
      fakeAsync((async) {
        final trace = MediaSendPerf.begin('sink-failure');
        final gate = Completer<int>();
        int? result;
        trace.measure('compress', () => gate.future).then((v) => result = v);
        async.elapse(const Duration(seconds: 6));
        gate.complete(7);
        async.flushMicrotasks();
        trace.finish('success');
        expect(result, 7);
        expect(MediaSendPerf.lookup('sink-failure'), isNull);
      });
    } finally {
      debugPrint = previous;
    }
  });

  test('diagnostic history is bounded and excludes local message identities',
      () {
    final previous = debugPrint;
    debugPrint = (String? _, {int? wrapWidth}) {};
    try {
      for (var i = 0; i < 80; i++) {
        MediaSendPerf.begin('private-local-$i').finish('failed');
      }
      expect(MediaSendPerf.recentEvents.length, 64);
      expect(MediaSendPerf.recentEvents.toString(),
          isNot(contains('private-local')));
      expect(() => MediaSendPerf.recentEvents.clear(), throwsUnsupportedError);
    } finally {
      debugPrint = previous;
    }
  });
}
