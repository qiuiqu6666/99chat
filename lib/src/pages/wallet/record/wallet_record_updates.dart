import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import '../wallet_repository.dart';
import 'wallet_record_models.dart';

/// Committed local ledger data, scoped to the account and exact server query.
class WalletRecordCommit {
  const WalletRecordCommit(this.identity, this.scopeKey);
  final SessionIdentity identity;
  final String scopeKey;
}

/// Optional capability: a commit refresh must only reread local data.
abstract interface class WalletRecordLocalUpdates {
  Stream<WalletRecordCommit> get recordCommits;
  String recordScopeKey(HistoryRecordFilter filter);
  Future<List<WalletRecordDto>> readLocalRecords(HistoryRecordFilter filter);
}
