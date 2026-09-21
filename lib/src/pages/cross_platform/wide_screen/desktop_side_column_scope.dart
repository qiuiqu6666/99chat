import 'package:flutter/material.dart';

class DesktopSideColumnRoute<T> extends MaterialPageRoute<T> {
  DesktopSideColumnRoute({
    required WidgetBuilder builder,
    required this.title,
  }) : super(
          builder: builder,
          settings: RouteSettings(name: title),
        );

  final String title;
}

class DesktopSideColumnScope extends InheritedWidget {
  const DesktopSideColumnScope({
    super.key,
    required super.child,
  });

  static DesktopSideColumnScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DesktopSideColumnScope>();
  }

  static Future<T?> push<T>(
    BuildContext context, {
    required String title,
    required Widget page,
  }) {
    return Navigator.of(context).push<T>(
      DesktopSideColumnRoute<T>(
        title: title,
        builder: (_) => page,
      ),
    );
  }

  @override
  bool updateShouldNotify(covariant DesktopSideColumnScope oldWidget) => false;
}
