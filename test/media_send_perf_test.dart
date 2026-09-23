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
}
