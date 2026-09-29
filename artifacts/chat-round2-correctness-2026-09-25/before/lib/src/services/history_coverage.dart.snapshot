/// Public application boundary for per-account, per-conversation history
/// continuity metadata.
///
/// The UIKit package owns the shape of the metadata because it also owns the
/// reconciliation writer.  The app owns persistence and session scoping.  The
/// aliases below keep that boundary explicit without creating a second copy
/// of the coverage state.
library;

import 'package:tencent_cloud_chat_demo/src/services/message_history_coverage_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';

typedef HistoryCoverage = MessageHistoryCoverage;
typedef HistoryCoverageStatus = MessageHistoryCoverageStatus;
typedef HistoryCoverageDirection = MessageHistoryCoverageDirection;
typedef HistoryCoverageHole = MessageHistoryHole;
typedef HistoryCoverageHoleStatus = MessageHistoryHoleStatus;
typedef HistoryCoverageRange = MessageHistoryCoverageRange;
typedef HistoryCoveragePage = MessageHistoryPageRecord;

/// Account-scoped persistence facade used by the history coordinator.
///
/// [MessageHistoryCoverageStore] is retained as the storage implementation so
/// existing migrations and clear-epoch safeguards remain in one place.
class HistoryCoverageStore implements MessageHistoryCoverageRepository {
  HistoryCoverageStore._();

  static final HistoryCoverageStore instance = HistoryCoverageStore._();

  MessageHistoryCoverageStore get _delegate =>
      MessageHistoryCoverageStore.instance;

  @override
  Future<HistoryCoverage?> load(String conversationID) =>
      _delegate.load(conversationID);

  Future<HistoryCoverage?> loadForOwner(
    String ownerUserId,
    String conversationID,
  ) =>
      _delegate.loadForOwner(ownerUserId, conversationID);

  @override
  Future<void> save(HistoryCoverage coverage) => _delegate.save(coverage);

  Future<void> saveForOwner(
    String ownerUserId,
    HistoryCoverage coverage,
  ) =>
      _delegate.saveForOwner(ownerUserId, coverage);

  @override
  Future<void> clearConversation(
    String conversationID, {
    required bool isGroup,
    required int clearEpoch,
  }) =>
      _delegate.clearConversation(
        conversationID,
        isGroup: isGroup,
        clearEpoch: clearEpoch,
      );

  @override
  Future<void> clearSession() => _delegate.clearSession();

  Future<void> clearForOwner(String? ownerUserId) =>
      _delegate.clearForOwner(ownerUserId);
}
