/// Due-only recovery predicate. Completed/abandoned rows stay durable for
/// idempotency, but the worker never scans them. `next_retry_at <= now`
/// is the due fence; live processing rows stay excluded by the stale clause.
class ImInboxRecoveryQuery {
  static const pendingPredicate =
      "status <> 'completed' AND status <> 'abandoned'";
  static const indexName = 'idx_message_event_recovery_due';
  static const legacyIndexName = 'idx_message_event_recovery_pending';
  static const orderBy = 'recovery_priority ASC, next_retry_at ASC';

  static String where({required bool hasDomainGeneration}) => <String>[
        'owner_user_id = ?',
        'account_generation = ?',
        if (hasDomainGeneration) 'domain_generation = ?',
        pendingPredicate,
        'next_retry_at <= ?',
        "(status IN ('prepared', 'metadataCommitted', 'projectionPublished') "
            "OR (status = 'processing' AND "
            '(processing_started_at IS NULL OR processing_started_at <= ?)))',
      ].join(' AND ');

  static String pendingWhere({required bool hasDomainGeneration}) => <String>[
        'owner_user_id = ?',
        'account_generation = ?',
        if (hasDomainGeneration) 'domain_generation = ?',
        pendingPredicate,
      ].join(' AND ');

  static List<Object?> arguments({
    required String ownerUserId,
    required int accountGeneration,
    int? domainGeneration,
    required int nowMs,
    required int staleBeforeMs,
  }) =>
      <Object?>[
        ownerUserId,
        accountGeneration,
        if (domainGeneration != null) domainGeneration,
        nowMs,
        staleBeforeMs,
      ];

  static List<Object?> pendingArguments({
    required String ownerUserId,
    required int accountGeneration,
    int? domainGeneration,
  }) =>
      <Object?>[
        ownerUserId,
        accountGeneration,
        if (domainGeneration != null) domainGeneration,
      ];
}
