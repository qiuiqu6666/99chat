import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('historical messages are committed without awaiting online URL lookup',
      () {
    final source = File('lib/src/chat.dart').readAsStringSync();
    final callbackStart = source.indexOf('didGetHistoricalMessageList:');
    final callbackEnd = source.indexOf(
      'messageShouldMount:',
      callbackStart,
    );

    expect(callbackStart, greaterThanOrEqualTo(0));
    expect(callbackEnd, greaterThan(callbackStart));

    final callback = source.substring(callbackStart, callbackEnd);
    expect(
      callback.contains(
        'await ChatImageMessagePrefetch.resolveOnlineUrlsForMessages',
      ),
      isFalse,
    );
    expect(callback.contains('resolveOnlineUrlsForMessages'), isFalse);
  });

  test('route transition listeners are owned and cleared on dispose', () {
    final source = File('lib/src/chat.dart').readAsStringSync();

    expect(source.contains('_clearRouteTransitionListeners();'), isTrue);
    expect(
      source.contains('status != AnimationStatus.dismissed'),
      isTrue,
    );
  });

  test('chat initialization does not enter active registry twice', () {
    final source = File('lib/src/chat.dart').readAsStringSync();
    final initStart = source.indexOf('void initState()');
    final initEnd = source.indexOf('void didChangeDependencies()', initStart);

    expect(initStart, greaterThanOrEqualTo(0));
    expect(initEnd, greaterThan(initStart));

    final initBody = source.substring(initStart, initEnd);
    expect(
      RegExp(r'ActiveChatRegistry\.instance\.enter\(')
          .allMatches(initBody)
          .length,
      1,
    );
  });

  test('chat leave defers bubble cache eviction into batches', () {
    final chatSource = File('lib/src/chat.dart').readAsStringSync();
    final prefetchSource =
        File('lib/utils/chat_image_message_prefetch.dart').readAsStringSync();

    expect(
      chatSource.contains(
        'ChatImageMessagePrefetch.evictBubbleCacheForMessagesAfterFrame',
      ),
      isTrue,
    );
    expect(
      prefetchSource.contains('static const _leaveEvictBatchSize = 8;'),
      isTrue,
    );
    expect(
      prefetchSource.contains('_evictBubbleProvidersInBatches(providers, end)'),
      isTrue,
    );
  });

  test('image bubbles paint network thumbs during route transition', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitMessageItem/tim_uikit_chat_image_elem.dart',
    ).readAsStringSync();
    final buildStart = source.indexOf('Widget buildImageContent()');
    expect(buildStart, greaterThanOrEqualTo(0));
    final buildEnd = source.indexOf('return GestureDetector(', buildStart);
    expect(buildEnd, greaterThan(buildStart));
    final buildBody = source.substring(buildStart, buildEnd);

    // 转场中有 URL 即可挂网图，不再要求本 State 已解出过帧。
    expect(
      buildBody.contains("_readyImageFrameKeys.contains('net:"),
      isFalse,
    );
    expect(buildBody.contains('buildNetworkImageIfPossible()'), isTrue);

    // initImages 首帧即跑，不等 TickerMode。
    expect(source.contains('unawaited(initImages());'), isTrue);
    expect(
      source.contains(
        'runWhenTickerEnabled(\n'
        '        () => unawaited(initImages()),',
      ),
      isFalse,
    );
  });

  test('post-open enrichment owns URL resolve outside the history gate', () {
    final source = File('lib/src/chat.dart').readAsStringSync();
    final enrichmentStart = source.indexOf('_runOpenHistoryEnrichment(');
    final enrichmentEnd = source.indexOf(
      '_ensureGroupLocalTipsMergedOnOpen(',
      enrichmentStart,
    );
    expect(enrichmentStart, greaterThanOrEqualTo(0));
    expect(enrichmentEnd, greaterThan(enrichmentStart));
    final slice = source.substring(enrichmentStart, enrichmentEnd);
    expect(
      slice.contains('ChatImageMessagePrefetch.fromMessages(messages)'),
      isTrue,
    );
    expect(
      slice.contains(
        'ChatImageMessagePrefetch.resolveOnlineUrlsForMessages(messages)',
      ),
      isTrue,
    );
    final gateStart = source.indexOf('_prepareOpenHistoryGate(');
    final gateEnd = source.indexOf('_runOpenHistoryEnrichment(', gateStart);
    final gate = source.substring(gateStart, gateEnd);
    expect(gate.contains('resolveOnlineUrlsForMessages'), isFalse);
  });

  test('image prefetch never owns a cloud history request', () {
    final source =
        File('lib/utils/chat_image_message_prefetch.dart').readAsStringSync();
    final start = source.indexOf('static Future<ConversationPeekLoadResult>');
    final end = source.indexOf('static String? _conversationKey', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final loader = source.substring(start, end);
    expect(loader.contains('loadLocalForChatEntry'), isTrue);
    expect(loader.contains('loadForChatEntry'), isFalse);
  });

  test('route viewport coordinator does not await history warm', () {
    final source = File(
      'lib/src/services/chat_open_viewport_coordinator.dart',
    ).readAsStringSync();
    expect(source.contains('ensureCompleteOpenWindow'), isFalse);
    expect(source.contains('ConversationHistoryWarmScheduler'), isFalse);
    expect(
      source.contains('不会等待 SDK、云端或完整历史窗口'),
      isTrue,
    );
  });

  test('chat entry does not re-schedule the compatibility warm owner', () {
    final chatSource = File('lib/src/chat.dart').readAsStringSync();
    final separateSource = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/'
      'tui_chat_separate_view_model.dart',
    ).readAsStringSync();

    expect(
      chatSource.contains('scheduleWarmOpenHistoryReconcile'),
      isFalse,
    );
    expect(
      RegExp(
        r'^\s*void scheduleWarmOpenHistoryReconcile\(',
        multiLine: true,
      ).allMatches(separateSource).length,
      1,
    );
    expect(
      separateSource.contains('warm_open_reconcile_delegated'),
      isTrue,
    );
  });

  test('post-frame history recovery releases remote paging before UI gates',
      () {
    final source = File('lib/src/chat.dart').readAsStringSync();
    final scheduleStart =
        source.indexOf('void _scheduleDeferredHistoryVerification(');
    final runnerStart = source.indexOf(
        'Future<void> _runDeferredHistoryVerification(', scheduleStart);

    expect(scheduleStart, greaterThanOrEqualTo(0));
    expect(runnerStart, greaterThan(scheduleStart));

    final scheduler = source.substring(scheduleStart, runnerStart);
    expect(scheduler, contains('allowRemoteHistoryAfterFirstFrame()'));
    expect(scheduler, contains('localWindowIsEmpty'));
    expect(scheduler, contains('? Duration.zero'));

    final runnerEnd =
        source.indexOf('void _tryMarkChatOpenEnriched()', runnerStart);
    final runner = source.substring(runnerStart, runnerEnd);
    expect(
      runner,
      contains('chat_open_cloud_verify_requeued_by_user_state'),
    );
    expect(
      RegExp(r'_runDeferredHistoryVerification\(').allMatches(runner).length,
      greaterThanOrEqualTo(2),
    );
  });
}
