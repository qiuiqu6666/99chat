/// Recognizes double taps on an already selected home tab.
class HomeTabReselection {
  int? _lastIndex;
  Duration? _lastTap;

  void reset() {
    _lastIndex = null;
    _lastTap = null;
  }

  bool registerTap({
    required int index,
    required int selectedIndex,
    required Duration elapsed,
  }) {
    if (index != selectedIndex) {
      reset();
      return false;
    }
    final previous = _lastTap;
    final repeated = _lastIndex == index &&
        previous != null &&
        elapsed >= previous &&
        elapsed - previous <= const Duration(milliseconds: 300);
    if (repeated) {
      reset();
    } else {
      _lastIndex = index;
      _lastTap = elapsed;
    }
    return repeated;
  }
}
