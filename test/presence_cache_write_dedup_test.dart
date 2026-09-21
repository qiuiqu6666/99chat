import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:tencent_cloud_chat_demo/src/services/coalesced_presence_cache.dart';

class RecordingPreferences extends InMemorySharedPreferencesStore {
  RecordingPreferences() : super.empty();
  int writes = 0;
  bool fail = false;
  Completer<void>? barrier;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    await barrier?.future;
    if (fail) return false;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingPreferences store;
  late CoalescedPresenceCache cache;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = RecordingPreferences();
    SharedPreferencesStorePlatform.instance = store;
    cache = CoalescedPresenceCache();
  });

  test('identical events across flush intervals produce no extra writes',
      () async {
    await cache.merge('a', {'u': 100, 'v': 'everyone'});
    for (var i = 0; i < 10; i++) {
      await cache.merge('a', {'v': 'everyone', 'u': 100});
    }
    expect(store.writes, 1);
    await cache.merge('a', {'u': 101});
    expect(store.writes, 2);
  });

  test('failed persistence allows an identical retry', () async {
    store.fail = true;
    await expectLater(cache.merge('a', {'u': 100}), throwsStateError);
    store.fail = false;
    await cache.merge('a', {'u': 100});
    expect(store.writes, 2);
    expect(await store.getAll(), containsPair('flutter.a', '{"u":100}'));
  });

  test('duplicate in flight waits; clear precedes new account writes',
      () async {
    store.barrier = Completer<void>();
    final first = cache.merge('a', {'u': 100});
    await Future<void>.delayed(const Duration(milliseconds: 230));
    var duplicateDone = false;
    final duplicate =
        cache.merge('a', {'u': 100}).then((_) => duplicateDone = true);
    final clear = cache.clear('a');
    final newWrite = cache.merge('a', {'v': 200});
    await Future<void>.delayed(const Duration(milliseconds: 230));
    expect(duplicateDone, isFalse);
    store.barrier!.complete();
    await Future.wait([first, duplicate, clear, newWrite]);
    final values = await store.getAll();
    expect(jsonDecode(values['flutter.a']! as String), {'v': 200});
  });

  test('evicted account snapshots reload and still avoid identical writes',
      () async {
    for (var i = 0; i < CoalescedPresenceCache.maxSnapshots + 2; i++) {
      await cache.merge('account$i', {'u': i});
    }
    final before = store.writes;
    await cache.merge('account0', {'u': 0});
    expect(store.writes, before);
  });
}
