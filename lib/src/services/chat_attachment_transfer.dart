import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/chat_attachment_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_diagnostics.dart';

/// No IM/UI side effects: resumable transfer reads server-confirmed parts and
/// streams bounded file ranges. The caller persists each durable transition.
class ChatAttachmentTransfer {
  ChatAttachmentTransfer({required this.api, Dio? storageDio})
      : storage = storageDio ??
            Dio(BaseOptions(
                connectTimeout: 30000,
                receiveTimeout: 120000,
                sendTimeout: 120000,
                followRedirects: false));
  final ChatAttachmentApi api;
  final Dio storage;

  static String signedUrl(Map<String, dynamic> data) {
    final value = attachmentString(data['url'] ??
        data['uploadUrl'] ??
        data['presignedUrl'] ??
        data['downloadUrl']);
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const ChatAttachmentException('INVALID_RESPONSE', '附件传输地址无效');
    }
    return value;
  }

  static Map<String, dynamic> signedHeaders(Map<String, dynamic> data) {
    final headers = attachmentMap(data['headers']);
    // Never permit a response to forward business credentials to object storage.
    return Map.fromEntries(headers.entries.where((entry) {
      final key = entry.key.toLowerCase();
      return key != 'authorization' &&
          key != 'cookie' &&
          !key.startsWith('x-device') &&
          !key.startsWith('x-app') &&
          !key.startsWith('x-client');
    }));
  }

  Future<void> upload(
    ChatAttachmentTask task, {
    required CancelToken cancelToken,
    required void Function() checkSession,
    required Future<void> Function() persist,
    required void Function(double) onProgress,
    int maxParallelParts = 2,
  }) async {
    checkSession();
    final source = File(task.sourcePath);
    if (!await source.exists() || await source.length() != task.sizeBytes) {
      throw const ChatAttachmentException('LOCAL_FILE_MISSING', '待上传文件已变化');
    }
    if (task.uploadId == null) {
      final init = await api.initUpload({
        'clientUploadKey': task.taskId,
        ...task.target.toJson(),
        'kind': task.kind,
        'nativeMessageKind': task.nativeMessageKind,
        'originalName': task.name,
        'mimeType': task.mimeType,
        'declaredSizeBytes': task.sizeBytes,
        if (task.durationMs != null) 'durationMs': task.durationMs,
        if (task.width != null) 'width': task.width,
        if (task.height != null) 'height': task.height,
      }, cancelToken: cancelToken);
      checkSession();
      final initializedUploadId = attachmentOptionalString(init['uploadId']);
      final initializedAttachmentId =
          attachmentOptionalString(init['attachmentId']);
      final initializedPartSize = attachmentInt(init['partSizeBytes']);
      final expectedParts =
          (task.sizeBytes / math.max(1, initializedPartSize)).ceil();
      if (initializedUploadId == null ||
          initializedAttachmentId == null ||
          initializedPartSize <= 0 ||
          attachmentInt(init['expectedPartCount']) != expectedParts) {
        throw const ChatAttachmentException('INVALID_RESPONSE', '上传会话信息不完整');
      }
      task.uploadId = initializedUploadId;
      task.attachmentId = initializedAttachmentId;
      task.partSizeBytes = initializedPartSize;
      await persist();
    }
    checkSession();
    final uploadId = task.uploadId!;
    if (task.partSizeBytes <= 0 || task.attachmentId == null) {
      throw const ChatAttachmentException('INVALID_RESPONSE', '上传会话信息不完整');
    }
    final count = (task.sizeBytes / task.partSizeBytes).ceil();
    final confirmed = <int>{};
    var after = 0;
    var alreadyCompleted = false;
    for (var page = 0; page <= count; page++) {
      checkSession();
      final status = await api.status(uploadId,
          afterPartNumber: after, cancelToken: cancelToken);
      checkSession();
      final state = attachmentString(status['status']).toLowerCase();
      if (state == 'completed' || state == 'ready') {
        alreadyCompleted = true;
        break;
      }
      if (const {'expired', 'aborted', 'cancelled'}.contains(state)) {
        throw const ChatAttachmentException('UPLOAD_EXPIRED', '上传会话已结束');
      }
      final rows = status['parts'] ?? status['confirmedParts'];
      if (rows is! List) {
        throw const ChatAttachmentException('INVALID_RESPONSE', '缺少已确认分片列表');
      }
      var next = after;
      for (final row in rows) {
        final part = attachmentMap(row);
        final number = attachmentInt(part['partNumber']);
        final bytes = attachmentInt(part['sizeBytes'] ?? part['size']);
        if (number < 1 || number > count) {
          throw const ChatAttachmentException('INVALID_RESPONSE', '分片编号无效');
        }
        final expected = math.min(task.partSizeBytes,
            task.sizeBytes - (number - 1) * task.partSizeBytes);
        if (bytes == expected) confirmed.add(number);
        next = math.max(next, number);
      }
      if (status['hasMore'] == false ||
          (rows.length < 100 && status['hasMore'] != true)) {
        break;
      }
      if (next <= after) {
        throw const ChatAttachmentException('INVALID_RESPONSE', '分片分页未推进');
      }
      after = next;
      if (page == count) {
        throw const ChatAttachmentException('INVALID_RESPONSE', '分片分页超限');
      }
    }
    if (!alreadyCompleted) {
      final missing = [
        for (var n = 1; n <= count; n++)
          if (!confirmed.contains(n)) n
      ];
      final bytesByPart = <int, int>{
        for (final n in confirmed)
          n: math.min(task.partSizeBytes,
              task.sizeBytes - (n - 1) * task.partSizeBytes),
      };
      void progress() => onProgress(
          bytesByPart.values.fold<int>(0, (a, b) => a + b) / task.sizeBytes);
      progress();
      // Each batch has at most two file streams in memory. Failed URLs are
      // refreshed, never retried through the API client's JWT interceptors.
      final parallel = maxParallelParts.clamp(1, 2);
      for (var start = 0; start < missing.length; start += parallel) {
        final batch = missing.skip(start).take(parallel).toList();
        checkSession();
        final results = await Future.wait(batch.map((number) async {
          for (var attempt = 0; attempt < 3; attempt++) {
            checkSession();
            final urls = await api.partUrls(uploadId, [number],
                cancelToken: cancelToken);
            checkSession();
            final matches = urls
                .where((u) => attachmentInt(u['partNumber']) == number)
                .toList();
            if (matches.length != 1 ||
                attachmentString(matches.single['method']).toUpperCase() !=
                    'PUT') {
              throw const ChatAttachmentException(
                  'INVALID_RESPONSE', '分片签名与请求不匹配');
            }
            final grant = matches.single;
            final offset = (number - 1) * task.partSizeBytes;
            final length =
                math.min(task.partSizeBytes, task.sizeBytes - offset);
            try {
              final headers = signedHeaders(grant);
              final request = Options(
                      method: 'PUT',
                      headers: {...headers, 'Content-Length': length},
                      followRedirects: false,
                      responseType: ResponseType.plain)
                  .compose(storage.options, signedUrl(grant),
                      data: source.openRead(offset, offset + length),
                      cancelToken: cancelToken, onSendProgress: (sent, total) {
                bytesByPart[number] = math.min(sent, length);
                progress();
              });
              // Dio 4 composes a default JSON Content-Type, even for streams.
              // A presigned PUT must use the exact signed Content-Type, including
              // its absence. Passing contentType:null to Options is insufficient.
              request.contentType = headers.entries
                  .where((entry) => entry.key.toLowerCase() == 'content-type')
                  .map((entry) => entry.value?.toString())
                  .firstWhere((_) => true, orElse: () => null);
              await storage.fetch<dynamic>(request);
              checkSession();
              bytesByPart[number] = length;
              progress();
              return;
            } on DioError catch (error) {
              if (CancelToken.isCancel(error)) rethrow;
              final status = error.response?.statusCode;
              final ossCode = _ossErrorCode(error.response?.data);
              ChatAttachmentDiagnostics.event('part_upload_failed', {
                'partNumber': number,
                'attempt': attempt + 1,
                'httpStatus': status,
                'dioType': error.type.name,
                'causeType': error.error?.runtimeType.toString(),
                'ossCode': ossCode,
                'signedContentTypePresent': signedHeaders(grant)
                    .keys
                    .any((key) => key.toLowerCase() == 'content-type'),
                'requestContentTypePresent':
                    error.requestOptions.contentType != null,
              });
              if (attempt == 2 ||
                  const {
                    'SignatureDoesNotMatch',
                    'InvalidAccessKeyId',
                    'AccessDenied',
                    'NoSuchUpload',
                    'RequestTimeTooSkewed'
                  }.contains(ossCode) ||
                  (status != null &&
                      status != 403 &&
                      status != 408 &&
                      status != 429 &&
                      status < 500)) {
                throw _storageError(error, ossCode);
              }
              await Future<void>.delayed(
                  Duration(milliseconds: 500 * (1 << attempt)));
            }
          }
        }), eagerError: false);
        if (results.length != batch.length) {
          throw StateError('incomplete upload batch');
        }
      }
    }
    checkSession();
    final completed = await api.complete(uploadId, cancelToken: cancelToken);
    checkSession();
    var metadata = attachmentMap(completed['attachment']);
    if (metadata.isEmpty) metadata = completed;
    if (attachmentString(metadata['status']).toLowerCase() != 'ready' ||
        attachmentString(metadata['attachmentId']).isEmpty ||
        attachmentInt(metadata['sizeBytes']) <= 0 ||
        attachmentDate(metadata['expiresAt']) == null) {
      metadata =
          await api.metadata(task.attachmentId!, cancelToken: cancelToken);
      checkSession();
    }
    if (attachmentString(metadata['status']).toLowerCase() != 'ready') {
      throw const ChatAttachmentException('ATTACHMENT_NOT_READY', '附件正在处理');
    }
    final actualSize = attachmentInt(metadata['sizeBytes']);
    if (actualSize != task.sizeBytes ||
        attachmentString(metadata['attachmentId']) != task.attachmentId) {
      throw const ChatAttachmentException('INVALID_RESPONSE', '附件完成信息不匹配');
    }
    task.expiresAt = attachmentDate(metadata['expiresAt']);
    if (task.expiresAt == null ||
        !task.expiresAt!.isAfter(DateTime.now().toUtc())) {
      throw const ChatAttachmentException('ATTACHMENT_EXPIRED', '附件已过期');
    }
    task.state = 'ready';
    task.progress = 1;
    await persist();
  }
}

// Extract only known storage error codes. Never log the body: OSS error XML can
// include the signed URL, AccessKeyId, signature and canonical request.
String? _ossErrorCode(dynamic body) {
  if (body is! String) return null;
  final prefix = body.substring(0, math.min(body.length, 8192));
  final code =
      RegExp(r'<Code>\s*([A-Za-z0-9]+)\s*</Code>').firstMatch(prefix)?.group(1);
  return const {
    'SignatureDoesNotMatch',
    'AccessDenied',
    'InvalidAccessKeyId',
    'ExpiredToken',
    'SecurityTokenExpired',
    'InvalidSecurityToken',
    'RequestTimeTooSkewed',
    'NoSuchUpload',
    'InvalidPart',
    'InvalidArgument',
    'InvalidRequest',
    'InvalidDigest',
    'BadDigest',
    'RequestTimeout',
    'SlowDown',
    'ServiceUnavailable',
    'InternalError',
    'NoSuchBucket',
    'EntityTooLarge',
    'AccessForbidden',
  }.contains(code)
      ? code
      : null;
}

ChatAttachmentException _storageError(DioError error, String? ossCode) {
  if (ossCode == 'SignatureDoesNotMatch') {
    return const ChatAttachmentException(
        'STORAGE_SIGNATURE_MISMATCH', '存储签名校验失败，请检查后端签名与上传请求头');
  }
  if (ossCode == 'NoSuchUpload') {
    return const ChatAttachmentException('UPLOAD_EXPIRED', '上传会话已失效');
  }
  if (ossCode != null) {
    return ChatAttachmentException('STORAGE_REJECTED', '存储服务拒绝上传（$ossCode）');
  }
  if (error.error is HandshakeException) {
    return const ChatAttachmentException(
        'STORAGE_TLS_ERROR', '无法验证存储服务证书，请检查存储域名与证书');
  }
  if (const {
    DioErrorType.connectTimeout,
    DioErrorType.sendTimeout,
    DioErrorType.receiveTimeout
  }.contains(error.type)) {
    return const ChatAttachmentException('STORAGE_TIMEOUT', '分片上传超时，请检查网络后继续');
  }
  final status = error.response?.statusCode;
  if (status != null) {
    return ChatAttachmentException(
        'STORAGE_HTTP_ERROR', '分片上传失败（HTTP $status），请重试');
  }
  return const ChatAttachmentException(
      'STORAGE_CONNECTION_FAILED', '无法连接存储服务，请检查网络与存储域名后继续');
}
