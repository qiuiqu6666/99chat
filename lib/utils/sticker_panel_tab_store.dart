import 'package:shared_preferences/shared_preferences.dart';

/// Device-local presentation preference, shared by all chat panels.
class StickerPanelTabStore {
  static final instance = StickerPanelTabStore();
  static const preferenceKey = 'sticker_panel_selected_pack_v1';

  String? selectedName;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // A selection made while storage was loading always wins.
      selectedName ??= prefs.getString(preferenceKey);
    } catch (_) {
      // The panel remains usable when local preferences are unavailable.
    }
  }

  Future<void> select(String name) {
    selectedName = name;
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(preferenceKey, name);
      } catch (_) {
        // Keep the in-memory selection even if persistence fails.
      }
    });
    return _writes;
  }

  static int indexFor(List<String> names, String? selectedName) {
    final index = names.indexOf(selectedName ?? '');
    return index < 0 ? 0 : index;
  }
}
