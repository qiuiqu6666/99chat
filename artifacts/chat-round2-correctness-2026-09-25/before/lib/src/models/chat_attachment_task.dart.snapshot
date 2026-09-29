import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';

class ChatAttachmentTask {
  ChatAttachmentTask({
    required this.taskId,
    required this.ownerUserId,
    required this.target,
    required this.sourcePath,
    required this.name,
    required this.kind,
    required this.nativeMessageKind,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.mediaBatchId,
    this.mediaBatchIndex,
    this.snapshotPath,
    this.durationMs,
    this.width,
    this.height,
    this.state = 'preparing',
    this.uploadId,
    this.attachmentId,
    this.referenceId,
    this.thumbnailAttachmentId,
    this.partSizeBytes = 8388608,
    this.expiresAt,
    this.error = '',
    this.progress = 0,
  });
  final String taskId, ownerUserId, name, kind, nativeMessageKind, mimeType;
  final ChatAttachmentTarget target;
  final int sizeBytes, createdAt;
  final String? mediaBatchId;
  final int? mediaBatchIndex;
  String sourcePath;
  String? snapshotPath;
  final int? durationMs, width, height;
  String state, error;
  String? uploadId, attachmentId, referenceId, thumbnailAttachmentId;
  int partSizeBytes;
  DateTime? expiresAt;
  double progress;
  bool get canResume => const {
        'preparing',
        'uploading',
        'paused',
        'failed',
        'ready'
      }.contains(state);
  bool get terminal =>
      state == 'sent' || state == 'cancelled' || state == 'handedOff';
  ChatAttachment get message => ChatAttachment(
      attachmentId: attachmentId!,
      referenceId: referenceId!,
      kind: kind,
      name: name,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      durationMs: durationMs,
      width: width,
      height: height,
      thumbnailAttachmentId: thumbnailAttachmentId);
  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'ownerUserId': ownerUserId,
        ...target.toJson(),
        'sourcePath': sourcePath,
        'name': name,
        'kind': kind,
        'nativeMessageKind': nativeMessageKind,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'createdAt': createdAt,
        if (mediaBatchId != null) 'mediaBatchId': mediaBatchId,
        if (mediaBatchIndex != null) 'mediaBatchIndex': mediaBatchIndex,
        'snapshotPath': snapshotPath,
        'durationMs': durationMs,
        'width': width,
        'height': height,
        'state': state,
        'error': error,
        'uploadId': uploadId,
        'attachmentId': attachmentId,
        'referenceId': referenceId,
        'thumbnailAttachmentId': thumbnailAttachmentId,
        'partSizeBytes': partSizeBytes,
        'expiresAt': expiresAt?.toIso8601String(),
        'progress': progress,
      };
  factory ChatAttachmentTask.fromJson(Map<String, dynamic> j) =>
      ChatAttachmentTask(
        taskId: attachmentString(j['taskId']),
        ownerUserId: attachmentString(j['ownerUserId']),
        target: ChatAttachmentTarget(
            isGroup: j['conversationType'] == 'group',
            id: attachmentString(j[
                j['conversationType'] == 'group' ? 'groupId' : 'peerUserId'])),
        sourcePath: attachmentString(j['sourcePath']),
        name: attachmentString(j['name']),
        kind: attachmentString(j['kind']),
        nativeMessageKind: attachmentString(j['nativeMessageKind']),
        mimeType: attachmentString(j['mimeType']),
        sizeBytes: attachmentInt(j['sizeBytes']),
        createdAt: attachmentInt(j['createdAt']),
        mediaBatchId: attachmentOptionalString(j['mediaBatchId']),
        mediaBatchIndex: j['mediaBatchIndex'] is int &&
                (j['mediaBatchIndex'] as int) >= 0
            ? j['mediaBatchIndex'] as int
            : null,
        snapshotPath: attachmentOptionalString(j['snapshotPath']),
        durationMs: attachmentPositiveInt(j['durationMs']),
        width: attachmentPositiveInt(j['width']),
        height: attachmentPositiveInt(j['height']),
        state: attachmentString(j['state']),
        error: attachmentString(j['error']),
        uploadId: attachmentOptionalString(j['uploadId']),
        attachmentId: attachmentOptionalString(j['attachmentId']),
        referenceId: attachmentOptionalString(j['referenceId']),
        thumbnailAttachmentId:
            attachmentOptionalString(j['thumbnailAttachmentId']),
        partSizeBytes: attachmentPositiveInt(j['partSizeBytes']) ?? 8388608,
        expiresAt: attachmentDate(j['expiresAt']),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
      );
}
