import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/utils/phone_format.dart';

import '../api/sync_api.dart';
import 'sync_fingerprint.dart';

class LocalContactRecord {
  LocalContactRecord({
    required this.localContactId,
    required this.displayName,
    required this.phones,
    required this.fingerprint,
    this.takenAt,
  });

  final String localContactId;
  final String displayName;
  final List<String> phones;
  final String fingerprint;
  final DateTime? takenAt;

  ContactSyncItemPayload toPayload() => ContactSyncItemPayload(
        localContactId: localContactId,
        fingerprint: fingerprint,
        displayName: displayName,
        phones: phones,
        takenAt: takenAt,
      );
}

enum ContactCollectionStatus { success, permissionDenied, failed }

class ContactCollectionResult {
  const ContactCollectionResult(this.status, [this.records = const []]);
  final ContactCollectionStatus status;
  final List<LocalContactRecord> records;
  bool get succeeded => status == ContactCollectionStatus.success;
}

class ContactSyncCollector {
  // Lookup callers retain their empty-list fallback. Sync consumes the explicit
  // outcome so a platform failure can never become a deletion snapshot.
  static Future<List<LocalContactRecord>> collectAll() async =>
      (await collectResult()).records;

  static Future<ContactCollectionResult> collectResult() async {
    try {
      if (!await PermissionGuard.hasContactsForDeviceSync()) {
        return const ContactCollectionResult(
            ContactCollectionStatus.permissionDenied);
      }
      return ContactCollectionResult(ContactCollectionStatus.success,
          _normalize(await FlutterContacts.getContacts(withProperties: true)));
    } catch (error) {
      debugPrint('ContactSyncCollector: read contacts failed: $error');
      return const ContactCollectionResult(ContactCollectionStatus.failed);
    }
  }

  static List<LocalContactRecord> _normalize(List<Contact> contacts) {
    final records = <LocalContactRecord>[];
    for (final c in contacts) {
      final rawPhones = <String>[];
      for (final phone in c.phones) {
        final systemNormalized = phone.normalizedNumber.trim();
        if (systemNormalized.isNotEmpty) {
          rawPhones.add(systemNormalized);
        } else {
          rawPhones.add(phone.number);
        }
      }
      final normalized = SyncFingerprint.normalizePhoneList(rawPhones);
      final phones = normalized.isNotEmpty
          ? normalized
          : rawPhones
              .map(PhoneFormat.cleanContactPhoneRaw)
              .where((phone) => phone.isNotEmpty)
              .toList();
      if (phones.isEmpty) {
        continue;
      }
      final displayName = c.displayName.trim().isNotEmpty
          ? c.displayName.trim()
          : (c.name.first.isNotEmpty ? c.name.first : phones.first);
      final fingerprint = SyncFingerprint.contactFingerprint(
        displayName: displayName,
        phones: phones,
      );
      records.add(LocalContactRecord(
        localContactId: c.id,
        displayName: displayName,
        phones: phones,
        fingerprint: fingerprint,
      ));
    }
    return records;
  }
}
