import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';

/// A failed/never-completing bootstrap must leave a visible way to recover.
/// This widget is removed when the parent has a renderable message window.
class ChatHistoryRecoveryNotice extends StatefulWidget {
  const ChatHistoryRecoveryNotice(
      {super.key,
      required this.conversationID,
      required this.onRetry,
      this.onTimeout});
  final String conversationID;
  final Future<void> Function() onRetry;
  final VoidCallback? onTimeout;

  @override
  State<ChatHistoryRecoveryNotice> createState() =>
      _ChatHistoryRecoveryNoticeState();
}

class _ChatHistoryRecoveryNoticeState extends State<ChatHistoryRecoveryNotice> {
  Timer? _deadline;
  Timer? _progress;
  bool _waiting = false;
  bool _visible = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _progress = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _waiting = true);
    });
    _deadline = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      ChatRecoveryTrace.log('window_not_visible',
          conversationID: widget.conversationID);
      setState(() => _visible = true);
      widget.onTimeout?.call();
    });
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    ChatRecoveryTrace.log('window_retry',
        conversationID: widget.conversationID);
    try {
      await widget.onRetry().timeout(const Duration(seconds: 25));
    } catch (error) {
      ChatRecoveryTrace.log('window_retry_failed',
          conversationID: widget.conversationID,
          fields: {'errorType': error.runtimeType});
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _progress?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_visible && !_waiting
      ? const SizedBox.shrink()
      : Center(
          child: Card(
              child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_visible ? '消息暂时未能显示' : '正在加载消息…'),
            if (_visible)
              TextButton(
                  onPressed: _retrying ? null : _retry,
                  child: Text(_retrying ? '正在重新加载…' : '重新加载')),
          ]),
        )));
}
