/// Host-injected toast presenter for UIKit feedback that must share the
/// application toast bubble (copy / save / etc.).
class TUIKitInfoToast {
  TUIKitInfoToast._();

  /// Set by the host app to render with its compact toast bubble.
  static void Function(String message)? presenter;

  static void show(String message) {
    final showToast = presenter;
    final text = message.trim();
    if (showToast == null || text.isEmpty) {
      return;
    }
    showToast(text);
  }
}
