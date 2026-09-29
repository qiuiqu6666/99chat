import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_feed_perf.dart';

void main() {
  setUp(() {
    ConversationFeedPerf.debugEnabledOverride = true;
    ConversationFeedPerf.resetForTest();
  });

  tearDown(() {
    ConversationFeedPerf.debugSink = null;
    ConversationFeedPerf.debugEnabledOverride = null;
    ConversationFeedPerf.resetForTest();
  });

  test('aggregates counters, reasons, gauges, and durations per window', () {
    var now = 100;
    final lines = <String>[];
    ConversationFeedPerf.debugNowMillis = () => now;
    ConversationFeedPerf.debugSink = lines.add;

    ConversationFeedPerf.increment(
      'feed_revision',
      amount: 2,
      reason: 'sdk realtime',
    );
    ConversationFeedPerf.gauge('feed_revision_value', 7);
    ConversationFeedPerf.recordDurationMicros('feed_build', 1200);
    ConversationFeedPerf.recordDurationMicros('feed_build', 800);

    now = 1101;
    ConversationFeedPerf.increment('next_window');

    expect(lines, hasLength(1));
    expect(lines.single, contains('windowMs=1001'));
    expect(lines.single, contains('feed_revision=2'));
    expect(lines.single, contains('feed_revision_sdk_realtime=2'));
    expect(lines.single, contains('feed_revision_value=7'));
    expect(lines.single, contains('feed_build_samples=2'));
    expect(lines.single, contains('feed_build_us=2000'));
    expect(lines.single, contains('feed_build_usMax=1200'));
  });

  test('stays silent while disabled', () {
    final lines = <String>[];
    ConversationFeedPerf.debugEnabledOverride = false;
    ConversationFeedPerf.debugSink = lines.add;

    ConversationFeedPerf.increment('feed_revision');
    ConversationFeedPerf.gauge('feed_revision_value', 1);
    ConversationFeedPerf.flushForTest();

    expect(lines, isEmpty);
    expect(ConversationFeedPerf.snapshot(), isEmpty);
  });

  test('row retention events increment, gauge, and emit immediate fields', () {
    final lines = <String>[];
    ConversationFeedPerf.debugSink = lines.add;

    ConversationFeedPerf.recordRowRetention(
      event: 'row_init',
      conversationKeyHash: 'abc123def456',
      timestamp: 42,
      activeRowCount: 7,
      keepAliveCount: 2,
    );

    expect(lines, hasLength(1));
    expect(lines.single, contains('event=row_init'));
    expect(lines.single, contains('conversationKeyHash=abc123def456'));
    expect(lines.single, contains('timestamp=42'));
    expect(lines.single, contains('activeRowCount=7'));
    expect(lines.single, contains('keepAliveCount=2'));
    expect(ConversationFeedPerf.snapshot()['row_init'], 1);
    expect(ConversationFeedPerf.snapshot()['activeRowCount'], 7);
    expect(ConversationFeedPerf.snapshot()['keepAliveCount'], 2);
  });
}
