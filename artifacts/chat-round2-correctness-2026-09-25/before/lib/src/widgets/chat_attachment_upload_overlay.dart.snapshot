import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/chat_attachment_upload_projection.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_file_card.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_video_card.dart';

/// Mounts the durable task projection without occupying space above the chat.
class ChatAttachmentUploadOverlayBinding extends StatefulWidget {
  const ChatAttachmentUploadOverlayBinding({super.key, required this.target});
  final ChatAttachmentTarget target;
  @override
  State<ChatAttachmentUploadOverlayBinding> createState() =>
      _UploadOverlayBindingState();
}

class _UploadOverlayBindingState
    extends State<ChatAttachmentUploadOverlayBinding> {
  final service = ChatAttachmentService.instance;
  final overlays = LocalMessageOverlayStore.instance;
  late final String owner;
  bool scheduled = false;
  String? signature;

  @override
  void initState() {
    super.initState();
    owner = ApiClient.instance.authenticatedUserId;
    service.addListener(_scheduleSync);
    overlays.addListener(_overlaysChanged);
    _scheduleSync();
    unawaited(service.load().catchError((_) {}));
    unawaited(service.refreshPolicy().then<void>((_) {}).catchError((_) {}));
  }

  void _overlaysChanged() {
    signature = null;
    _scheduleSync();
  }

  void _scheduleSync() {
    if (scheduled || !mounted) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted || owner != ApiClient.instance.authenticatedUserId) return;
      final tasks = service.tasksFor(widget.target);
      // No list rebuild for every percentage tick. Only the card subscribes to
      // progress; reference availability and task additions/removals change rows.
      final next = tasks
          .map((task) =>
              '${task.taskId}:${task.attachmentId}:${task.referenceId}')
          .join('|');
      if (signature == next) return;
      syncAttachmentUploadOverlays(
          store: overlays, owner: owner, target: widget.target, tasks: tasks);
      signature = next;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    service.removeListener(_scheduleSync);
    overlays.removeListener(_overlaysChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A complete local row, so SDK resend/forward/delete actions cannot act on an
/// upload placeholder. No delivery check mark is shown before IM dispatch.
class ChatAttachmentPendingMessage extends StatelessWidget {
  const ChatAttachmentPendingMessage(
      {super.key,
      required this.taskId,
      required this.owner,
      required this.target});
  final String taskId, owner;
  final ChatAttachmentTarget target;

  Future<void> _action(
      BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is ChatAttachmentException
              ? error.userMessage
              : '附件操作失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ChatAttachmentService.instance;
    return AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          if (ApiClient.instance.authenticatedUserId != owner) {
            return const SizedBox.shrink();
          }
          final matches =
              service.tasksFor(target).where((task) => task.taskId == taskId);
          if (matches.isEmpty) return const SizedBox.shrink();
          final ChatAttachmentTask task = matches.first;
          final running = service.isRunning(task.taskId);
          final unknown =
              task.state == 'dispatching' || task.state == 'outcomeUnknown';
          final label = switch (task.state) {
            'preparing' => '准备上传…',
            'uploading' => '上传 ${(task.progress.clamp(0, 1) * 100).floor()}%',
            'ready' => '等待发送…',
            'dispatching' => '消息发送中…',
            'outcomeUnknown' => '发送结果待确认，请勿重复发送',
            'paused' => '已暂停，点击继续',
            _ => task.error.isEmpty ? '发送失败，点击重试' : task.error,
          };
          final time = TimeOfDay.fromDateTime(
              DateTime.fromMillisecondsSinceEpoch(task.createdAt));
          return Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 12),
            child: Align(
                alignment: Alignment.centerRight,
                child: Stack(children: [
                  if (task.kind == 'video')
                    ChatAttachmentVideoCard(
                      thumbnail: !kIsWeb && task.snapshotPath != null
                          ? FileImage(File(task.snapshotPath!))
                          : null,
                      sizeBytes: task.sizeBytes,
                      durationMs: task.durationMs,
                      videoWidth: task.width,
                      videoHeight: task.height,
                      busy: running,
                      paused: task.state == 'paused',
                      progress: task.progress,
                      indeterminate: task.state != 'uploading',
                      uploadStatus: label,
                      onOpen: unknown
                          ? null
                          : () => unawaited(
                              _action(context, () => service.resume(task))),
                      onPause: unknown
                          ? null
                          : () => unawaited(
                              _action(context, () => service.pause(task))),
                      onCancel: unknown
                          ? null
                          : () => unawaited(
                              _action(context, () => service.cancel(task))),
                    )
                  else
                    ChatAttachmentFileCard(
                      name: task.name,
                      sizeBytes: task.sizeBytes,
                      isSelf: true,
                      isLocal: false,
                      busy: running,
                      progress: task.progress,
                      error: task.state == 'failed' ? task.error : '',
                      uploadStatus: label,
                      uploadIndeterminate: task.state == 'preparing',
                      onOpen: () {
                        if (!unknown) {
                          unawaited(
                              _action(context, () => service.resume(task)));
                        }
                      },
                      onPause: () => unawaited(_action(
                          context,
                          () => running
                              ? service.pause(task)
                              : service.resume(task))),
                      onCancel: unknown
                          ? null
                          : () => unawaited(
                              _action(context, () => service.cancel(task))),
                    ),
                  Positioned(
                      right: 8,
                      bottom: 3,
                      child: IgnorePointer(
                          child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                              '${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}',
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xff9aa3af))),
                          const SizedBox(width: 3),
                          const Icon(Icons.schedule,
                              size: 11, color: Color(0xff9aa3af)),
                        ],
                      ))),
                ])),
          );
        });
  }
}
