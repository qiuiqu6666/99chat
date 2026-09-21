import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';

class MediaPreviewCircleButton extends StatelessWidget {
  const MediaPreviewCircleButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class MediaPreviewTopBar extends StatelessWidget {
  const MediaPreviewTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.onMore,
    this.galleryIndicator,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onMore;
  final String? galleryIndicator;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: Row(
        children: [
          MediaPreviewCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: onBack,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title.isNotEmpty ? title : ' ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          galleryIndicator != null
                              ? '$subtitle · $galleryIndicator'
                              : subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11,
                            height: 1.1,
                          ),
                        ),
                      ] else if (galleryIndicator != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          galleryIndicator!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onMore != null)
            MediaPreviewCircleButton(
              icon: Icons.more_horiz_rounded,
              onPressed: onMore!,
            )
          else
            const SizedBox(width: 40, height: 40),
        ],
      ),
    );
  }
}

class MediaPreviewBottomBar extends StatelessWidget {
  const MediaPreviewBottomBar({
    this.onShare,
    this.onEdit,
    this.onDownload,
    this.onDelete,
    this.onOpenMedia,
    this.onTogglePlayback,
    this.isPlaybackActive,
    this.downloadOnly = false,
    this.showPreviewTools = false,
    this.onZoomOut,
    this.onZoomIn,
    this.onRotate,
    this.onResetView,
    super.key,
  });

  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenMedia;
  final VoidCallback? onTogglePlayback;
  final bool? isPlaybackActive;
  final bool downloadOnly;
  final bool showPreviewTools;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onRotate;
  final VoidCallback? onResetView;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 16;
    const horizontalPadding = 12.0;
    const actionSpacing = 4.0;
    if (downloadOnly) {
      if (onDownload == null) {
        return const SizedBox.shrink();
      }
      return Positioned(
        left: 0,
        right: horizontalPadding,
        bottom: bottom,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _BottomAction(
              icon: Icons.download_rounded,
              onPressed: onDownload,
            ),
          ],
        ),
      );
    }
    return Positioned(
      left: 0,
      right: horizontalPadding,
      bottom: bottom,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (showPreviewTools)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BottomAction(
                  icon: Icons.remove_rounded,
                  onPressed: onZoomOut,
                ),
                const SizedBox(width: actionSpacing),
                _BottomAction(
                  icon: Icons.add_rounded,
                  onPressed: onZoomIn,
                ),
                const SizedBox(width: actionSpacing),
                _BottomAction(
                  icon: Icons.rotate_right_rounded,
                  onPressed: onRotate,
                ),
                const SizedBox(width: actionSpacing),
                _BottomAction(
                  icon: Icons.fit_screen_rounded,
                  onPressed: onResetView,
                ),
              ],
            )
          else if (onTogglePlayback != null && isPlaybackActive != null)
            _BottomAction(
              icon: isPlaybackActive!
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              onPressed: onTogglePlayback,
            )
          else
            const SizedBox(width: 40, height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!showPreviewTools) ...[
                _BottomAction(
                  icon: Icons.ios_share_rounded,
                  onPressed: onShare,
                ),
                const SizedBox(width: actionSpacing),
                _BottomAction(
                  icon: Icons.title_rounded,
                  onPressed: onEdit,
                ),
                const SizedBox(width: actionSpacing),
              ],
              _BottomAction(
                icon: Icons.download_rounded,
                onPressed: onDownload,
              ),
              if (onOpenMedia != null) ...[
                const SizedBox(width: actionSpacing),
                _BottomAction(
                  icon: Icons.grid_view_rounded,
                  onPressed: onOpenMedia,
                ),
              ],
              if (!showPreviewTools) ...[
                const SizedBox(width: actionSpacing),
                _BottomAction(
                  icon: Icons.delete_outline_rounded,
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Win/Mac 独立小窗：深色遮罩上的左右翻页 + 底部「第 N 张图片，共 M 张」。
class MediaPreviewDesktopOverlayChrome extends StatelessWidget {
  const MediaPreviewDesktopOverlayChrome({
    required this.page,
    required this.count,
    this.onPrevious,
    this.onNext,
    this.onShare,
    this.onDownload,
    this.onMore,
    this.onRotate,
    super.key,
  });

  final int page;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onShare;
  final VoidCallback? onDownload;
  final VoidCallback? onMore;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 18;
    final label = TIM_t_para(
      "第 {{option1}} 张图片，共 {{option2}} 张",
      "第 $page 张图片，共 $count 张",
    )(option1: '$page', option2: '$count');
    return Stack(
      children: [
        if (onPrevious != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: MediaPreviewCircleButton(
                icon: Icons.chevron_left_rounded,
                onPressed: onPrevious!,
              ),
            ),
          ),
        if (onNext != null)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: MediaPreviewCircleButton(
                icon: Icons.chevron_right_rounded,
                onPressed: onNext!,
              ),
            ),
          ),
        Positioned(
          left: 20,
          right: 16,
          bottom: bottom,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _BottomAction(
                icon: Icons.ios_share_rounded,
                onPressed: onShare,
              ),
              const SizedBox(width: 4),
              _BottomAction(
                icon: Icons.rotate_right_rounded,
                onPressed: onRotate,
              ),
              const SizedBox(width: 4),
              _BottomAction(
                icon: Icons.download_rounded,
                onPressed: onDownload,
              ),
              const SizedBox(width: 4),
              _BottomAction(
                icon: Icons.more_horiz_rounded,
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

enum MediaPreviewDesktopMoreAction {
  goToMessage,
  copy,
  forward,
  delete,
  saveAs,
  showAllImages,
}

/// Win/Mac 独立小窗「更多」：深色桌面菜单，不用手机端 CupertinoActionSheet。
Future<void> showMediaPreviewDesktopMoreMenu({
  required BuildContext context,
  VoidCallback? onGoToMessage,
  VoidCallback? onCopy,
  VoidCallback? onForward,
  VoidCallback? onDelete,
  VoidCallback? onSaveAs,
  VoidCallback? onShowAllImages,
  Offset? globalPosition,
}) async {
  final handlers = <MediaPreviewDesktopMoreAction, VoidCallback?>{
    MediaPreviewDesktopMoreAction.goToMessage: onGoToMessage,
    MediaPreviewDesktopMoreAction.copy: onCopy,
    MediaPreviewDesktopMoreAction.forward: onForward,
    MediaPreviewDesktopMoreAction.delete: onDelete,
    MediaPreviewDesktopMoreAction.saveAs: onSaveAs,
    MediaPreviewDesktopMoreAction.showAllImages: onShowAllImages,
  };
  if (handlers.values.every((handler) => handler == null)) {
    return;
  }

  final selected = await showMenu<MediaPreviewDesktopMoreAction>(
    context: context,
    position: _desktopMoreMenuPosition(
      context,
      globalPosition: globalPosition,
    ),
    color: const Color(0xFF2C2C2C),
    elevation: 10,
    shadowColor: Colors.black.withValues(alpha: 0.45),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    items: [
      _desktopMoreItem(
        MediaPreviewDesktopMoreAction.goToMessage,
        Icons.visibility_outlined,
        TIM_t('前往消息'),
        enabled: onGoToMessage != null,
      ),
      _desktopMoreItem(
        MediaPreviewDesktopMoreAction.copy,
        Icons.copy_outlined,
        TIM_t('复制'),
        enabled: onCopy != null,
      ),
      _desktopMoreItem(
        MediaPreviewDesktopMoreAction.forward,
        Icons.reply_outlined,
        TIM_t('转发'),
        enabled: onForward != null,
      ),
      _desktopMoreItem(
        MediaPreviewDesktopMoreAction.delete,
        Icons.delete_outline_rounded,
        TIM_t('删除'),
        enabled: onDelete != null,
      ),
      _desktopMoreItem(
        MediaPreviewDesktopMoreAction.saveAs,
        Icons.download_outlined,
        TIM_t('另存为...'),
        enabled: onSaveAs != null,
      ),
      _desktopMoreItem(
        MediaPreviewDesktopMoreAction.showAllImages,
        Icons.grid_view_outlined,
        TIM_t('显示所有图片'),
        enabled: onShowAllImages != null,
      ),
    ],
  );
  if (selected == null) {
    return;
  }
  handlers[selected]?.call();
}

PopupMenuItem<MediaPreviewDesktopMoreAction> _desktopMoreItem(
  MediaPreviewDesktopMoreAction action,
  IconData icon,
  String label, {
  required bool enabled,
}) {
  const color = Color(0xFFEDEDED);
  return PopupMenuItem<MediaPreviewDesktopMoreAction>(
    value: action,
    enabled: enabled,
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: color,
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    ),
  );
}

RelativeRect _desktopMoreMenuPosition(
  BuildContext context, {
  Offset? globalPosition,
}) {
  if (globalPosition != null) {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is RenderBox) {
      final local = overlay.globalToLocal(globalPosition);
      return RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      );
    }
  }
  final size = MediaQuery.sizeOf(context);
  const menuWidth = 220.0;
  const right = 16.0;
  const bottomChrome = 62.0;
  const estimatedHeight = 276.0;
  return RelativeRect.fromLTRB(
    size.width - menuWidth - right,
    (size.height - estimatedHeight - bottomChrome).clamp(8.0, size.height),
    right,
    bottomChrome,
  );
}

Future<void> showMediaPreviewMoreSheet({
  required BuildContext context,
  VoidCallback? onDownload,
  VoidCallback? onEdit,
  VoidCallback? onForward,
  VoidCallback? onDelete,
}) async {
  final actions = <Widget>[];

  void addAction(String label, VoidCallback? handler) {
    if (handler == null) {
      return;
    }
    actions.add(
      CupertinoActionSheetAction(
        onPressed: () {
          Navigator.pop(context);
          handler();
        },
        child: Text(label),
      ),
    );
  }

  addAction(TIM_t('保存到相册'), onDownload);
  addAction(TIM_t('编辑'), onEdit);
  addAction(TIM_t('转发'), onForward);
  if (onDelete != null) {
    actions.add(
      CupertinoActionSheetAction(
        isDestructiveAction: true,
        onPressed: () {
          Navigator.pop(context);
          onDelete();
        },
        child: Text(TIM_t('删除')),
      ),
    );
  }

  if (actions.isEmpty) {
    return;
  }

  await showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      actions: actions,
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(sheetContext),
        child: Text(TIM_t('取消')),
      ),
    ),
  );
}
