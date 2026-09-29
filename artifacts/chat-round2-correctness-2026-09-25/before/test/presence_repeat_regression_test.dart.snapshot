import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';

class CountingPrefs extends InMemorySharedPreferencesStore {
  CountingPrefs() : super.empty();
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key.contains('presence_')) writes++;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('identical presence beyond coalescing interval avoids repeated writes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = CountingPrefs();
    SharedPreferencesStorePlatform.instance = prefs;
    final provider = PresenceProvider();
    try {
      await Future<void>.delayed(Duration.zero);
      provider.applyPresenceChanged(
          peerUserId: '12345',
          lastActiveAt: 1700000000000,
          lastActiveVisibility: 'everyone');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      SharedPreferencesStorePlatform.instance = prefs;
      final settings = await SharedPreferences.getInstance();
      await settings.setString('presence_probe', 'test');
      expect(prefs.writes, greaterThan(0));
      prefs.writes = 0;
      var notifications = 0;
      provider.addListener(() => notifications++);
      for (var i = 0; i < 10; i++) {
        provider.applyPresenceChanged(
            peerUserId: '12345',
            lastActiveAt: 1700000000000,
            lastActiveVisibility: 'everyone');
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(notifications, 0);
      expect(prefs.writes, 0);
      // Counts calls into the preferences backend, not physical disk flushes.
      debugPrint(
          '10 identical events: UI notifications=$notifications, preference writes=${prefs.writes}');
    } finally {
      provider.dispose();
    }
  });
}
