import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/features/paint_editor/widgets/paint_editor_appbar.dart';
import 'package:pro_image_editor/features/paint_editor/widgets/paint_editor_bottombar.dart';
import 'package:pro_image_editor/features/text_editor/widgets/text_editor_appbar.dart';

/// 悬浮顶栏 / 底栏的半透明背景色（50% 黑）。
const Color kAppImageEditorBarOverlayColor = Color(0x80000000);

/// 通用悬浮容器：贴顶或贴底，自行补齐系统状态栏 / 底部手势区高度。
///
/// 编辑器本身的 [SafeArea] 已被关闭，因此这里通过 [MediaQuery.paddingOf]
/// 读取安全区，并用 [MediaQuery.removePadding] 防止包内 `AppBar` 类组件
/// 再次叠加状态栏 padding。
class AppImageEditorFloatingBar extends StatelessWidget {
  const AppImageEditorFloatingBar.top({super.key, required this.child})
      : isTop = true,
        barHeight = kToolbarHeight;

  const AppImageEditorFloatingBar.bottom({super.key, required this.child})
      : isTop = false,
        barHeight = kBottomNavigationBarHeight;

  final bool isTop;
  final double barHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final inset = isTop ? padding.top : padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      child: Container(
        height: barHeight + inset,
        color: kAppImageEditorBarOverlayColor,
        padding: EdgeInsets.only(
          top: isTop ? inset : 0,
          bottom: isTop ? 0 : inset,
        ),
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: SizedBox(height: barHeight, child: child),
        ),
      ),
    );
  }
}

/// 主编辑器悬浮顶栏：关闭 / 撤销 / 重做 / 完成。
class AppImageEditorMainTopBar extends StatelessWidget {
  const AppImageEditorMainTopBar({super.key, required this.editor});

  final ProImageEditorState editor;

  @override
  Widget build(BuildContext context) {
    if (editor.selectedLayerIndex >= 0) {
      return const SizedBox.shrink();
    }
    final style = editor.configs.mainEditor.style;
    final icons = editor.configs.mainEditor.icons;
    final i18n = editor.configs.i18n;
    final fg = style.appBarColor;
    return AppImageEditorFloatingBar.top(
      child: Row(
        children: [
          if (editor.configs.mainEditor.enableCloseButton)
            IconButton(
              tooltip: i18n.cancel,
              icon: Icon(icons.closeEditor, color: fg),
              onPressed: editor.closeEditor,
            ),
          const Spacer(),
          IconButton(
            tooltip: i18n.undo,
            icon: Icon(
              icons.undoAction,
              color: editor.stateManager.canUndo ? fg : fg.withAlpha(80),
            ),
            onPressed: editor.undoAction,
          ),
          IconButton(
            tooltip: i18n.redo,
            icon: Icon(
              icons.redoAction,
              color: editor.stateManager.canRedo ? fg : fg.withAlpha(80),
            ),
            onPressed: editor.redoAction,
          ),
          IconButton(
            tooltip: i18n.done,
            iconSize: 28,
            icon: Icon(icons.doneIcon, color: fg),
            onPressed: editor.doneEditing,
          ),
        ],
      ),
    );
  }
}

/// 主编辑器悬浮底栏：涂鸦 / 文字 / 裁剪三个入口。
class AppImageEditorMainBottomBar extends StatelessWidget {
  const AppImageEditorMainBottomBar({super.key, required this.editor});

  final ProImageEditorState editor;

  Widget _entry({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (editor.selectedLayerIndex >= 0) {
      return const SizedBox.shrink();
    }
    final cfg = editor.configs;
    final fg = cfg.mainEditor.style.bottomBarColor;
    return AppImageEditorFloatingBar.bottom(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _entry(
            icon: cfg.paintEditor.icons.bottomNavBar,
            label: cfg.i18n.paintEditor.bottomNavigationBarText,
            onTap: editor.openPaintEditor,
            color: fg,
          ),
          _entry(
            icon: cfg.textEditor.icons.bottomNavBar,
            label: cfg.i18n.textEditor.bottomNavigationBarText,
            onTap: () => editor.openTextEditor(),
            color: fg,
          ),
          _entry(
            icon: cfg.cropRotateEditor.icons.bottomNavBar,
            label: cfg.i18n.cropRotateEditor.bottomNavigationBarText,
            onTap: editor.openCropRotateEditor,
            color: fg,
          ),
        ],
      ),
    );
  }
}

/// 涂鸦编辑器悬浮顶栏：复用包内默认 [PaintEditorAppBar]。
class AppImageEditorPaintTopBar extends StatelessWidget {
  const AppImageEditorPaintTopBar({super.key, required this.editor});

  final PaintEditorState editor;

  @override
  Widget build(BuildContext context) {
    return AppImageEditorFloatingBar.top(
      child: LayoutBuilder(
        builder: (context, constraints) => PaintEditorAppBar(
          paintEditorConfigs: editor.paintEditorConfigs,
          i18n: editor.i18n.paintEditor,
          constraints: constraints,
          onUndo: editor.undoAction,
          onRedo: editor.redoAction,
          onToggleFill: editor.toggleFill,
          onTapMenuFill: () {
            editor.toggleFill();
            if (editor.designMode == ImageEditorDesignMode.cupertino) {
              Navigator.of(context).pop();
            }
          },
          onDone: editor.done,
          onClose: editor.close,
          canUndo: editor.canUndo,
          canRedo: editor.canRedo,
          isFillMode: editor.fillBackground,
          onOpenOpacityBottomSheet: editor.openOpacityBottomSheet,
          onOpenLineWeightBottomSheet: editor.openLinWidthBottomSheet,
          designMode: editor.designMode,
        ),
      ),
    );
  }
}

/// 涂鸦编辑器悬浮底栏：复用包内默认 [PaintEditorBottombar]。
class AppImageEditorPaintBottomBar extends StatefulWidget {
  const AppImageEditorPaintBottomBar({super.key, required this.editor});

  final PaintEditorState editor;

  @override
  State<AppImageEditorPaintBottomBar> createState() =>
      _AppImageEditorPaintBottomBarState();
}

class _AppImageEditorPaintBottomBarState
    extends State<AppImageEditorPaintBottomBar> {
  late final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    return AppImageEditorFloatingBar.bottom(
      child: PaintEditorBottombar(
        configs: editor.paintEditorConfigs,
        paintMode: editor.paintMode,
        i18n: editor.i18n.paintEditor,
        theme: editor.theme,
        enableZoom: editor.paintEditorConfigs.enableZoom,
        paintModes: editor.paintModes,
        setMode: editor.setMode,
        bottomBarScrollCtrl: _scrollCtrl,
      ),
    );
  }
}

/// 文字编辑器悬浮顶栏：复用包内默认 [TextEditorAppBar]。
class AppImageEditorTextTopBar extends StatelessWidget {
  const AppImageEditorTextTopBar({super.key, required this.editor});

  final TextEditorState editor;

  @override
  Widget build(BuildContext context) {
    return AppImageEditorFloatingBar.top(
      child: LayoutBuilder(
        builder: (context, constraints) => TextEditorAppBar(
          textEditorConfigs: editor.textEditorConfigs,
          i18n: editor.i18n.textEditor,
          onClose: editor.close,
          onDone: editor.done,
          align: editor.align,
          onToggleTextAlign: editor.toggleTextAlign,
          onOpenFontScaleBottomSheet: editor.openFontScaleBottomSheet,
          onToggleBackgroundMode: editor.toggleBackgroundMode,
          designMode: editor.designMode,
          constraints: constraints,
        ),
      ),
    );
  }
}

List<ReactiveWidget> appImageEditorMainBodyItems(
  ProImageEditorState editor,
  Stream<void> stream,
) {
  return [
    ReactiveWidget(
      stream: stream,
      builder: (_) => AppImageEditorMainTopBar(editor: editor),
    ),
    ReactiveWidget(
      stream: stream,
      builder: (_) => AppImageEditorMainBottomBar(editor: editor),
    ),
  ];
}

List<ReactiveWidget> appImageEditorPaintBodyItems(
  PaintEditorState editor,
  Stream<void> stream,
) {
  return [
    ReactiveWidget(
      stream: stream,
      builder: (_) => AppImageEditorPaintTopBar(editor: editor),
    ),
    ReactiveWidget(
      stream: stream,
      builder: (_) => AppImageEditorPaintBottomBar(editor: editor),
    ),
  ];
}

List<ReactiveWidget> appImageEditorTextBodyItems(
  TextEditorState editor,
  Stream<void> stream,
) {
  return [
    ReactiveWidget(
      stream: stream,
      builder: (_) => AppImageEditorTextTopBar(editor: editor),
    ),
  ];
}
