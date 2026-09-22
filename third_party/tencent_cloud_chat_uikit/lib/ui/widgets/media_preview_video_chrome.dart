import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_video_progress_bar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_chrome.dart';

/// Shared by single-video and mixed-media previews. Only the controls fade;
/// the video texture stays outside this subtree.
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

  @override
  State<MediaPreviewVideoChrome> createState() =>
      MediaPreviewVideoChromeState();
}

class MediaPreviewVideoChromeState extends State<MediaPreviewVideoChrome>
    with WidgetsBindingObserver {
  Timer? _hideTimer;
  bool _visible = true;
  bool _scrubbing = false;
  bool _menuOpen = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant MediaPreviewVideoChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerKey != widget.playerKey) {
      _scrubbing = false;
      _visible = true;
    }
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.isReady != widget.isReady ||
        oldWidget.active != widget.active ||
        oldWidget.playerKey != widget.playerKey) {
      if (!widget.isPlaying || !widget.isReady) _visible = true;
      _scheduleHide();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) showControls();
    _scheduleHide();
  }

  void showControls() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void toggleControls() {
    if (!mounted || _scrubbing || _menuOpen || !widget.active) return;
    setState(() => _visible = !_visible);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_visible ||
        !_foreground ||
        !widget.active ||
        !widget.isReady ||
        !widget.isPlaying ||
        _scrubbing ||
        _menuOpen) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
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
        _menuOpen = false;
        showControls();
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);
    final compact = MediaQuery.sizeOf(context).height < 450;
    final hasActions = widget.onForward != null ||
        widget.onSave != null ||
        widget.onDelete != null;
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
                      onMore: _showMore,
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
                    (hasActions ? 56 : 0),
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
                bottom:
                    insets.bottom + (compact ? 8 : 18) + (hasActions ? 56 : 0),
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
                    const SizedBox(width: 4),
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
                  left: insets.left + 20,
                  right: insets.right + 20,
                  bottom: insets.bottom + 8,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children: [
                      if (widget.onForward != null)
                        _actionButton(
                          id: 'forward',
                          icon: CupertinoIcons.arrowshape_turn_up_right_fill,
                          label: TIM_t('转发'),
                          action: widget.onForward!,
                        ),
                      if (widget.onSave != null)
                        _actionButton(
                          id: 'save',
                          icon: CupertinoIcons.square_arrow_down_fill,
                          label: TIM_t('保存'),
                          action: widget.onSave!,
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
    return Material(
      color: const Color(0xFF383838),
      shape: const CircleBorder(),
      child: IconButton(
        key: ValueKey('video-inline-$id'),
        tooltip: label,
        onPressed: () => _runAction(action),
        color: Colors.white,
        iconSize: 23,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: Icon(icon),
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
        iconSize: 25,
        color: Colors.white,
        disabledColor: Colors.white38,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
      );
}

Future<void> showMediaPreviewVideoActions({
  required BuildContext context,
  required double playbackSpeed,
  required Future<void> Function() onDownload,
  required Future<void> Function(double) onSpeedChanged,
  Future<void> Function()? onForward,
  Future<void> Function()? onDelete,
  Future<void> Function()? onPictureInPicture,
  VoidCallback? onOpenMedia,
}) async {
  const speeds = [1.0, 1.5, 2.0];
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
          primaryColor: CupertinoColors.activeBlue,
        ),
        child: CupertinoActionSheet(
          title: Text(TIM_t('播放速度')),
          message: SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<double>(
              groupValue: speeds.contains(playbackSpeed) ? playbackSpeed : null,
              children: {
                for (final speed in speeds)
                  speed: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Text(
                      '${speed.toStringAsFixed(1)}×',
                      maxLines: 1,
                      style: CupertinoTheme.of(sheetContext)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
              },
              onValueChanged: (speed) {
                if (speed != null) Navigator.pop(sheetContext, 'speed_$speed');
              },
            ),
          ),
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
    default:
      if (action?.startsWith('speed_') == true) {
        final speed = double.tryParse(action!.substring(6));
        if (speed != null) await onSpeedChanged(speed);
      }
  }
}
