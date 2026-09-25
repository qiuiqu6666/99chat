import 'dart:async';
import 'media_preview_reference_button.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_video_progress_bar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_chrome.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';

/// Shared by single-video and mixed-media previews. Controls stay visible until
/// manually hidden; the video texture stays outside this subtree.
class MediaPreviewVideoChrome extends StatefulWidget {
  const MediaPreviewVideoChrome({
    super.key,
    required this.playerKey,
    required this.title,
    required this.subtitle,
    required this.isPlaying,
    required this.isReady,
    required this.onBack,
    required this.onTogglePlayback,
    required this.onMore,
    this.onForward,
    this.onSave,
    this.onDelete,
    this.onOpenMedia,
    this.attachmentChanges,
    this.galleryIndicator,
    this.opacity = 1,
    this.active = true,
  });

  final GlobalKey<TIMUIKitVideoPlayerState> playerKey;
  final Listenable? attachmentChanges;
  final String title;
  final String subtitle;
  final String? galleryIndicator;
  final bool isPlaying;
  final bool isReady;
  final bool active;
  final double opacity;
  final VoidCallback onBack;
  final VoidCallback onTogglePlayback;
  final Future<void> Function() onMore;
  final Future<void> Function()? onForward;
  final Future<void> Function()? onSave;
  final Future<void> Function()? onDelete;
  final VoidCallback? onOpenMedia;

  @override
  State<MediaPreviewVideoChrome> createState() =>
      MediaPreviewVideoChromeState();
}

class MediaPreviewVideoChromeState extends State<MediaPreviewVideoChrome>
    with WidgetsBindingObserver {
  bool _visible = true;
  bool _scrubbing = false;
  bool _menuOpen = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant MediaPreviewVideoChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerKey != widget.playerKey) {
      _scrubbing = false;
      _visible = true;
    }
    if (oldWidget.playerKey != widget.playerKey ||
        oldWidget.galleryIndicator != widget.galleryIndicator) {
      _saving = false;
    }
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.isReady != widget.isReady ||
        oldWidget.active != widget.active ||
        oldWidget.playerKey != widget.playerKey) {
      if (!widget.isPlaying || !widget.isReady) _visible = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) showControls();
  }

  void showControls() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
  }

  void toggleControls() {
    if (!mounted || _scrubbing || _menuOpen || !widget.active) return;
    setState(() => _visible = !_visible);
  }

  void _onScrubbingChanged(bool scrubbing) {
    if (!mounted) return;
    setState(() => _scrubbing = scrubbing);
    showControls();
  }

  Future<void> showActions() => _showMore();

  Future<void> _showMore() => _runAction(widget.onMore);

  Future<void> _runAction(Future<void> Function() action) async {
    if (_menuOpen) return;
    _menuOpen = true;
    showControls();
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _menuOpen = false);
        showControls();
      }
    }
  }

  Future<void> _runSave(Future<void> Function() action) async {
    if (_menuOpen || _saving) return;
    setState(() => _saving = true);
    try {
      await _runAction(action);
    } catch (error) {
      debugPrint(
          '[VideoSave] stage=preview_action_failed type=${error.runtimeType}');
      if (mounted) notifySaveVideoResult(context, success: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);
    final compact = MediaQuery.sizeOf(context).height < 450;
    final hasActions = widget.onForward != null ||
        widget.onSave != null ||
        widget.onDelete != null ||
        widget.onOpenMedia != null;
    return IgnorePointer(
      ignoring: !widget.active || !_visible || widget.opacity < 0.96,
      child: Opacity(
        opacity: widget.opacity.clamp(0.0, 1.0),
        child: AnimatedOpacity(
          key: const ValueKey('video-controls-fade'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          opacity: _visible ? 1 : 0,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                bottom: 0,
                left: insets.left,
                right: insets.right,
                child: Stack(
                  children: [
                    MediaPreviewTopBar(
                      title: widget.title,
                      subtitle: widget.subtitle,
                      galleryIndicator: widget.galleryIndicator,
                      onBack: widget.onBack,
                    ),
                  ],
                ),
              ),
              if (widget.isReady && !widget.isPlaying && !_scrubbing)
                Center(
                  child: Material(
                    color: const Color(0x33000000),
                    shape: const CircleBorder(
                      side: BorderSide(color: Colors.white70, width: 1.5),
                    ),
                    child: IconButton(
                      key: const ValueKey('video-center-play'),
                      tooltip: TIM_t('播放'),
                      icon: const Icon(Icons.play_arrow_rounded),
                      color: Colors.white,
                      iconSize: 44,
                      padding: const EdgeInsets.all(10),
                      onPressed: widget.onTogglePlayback,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: insets.bottom +
                    (compact ? 88 : 126) +
                    (hasActions ? MediaPreviewReferenceButton.buttonSize + 16 : 0),
                child: const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xA6000000)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: insets.left + 8,
                right: insets.right + 20,
                bottom: insets.bottom +
                    (hasActions
                        ? MediaPreviewReferenceButton.buttonSize + 16
                        : (compact ? 4 : 8)),
                child: Row(
                  children: [
                    _VideoButton(
                      icon: widget.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      label: widget.isPlaying ? TIM_t('暂停') : TIM_t('播放'),
                      onPressed:
                          widget.isReady ? widget.onTogglePlayback : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MediaPreviewVideoProgressBar(
                        playerKey: widget.playerKey,
                        attachmentChanges: widget.attachmentChanges,
                        embedded: true,
                        enabled: widget.active && widget.isReady,
                        onScrubbingChanged: _onScrubbingChanged,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasActions)
                Positioned(
                  left: insets.left + 12,
                  right: insets.right + 12,
                  bottom: insets.bottom + 16,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    children: [
                      if (widget.onForward != null)
                        _actionButton(
                          id: 'forward',
                          icon: Icons.ios_share_rounded,
                          label: TIM_t('转发'),
                          action: widget.onForward!,
                        ),
                      if (widget.onSave != null)
                        _actionButton(
                          id: 'save',
                          icon: Icons.download_rounded,
                          label: TIM_t('保存'),
                          action: widget.onSave!,
                        ),
                      if (widget.onOpenMedia != null)
                        MediaPreviewGalleryButton(
                          onPressed: widget.onOpenMedia!,
                        ),
                      if (widget.onDelete != null)
                        _actionButton(
                          id: 'delete',
                          icon: Icons.delete_outline_rounded,
                          label: TIM_t('删除'),
                          action: widget.onDelete!,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String id,
    required IconData icon,
    required String label,
    required Future<void> Function() action,
  }) {
    final saving = id == 'save' && _saving;
    return Tooltip(
      message: saving ? TIM_t('正在保存视频…') : label,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: saving
            ? Transform.scale(
                key: const ValueKey('video-save-loading'),
                scale: MediaPreviewReferenceButton.visualScale,
                transformHitTests: false,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: const SizedBox(
                    width: MediaPreviewReferenceButton.buttonSize,
                    height: MediaPreviewReferenceButton.buttonSize,
                    child: Center(
                      child: CupertinoActivityIndicator(
                        radius: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              )
            : MediaPreviewReferenceButton(
                key: ValueKey('video-inline-$id'),
                icon: icon,
                label: label,
                onPressed: () => unawaited(
                    id == 'save' ? _runSave(action) : _runAction(action)),
              ),
      ),
    );
  }
}

class _VideoButton extends StatelessWidget {
  const _VideoButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        icon: Icon(icon),
        iconSize: 32,
        color: Colors.white,
        disabledColor: Colors.white38,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
        onPressed: onPressed,
      );
}

Future<void> showMediaPreviewVideoActions({
  required BuildContext context,
  required Future<void> Function() onDownload,
  Future<void> Function()? onForward,
  Future<void> Function()? onDelete,
  Future<void> Function()? onPictureInPicture,
  VoidCallback? onOpenMedia,
}) async {
  final action = await showCupertinoModalPopup<String>(
    context: context,
    semanticsDismissible: true,
    builder: (sheetContext) {
      Widget item(String action, String label, {bool destructive = false}) =>
          CupertinoActionSheetAction(
            key: ValueKey('video-action-$action'),
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(sheetContext, action),
            child: Text(label),
          );
      return CupertinoTheme(
        data: CupertinoTheme.of(sheetContext).copyWith(
          primaryColor: const CupertinoDynamicColor.withBrightness(
            color: Color(0xFF616161),
            darkColor: Color(0xFFD1D1D6),
          ),
        ),
        child: CupertinoActionSheet(
          actions: [
            item('save', TIM_t('保存视频')),
            if (onForward != null) item('forward', TIM_t('转发')),
            if (onOpenMedia != null) item('media', TIM_t('查看全部媒体')),
            if (onDelete != null)
              item('delete', TIM_t('删除'), destructive: true),
          ],
          cancelButton: CupertinoActionSheetAction(
            key: const ValueKey('video-action-cancel'),
            isDefaultAction: true,
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(TIM_t('取消')),
          ),
        ),
      );
    },
  );
  if (!context.mounted) return;
  switch (action) {
    case 'save':
      await onDownload();
    case 'forward':
      await onForward?.call();
    case 'delete':
      await onDelete?.call();
    case 'pip':
      await onPictureInPicture?.call();
    case 'media':
      onOpenMedia?.call();
  }
}
