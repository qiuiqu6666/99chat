import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';

class ChatAttachmentService extends ChangeNotifier {
  static final instance = ChatAttachmentService();
  static bool get mobileSupported => false;
  ChatAttachmentPolicy get routingPolicy => const ChatAttachmentPolicy();
  bool isRunning(String taskId) => false;
  List<ChatAttachmentTask> tasksFor(ChatAttachmentTarget target) => [];
  Future<void> load() async {}
  Future<ChatAttachmentPolicy> refreshPolicy({bool force = false}) async =>
      const ChatAttachmentPolicy();
  Future<bool> handles(String? path, String nativeKind) async => false;
  Future<void> start(
          {required String path,
          required ChatAttachmentTarget target,
          required String nativeMessageKind,
          String? mediaBatchId,
          int? mediaBatchIndex,
          String? name,
          String? snapshotPath,
          int? durationMs,
          int? width,
          int? height,
      void Function()? onQueued}) async =>
      throw const ChatAttachmentException('ATTACHMENT_DISABLED', '请在新版手机端查看附件');
  Future<void> resume(ChatAttachmentTask task) async {}
  Future<void> pause(ChatAttachmentTask task) async {}
  Future<void> cancel(ChatAttachmentTask task) async {}
  Future<void> observeSent(ChatAttachment attachment) async {}
  Future<String?> localPath(ChatAttachment attachment,
          {bool thumbnail = false}) async =>
      null;
}
