import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_store.dart';

/// 搜索栏下方随主题切换的分组胶囊条。
/// 无分组时不应挂载本组件。
class ConversationFolderChipBar extends StatefulWidget {
  const ConversationFolderChipBar({
    super.key,
    required this.folders,
    required this.selectedFolderId,
    required this.unreadForFolder,
    this.hasNotifiableUnreadForFolder,
    required this.onSelectAll,
    required this.onSelectFolder,
    required this.onCreateFolder,
    required this.reorderEditing,
    this.onExitReorderEditing,
    this.onDeleteFolder,
    this.onFolderLongPress,
    this.onReorderFolders,
  });

  final List<ConversationFolder> folders;
  final String? selectedFolderId;
  final int Function(ConversationFolder folder) unreadForFolder;
  final bool Function(ConversationFolder folder)? hasNotifiableUnreadForFolder;
  final VoidCallback onSelectAll;
  final ValueChanged<String> onSelectFolder;
  final VoidCallback onCreateFolder;
  final bool reorderEditing;
  final VoidCallback? onExitReorderEditing;
  final ValueChanged<ConversationFolder>? onDeleteFolder;
  final ValueChanged<ConversationFolder>? onFolderLongPress;
  final void Function(int oldIndex, int newIndex)? onReorderFolders;

  static const Color _barBg = Color(0xFFFFFFFF);
  static const Color _selectedBg = Color(0xFFECECEC);
  static const Color _labelColor = Color(0xFF1C1C1E);
  static const Color _badgeBg = Color(0xFFA8A8AE);
  static const Color _addFg = Color(0xFF8E8E93);

  @override
  State<ConversationFolderChipBar> createState() =>
      _ConversationFolderChipBarState();
}

class _ConversationFolderChipBarState extends State<ConversationFolderChipBar> {
  late List<ConversationFolder> _folders;
  List<String>? _pendingReorderIds;
  late final ScrollController _scrollController;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _folders = List<ConversationFolder>.of(widget.folders);
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ConversationFolderChipBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resolved = ConversationFolderStore.resolveFolderBarDisplay(
      local: _folders,
      parent: widget.folders,
      pendingReorderIds: _pendingReorderIds,
    );
    _folders = resolved.folders;
    _pendingReorderIds = resolved.pendingReorderIds;
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      _folders = ConversationFolderStore.foldersAfterReorder(
        folders: _folders,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
      _pendingReorderIds =
          _folders.map((f) => f.folderId).toList(growable: false);
    });
    widget.onReorderFolders?.call(oldIndex, newIndex);
  }

  static void _ignoreReorder(int oldIndex, int newIndex) {}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final barBackground = dark ? theme.colorScheme.surfaceContainerLow : ConversationFolderChipBar._barBg;
    final addForeground = dark ? theme.colorScheme.onSurfaceVariant : ConversationFolderChipBar._addFg;
    if (_folders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
      child: Row(
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: barBackground,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow:
                      dark || defaultTargetPlatform == TargetPlatform.android
                          ? const <BoxShadow>[]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              ),
                            ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: SizedBox(
                    height: 32,
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      primary: false,
                      scrollController: _scrollController,
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.zero,
                      header: _Segment(
                        label: AppI18n.of(context).t(
                          zhHans: '全部',
                          zhHant: '全部',
                          en: 'All',
                          ja: 'すべて',
                          ko: '전체',
                        ),
                        selected: widget.selectedFolderId == null,
                        badge: 0,
                        onTap: () {
                          if (widget.reorderEditing) {
                            widget.onExitReorderEditing?.call();
                          }
                          widget.onSelectAll();
                        },
                      ),
                      itemCount: _folders.length,
                      onReorder: widget.onReorderFolders == null
                          ? _ignoreReorder
                          : _onReorder,
                      onReorderStart: (_) {
                        setState(() {
                          _isDragging = true;
                        });
                      },
                      onReorderEnd: (_) {
                        setState(() {
                          _isDragging = false;
                        });
                      },
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, _) {
                            final t =
                                Curves.easeOut.transform(animation.value);
                            return Material(
                              elevation: 3 * t,
                              color: Colors.transparent,
                              shadowColor: Colors.black26,
                              borderRadius: BorderRadius.circular(999),
                              child: child,
                            );
                          },
                        );
                      },
                      itemBuilder: (context, index) {
                        final folder = _folders[index];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey<String>(folder.folderId),
                          index: index,
                          enabled: widget.reorderEditing,
                          child: _Segment(
                            label: folder.name,
                            selected:
                                widget.selectedFolderId == folder.folderId,
                            badge: widget.unreadForFolder(folder),
                            notifiable: widget.hasNotifiableUnreadForFolder?.call(folder) ?? true,
                            onTap: () =>
                                widget.onSelectFolder(folder.folderId),
                            onLongPress: widget.reorderEditing ||
                                    widget.onFolderLongPress == null
                                ? null
                                : () => widget.onFolderLongPress!(folder),
                            onSecondaryTap: widget.reorderEditing ||
                                    widget.onFolderLongPress == null
                                ? null
                                : () => widget.onFolderLongPress!(folder),
                            jiggle: widget.reorderEditing && !_isDragging,
                            showClose: widget.reorderEditing,
                            onClose: widget.onDeleteFolder == null
                                ? null
                                : () => widget.onDeleteFolder!(folder),
                            jigglePhaseMs:
                                folder.folderId.hashCode.abs() % 120,
                            jiggleInvert: folder.folderId.hashCode.isOdd,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: widget.reorderEditing
                  ? () => widget.onExitReorderEditing?.call()
                  : widget.onCreateFolder,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: barBackground,
                  shape: BoxShape.circle,
                  boxShadow:
                      dark || defaultTargetPlatform == TargetPlatform.android
                          ? const <BoxShadow>[]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 1),
                              ),
                            ],
                ),
                child: Icon(
                  widget.reorderEditing
                      ? Icons.check_rounded
                      : Icons.add_rounded,
                  size: 21,
                  color: addForeground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipJiggle extends StatefulWidget {
  const _ChipJiggle({
    required this.phase,
    required this.invert,
    required this.child,
  });

  final Duration phase;
  final bool invert;
  final Widget child;

  @override
  State<_ChipJiggle> createState() => _ChipJiggleState();
}

class _ChipJiggleState extends State<_ChipJiggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.invert ? 1 : 0,
    );
    _delay = Timer(widget.phase, () {
      if (!mounted) {
        return;
      }
      _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          alignment: Alignment.center,
          angle: 0.045 * (2 * _controller.value - 1),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.badge,
    this.notifiable = true,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.jiggle = false,
    this.showClose = false,
    this.onClose,
    this.jigglePhaseMs = 0,
    this.jiggleInvert = false,
  });

  final String label;
  final bool selected;
  final int badge;
  final bool notifiable;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool jiggle;
  final bool showClose;
  final VoidCallback? onClose;
  final int jigglePhaseMs;
  final bool jiggleInvert;

  @override
  Widget build(BuildContext context) {
    final badgeText = badge > 99 ? '99+' : '$badge';
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onSecondaryTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? (dark
                      ? colors.surfaceContainerHighest
                      : ConversationFolderChipBar._selectedBg)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: dark
                        ? colors.onSurface
                        : ConversationFolderChipBar._labelColor,
                    height: 1.1,
                  ),
                ),
                if (showClose) ...[
                  const SizedBox(width: 2),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: dark
                          ? colors.onSurfaceVariant
                          : ConversationFolderChipBar._addFg,
                    ),
                  ),
                ] else if (badge > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    height: 16,
                    padding: EdgeInsets.symmetric(
                      horizontal: badgeText.length > 1 ? 4 : 0,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: notifiable ? const Color(0xFFFF524B) : dark
                          ? colors.secondaryContainer
                          : ConversationFolderChipBar._badgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color:
                            !notifiable && dark ? colors.onSecondaryContainer : Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (jiggle) {
      content = _ChipJiggle(
        phase: Duration(milliseconds: jigglePhaseMs),
        invert: jiggleInvert,
        child: content,
      );
    }
    return content;
  }
}
