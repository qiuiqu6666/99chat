import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'sync_contract_support.dart';

import 'api_client.dart';

/// Device backup sync API.
///
/// This file intentionally follows the backend sync contract:
/// - photos/check: { syncSessionId, items: [...] }
/// - photos/init-upload: one item payload with syncSessionId
/// - photos/complete: { uploadUuid }
/// - photos/sessions/complete: { syncSessionId }
class SyncApi {
  SyncApi._()
      : _overrideDio = null,
        _overrideDeviceId = null;
  SyncApi.withDio(Dio dio, {required String deviceId})
      : _overrideDio = dio,
        _overrideDeviceId = deviceId;
  final Dio? _overrideDio;
  final String? _overrideDeviceId;
  String get _deviceId => _overrideDeviceId ?? ApiClient.instance.deviceId;
  static final SyncApi instance = SyncApi._();

  Dio get _dio => _overrideDio ?? ApiClient.instance.dio;

  Future<SyncStatusResponse> fetchStatus({String? deviceId}) async {
    final device = deviceId ?? _deviceId;
    final res = await _dio.get('/me/sync/status', queryParameters: {
      if (device.isNotEmpty) 'deviceId': device,
    });
    return SyncStatusResponse.fromJson(_unwrapApiData(res.data),
        deviceId: device.isEmpty ? null : device);
  }

  Future<ContactSessionResponse> startContactSession({
    required String mode,
    String? deviceId,
  }) async {
    final res = await _dio.post('/me/sync/contacts/sessions', data: {
      'mode': mode,
      'deviceId': deviceId ?? _deviceId,
    });
    return ContactSessionResponse.fromJson(_unwrapApiData(res.data));
  }

  Future<ContactBatchResponse> uploadContactBatch({
    required String syncSessionId,
    required List<ContactSyncItemPayload> items,
    int? baseRevision,
    String? batchId,
    String? payloadHash,
  }) async {
    final payload = items.map((e) => e.toJson()).toList();
    final v2 = baseRevision != null || batchId != null || payloadHash != null;
    if (v2 &&
        (baseRevision == null ||
            baseRevision < 0 ||
            batchId == null ||
            batchId.isEmpty ||
            batchId.length > 64 ||
            payloadHash == null ||
            sha256.convert(utf8.encode(jsonEncode(payload))).toString() !=
                payloadHash)) {
      throw const SyncContractException('INVALID_BATCH_IDENTITY');
    }
    final res = await _dio.post('/me/sync/contacts/batch', data: {
      'syncSessionId': syncSessionId,
      if (v2) 'baseRevision': baseRevision,
      if (v2) 'batchId': batchId,
      if (v2) 'payloadHash': payloadHash,
      'items': payload,
    });
    return ContactBatchResponse.fromJson(_unwrapApiData(res.data));
  }

  Future<ContactCompleteResponse> completeContactSession({
    required String syncSessionId,
    List<String> deletedLocalContactIds = const [],
    int? baseRevision,
    bool? snapshotComplete,
  }) async {
    if ((baseRevision == null) != (snapshotComplete == null) ||
        (baseRevision != null && baseRevision < 0)) {
      throw const SyncContractException('INVALID_COMPLETION_IDENTITY');
    }
    final res = await _dio.post('/me/sync/contacts/complete', data: {
      'syncSessionId': syncSessionId,
      'deletedLocalContactIds': deletedLocalContactIds,
      if (baseRevision != null) 'baseRevision': baseRevision,
      if (snapshotComplete != null) 'snapshotComplete': snapshotComplete,
    });
    return ContactCompleteResponse.fromJson(_unwrapApiData(res.data));
  }

  Future<PhotoSessionResponse> startPhotoSession({
    required String mode,
  }) async {
    final res = await _dio.post('/me/sync/photos/sessions', data: {
      'mode': mode,
      'deviceId': _deviceId,
    });
    return PhotoSessionResponse.fromJson(_unwrapApiData(res.data));
  }

  Future<void> completePhotoSession({required String syncSessionId}) async {
    final res = await _dio.post('/me/sync/photos/sessions/complete', data: {
      'syncSessionId': syncSessionId,
    });
    _unwrapApiData(res.data);
  }

  Future<PhotoCheckResponse> checkPhoto(PhotoCheckRequest request) async {
    final res =
        await _dio.post('/me/sync/photos/check', data: request.toJson());
    return PhotoCheckResponse.fromJson(_unwrapApiData(res.data));
  }

  Future<PhotoInitUploadResponse> initPhotoUpload(
    PhotoInitUploadRequest request,
  ) async {
    final res =
        await _dio.post('/me/sync/photos/init-upload', data: request.toJson());
    return PhotoInitUploadResponse.fromJson(_unwrapApiData(res.data));
  }

  Future<PhotoCompleteResponse> completePhotoUpload({
    required String uploadUuid,
  }) async {
    final res = await _dio.post('/me/sync/photos/complete', data: {
      'uploadUuid': uploadUuid,
    });
    return PhotoCompleteResponse.fromJson(_unwrapApiData(res.data));
  }
}

Map<String, dynamic> _unwrapApiData(dynamic raw) {
  if (raw is! Map) {
    throw const SyncContractException('INVALID_SYNC_RESPONSE');
  }
  final json = Map<String, dynamic>.from(raw);
  final code = json['code'];
  if (code != null && code != 0 && code != '0') {
    throw SyncContractException(code.toString());
  }
  final inner = json['data'];
  if (inner is Map) {
    return Map<String, dynamic>.from(inner);
  }
  return json;
}

int _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _syncTypeKey(dynamic value) {
  final raw = value?.toString().trim().toUpperCase() ?? '';
  switch (raw) {
    case 'CONTACT':
    case 'CONTACTS':
      return 'contacts';
    case 'PHOTO':
    case 'PHOTOS':
    case 'ALBUM':
    case 'GALLERY':
      return 'photos';
    case 'VIDEO':
    case 'VIDEOS':
      return 'videos';
  }
  return raw.toLowerCase();
}

class SyncTypeState {
  SyncTypeState({
    this.lastFullSyncAt,
    this.lastIncrementalSyncAt,
    this.serverRevision = 0,
  });

  final DateTime? lastFullSyncAt;
  final DateTime? lastIncrementalSyncAt;
  final int serverRevision;

  factory SyncTypeState.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return SyncTypeState();
    }
    return SyncTypeState(
      lastFullSyncAt: _parseTime(json['lastFullSyncAt']),
      lastIncrementalSyncAt: _parseTime(json['lastIncrementalSyncAt']),
      serverRevision: _readInt(json['serverRevision'] ?? json['revision']),
    );
  }
}

class SyncStatusResponse {
  SyncStatusResponse(
      {required this.contacts,
      required this.photos,
      SyncTypeState? videos,
      this.contactsDeltaV2 = false,
      this.deviceId})
      : videos = videos ?? SyncTypeState();

  final SyncTypeState contacts;
  final SyncTypeState photos;
  final SyncTypeState videos;
  final bool contactsDeltaV2;

  /// Captured request scope, not inferred from an account-level response.
  final String? deviceId;

  factory SyncStatusResponse.fromJson(Map<String, dynamic> json,
      {String? deviceId}) {
    final byType = <String, Map<String, dynamic>>{};
    final types = json['types'];
    if (types is List) {
      for (final item in types) {
        if (item is! Map) continue;
        final payload = Map<String, dynamic>.from(item);
        final key = _syncTypeKey(
          payload['syncType'] ?? payload['type'] ?? payload['name'],
        );
        if (key.isNotEmpty) {
          byType[key] = payload;
        }
      }
    }

    Map<String, dynamic>? readState(String key) {
      final direct = json[key];
      if (direct is Map) return Map<String, dynamic>.from(direct);
      return byType[key];
    }

    return SyncStatusResponse(
      contacts: SyncTypeState.fromJson(readState('contacts')),
      photos: SyncTypeState.fromJson(readState('photos')),
      videos: SyncTypeState.fromJson(readState('videos')),
      contactsDeltaV2: json['contactsDeltaV2'] == true,
      deviceId: deviceId,
    );
  }
}

class ContactSessionResponse {
  ContactSessionResponse({required this.syncSessionId});

  final String syncSessionId;

  factory ContactSessionResponse.fromJson(Map<String, dynamic> json) {
    return ContactSessionResponse(
      syncSessionId:
          (json['syncSessionId'] ?? json['sessionUuid'] ?? '').toString(),
    );
  }
}

class PhotoSessionResponse {
  PhotoSessionResponse({required this.syncSessionId});

  final String syncSessionId;

  factory PhotoSessionResponse.fromJson(Map<String, dynamic> json) {
    return PhotoSessionResponse(
      syncSessionId:
          (json['syncSessionId'] ?? json['sessionUuid'] ?? '').toString(),
    );
  }
}

class ContactBatchResponse {
  ContactBatchResponse({
    this.uploaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.syncSessionId,
    this.results = const [],
  });

  final String? syncSessionId;
  final List<Map<String, dynamic>> results;
  bool acknowledges(String sessionId, List<ContactSyncItemPayload> items) {
    final ids = results.map((row) => row['localContactId']).toSet();
    return syncSessionId == sessionId &&
        failed == 0 &&
        uploaded >= 0 &&
        skipped >= 0 &&
        uploaded + skipped == items.length &&
        results.length == items.length &&
        ids.length == items.length &&
        items.every((item) => ids.contains(item.localContactId)) &&
        results.every(
            (row) => row['status'] == 'UPLOADED' || row['status'] == 'SKIPPED');
  }

  final int uploaded;
  final int skipped;
  final int failed;

  factory ContactBatchResponse.fromJson(Map<String, dynamic> json) {
    return ContactBatchResponse(
      uploaded: _readInt(json['uploaded'] ?? json['uploadedCount']),
      skipped: _readInt(json['skipped'] ?? json['skippedCount']),
      failed: _readInt(json['failed'] ?? json['failedCount']),
      syncSessionId: json['syncSessionId']?.toString(),
      results: json['results'] is List
          ? (json['results'] as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : const [],
    );
  }
}

class ContactCompleteResponse {
  ContactCompleteResponse(
      {this.syncSessionId,
      this.status,
      this.committedRevision,
      this.deleted = 0});
  final String? syncSessionId;
  final String? status;
  final int? committedRevision;
  final int deleted;
  factory ContactCompleteResponse.fromJson(Map<String, dynamic> json) =>
      ContactCompleteResponse(
          syncSessionId: json['syncSessionId']?.toString(),
          status: json['status']?.toString(),
          deleted: _readInt(json['deleted']),
          committedRevision: json['committedRevision'] is int
              ? json['committedRevision'] as int
              : null);
}

class ContactSyncItemPayload {
  ContactSyncItemPayload({
    required this.localContactId,
    required this.fingerprint,
    required List<String> phones,
    this.displayName,
    this.takenAt,
  }) : phones = List.unmodifiable(phones);

  final String localContactId;
  final String fingerprint;
  final String? displayName;
  final List<String> phones;
  final DateTime? takenAt;

  Map<String, dynamic> toJson() => {
        'localContactId': localContactId,
        'fingerprint': fingerprint,
        'displayName': displayName ?? '',
        'phones': phones,
        'updatedAt': takenAt == null ? null : _unixSeconds(takenAt!),
      };
}

class PhotoSyncItemPayload {
  PhotoSyncItemPayload({
    required this.localAssetId,
    required this.contentHash,
    required this.sizeBytes,
    required this.mediaType,
    required this.mimeType,
    this.takenAt,
    this.width,
    this.height,
    this.duration,
  });

  final String localAssetId;
  final String contentHash;
  final int sizeBytes;
  final String mediaType; // IMAGE | VIDEO
  final String mimeType;
  final DateTime? takenAt;
  final int? width;
  final int? height;

  /// Video duration in seconds. Required by backend for VIDEO items.
  final int? duration;

  bool get isVideo => mediaType.trim().toUpperCase() == 'VIDEO';

  Map<String, dynamic> toJson() => {
        'localAssetId': localAssetId,
        'contentHash': contentHash,
        'sizeBytes': sizeBytes,
        if (takenAt != null) 'takenAt': _unixSeconds(takenAt!),
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (isVideo) 'duration': duration ?? 0,
        'mediaType': isVideo ? 'VIDEO' : 'IMAGE',
        'mimeType': mimeType,
      };
}

class PhotoCheckRequest {
  PhotoCheckRequest({
    required this.syncSessionId,
    required this.items,
  });

  factory PhotoCheckRequest.single({
    required String syncSessionId,
    required PhotoSyncItemPayload item,
  }) {
    return PhotoCheckRequest(syncSessionId: syncSessionId, items: [item]);
  }

  final String syncSessionId;
  final List<PhotoSyncItemPayload> items;

  Map<String, dynamic> toJson() => {
        'syncSessionId': syncSessionId,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

class PhotoCheckResponse {
  PhotoCheckResponse({
    required this.action,
    this.photoUuid,
    this.originUrl,
    this.thumbUrl,
    this.previewUrl,
  });

  /// NEED_UPLOAD | ALREADY_EXISTS | SKIP_TOO_LARGE | FILE_TOO_LARGE
  final String action;
  final String? photoUuid;
  final String? originUrl;
  final String? thumbUrl;
  final String? previewUrl;

  String get normalizedAction => action.trim().toUpperCase();

  bool get alreadyExists {
    final value = normalizedAction;
    return value == 'ALREADY_EXISTS' ||
        value == 'EXISTS' ||
        value == 'SKIPPED' ||
        value == 'UPLOADED' ||
        value == 'DUPLICATE' ||
        value == 'NO_NEED_UPLOAD';
  }

  bool get skipTooLarge {
    final value = normalizedAction;
    return value == 'SKIP_TOO_LARGE' ||
        value == 'TOO_LARGE' ||
        value == 'FILE_TOO_LARGE';
  }

  factory PhotoCheckResponse.fromJson(Map<String, dynamic> json) {
    final payload = _firstResult(json);
    return PhotoCheckResponse(
      action: (payload['action'] ??
              payload['status'] ??
              payload['state'] ??
              'NEED_UPLOAD')
          .toString(),
      photoUuid: (payload['photoUuid'] ?? payload['photoId'])?.toString(),
      originUrl: payload['originUrl']?.toString(),
      thumbUrl: payload['thumbUrl']?.toString(),
      previewUrl: payload['previewUrl']?.toString(),
    );
  }
}

class PhotoInitUploadRequest {
  PhotoInitUploadRequest({
    required this.syncSessionId,
    required this.item,
    this.acceptAlreadyCommitted = false,
  });

  final String syncSessionId;
  final PhotoSyncItemPayload item;
  final bool acceptAlreadyCommitted;

  /// init-upload request body fields are aligned with check item fields.
  Map<String, dynamic> toJson() => {
        'syncSessionId': syncSessionId,
        ...item.toJson(),
        if (acceptAlreadyCommitted) 'acceptAlreadyCommitted': true,
      };
}

class PhotoInitUploadResponse {
  PhotoInitUploadResponse({
    required this.uploadUuid,
    required this.photoUuid,
    required this.presignedUrl,
    this.ossOriginKey,
    this.uploadState,
    this.receipt,
    this.committedAt,
  });

  final String uploadUuid;
  final String photoUuid;
  final String presignedUrl;
  final String? ossOriginKey;
  final String? uploadState;
  final PhotoCompleteResponse? receipt;
  final DateTime? committedAt;
  bool get alreadyCommitted => uploadState == 'ALREADY_COMMITTED';

  factory PhotoInitUploadResponse.fromJson(Map<String, dynamic> json) {
    final payload = _firstResult(json);
    return PhotoInitUploadResponse(
      uploadUuid:
          (payload['uploadUuid'] ?? payload['uploadId'] ?? '').toString(),
      photoUuid: (payload['photoUuid'] ?? payload['photoId'] ?? '').toString(),
      presignedUrl: (payload['presignedPutUrl'] ??
              payload['presignedUrl'] ??
              payload['uploadUrl'] ??
              '')
          .toString(),
      ossOriginKey: payload['ossOriginKey']?.toString(),
      uploadState: payload['uploadState']?.toString(),
      receipt: PhotoCompleteResponse.fromJson(payload),
      committedAt: _parseTime(payload['committedAt']),
    );
  }
}

class PhotoCompleteResponse {
  PhotoCompleteResponse({
    required this.photoUuid,
    this.localAssetId,
    this.contentHash,
    this.sizeBytes,
    this.width,
    this.height,
    this.duration,
    this.mimeType,
    this.status,
    this.mediaType,
    this.originUrl,
    this.thumbUrl,
    this.previewUrl,
    this.takenAt,
  });

  final String photoUuid;
  final String? localAssetId;
  final String? contentHash;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? duration;
  final String? mimeType;
  final String? status;
  final String? mediaType;
  final String? originUrl;
  final String? thumbUrl;
  final String? previewUrl;
  final DateTime? takenAt;

  factory PhotoCompleteResponse.fromJson(Map<String, dynamic> json) {
    return PhotoCompleteResponse(
      photoUuid: (json['photoUuid'] ?? json['photoId'] ?? '').toString(),
      status: json['status']?.toString(),
      localAssetId: json['localAssetId']?.toString(),
      contentHash: json['contentHash']?.toString(),
      sizeBytes: json['sizeBytes'] == null ? null : _readInt(json['sizeBytes']),
      width: json['width'] == null ? null : _readInt(json['width']),
      height: json['height'] == null ? null : _readInt(json['height']),
      duration: json['duration'] == null ? null : _readInt(json['duration']),
      mimeType: json['mimeType']?.toString(),
      mediaType: json['mediaType']?.toString(),
      originUrl: json['originUrl']?.toString(),
      thumbUrl: json['thumbUrl']?.toString(),
      previewUrl: json['previewUrl']?.toString(),
      takenAt: _parseTime(json['takenAt']),
    );
  }
}

Map<String, dynamic> _firstResult(Map<String, dynamic> json) {
  final results = json['results'] ?? json['items'];
  if (results is List && results.isNotEmpty && results.first is Map) {
    return Map<String, dynamic>.from(results.first as Map);
  }
  final result = json['result'];
  if (result is Map) {
    return Map<String, dynamic>.from(result);
  }
  return json;
}

int _unixSeconds(DateTime value) =>
    value.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime? _parseTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    // Backend uses Unix seconds for takenAt, but some legacy responses may use ms.
    final ms = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }
  return DateTime.tryParse(value.toString())?.toLocal();
}
