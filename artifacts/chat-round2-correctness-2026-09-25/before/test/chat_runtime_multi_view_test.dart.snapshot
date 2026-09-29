import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_protocol.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_view_session.dart';

void main() {
  final scope = RuntimeAccountScope(
      ownerUserID: 'owner', accountEpoch: 1, sdkDomainEpoch: 2);
  RuntimeViewSession view(int visit) => RuntimeViewSession(
      scope: scope,
      conversationKey: 'group_room',
      clearEpoch: 3,
      visitID: visit);
  RuntimeViewSession ready(RuntimeViewSession start) {
    final loading =
        start.beginReturn(targetMessageID: 'b', unreadMessageIDs: ['a', 'b']);
    return loading.installWindow(
        expectedOperation: loading.operation,
        revision: 1,
        messageIDs: [
          'a',
          'b',
          'later'
        ]).acknowledgeLayout(
        expectedOperation: loading.operation,
        expectedWindowRevision: 1,
        revision: 1);
  }

  RuntimeViewportProof proof(RuntimeViewSession state,
          {int? visit,
          int? operation,
          int? windowRevision,
          int? layoutRevision,
          int? epoch,
          RuntimeAccountScope? account,
          Iterable<String> ids = const ['b', 'later'],
          bool edge = true}) =>
      RuntimeViewportProof(
          scope: account ?? scope,
          conversationKey: state.conversationKey,
          clearEpoch: epoch ?? state.clearEpoch,
          visitID: visit ?? state.visitID,
          operation: operation ?? state.operation,
          windowRevision: windowRevision ?? state.windowRevision,
          layoutRevision: layoutRevision ?? state.layoutRevision,
          coveredMessageIDs: ids,
          atTargetEdge: edge);

  test('two views share identity but never search anchors or return state', () {
    final searching = view(1).beginSearch('old-message');
    final following = ready(view(2));
    final result = following.confirmReturn(proof(following));
    expect(result, isNotNull);
    expect(result!.view.phase, RuntimeViewPhase.followingLatest);
    expect(searching.phase, RuntimeViewPhase.reading);
    expect(searching.searchAnchor, 'old-message');
    expect(searching.targetMessageID, isNull);
    expect(following.confirmReturn(proof(following, visit: 1)), isNull);
  });

  test('finite boundary completes while later arrivals remain unread', () {
    final state = ready(view(1));
    final result = state.confirmReturn(proof(state));
    expect(result!.coveredMessageIDs, {'b'});
    expect(result.coveredMessageIDs, isNot(contains('a')));
    expect(result.coveredMessageIDs, isNot(contains('later')));
    expect(state.capturedUnreadIDs, {'a', 'b'});
  });

  test(
      'old account clear visit operation window and layout proofs are rejected',
      () {
    final state = ready(view(1));
    final stale = [
      proof(state, visit: 9),
      proof(state, operation: 0),
      proof(state, epoch: 2),
      proof(state, windowRevision: 0),
      proof(state, layoutRevision: 0),
      proof(state,
          account: RuntimeAccountScope(
              ownerUserID: 'owner', accountEpoch: 0, sdkDomainEpoch: 2)),
      proof(state, ids: ['a']),
      proof(state, ids: ['b', 'uninstalled']),
      proof(state, edge: false)
    ];
    for (final value in stale) {
      expect(state.confirmReturn(value), isNull);
    }
    expect(state.close().confirmReturn(proof(state)), isNull);
    expect(state.beginSearch('other').confirmReturn(proof(state)), isNull);
  });

  test('replacing a rendered window requires fresh layout confirmation', () {
    final state = ready(view(1));
    final replacement = state.installWindow(
        expectedOperation: state.operation, revision: 2, messageIDs: ['b']);
    expect(replacement.phase, RuntimeViewPhase.waitingLayout);
    expect(replacement.confirmReturn(proof(replacement)), isNull);
    expect(
        identical(
            replacement.acknowledgeLayout(
                expectedOperation: state.operation,
                expectedWindowRevision: 1,
                revision: 2),
            replacement),
        isTrue);
    final laidOut = replacement.acknowledgeLayout(
        expectedOperation: state.operation,
        expectedWindowRevision: 2,
        revision: 2);
    expect(laidOut.confirmReturn(proof(laidOut, ids: ['b'])), isNotNull);
  });

  test('a superseded window response cannot replace the new search window', () {
    final old = ready(view(1));
    final search = old.beginSearch('target');
    expect(
        identical(
            search.installWindow(
                expectedOperation: old.operation,
                revision: 9,
                messageIDs: ['wrong']),
            search),
        isTrue);
    expect(search.searchAnchor, 'target');
  });
  test('a replacement missing the finite goal returns to loading', () {
    final state = ready(view(1));
    final replacement = state.installWindow(
        expectedOperation: state.operation, revision: 2, messageIDs: ['a']);
    expect(replacement.phase, RuntimeViewPhase.loadingLatest);
    expect(replacement.confirmReturn(proof(replacement, ids: ['a'])), isNull);
  });

  test('invalid page identity is rejected at the boundary', () {
    expect(
        () => RuntimeViewSession(
            scope: scope, conversationKey: '', clearEpoch: 0, visitID: 1),
        throwsArgumentError);
    expect(
        () => RuntimeViewSession(
            scope: scope,
            conversationKey: 'group_room',
            clearEpoch: -1,
            visitID: 1),
        throwsArgumentError);
    expect(
        () => RuntimeViewSession(
            scope: scope,
            conversationKey: 'group_room',
            clearEpoch: 0,
            visitID: 0),
        throwsArgumentError);
  });
}
