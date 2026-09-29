import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/history_search_coordinator.dart';

final _scope = AccountScopedConversationKey(
  ownerUserId: 'queue-owner',
  conversationType: ImConversationType.group,
  conversationId: 'queue-room',
);

Im06HistoryRequest _request(
  String id,
  int generation,
  ImHistoryDirection direction, {
  int clearEpoch = 0,
  int? count,
}) =>
    Im06HistoryRequest(
      scope: _scope,
      platform: ImPlatform.android,
      requestedSource: ImHistorySource.cloud,
      direction: direction,
      requestId: id,
      requestGeneration: generation,
      accountGeneration: 1,
      domainGeneration: 2,
      clearEpoch: clearEpoch,
      count: count ?? generation,
      cursor: direction == ImHistoryDirection.latest
          ? const Im06HistoryCursor.latest()
          : Im06HistoryCursor(messageId: 'anchor-$id'),
    );

class _Adapter implements Im06HistorySearchAdapter {
  final requests = <Im06HistoryRequest>[];
  final started = Completer<void>();
  Completer<void>? release;
  int Function(Im06HistoryRequest request)? proofGeneration;
  int Function(Im06HistoryRequest request)? proofAccountGeneration;

  @override
  Future<SdkResult<Im06HistoryPage>> readHistory(
      Im06HistoryRequest request) async {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    if (requests.length == 1) await release?.future;
    return SdkResult.success(
        data: Im06HistoryPage(
      actualSource: request.requestedSource,
      proof: HistoryProof(
        scope: request.scope,
        platform: request.platform,
        accountGeneration:
            proofAccountGeneration?.call(request) ?? request.accountGeneration,
        domainGeneration: request.domainGeneration,
        requestGeneration:
            proofGeneration?.call(request) ?? request.requestGeneration,
        requestId: request.requestId,
        direction: request.direction,
        requestedSource: request.requestedSource,
        actualSource: request.requestedSource,
        level: ImHistoryProofLevel.transportObserved,
        returnedCount: 1,
        isFinished: false,
      ),
      isCompleted: false,
      returnedBounds:
          const Im06MessageBounds(oldestSequence: 1, newestSequence: 1),
      messages: const <Object?>['message'],
    ));
  }

  @override
  Future<SdkResult<Im06SearchPage>> search(Im06SearchRequest request) =>
      throw UnimplementedError();
}

void main() {
  for (final direction in [
    ImHistoryDirection.newer,
    ImHistoryDirection.latest
  ]) {
    test('queued ${direction.name} reaches SDK before later gallery older',
        () async {
      final adapter = _Adapter()..release = Completer<void>();
      final coordinator = Im06HistorySearchCoordinator(adapter: adapter);
      final active = coordinator
          .readHistory(_request('active', 1, ImHistoryDirection.latest));
      await adapter.started.future;
      final user = coordinator.readHistory(_request('return', 2, direction));
      final gallery = coordinator
          .readHistory(_request('gallery', 3, ImHistoryDirection.older));
      adapter.release!.complete();

      final results = await Future.wait([active, user, gallery]);
      expect(results.every((result) => result.isSuccess), isTrue);
      expect(adapter.requests.map((request) => request.requestId),
          ['active', 'return', 'gallery']);
      expect(results[1].page!.proof.requestGeneration, 2);
      expect(coordinator.coverageFor(_scope).ranges, hasLength(3));
    });
  }

  test('exact duplicate reads still share one SDK Future', () async {
    final adapter = _Adapter()..release = Completer<void>();
    final coordinator = Im06HistorySearchCoordinator(adapter: adapter);
    final first = coordinator.readHistory(
        _request('first', 1, ImHistoryDirection.latest, count: 40));
    await adapter.started.future;
    final duplicate = coordinator.readHistory(
        _request('duplicate', 2, ImHistoryDirection.latest, count: 40));
    expect(identical(first, duplicate), isTrue);
    adapter.release!.complete();
    expect((await first).isSuccess, isTrue);
    expect((await duplicate).isSuccess, isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('late submission of an older generation is still rejected', () async {
    final adapter = _Adapter();
    final coordinator = Im06HistorySearchCoordinator(adapter: adapter);
    expect(
        (await coordinator
                .readHistory(_request('current', 5, ImHistoryDirection.latest)))
            .isSuccess,
        isTrue);
    final stale = await coordinator
        .readHistory(_request('stale', 4, ImHistoryDirection.older));
    expect(stale.error, Im06CoordinatorError.staleResponse);
    expect(adapter.requests.map((request) => request.requestId), ['current']);
    expect(coordinator.coverageFor(_scope).ranges, hasLength(1));
  });

  test('history predating a committed clear barrier stays rejected', () async {
    final adapter = _Adapter();
    final coordinator = Im06HistorySearchCoordinator(adapter: adapter);
    expect(
        (await coordinator.readHistory(_request(
                'cleared', 1, ImHistoryDirection.latest,
                clearEpoch: 2)))
            .isSuccess,
        isTrue);
    final stale = await coordinator.readHistory(
        _request('pre-clear', 2, ImHistoryDirection.older, clearEpoch: 1));
    expect(stale.error, Im06CoordinatorError.staleResponse);
    expect(adapter.requests.map((request) => request.requestId), ['cleared']);
    expect(coordinator.coverageFor(_scope).clearEpoch, 2);
  });

  test('response from a superseded request cannot publish coverage', () async {
    final adapter = _Adapter()
      ..proofGeneration = (request) => request.requestGeneration - 1;
    final coordinator = Im06HistorySearchCoordinator(adapter: adapter);
    final result = await coordinator
        .readHistory(_request('current', 2, ImHistoryDirection.latest));
    expect(result.error, Im06CoordinatorError.proofMismatch);
    expect(coordinator.coverageFor(_scope).ranges, isEmpty);
  });

  test('response from an old account generation cannot publish coverage',
      () async {
    final adapter = _Adapter()..proofAccountGeneration = (_) => 0;
    final coordinator = Im06HistorySearchCoordinator(adapter: adapter);
    final result = await coordinator
        .readHistory(_request('current', 1, ImHistoryDirection.latest));
    expect(result.error, Im06CoordinatorError.proofMismatch);
    expect(coordinator.coverageFor(_scope).ranges, isEmpty);
  });
}
