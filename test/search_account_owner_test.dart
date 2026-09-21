import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/search_account_owner.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_state.dart';

void main() {
  test('native login needs no UIKit login or self-profile cache', () {
    expect(
      resolveSearchAccountOwner(
        session: const SessionState(phase: SessionPhase.ready, userId: 'owner'),
        authenticatedUserId: 'owner',
      ),
      'owner',
    );
  });

  test('offline owner can still request SDK-local search', () {
    expect(
      resolveSearchAccountOwner(
        session:
            const SessionState(phase: SessionPhase.offline, userId: 'owner'),
        authenticatedUserId: 'owner',
      ),
      'owner',
    );
  });

  test('new business account rejects the previous native SDK owner', () {
    expect(
      resolveSearchAccountOwner(
        session: const SessionState(phase: SessionPhase.ready, userId: 'old'),
        authenticatedUserId: 'new',
        coreUserId: 'new',
        coreLoginSucceeded: true,
      ),
      isEmpty,
    );
  });

  test('legacy UIKit login requires matching authenticated identity', () {
    for (final authenticated in ['', 'other', 'owner']) {
      for (final succeeded in [false, true]) {
        expect(
          resolveSearchAccountOwner(
            session: const SessionState.unknown(),
            authenticatedUserId: authenticated,
            coreUserId: ' owner ',
            coreLoginSucceeded: succeeded,
          ),
          authenticated == 'owner' && succeeded ? 'owner' : '',
        );
      }
    }
  });

  for (final phase in SessionPhase.values.where((phase) =>
      phase != SessionPhase.ready &&
      phase != SessionPhase.offline &&
      phase != SessionPhase.unknown)) {
    test('$phase cannot revive a stale UIKit login', () {
      expect(
        resolveSearchAccountOwner(
          session: SessionState(phase: phase, userId: 'owner'),
          authenticatedUserId: 'owner',
          coreUserId: 'owner',
          coreLoginSucceeded: true,
        ),
        isEmpty,
      );
    });
  }
}
