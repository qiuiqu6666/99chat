import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/user_api.dart';
import 'package:tencent_cloud_chat_demo/src/env.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_sync_collector.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/phone_format.dart';
import 'package:tencent_cloud_chat_demo/utils/user_api_error_message.dart';

enum ContactFriendStatus {
  unregistered,
  registeredNotFriend,
  registeredFriend,
}

class ContactFriendEntry {
  ContactFriendEntry({
    required this.localContactId,
    required this.displayName,
    required this.primaryPhone,
    required this.phones,
    required this.status,
    this.user,
  });

  final String localContactId;
  final String displayName;
  final String primaryPhone;
  final List<String> phones;
  final ContactFriendStatus status;
  final UserSearchResult? user;
}

class ContactFriendsLookupService {
  ContactFriendsLookupService._();

  static const int _batchSize = 500;

  static Future<List<ContactFriendEntry>> loadEntries({
    void Function(List<ContactFriendEntry>)? onPartial,
    bool Function()? isCancelled,
  }) async {
    if (!await PermissionGuard.hasContactsForDeviceSync()) {
      throw ContactFriendsLookupException(
        AppI18n.current.t(
          zhHans: '未开启通讯录权限，无法查看通讯录好友',
          zhHant: '未開啟通訊錄權限，無法查看通訊錄好友',
          en: 'Contacts permission is required to view phone contacts.',
          ja: '連絡先を表示するには連絡先権限が必要です。',
          ko: '연락처를 보려면 연락처 권한이 필요합니다.',
        ),
      );
    }

    final contacts = await ContactSyncCollector.collectAll();
    if (contacts.isEmpty) {
      return const [];
    }

    return matchEntries(contacts, onPartial: onPartial, isCancelled: isCancelled);
  }

  static Future<List<ContactFriendEntry>> matchEntries(
    List<LocalContactRecord> contacts, {
    void Function(List<ContactFriendEntry>)? onPartial,
    bool Function()? isCancelled,
    Future<Map<String, ContactMatchItem>> Function(List<String>)? matchBatch,
  }) async {
    final entries = <ContactFriendEntry>[];
    for (var start = 0; start < contacts.length; start += _batchSize) {
      if (isCancelled?.call() == true) return entries;
      final batchContacts = contacts.skip(start).take(_batchSize);
      final uniquePhones = PhoneFormat.filterForContactMatch(
          batchContacts.expand((contact) => contact.phones));
      Map<String, ContactMatchItem> phoneLookup;
      try {
        phoneLookup = matchBatch != null ? await matchBatch(uniquePhones)
            : await _matchPhones(uniquePhones, isCancelled: isCancelled);
      } on ContactFriendsLookupException {
        phoneLookup = <String, ContactMatchItem>{};
      }
      if (isCancelled?.call() == true) return entries;
      for (final contact in batchContacts) {
        ContactMatchItem? matched;
        String primaryPhone = contact.phones.first;
        for (final phone in contact.phones) {
          final lookupKey = _resolveLookupKey(phone);
          if (lookupKey == null) {
            continue;
          }
          final hit = phoneLookup[lookupKey];
          if (hit != null && hit.registered) {
            matched = hit;
            primaryPhone = phone;
            break;
          }
        }

        final status = _resolveStatus(matched);
        entries.add(
          ContactFriendEntry(
            localContactId: contact.localContactId,
            displayName: contact.displayName,
            primaryPhone: PhoneFormat.cleanContactPhoneRaw(primaryPhone),
            phones: contact.phones
                .map(PhoneFormat.cleanContactPhoneRaw)
                .where((phone) => phone.isNotEmpty)
                .toList(),
            status: status,
            user: matched?.toUserSearchResult(),
          ),
        );
      }

      onPartial?.call(List<ContactFriendEntry>.unmodifiable(entries));
      await Future<void>.delayed(Duration.zero);
    }

    entries.sort(ContactFriendsLookupService.compareEntries);
    return entries;
  }

  static int compareEntries(ContactFriendEntry a, ContactFriendEntry b) =>
      _compareEntries(a, b);

  static ContactFriendStatus _resolveStatus(ContactMatchItem? match) {
    if (match == null || !match.registered) {
      return ContactFriendStatus.unregistered;
    }
    final userId = ChatIdFormat.rawUserUid(match.userId ?? '');
    if (userId.isEmpty) {
      return ContactFriendStatus.unregistered;
    }
    if (match.isFriend == true) {
      return ContactFriendStatus.registeredFriend;
    }
    if (match.isFriend == false) {
      return ContactFriendStatus.registeredNotFriend;
    }
    return ContactFriendStatus.registeredNotFriend;
  }

  static int _compareEntries(ContactFriendEntry a, ContactFriendEntry b) {
    final rankA = _statusRank(a.status);
    final rankB = _statusRank(b.status);
    if (rankA != rankB) {
      return rankA.compareTo(rankB);
    }
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  static int _statusRank(ContactFriendStatus status) {
    switch (status) {
      case ContactFriendStatus.registeredFriend:
        return 0;
      case ContactFriendStatus.registeredNotFriend:
        return 1;
      case ContactFriendStatus.unregistered:
        return 2;
    }
  }

  static Future<Map<String, ContactMatchItem>> _matchPhones(List<String> phones,
      {bool Function()? isCancelled}) async {
    final lookup = <String, ContactMatchItem>{};
    if (phones.isEmpty) {
      return lookup;
    }

    for (var i = 0; i < phones.length; i += _batchSize) {
      if (isCancelled?.call() == true) return lookup;
      final end =
          (i + _batchSize > phones.length) ? phones.length : i + _batchSize;
      final batch = phones.sublist(i, end);
      final items = await _matchPhoneBatch(batch);
      for (final item in items) {
        lookup[item.phone] = item;
      }
    }
    return lookup;
  }

  static Future<List<ContactMatchItem>> _matchPhoneBatch(
    List<String> phones,
  ) async {
    try {
      return await UserApi.instance.matchContacts(
        phones: phones,
        phoneCountry: AppEnv.defaultPhoneCountry,
        includeFriendStatus: true,
      );
    } on DioError catch (e) {
      if (_isInvalidInput(e) && phones.length > 1) {
        final filtered = PhoneFormat.filterForContactMatch(phones);
        if (filtered.isNotEmpty && filtered.length < phones.length) {
          try {
            return await UserApi.instance.matchContacts(
              phones: filtered,
              phoneCountry: AppEnv.defaultPhoneCountry,
              includeFriendStatus: true,
            );
          } on DioError catch (retryError) {
            throw ContactFriendsLookupException(
              UserApiErrorMessage.fromContactMatch(retryError),
            );
          }
        }
      }
      throw ContactFriendsLookupException(
          UserApiErrorMessage.fromContactMatch(e));
    }
  }

  static String? _resolveLookupKey(String phone) {
    final resolved = PhoneFormat.isValidE164(phone)
        ? phone.trim()
        : PhoneFormat.tryResolveContactPhone(phone);
    if (resolved == null || !PhoneFormat.isValidForContactMatch(resolved)) {
      return null;
    }
    return resolved;
  }

  static bool _isInvalidInput(DioError e) {
    final data = e.response?.data;
    if (data is Map) {
      return data['code']?.toString() == 'INVALID_INPUT';
    }
    return false;
  }
}

class ContactFriendsLookupException implements Exception {
  ContactFriendsLookupException(this.message);

  final String message;

  @override
  String toString() => message;
}
