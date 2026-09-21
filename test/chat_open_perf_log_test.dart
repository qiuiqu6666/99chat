import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';

void main() {
  tearDown(() {
    ChatOpenPerfLog.resetForTest();
    ChatOpenPerfLog.debugSink = null;
  });

  test('emits milestones and summary without raw identifiers', () {
    final lines = <String>[];
    ChatOpenPerfLog.debugSink = lines.add;

    ChatOpenPerfLog.beginOpen(
      conversationID: 'c2c_user_private_123',
      phase: 'conv_item_tap',
      extras: const <String, Object?>{
        'rawConvID': 'c2c_user_private_123',
      },
    );
    ChatOpenPerfLog.markMessagesFirstVisible(
      conversationID: 'c2c_user_private_123',
      messageCount: 3,
    );

    expect(lines[0], contains('[ChatOpenPerf] event=session_begin'));
    expect(lines[1], contains('event=messages_first_visible'));
    expect(lines[2], contains('event=open_summary'));
    expect(lines[3], contains('event=open_trace_summary'));
    expect(lines[2], contains('region=⑧打开汇总'));
    expect(lines[2], contains('session=open_'));
    expect(lines[2], contains('totalMs='));
    expect(lines[3], contains('phase=first_visible'));
    expect(lines.join('\n'), isNot(contains('c2c_user_private_123')));
    expect(lines.join('\n'), contains('convHash='));
  });

  test('does not emit an empty-message milestone', () {
    final lines = <String>[];
    ChatOpenPerfLog.debugSink = lines.add;

    ChatOpenPerfLog.beginOpen(
      conversationID: 'empty_conversation',
      phase: 'conv_item_tap',
    );
    ChatOpenPerfLog.markMessagesFirstVisible(
      conversationID: 'empty_conversation',
      messageCount: 0,
    );

    expect(lines, hasLength(1));
    expect(lines.single, contains('event=session_begin'));
  });

  test('keeps requestId chatOpenTraceId and source in plaintext', () {
    final lines = <String>[];
    ChatOpenPerfLog.debugSink = lines.add;

    ChatOpenPerfLog.beginOpen(
      conversationID: 'c2c_user_private_123',
      phase: 'conv_item_tap',
    );
    ChatOpenPerfLog.mark(
      'viewport_prepare_start',
      extras: const <String, Object?>{
        'requestId': 7,
        'prepareId': 7,
        'source': 'list',
        'openGeneration': 3,
      },
    );

    final line = lines.last;
    expect(line, contains('requestId=7'));
    expect(line, contains('prepareId=7'));
    expect(line, contains('source=list'));
    expect(line, contains('openGeneration=3'));
    expect(line, contains('chatOpenTraceId=open_'));
    expect(line, isNot(contains('c2c_user_private_123')));
  });

  test('open_trace_summary splits producers and owned ignored work', () {
    final lines = <String>[];
    ChatOpenPerfLog.debugSink = lines.add;

    ChatOpenPerfLog.beginOpen(
      conversationID: 'c2c_user_private_123',
      phase: 'conv_item_tap',
    );
    ChatOpenPerfLog.mark('viewport_prepare_start');
    ChatOpenPerfLog.mark('app_hydrate_registered');
    ChatOpenPerfLog.mark('app_hydrate_started');
    ChatOpenPerfLog.mark('app_hydrate_commit');
    ChatOpenPerfLog.mark('app_bootstrap_commit');
    ChatOpenPerfLog.mark('chat_reload_if_empty_load');
    ChatOpenPerfLog.mark('uikit_loadChatRecord_local_started');
    ChatOpenPerfLog.mark(
      'viewport_prepare_ignored',
      extras: const <String, Object?>{
        'owned': true,
        'dbRead': true,
        'sdkRead': false,
        'committed': true,
        'ignoredReason': 'requestIdMismatch',
      },
    );
    ChatOpenPerfLog.mark(
      'viewport_prepare_ignored',
      extras: const <String, Object?>{
        'owned': false,
        'joined': true,
        'dbRead': false,
        'sdkRead': false,
        'committed': false,
        'ignoredReason': 'requestIdMismatch',
      },
    );
    ChatOpenPerfLog.emitOpenTraceSummary(phase: 'pop');

    final summary = lines.last;
    expect(summary, contains('event=open_trace_summary'));
    expect(summary, contains('phase=pop'));
    expect(summary, contains('prepareCount=1'));
    expect(summary, contains('actualHydrateCount=1'));
    expect(summary, contains('hydrateStartedCount=1'));
    expect(summary, contains('hydrateCommitCount=1'));
    expect(summary, contains('appBootstrapProducerCount=1'));
    expect(summary, contains('reloadIfEmptyCount=1'));
    expect(summary, contains('uikitProducerCount=1'));
    expect(summary, contains('ignoredPrepareCount=2'));
    expect(summary, contains('ignoredAfterDbRead=1'));
    expect(summary, contains('ignoredAfterCommit=1'));
    expect(summary, contains('ignoredAfterSdkRead=0'));
  });

  test('late hydrate commit stays on the creating session', () {
    final lines = <String>[];
    ChatOpenPerfLog.debugSink = lines.add;

    ChatOpenPerfLog.beginOpen(
      conversationID: 'c2c_user_a',
      phase: 'conv_item_tap',
    );
    final sessionA = ChatOpenPerfLog.captureCurrent();
    ChatOpenPerfLog.mark('app_hydrate_registered', trace: sessionA);
    ChatOpenPerfLog.mark('app_hydrate_started', trace: sessionA);

    ChatOpenPerfLog.beginOpen(
      conversationID: 'c2c_user_b',
      phase: 'conv_item_tap',
    );
    ChatOpenPerfLog.mark('app_hydrate_commit', trace: sessionA);

    ChatOpenPerfLog.emitOpenTraceSummary(phase: 'pop');
    final sessionBSummary = lines.last;
    expect(sessionBSummary, contains('hydrateCommitCount=0'));
    expect(sessionBSummary, contains('hydrateStartedCount=0'));

    ChatOpenPerfLog.emitOpenTraceSummary(phase: 'pop', trace: sessionA);
    final sessionASummary = lines.last;
    expect(sessionASummary, contains(sessionA.chatOpenTraceId));
    expect(sessionASummary, contains('hydrateStartedCount=1'));
    expect(sessionASummary, contains('hydrateCommitCount=1'));

    final commitLine = lines.firstWhere(
      (line) => line.contains('event=app_hydrate_commit'),
    );
    expect(commitLine, contains('chatOpenTraceId=${sessionA.chatOpenTraceId}'));
    expect(
      commitLine,
      isNot(contains('chatOpenTraceId=${ChatOpenPerfLog.chatOpenTraceId}')),
    );
  });

  test('elapsedMs uses the owning session t0', () {
    final lines = <String>[];
    ChatOpenPerfLog.debugSink = lines.add;

    ChatOpenPerfLog.beginOpen(
      conversationID: 'c2c_user_a',
      phase: 'conv_item_tap',
    );
    final sessionA = ChatOpenPerfLog.captureCurrent();
    final agedA = ChatOpenTraceContext(
      session: sessionA.session,
      chatOpenTraceId: sessionA.chatOpenTraceId,
      requestId: sessionA.requestId,
      conversationKey: sessionA.conversationKey,
      t0Ms: sessionA.t0Ms - 500,
    );
    ChatOpenPerfLog.beginOpen(
      conversationID: 'c2c_user_b',
      phase: 'conv_item_tap',
    );
    ChatOpenPerfLog.mark('app_hydrate_commit', trace: agedA);

    final commitLine = lines.firstWhere(
      (line) => line.contains('event=app_hydrate_commit'),
    );
    final match = RegExp(r'elapsedMs=(\d+)').firstMatch(commitLine);
    expect(match, isNotNull);
    expect(int.parse(match!.group(1)!), greaterThanOrEqualTo(500));
  });

  test('settle_2s is not cancelled by a later beginOpen', () {
    fakeAsync((async) {
      final lines = <String>[];
      ChatOpenPerfLog.debugSink = lines.add;

      ChatOpenPerfLog.beginOpen(
        conversationID: 'c2c_user_a',
        phase: 'conv_item_tap',
      );
      final sessionA = ChatOpenPerfLog.chatOpenTraceId;
      ChatOpenPerfLog.beginOpen(
        conversationID: 'c2c_user_b',
        phase: 'conv_item_tap',
      );
      final sessionB = ChatOpenPerfLog.chatOpenTraceId;
      async.elapse(const Duration(milliseconds: 2000));

      final settles = lines
          .where((line) => line.contains('phase=settle_2s'))
          .toList();
      expect(settles, hasLength(2));
      expect(
        settles.any((line) => line.contains('chatOpenTraceId=$sessionA')),
        isTrue,
      );
      expect(
        settles.any((line) => line.contains('chatOpenTraceId=$sessionB')),
        isTrue,
      );
    });
  });
}
