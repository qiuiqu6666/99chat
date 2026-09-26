import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_mention_read_store.dart';

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();
  final entered = Completer<void>();
  Completer<void>? barrier;
  bool fail = false;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (!entered.isCompleted) entered.complete();
    await barrier?.future;
    if (fail) return false;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('exact consumed sequence survives a new store instance', () async {
    final store = GroupMentionReadStore();
    expect(await store.acknowledge('alice', 'group_@TGS#room', '0042'), isTrue);
    final restarted = GroupMentionReadStore();
    expect(await restarted.load('alice', '@TGS#room'), {'42'});
    expect(await restarted.load('alice', '@TGS#other'), isEmpty);
    expect(await restarted.load('bob', '@TGS#room'), isEmpty);
    // An older unvisited mention and a new mention are not implicitly consumed.
    expect(
        (await restarted.load('alice', '@TGS#room')).contains('41'), isFalse);
    expect(
        (await restarted.load('alice', '@TGS#room')).contains('43'), isFalse);
  });

  test('concurrent taps persist every exact sequence without lost updates',
      () async {
    final store = GroupMentionReadStore();
    await Future.wait([
      store.acknowledge('alice', 'group_room', '42'),
      store.acknowledge('alice', 'room', '43'),
      store.acknowledge('alice', 'room', '42'),
    ]);
    expect(await GroupMentionReadStore().load('alice', 'room'), {'42', '43'});
  });

  test('missing owner and invalid sequence cannot create an acknowledgement',
      () async {
    final store = GroupMentionReadStore();
    expect(await store.acknowledge('', 'room', '42'), isFalse);
    expect(await store.acknowledge('alice', 'room', '0'), isFalse);
    expect(await store.acknowledge('alice', 'room', 'bad'), isFalse);
    expect(await store.load('alice', 'room'), isEmpty);
  });

  test('reopening waits for an in-flight mention acknowledgement', () async {
    final prefs = _ControlledPreferences()..barrier = Completer<void>();
    SharedPreferencesStorePlatform.instance = prefs;
    final store = GroupMentionReadStore();
    final write = store.acknowledge('alice', 'room', '42');
    await prefs.entered.future;
    expect(store.cached('alice', 'room'), isNull);
    var restored = false;
    final reopening = store.load('alice', 'room').then((value) {
      restored = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(restored, isFalse);
    prefs.barrier!.complete();
    expect(await write, isTrue);
    expect(await reopening, {'42'});
  });

  test('failed persistence retains reminder and allows a later retry',
      () async {
    final prefs = _ControlledPreferences()..fail = true;
    SharedPreferencesStorePlatform.instance = prefs;
    final store = GroupMentionReadStore();
    expect(await store.acknowledge('alice', 'room', '42'), isFalse);
    expect(await store.load('alice', 'room'), isEmpty);
    prefs.fail = false;
    expect(await store.acknowledge('alice', 'room', '42'), isTrue);
    expect(await GroupMentionReadStore().load('alice', 'room'), {'42'});
  });
}
