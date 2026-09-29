import 'dart:async';
import 'package:dio/dio.dart';

class SyncContractException implements Exception {
  const SyncContractException(this.code);
  final String code;
  @override
  String toString() => 'SyncContractException($code)';
}

String? syncErrorCode(Object error) {
  if (error is SyncContractException) return error.code;
  if (error is DioError) {
    final body = error.response?.data;
    if (body is Map && body['code'] is String) {
      return body['code'] as String;
    }
  }
  return null;
}

bool isTransientSyncError(Object error) {
  if (syncErrorCode(error) == 'BATCH_RETRY') return true;
  if (error is! DioError || error.type == DioErrorType.cancel) return false;
  if (error.response != null) {
    return const [408, 429, 500, 502, 503, 504]
        .contains(error.response!.statusCode);
  }
  return error.type == DioErrorType.connectTimeout ||
      error.type == DioErrorType.receiveTimeout ||
      error.type == DioErrorType.sendTimeout ||
      error.type == DioErrorType.other;
}

typedef SyncRequestGuard = FutureOr<bool> Function();

Future<void> checkSyncGuard(SyncRequestGuard isCurrent) async {
  if (!await isCurrent()) throw const SyncContractException('STALE_SYNC');
}

/// Only for reads or operations whose request identity makes replay idempotent.
/// Do not use for session creation or init-upload.
Future<T> retrySyncRequest<T>(
  Future<T> Function() request, {
  required SyncRequestGuard isCurrent,
  Duration delay = const Duration(milliseconds: 250),
}) async {
  for (var attempt = 0;; attempt++) {
    await checkSyncGuard(isCurrent);
    try {
      final result = await request();
      await checkSyncGuard(isCurrent);
      return result;
    } catch (error) {
      if (attempt >= 2 || !isTransientSyncError(error)) rethrow;
      await Future<void>.delayed(delay * (attempt + 1));
    }
  }
}
