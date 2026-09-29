import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../api/sync_api.dart';
import '../api/sync_contract_support.dart';
import 'contact_sync_collector.dart';
import 'contact_sync_plan.dart';

class ContactSyncBaseline {
  ContactSyncBaseline(
      {required this.ownerUserId,
      required this.deviceId,
      required this.revision,
      required Map<String, String> fingerprints})
      : fingerprints = Map.unmodifiable(fingerprints);
  final String ownerUserId;
  final String deviceId;
  final int revision;
  final Map<String, String> fingerprints;

  Map<String, dynamic> toJson() => {
        'ownerUserId': ownerUserId,
        'deviceId': deviceId,
        'revision': revision,
        'fingerprints': fingerprints
      };

  static ContactSyncBaseline? fromJson(Map<String, dynamic> json) {
    final revision = json['revision'];
    final rows = json['fingerprints'];
    if (json['ownerUserId'] is! String ||
        json['deviceId'] is! String ||
        revision is! int ||
        revision < 0 ||
        rows is! Map ||
        rows.entries.any((e) => e.key is! String || e.value is! String)) {
      return null;
    }
    return ContactSyncBaseline(
        ownerUserId: json['ownerUserId'] as String,
        deviceId: json['deviceId'] as String,
        revision: revision,
        fingerprints: Map<String, String>.from(rows));
  }
}

/// No baseline is returned until every immutable batch is acknowledged and the
/// exact session completion receipt has been validated. The production gate
/// stays off independently of the server capability.
class ContactSyncTransaction {
  ContactSyncTransaction(
    this.api, {
    this.enabled = ContactSyncPlan.deviceScopedDeltaEnabled,
    this.retryDelay = const Duration(milliseconds: 250),
  });
  final SyncApi api;
  final bool enabled;
  final Duration retryDelay;

  Future<ContactSyncBaseline?> run({
    required String ownerUserId,
    required String deviceId,
    required ContactCollectionResult collection,
    required SyncRequestGuard isCurrent,
    ContactSyncBaseline? baseline,
    SyncStatusResponse? initialStatus,
  }) async {
    if (!enabled || !collection.succeeded) return null;
    if (ownerUserId.isEmpty || deviceId.isEmpty) {
      throw const SyncContractException('DEVICE_NOT_BOUND');
    }
    await checkSyncGuard(isCurrent);
    final current = List<LocalContactRecord>.unmodifiable(collection.records);
    final ids = current.map((row) => row.localContactId).toSet();
    if (ids.length != current.length || ids.contains('')) {
      throw const SyncContractException('INVALID_CONTACT_SNAPSHOT');
    }
    SyncStatusResponse status = initialStatus ??
        await retrySyncRequest(() => api.fetchStatus(deviceId: deviceId),
            isCurrent: isCurrent, delay: retryDelay);
    var forceFull = false;
    for (var round = 0; round < 2; round++) {
      await checkSyncGuard(isCurrent);
      if (!status.contactsDeltaV2 || status.deviceId != deviceId) return null;
      final revision = status.contacts.serverRevision;
      final matched = baseline != null &&
          baseline.ownerUserId == ownerUserId &&
          baseline.deviceId == deviceId &&
          baseline.revision == revision;
      final canDelta =
          !forceFull && matched && status.contacts.lastFullSyncAt != null;
      // A revision mismatch invalidates both the diff and the deletion list.
      final previous = matched ? baseline.fingerprints : <String, String>{};
      final plan = ContactSyncPlan.build(
          current: current,
          previous: previous,
          hasServerBaseline: canDelta,
          deviceScopedDelta: true);
      try {
        await checkSyncGuard(isCurrent);
        final session = await api.startContactSession(
            mode: canDelta ? 'INCREMENTAL' : 'FULL', deviceId: deviceId);
        await checkSyncGuard(isCurrent);
        if (session.syncSessionId.isEmpty) {
          throw const SyncContractException('INVALID_SYNC_SESSION');
        }
        for (var start = 0; start < plan.uploads.length; start += 100) {
          final end = (start + 100).clamp(0, plan.uploads.length);
          final items = List<ContactSyncItemPayload>.unmodifiable(
              plan.uploads.sublist(start, end).map((row) => row.toPayload()));
          final batchId = const Uuid().v4();
          final hash = sha256
              .convert(utf8.encode(
                  jsonEncode(items.map((row) => row.toJson()).toList())))
              .toString();
          final response = await retrySyncRequest(
              () => api.uploadContactBatch(
                  syncSessionId: session.syncSessionId,
                  items: items,
                  baseRevision: revision,
                  batchId: batchId,
                  payloadHash: hash),
              isCurrent: isCurrent,
              delay: retryDelay);
          if (!response.acknowledges(session.syncSessionId, items)) {
            throw const SyncContractException('CONTACT_BATCH_INCOMPLETE');
          }
        }
        final receipt = await retrySyncRequest(
            () => api.completeContactSession(
                syncSessionId: session.syncSessionId,
                baseRevision: revision,
                snapshotComplete: true,
                deletedLocalContactIds: plan.deletedIds),
            isCurrent: isCurrent,
            delay: retryDelay);
        if (receipt.syncSessionId != session.syncSessionId ||
            receipt.status != 'COMPLETED' ||
            receipt.committedRevision == null ||
            receipt.committedRevision! <= revision) {
          throw const SyncContractException('INVALID_CONTACT_RECEIPT');
        }
        return ContactSyncBaseline(
            ownerUserId: ownerUserId,
            deviceId: deviceId,
            revision: receipt.committedRevision!,
            fingerprints: plan.snapshot);
      } catch (error) {
        final code = syncErrorCode(error);
        if (round != 0 ||
            (code != 'REVISION_CONFLICT' && code != 'REQUIRE_FULL_SYNC'))
          rethrow;
        status = await retrySyncRequest(
            () => api.fetchStatus(deviceId: deviceId),
            isCurrent: isCurrent,
            delay: retryDelay);
        // Never silently attach a newer revision to an old diff. Start a fresh
        // FULL session once; a second conflict is left for the next sync run.
        forceFull = true;
        baseline = null;
      }
    }
    return null;
  }
}
