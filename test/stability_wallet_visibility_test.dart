import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_controller.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_snapshot_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order_events.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_controller.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_updates.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'stability_wallet_ownership_test.dart'
    show ControlledWalletRepository, snapshot;

class MemorySnapshotStore extends WalletSnapshotLocalStore {
  @override
  Future<WalletDto?> read(String owner) async => null;
  @override
  Future<void> write(String owner, WalletDto data) async {}
}

class CommitRepository extends ControlledWalletRepository
    implements WalletRecordLocalUpdates {
  final commits = StreamController<WalletRecordCommit>.broadcast(sync: true);
  var localReads = 0;
  @override
  Stream<WalletRecordCommit> get recordCommits => commits.stream;
  @override
  String recordScopeKey(HistoryRecordFilter filter) => filter.name;
  @override
  Future<List<WalletRecordDto>> readLocalRecords(
      HistoryRecordFilter filter) async {
    localReads++;
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() async {
    await ApiClient.instance.clearToken();
  });

  test('hidden balance bursts produce zero requests and one refresh on return',
      () async {
    final repo = ControlledWalletRepository();
    final controller =
        WalletController(repo: repo, localStore: MemorySnapshotStore());
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications++;
    });
    controller.setActive(false);
    for (var i = 0; i < 10; i++) {
      WalletOrderEvents.notifyBalance();
    }
    await Future<void>.delayed(Duration.zero);
    expect(repo.wallets, isEmpty);
    expect(notifications, 0);
    expect(controller.hasDeferredRefresh, isTrue);
    expect(controller.setActive(true), isTrue);
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(repo.wallets.length, 1);
    repo.wallets.single.complete(snapshot('fresh'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.totalBal, 'fresh');
    expect(controller.hasDeferredRefresh, isFalse);
  });

  test('scoped ledger commits coalesce while hidden and only reread local data',
      () async {
    await ApiClient.instance.saveToken('token', userId: 'ledger-owner');
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: 'ledger-owner');
    final repo = CommitRepository();
    final controller = WalletRecordController(repo: repo);
    addTearDown(() async {
      await repo.commits.close();
    });
    final load = controller.load();
    repo.records.single.complete([]);
    await load;
    controller.setActive(false);
    for (var i = 0; i < 10; i++) {
      repo.commits.add(WalletRecordCommit(identity, 'all'));
    }
    repo.commits.add(WalletRecordCommit(identity, 'transfer'));
    repo.commits.add(WalletRecordCommit(
        SessionIdentity(ownerUserId: 'old', generation: identity.generation),
        'all'));
    expect(repo.localReads, 0);
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(repo.localReads, 1);
    expect(repo.records.length, 1,
        reason: 'Commit refresh never starts another network synchronization');
    repo.commits.add(WalletRecordCommit(identity, 'transfer'));
    await Future<void>.delayed(Duration.zero);
    expect(repo.localReads, 1);
    controller.dispose();
    repo.commits.add(WalletRecordCommit(identity, 'all'));
    await Future<void>.delayed(Duration.zero);
    expect(repo.localReads, 1);
  });

  test(
      'hidden dirty history does not reread another session before its own load',
      () async {
    await ApiClient.instance.saveToken('token', userId: 'old-ledger-owner');
    final oldIdentity = SessionIdentityService.instance
        .capture(ownerUserId: 'old-ledger-owner');
    final repo = CommitRepository();
    final controller = WalletRecordController(repo: repo);
    addTearDown(() async {
      controller.dispose();
      await repo.commits.close();
    });
    final load = controller.load();
    repo.records.single.complete([]);
    await load;
    controller.setActive(false);
    repo.commits.add(WalletRecordCommit(oldIdentity, 'all'));
    await ApiClient.instance.saveToken('new-token', userId: 'new-ledger-owner');
    SessionIdentityService.instance.invalidate();
    final newIdentity = SessionIdentityService.instance
        .capture(ownerUserId: 'new-ledger-owner');
    repo.commits.add(WalletRecordCommit(newIdentity, 'all'));
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(repo.localReads, 0);
    final reload = controller.load();
    repo.records.last.complete([]);
    await reload;
    repo.commits.add(WalletRecordCommit(newIdentity, 'all'));
    await Future<void>.delayed(Duration.zero);
    expect(repo.localReads, 1);
  });
}
