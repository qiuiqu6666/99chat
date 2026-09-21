import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_column_scope.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

/// 宽屏会话右侧设置列：占 Row 布局空间，列内自带 Navigator。
class DesktopSideSettingsShell extends StatefulWidget {
  const DesktopSideSettingsShell({
    super.key,
    required this.theme,
    required this.width,
    required this.title,
    required this.onClose,
    required this.child,
    this.hideHeader = false,
  });

  final TUITheme theme;
  final double width;
  final String title;
  final VoidCallback onClose;
  final Widget child;
  /// 单聊资料卡自带关闭按钮时，根页隐藏壳标题栏；二级页仍显示返回。
  final bool hideHeader;

  @override
  State<DesktopSideSettingsShell> createState() =>
      _DesktopSideSettingsShellState();
}

class _DesktopSideSettingsShellState extends State<DesktopSideSettingsShell> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  late final _HeaderObserver _observer;
  String? _routeTitle;
  bool _canPop = false;

  @override
  void initState() {
    super.initState();
    _observer = _HeaderObserver(_syncHeader);
  }

  void _syncHeader() {
    if (!mounted) {
      return;
    }
    final nextCanPop = _observer.canPop;
    final nextTitle = _observer.title;
    if (nextCanPop == _canPop && nextTitle == _routeTitle) {
      return;
    }
    // Navigator 首路由在 build 里 didPush；不能在这里同步 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (nextCanPop == _canPop && nextTitle == _routeTitle) {
        return;
      }
      setState(() {
        _canPop = nextCanPop;
        _routeTitle = nextTitle;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.theme.wideBackgroundColor ?? const Color(0xFFFFFFFF);
    final headerBg = widget.theme.appbarBgColor ?? bg;
    final textColor = widget.theme.darkTextColor ?? const Color(0xFF111827);
    final weak = widget.theme.weakTextColor ?? const Color(0xFF9CA3AF);
    final line = widget.theme.weakDividerColor ?? const Color(0xFFE8EAED);
    final title = (_canPop ? _routeTitle : null)?.trim();
    final headerTitle =
        (title != null && title.isNotEmpty) ? title : widget.title;

    return SizedBox(
      width: widget.width,
      child: DesktopSideColumnScope(
        child: Material(
          color: bg,
          elevation: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                left: BorderSide(color: line.withValues(alpha: 0.9)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.hideHeader || _canPop)
                Container(
                  height: 56,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  decoration: BoxDecoration(
                    color: headerBg,
                    border: Border(
                      bottom: BorderSide(color: line.withValues(alpha: 0.85)),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (_canPop)
                        IconButton(
                          onPressed: () {
                            _navKey.currentState?.maybePop();
                          },
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: widget.theme.primaryColor ??
                                const Color(0xFF1E90FF),
                          ),
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          headerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: widget.onClose,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.close_rounded,
                              size: 22,
                              color: weak,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Navigator(
                    key: _navKey,
                    observers: [_observer],
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute<void>(
                        settings: RouteSettings(name: widget.title),
                        builder: (_) => widget.child,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderObserver extends NavigatorObserver {
  _HeaderObserver(this.onChange);

  final VoidCallback onChange;
  String? title;
  bool canPop = false;

  void _refresh(Route<dynamic>? route) {
    title = route?.settings.name;
    canPop = navigator?.canPop() ?? false;
    onChange();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _refresh(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _refresh(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _refresh(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _refresh(previousRoute);
  }
}
