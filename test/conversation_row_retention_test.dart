import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_feed_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_row_retention.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ConversationPerfFlags.debugConversationRowRetentionOverride = true;
    ConversationFeedPerf.debugEnabledOverride = true;
    ConversationFeedPerf.resetForTest();
    ConversationPerfGateLog.resetCountsForTest();
  });

  tearDown(() {
    ConversationPerfFlags.debugConversationRowRetentionOverride = null;
    ConversationFeedPerf.debugEnabledOverride = null;
    ConversationFeedPerf.debugSink = null;
    ConversationFeedPerf.resetForTest();
  });

  test('tryRetain hits, 3rd evicts oldest, dispose unregisters', () {
    final retention = ConversationRowRetention(limit: 2);
    final a = _FakeHost('a')..isKeptAlive = true;
    final b = _FakeHost('b')..isKeptAlive = true;
    final c = _FakeHost('c')..isKeptAlive = true;
    retention.register(a);
    retention.register(b);
    retention.register(c);
    retention.probe();

    expect(retention.keepAliveCount, 2);
    expect(a.dropped, isTrue);
    expect(retention.evictionCount, 1);
    expect(
      ConversationPerfGateLog.eventCountsForTest['row_keepalive_evict'],
      1,
    );

    retention.unregister(b);
    expect(retention.keepAliveCount, lessThanOrEqualTo(1));
    expect(retention.activeRowCount, 2);
    retention.dispose();
  });

  test('near-zone keptAlive false removes from LRU as hit', () {
    final retention = ConversationRowRetention(limit: 2);
    final a = _FakeHost('a')..isKeptAlive = true;
    retention.register(a);
    retention.probe();
    expect(retention.keepAliveCount, 1);

    a.isKeptAlive = false;
    retention.probe();
    expect(retention.keepAliveCount, 0);
    expect(
      ConversationPerfGateLog.eventCountsForTest['row_keepalive_hit'],
      1,
    );
    retention.dispose();
  });

  test('disabled flag does not retain', () {
    ConversationPerfFlags.debugConversationRowRetentionOverride = false;
    final retention = ConversationRowRetention(limit: 2);
    final a = _FakeHost('a')..isKeptAlive = true;
    retention.register(a);
    retention.probe();
    expect(retention.keepAliveCount, 0);
    retention.dispose();
  });

  test('conversationKeyHash is 12 chars and not the raw id', () {
    const id = 'c2c_user_1';
    final hash = ConversationRowRetention.conversationKeyHash(id);
    expect(hash.length, 12);
    expect(hash, isNot(id));
  });
}

class _FakeHost implements ConversationRowRetentionClient {
  _FakeHost(this.identity);

  @override
  final String identity;
  @override
  bool mounted = true;
  @override
  bool isKeptAlive = false;
  bool dropped = false;

  @override
  void dropKeepAlive() {
    dropped = true;
    isKeptAlive = false;
  }
}
