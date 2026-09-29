import 'package:flutter/widgets.dart';

/// Explicit work gate for pages retained by the home [IndexedStack].
///
/// [TickerMode] only pauses tickers. Provider and other inherited dependencies
/// can still notify an offstage tab, so expensive descendants should use this
/// scope to remove their listeners while [isActive] is false.
class HomeTabActivity extends InheritedWidget {
  const HomeTabActivity({
    super.key,
    required this.isActive,
    required super.child,
  });

  final bool isActive;

  static bool isActiveOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<HomeTabActivity>()
            ?.isActive ??
        true;
  }

  static bool read(BuildContext context) {
    return context.getInheritedWidgetOfExactType<HomeTabActivity>()?.isActive ??
        true;
  }

  @override
  bool updateShouldNotify(HomeTabActivity oldWidget) {
    return isActive != oldWidget.isActive;
  }
}
