import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service.dart';

/// Durable upload work remains visible when a picker closes or a chat is reopened.
/// Once handed to IM, the regular message bubble owns delivery/retry status.
class ChatAttachmentPendingStrip extends StatefulWidget {
  const ChatAttachmentPendingStrip({super.key, required this.target});
  final ChatAttachmentTarget target;
  @override
  State<ChatAttachmentPendingStrip> createState() =>
      _ChatAttachmentPendingStripState();
}

class _ChatAttachmentPendingStripState
    extends State<ChatAttachmentPendingStrip> {
  final service = ChatAttachmentService.instance;
  @override
  void initState() {
    super.initState();
    unawaited(service.load().catchError((_) {}));
    // Receiver capability must be registered even before this user sends files.
    unawaited(service.refreshPolicy().then<void>((_) {}).catchError((_) {}));
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is ChatAttachmentException
              ? error.userMessage
              : '附件操作失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final tasks = service.tasksFor(widget.target);
        if (tasks.isEmpty) return const SizedBox.shrink();
        return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: tasks.length,
                  itemBuilder: (context, index) => _row(tasks[index])),
            ));
      });
  Widget _row(ChatAttachmentTask task) {
    final running = service.isRunning(task.taskId);
    final unknown =
        task.state == 'outcomeUnknown' || task.state == 'dispatching';
    final label = switch (task.state) {
      'preparing' => '准备附件',
      'uploading' => '上传 ${(task.progress * 100).floor()}%',
      'ready' => '等待发送',
      'dispatching' => '消息发送中',
      'outcomeUnknown' => '发送结果待确认，请勿重复发送',
      'paused' => '已暂停',
      _ => task.error.isEmpty ? '发送失败' : task.error,
    };
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Icon(Icons.attach_file, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(label,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (running && !unknown)
                  LinearProgressIndicator(
                      value: task.state == 'preparing' ? null : task.progress),
              ])),
          if (!unknown)
            IconButton(
                tooltip: running ? '暂停上传' : '继续发送',
                icon: Icon(running ? Icons.pause : Icons.play_arrow),
                onPressed: () => _action(() =>
                    running ? service.pause(task) : service.resume(task))),
          if (!unknown)
            IconButton(
                tooltip: '取消任务',
                icon: const Icon(Icons.close),
                onPressed: () => _action(() => service.cancel(task))),
        ]));
  }
}
