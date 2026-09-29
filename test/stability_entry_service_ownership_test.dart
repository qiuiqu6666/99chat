import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_game_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_my_config.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/privileged_game_user_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_service.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('privilege warmup and remote completions keep their original session',
      () async {
    final reads = <Completer<bool?>>[];
    final remotes = <Completer<GroupGameStatus>>[];
    final writes = <String>[];
    final service = PrivilegedGameUserService.forTesting(
      readLocal: (_) {
        final result = Completer<bool?>();
        reads.add(result);
        return result.future;
      },
      writeLocal: (owner, enabled) async => writes.add('$owner:$enabled'),
      fetchRemote: () {
        final result = Completer<GroupGameStatus>();
        remotes.add(result);
        return result.future;
      },
    );
    addTearDown(() async {
      service.clearSession();
      for (final read in reads) {
        if (!read.isCompleted) read.complete(false);
      }
      await tick();
      for (final remote in remotes) {
        if (!remote.isCompleted)
          remote.complete(const GroupGameStatus(gameEnabled: false));
      }
      await tick();
    });
    final old = service.activateSession(userId: 'owner-a');
    service.clearSession();
    final current = service.activateSession(userId: 'owner-b');
    reads[1].complete(false);
    await current;
    reads[0].complete(true);
    await old;
    expect(service.isPrivileged, isFalse,
        reason: 'Old disk snapshot cannot enable the new account');
    expect(remotes.length, 1, reason: 'Old warmup must not start network work');

    service.clearSession();
    final reentered = service.activateSession(userId: 'owner-b');
    reads.last.complete(false);
    await reentered;
    expect(remotes.length, 2,
        reason: 'A pending old flight cannot suppress a new session');
    remotes.first.complete(const GroupGameStatus(gameEnabled: true));
    await tick();
    expect(service.isPrivileged, isFalse);
    expect(writes, isEmpty,
        reason: 'Old network response is rejected before persistence');
    remotes.last.complete(const GroupGameStatus(gameEnabled: false));
    await tick();
    expect(writes, ['owner-b:false']);
  });

  test('game config warmup and remote completions keep their original session',
      () async {
    final reads = <Completer<SangongMyConfig?>>[];
    final remotes = <Completer<SangongMyConfig>>[];
    final writes = <String>[];
    final service = SangongMyConfigService.forTesting(
      readLocal: (_) {
        final result = Completer<SangongMyConfig?>();
        reads.add(result);
        return result.future;
      },
      writeLocal: (owner, config) async =>
          writes.add('$owner:${config.tenantId}'),
      fetchRemote: () {
        final result = Completer<SangongMyConfig>();
        remotes.add(result);
        return result.future;
      },
    );
    addTearDown(() async {
      service.clearSession();
      for (final read in reads) {
        if (!read.isCompleted) read.complete(null);
      }
      await tick();
      for (final remote in remotes) {
        if (!remote.isCompleted) remote.complete(const SangongMyConfig());
      }
      await tick();
    });
    final old = service.ensureHydrated(userId: 'owner-a');
    service.clearSession();
    final current = service.ensureHydrated(userId: 'owner-b');
    reads[1].complete(const SangongMyConfig(tenantId: 'new-tenant'));
    await current;
    reads[0].complete(const SangongMyConfig(tenantId: 'old-tenant'));
    await old;
    expect(service.config.tenantId, 'new-tenant');
    final oldRemote = service.refreshFromNetwork();
    service.clearSession();
    final reentered = service.ensureHydrated(userId: 'owner-b');
    reads.last.complete(const SangongMyConfig(tenantId: 'reentered'));
    await reentered;
    final newRemote = service.refreshFromNetwork();
    expect(remotes.length, 2);
    remotes.first.complete(const SangongMyConfig(tenantId: 'stale-remote'));
    await oldRemote;
    expect(service.config.tenantId, 'reentered');
    expect(writes, isEmpty);
    remotes.last.complete(const SangongMyConfig(tenantId: 'current-remote'));
    await newRemote;
    expect(service.config.tenantId, 'current-remote');
    expect(writes, ['owner-b:current-remote']);
  });
}
