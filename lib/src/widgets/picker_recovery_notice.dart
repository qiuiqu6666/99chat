import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/picker_recovery_coordinator.dart';
import '../services/picker_recovery_service.dart';
import '../session/session_manager.dart';
import 'message_notification_banner.dart';

class PickerRecoveryNotice extends StatefulWidget {
  const PickerRecoveryNotice({super.key, required this.child});
  final Widget child;
  @override
  State<PickerRecoveryNotice> createState() => _PickerRecoveryNoticeState();
}

class _PickerRecoveryNoticeState extends State<PickerRecoveryNotice>
    with WidgetsBindingObserver {
  final _session = SessionManager.instance;
  List<PickerRecoveredDraft> _drafts = const [];
  bool _checking = false;
  bool _needsCheck = false;
  (String, int)? _lastChecked;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSession());
  }

  void _onSession() {
    if (!mounted) return;
    if (!_session.state.isReady) {
      if (_session.state.isLoggedOut) {
        _lastChecked = null;
        if (_drafts.isNotEmpty) setState(() => _drafts = const []);
      }
      return;
    }
    final key = (_session.state.userId ?? '', _session.sessionGeneration);
    if (_lastChecked != key) unawaited(_check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session.state.isReady) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_checking) {
      _needsCheck = true;
      return;
    }
    _checking = true;
    try {
      do {
        _needsCheck = false;
        final owner = _session.state.userId ?? '';
        final generation = _session.sessionGeneration;
        if (!mounted || owner.isEmpty || !_session.state.isReady) return;
        final drafts = await PickerRecoveryService.listCurrentDrafts();
        if (!mounted ||
            _session.state.userId != owner ||
            _session.sessionGeneration != generation ||
            _session.state.isLoggedOut) continue;
        _lastChecked = (owner, generation);
        setState(
            () => _drafts = drafts.where((d) => d.owner == owner).toList());
      } while (_needsCheck);
    } catch (_) {
      // Keep the durable journal; next foreground retries without consuming it.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showDrafts() async {
    final navigator = AppNavigator.key.currentState;
    if (navigator?.overlay == null) return;
    final owner = _session.state.userId;
    final generation = _session.sessionGeneration;
    final drafts = List<PickerRecoveredDraft>.of(_drafts);
    final remove = await showDialog<bool>(
        context: navigator!.overlay!.context,
        builder: (context) => AlertDialog(
              title: const Text('找回未完成的媒体选择'),
              content: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text(
                        '这些文件不会自动发送。聊天照片请回到原会话的相册入口确认。其他媒体的文件已保留，请回原功能重新选择。标为“发送状态待确认”的项目，请先检查原会话的发送记录。'),
                    const SizedBox(height: 12),
                    for (final draft in drafts)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '${draft.entry == 'chat.gallery' ? '聊天相册' : '媒体选择'} · ${draft.files.length} 个文件'
                              '${draft.claimed ? '（发送状态待确认）' : draft.error == null ? '' : '（部分文件未能恢复）'}')),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('放弃这些草稿')),
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('保留')),
              ],
            ));
    if (remove == true &&
        mounted &&
        _session.state.userId == owner &&
        _session.sessionGeneration == generation) {
      for (final draft in drafts) {
        await PickerRecoveryService.discardDraft(draft);
      }
      await _check();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_drafts.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            top: 8,
            child: SafeArea(
                child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                  dense: true,
                  title: Text('找回 ${_drafts.length} 次未完成的媒体选择'),
                  trailing: TextButton(
                      onPressed: _showDrafts, child: const Text('查看'))),
            )),
          ),
      ]);
}
