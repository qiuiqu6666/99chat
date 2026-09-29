import 'contact_sync_collector.dart';

/// Delta requires server-side device ownership and idempotent completion.
/// The backend now exposes that contract; keep the production gate off until
/// device isolation and replay behavior have passed end-to-end validation.
class ContactSyncPlan {
  ContactSyncPlan._(this.uploads, this.deletedIds, this.snapshot, this.mode);
  static const bool deviceScopedDeltaEnabled = false;
  final List<LocalContactRecord> uploads;
  final List<String> deletedIds;
  final Map<String, String> snapshot;
  final String mode;

  factory ContactSyncPlan.build({
    required List<LocalContactRecord> current,
    required Map<String, String> previous,
    required bool hasServerBaseline,
    bool deviceScopedDelta = deviceScopedDeltaEnabled,
  }) {
    final snapshot = {
      for (final row in current) row.localContactId: row.fingerprint
    };
    final delta = deviceScopedDelta && hasServerBaseline;
    return ContactSyncPlan._(
      delta
          ? current
              .where((row) => previous[row.localContactId] != row.fingerprint)
              .toList()
          : current,
      previous.keys.where((id) => !snapshot.containsKey(id)).toList(),
      snapshot,
      hasServerBaseline ? 'INCREMENTAL' : 'FULL',
    );
  }
}
