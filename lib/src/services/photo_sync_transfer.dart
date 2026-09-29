import 'dart:io';
import 'package:dio/dio.dart';
import '../api/sync_api.dart';
import '../api/sync_contract_support.dart';

enum PhotoSyncTransferResult { uploaded, alreadyCommitted, skippedTooLarge }

class PhotoSyncTransfer {
  PhotoSyncTransfer(this.api,
      {this.retryDelay = const Duration(milliseconds: 250)});
  final SyncApi api;
  final Duration retryDelay;

  Future<PhotoSyncTransferResult> upload({
    required String sessionId,
    required PhotoSyncItemPayload item,
    required File file,
    required Dio ossDio,
    required SyncRequestGuard isCurrent,
    CancelToken? cancelToken,
  }) async {
    Future<bool> allowed() async =>
        !(cancelToken?.isCancelled ?? false) && await isCurrent();
    await checkSyncGuard(allowed);
    final check = await retrySyncRequest(
        () => api.checkPhoto(
            PhotoCheckRequest.single(syncSessionId: sessionId, item: item)),
        isCurrent: allowed,
        delay: retryDelay);
    if (check.alreadyExists) return PhotoSyncTransferResult.alreadyCommitted;
    if (check.skipTooLarge) return PhotoSyncTransferResult.skippedTooLarge;
    for (var attempt = 0; attempt < 2; attempt++) {
      await checkSyncGuard(allowed);
      final init = await api.initPhotoUpload(PhotoInitUploadRequest(
          syncSessionId: sessionId, item: item, acceptAlreadyCommitted: true));
      await checkSyncGuard(allowed);
      if (init.alreadyCommitted) {
        _validateReceipt(init.receipt, item);
        return PhotoSyncTransferResult.alreadyCommitted;
      }
      if ((init.uploadState != null && init.uploadState != 'NEED_UPLOAD') ||
          init.uploadUuid.isEmpty ||
          init.presignedUrl.isEmpty) {
        throw const SyncContractException('INVALID_UPLOAD_RESPONSE');
      }
      try {
        await checkSyncGuard(allowed);
        final put = await ossDio.put<dynamic>(init.presignedUrl,
            data: file.openRead(),
            cancelToken: cancelToken,
            options: Options(headers: {
              'Content-Type': item.mimeType,
              'Content-Length': item.sizeBytes
            }));
        await checkSyncGuard(allowed);
        if (put.statusCode == null ||
            put.statusCode! < 200 ||
            put.statusCode! >= 300) {
          throw const SyncContractException('UPLOAD_NOT_ACCEPTED');
        }
        // A lost completion response retries ONLY the same uploadUuid, not PUT.
        final receipt = await retrySyncRequest(
            () => api.completePhotoUpload(uploadUuid: init.uploadUuid),
            isCurrent: allowed,
            delay: retryDelay);
        _validateReceipt(receipt, item);
        return PhotoSyncTransferResult.uploaded;
      } catch (error) {
        if (attempt != 0 ||
            !const ['CONTENT_MISMATCH', 'OSS_OBJECT_NOT_FOUND']
                .contains(syncErrorCode(error))) rethrow;
        // One bounded fresh init/PUT for an object the server could not verify.
        // No progress is committed on either failure.
      }
    }
    throw const SyncContractException('UPLOAD_NOT_COMMITTED');
  }

  void _validateReceipt(
      PhotoCompleteResponse? receipt, PhotoSyncItemPayload item) {
    if (receipt == null ||
        receipt.photoUuid.isEmpty ||
        receipt.contentHash != item.contentHash ||
        receipt.sizeBytes != item.sizeBytes ||
        (receipt.mediaType != null &&
            receipt.mediaType!.toUpperCase() != item.mediaType.toUpperCase())) {
      throw const SyncContractException('INVALID_UPLOAD_RECEIPT');
    }
  }
}
