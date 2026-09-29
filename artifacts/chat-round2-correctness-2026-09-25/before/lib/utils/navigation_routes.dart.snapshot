import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';

/// 全屏路由语义：
/// - [push]：普通移动端二级页（右滑 + 左侧 24px 返回）。本轮实现。
/// - present：全屏模态（自下而上）。本轮不实现，保留 [cupertino] 的 fullscreenDialog 与专用 Route。
/// - mediaPreview：Hero / 媒体预览专用 Route。本轮不实现，禁止用 [push]。
/// - call：通话专用淡入/退出。本轮不实现，禁止用 [push]。
class NavigationRoutes {
  NavigationRoutes._();

  static AppMaterialPageRoute<T> push<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool maintainState = true,
    bool? allowSnapshotting,
    bool enableFullScreenBackGesture = true,
    double edgeStartWidthPx = 24.0,
    int routeVisibilityDeferredFrames = 1,
    Duration transitionDuration = const Duration(milliseconds: 300),
  }) {
    return AppMaterialPageRoute<T>(
      builder: builder,
      settings: settings,
      maintainState: maintainState,
      allowSnapshotting: allowSnapshotting,
      enableFullScreenBackGesture: enableFullScreenBackGesture,
      edgeStartWidthPx: edgeStartWidthPx,
      routeVisibilityDeferredFrames: routeVisibilityDeferredFrames,
      transitionDuration: transitionDuration,
    );
  }

  static PageRoute<T> cupertino<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool maintainState = true,
    bool fullscreenDialog = false,
    bool allowSnapshotting = false,
  }) {
    if (fullscreenDialog) {
      return AppFullscreenDialogRoute<T>(
        builder: builder,
        settings: settings,
        maintainState: maintainState,
        allowSnapshotting: allowSnapshotting,
      );
    }
    return push<T>(
      builder: builder,
      settings: settings,
      maintainState: maintainState,
    );
  }
}
