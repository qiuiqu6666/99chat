import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/account_runtime_supervisor.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_protocol.dart';

void main() {
  test('the same causal input order replays to the same snapshots and effects',
      () async {
    final scope = RuntimeAccountScope(
        ownerUserID: 'owner', accountEpoch: 4, sdkDomainEpoch: 2);
    final events = [
      for (final id in ['insert', 'revoke', 'old-history', 'revoke'])
        RuntimeEnvelope(
            scope: scope,
            conversationKey: 'group_room',
            eventID: id,
            operationID: id,
            correlationID: 'scenario',
            source: 'test',
            kind: id,
            clearEpoch: 0,
            payload: RuntimeDocument({'id': 'message'}))
    ];
    Future<List<Object?>> replay(int batch) async {
      final runtime = AccountRuntimeSupervisor.shadow(
          scope: scope,
          eventsPerTurn: batch,
          initialState: (_) =>
              RuntimeDocument({'revoked': false, 'visible': false}),
          reducer: (before, event) {
            final revoked =
                before.document['revoked'] == true || event.kind == 'revoke';
            return RuntimeTransition(
                document:
                    RuntimeDocument({'revoked': revoked, 'visible': !revoked}),
                effects: event.kind == 'revoke'
                    ? [
                        RuntimeEffectIntent(
                            operationID: event.operationID,
                            kind: 'revoke',
                            payload: event.payload)
                      ]
                    : []);
          });
      final receipts = await Future.wait(events.map(runtime.dispatch));
      await runtime.close();
      return [
        for (final r in receipts)
          [
            r.eventID,
            r.ingressSequence,
            r.disposition.name,
            r.snapshot.revision,
            r.snapshot.document.values,
            r.effects.map((e) => e.operationID).toList()
          ]
      ];
    }

    expect(await replay(1), await replay(32));
  });
}
