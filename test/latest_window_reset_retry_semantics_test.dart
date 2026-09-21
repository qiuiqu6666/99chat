import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/history_search_coordinator.dart';

/// Guards the retry cadence of the latest-window reset: every retry must
/// reach the SDK again. Only an exact duplicate that is still in flight may
/// share a Future; a settled result is never reused for a later attempt.
final _scope = AccountScopedConversationKey(
  ownerUserId: 'reset-owner',
  conversationType: ImConversationType.group,
  conversationId: 'reset-room',
);

Im06HistoryRequest _latest(String id, int generation) => Im06HistoryRequest(
      scope: _scope,
      platform: ImPlatform.android,
      requestedSource: ImHistorySource.cloud,
      direction: ImHistoryDirection.latest,
      requestId: id,
      requestGeneration: generation,
      accountGeneration: 1,
      domainGeneration: 2,
      clearEpoch: 0,
      count: 20,
      cursor: const Im06HistoryCursor.latest(),
    );

class _CountingAdapter implements Im06HistorySearchAdapter {
  final requests = <Im06HistoryRequest>[];
  int newestSequence = 100;

  @override
  Future<SdkResult<Im06HistoryPage>> readHistory(
      Im06HistoryRequest request) async {
    requests.add(request);
    await Future<void>.delayed(Duration.zero);
    // Each SDK round trip observes a newer server edge.
    newestSequence += 10;
    return SdkResult.success(
      data: Im06HistoryPage(
        actualSource: request.requestedSource,
        proof: HistoryProof(
          scope: request.scope,
          platform: request.platform,
          accountGeneration: request.accountGeneration,
          domainGeneration: request.domainGeneration,
          requestGeneration: request.requestGeneration,
          requestId: request.requestId,
          direction: request.direction,
          requestedSource: request.requestedSource,
          actualSource: request.requestedSource,
          level: ImHistoryProofLevel.transportObserved,
          returnedCount: 1,
          isFinished: false,
        ),
        isCompleted: false,
        returnedBounds: Im06MessageBounds(
          oldestSequence: newestSequence - 19,
          newestSequence: newestSequence,
        ),
        messages: <Object?>['edge-$newestSequence'],
      ),
    );
  }

  @override
  Future<SdkResult<Im06SearchPage>> search(Im06SearchRequest request) =>
      throw UnimplementedError();
}

void main() {
  test('sequential latest-window retries each hit the SDK and see fresh data',
      () async {
    final adapter = _CountingAdapter();
    final coordinator = Im06HistorySearchCoordinator(adapter: adapter);

    final first = await coordinator.readHistory(_latest('retry-0', 1));
    final second = await coordinator.readHistory(_latest('retry-1', 2));
    final third = await coordinator.readHistory(_latest('retry-2', 3));

    expect(adapter.requests.map((r) => r.requestId),
        ['retry-0', 'retry-1', 'retry-2']);
    expect(first.page!.messages, ['edge-110']);
    expect(second.page!.messages, ['edge-120']);
    expect(third.page!.messages, ['edge-130']);
  });

  test('a settled result is not reused even for an identical request shape',
      () async {
    final adapter = _CountingAdapter();
    final coordinator = Im06HistorySearchCoordinator(adapter: adapter);

    final first = await coordinator.readHistory(_latest('same', 1));
    final again = await coordinator.readHistory(_latest('same', 1));

    expect(adapter.requests, hasLength(2));
    expect(first.page!.messages, ['edge-110']);
    expect(again.page!.messages, ['edge-120']);
  });
}
