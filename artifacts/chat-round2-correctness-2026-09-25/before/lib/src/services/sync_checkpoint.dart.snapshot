/// Durable cursor state for a backend-owned sync domain.
class SyncJobCheckpoint {
  const SyncJobCheckpoint({
    required this.ownerUserId,
    required this.domain,
    required this.scopeId,
    required this.accountGeneration,
    required this.snapshotRevision,
    required this.nextCursor,
    required this.hasMore,
    required this.persistedCount,
    required this.state,
    required this.updatedAt,
  });

  final String ownerUserId;
  final String domain;
  final String scopeId;
  final int accountGeneration;
  final String snapshotRevision;
  final String nextCursor;
  final bool hasMore;
  final int persistedCount;
  final String state;
  final int updatedAt;

  bool get isComplete => nextCursor.isEmpty && !hasMore;
}
