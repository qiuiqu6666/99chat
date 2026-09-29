import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_contract_support.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_sync_baseline_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_sync_collector.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_sync_plan.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_sync_transaction.dart';
import 'support/sync_contract_harness.dart';

LocalContactRecord row(String id, [String hash = 'unchanged']) =>
    LocalContactRecord(
        localContactId: id,
        displayName: '张三$id',
        phones: ['+861234'],
        fingerprint: hash);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncHarness h;
  late ContactSyncTransaction transaction;
  var revision = 5;
  var full = true;
  var current = true;
  var sessions = 0;
  Object normal(request) {
    final path = request.path as String;
    final body = request.data as Map?;
    if (path.endsWith('/status'))
      return {
        'contactsDeltaV2': true,
        'types': [
          {
            'syncType': 'CONTACTS',
            'serverRevision': revision,
            'lastFullSyncAt': full ? '2026-09-28T00:00:00Z' : null
          }
        ]
      };
    if (path.endsWith('/sessions')) return {'syncSessionId': 's${++sessions}'};
    if (path.endsWith('/batch'))
      return {
        'syncSessionId': body!['syncSessionId'],
        'uploaded': (body['items'] as List).length,
        'skipped': 0,
        'failed': 0,
        'results': [
          for (final item in body['items'])
            {'localContactId': item['localContactId'], 'status': 'UPLOADED'}
        ]
      };
    if (path.endsWith('/complete'))
      return {
        'syncSessionId': body!['syncSessionId'],
        'status': 'COMPLETED',
        'deleted': 0,
        'committedRevision': revision + 1
      };
    throw StateError(path);
  }

  ContactSyncBaseline baseline({String device = 'device-a', int rev = 5}) =>
      ContactSyncBaseline(
          ownerUserId: 'owner',
          deviceId: device,
          revision: rev,
          fingerprints: {'one': 'unchanged', 'old': 'old'});
  Future<ContactSyncBaseline?> run(List<LocalContactRecord> rows,
          {ContactSyncBaseline? before}) =>
      transaction.run(
          ownerUserId: 'owner',
          deviceId: 'device-a',
          collection:
              ContactCollectionResult(ContactCollectionStatus.success, rows),
          baseline: before,
          isCurrent: () => current);

  setUp(() {
    h = SyncHarness();
    revision = 5;
    full = true;
    current = true;
    sessions = 0;
    h.respond = normal;
    transaction =
        ContactSyncTransaction(h.api, enabled: true, retryDelay: Duration.zero);
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'production gate remains off even when the backend advertises capability',
      () async {
    expect(ContactSyncPlan.deviceScopedDeltaEnabled, isFalse);
    transaction = ContactSyncTransaction(h.api);
    expect(await run([row('one')]), isNull);
    expect(h.requests, isEmpty);
  });
  test('missing capability never falls into v2 writes', () async {
    h.respond = (_) => {'types': []};
    expect(await run([row('one')]), isNull);
    expect(h.requests, hasLength(1));
  });
  test('new device uses FULL and confirms all 100-item batches before commit',
      () async {
    full = false;
    revision = 0;
    final result = await run(List.generate(101, (i) => row('c$i')));
    expect(h.at('/status').single.queryParameters, {'deviceId': 'device-a'});
    expect(h.at('/sessions').single.data['mode'], 'FULL');
    expect(
        h.at('/batch').map((r) => (r.data['items'] as List).length), [100, 1]);
    expect(h.at('/complete').single.data['snapshotComplete'], isTrue);
    expect(result!.revision, 1);
    expect(result.fingerprints, hasLength(101));
  });
  test(
      'lost batch and completion responses replay identical request identities',
      () async {
    var batches = 0;
    var completions = 0;
    h.respond = (request) {
      if (request.path.endsWith('/batch') && batches++ == 0)
        throw lostResponse(request);
      if (request.path.endsWith('/complete') && completions++ == 0)
        throw lostResponse(request);
      return normal(request);
    };
    final result = await run([row('one'), row('new')], before: baseline());
    final batch = h.at('/batch');
    expect(batch, hasLength(2));
    expect(jsonEncode(batch[0].data), jsonEncode(batch[1].data));
    expect(batch[0].data['payloadHash'], matches(RegExp(r'^[a-f0-9]{64}$')));
    expect((batch[0].data['items'] as List).single['localContactId'], 'new');
    expect(h.at('/complete'), hasLength(2));
    expect(h.at('/complete').first.data, h.at('/complete').last.data);
    expect(result!.revision, 6);
  });
  for (final code in ['BATCH_RETRY', 'BATCH_CONFLICT', 'DEVICE_NOT_BOUND']) {
    test('$code has bounded retry and cannot complete a missing batch',
        () async {
      h.respond = (request) {
        if (request.path.endsWith('/batch'))
          throw contractError(request, code,
              status: code == 'DEVICE_NOT_BOUND' ? 403 : 409);
        return normal(request);
      };
      await expectLater(run([row('one')]), throwsA(anything));
      expect(h.at('/batch'), hasLength(code == 'BATCH_RETRY' ? 3 : 1));
      expect(h.at('/complete'), isEmpty);
    });
  }
  test('partial batch acknowledgement cannot advance the baseline', () async {
    h.respond = (request) => request.path.endsWith('/batch')
        ? {'syncSessionId': 's1', 'uploaded': 0, 'failed': 1}
        : normal(request);
    await expectLater(run([row('one')]), throwsA(isA<SyncContractException>()));
    expect(h.at('/complete'), isEmpty);
  });
  test('revision conflict starts a fresh FULL instead of relabelling old delta',
      () async {
    var first = true;
    h.respond = (request) {
      if (request.path.endsWith('/batch') && first) {
        first = false;
        revision = 7;
        throw contractError(request, 'REVISION_CONFLICT');
      }
      return normal(request);
    };
    final result = await run([row('one'), row('new')], before: baseline());
    expect(
        h.at('/sessions').map((r) => r.data['mode']), ['INCREMENTAL', 'FULL']);
    expect(h.at('/batch').last.data['baseRevision'], 7);
    expect(h.at('/batch').last.data['items'], hasLength(2));
    expect(h.at('/complete').single.data['deletedLocalContactIds'], isEmpty);
    expect(result!.revision, 8);
  });
  test('another device or mismatched revision is never used for deletion',
      () async {
    await run([row('one')], before: baseline(device: 'other-device'));
    expect(h.at('/sessions').single.data['mode'], 'FULL');
    expect(h.at('/complete').single.data['deletedLocalContactIds'], isEmpty);
  });
  test(
      'true empty collection commits an explicit device deletion with zero batches',
      () async {
    final result = await run([], before: baseline());
    expect(h.at('/batch'), isEmpty);
    expect(h.at('/complete').single.data['deletedLocalContactIds'],
        ['one', 'old']);
    expect(result!.fingerprints, isEmpty);
  });
  test('failed collection never opens a session or calls complete', () async {
    final result = await transaction.run(
        ownerUserId: 'owner',
        deviceId: 'device-a',
        collection:
            const ContactCollectionResult(ContactCollectionStatus.failed),
        isCurrent: () => true);
    expect(result, isNull);
    expect(h.requests, isEmpty);
  });
  test('account change while batch is pending prevents completion', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    h.respond = (request) async {
      if (request.path.endsWith('/batch')) {
        entered.complete();
        await release.future;
      }
      return normal(request);
    };
    final future = run([row('one')]);
    final assertion =
        expectLater(future, throwsA(isA<SyncContractException>()));
    await entered.future;
    current = false;
    release.complete();
    await assertion;
    expect(h.at('/complete'), isEmpty);
  });
  test('invalid completion receipt cannot produce a new baseline', () async {
    h.respond = (request) => request.path.endsWith('/complete')
        ? {
            'syncSessionId': 'another',
            'status': 'COMPLETED',
            'committedRevision': 6
          }
        : normal(request);
    await expectLater(run([row('one')]), throwsA(isA<SyncContractException>()));
  });
  test(
      'baseline persistence is owner/device scoped and logout clears only its owner',
      () async {
    final store = ContactSyncBaselineStore();
    await store.save(baseline(), isCurrent: () => true);
    await store.save(
        ContactSyncBaseline(
            ownerUserId: 'other',
            deviceId: 'device-a',
            revision: 9,
            fingerprints: {'x': 'y'}),
        isCurrent: () => true);
    expect((await store.read('owner', 'device-a'))!.revision, 5);
    expect(await store.read('owner', 'device-b'), isNull);
    await store.save(baseline(rev: 6), isCurrent: () => false);
    expect((await store.read('owner', 'device-a'))!.revision, 5);
    await store.clearOwner('owner');
    expect(await store.read('owner', 'device-a'), isNull);
    expect((await store.read('other', 'device-a'))!.revision, 9);
  });
}
