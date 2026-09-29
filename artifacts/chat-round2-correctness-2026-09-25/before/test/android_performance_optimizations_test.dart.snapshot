import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/paged_group_recipient_picker.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_member.dart';
import 'package:tencent_cloud_chat_demo/src/services/coalesced_presence_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_chat_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/splash_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('presence burst shares one flush and keeps every update', () async {
    final cache = CoalescedPresenceCache();
    final writes = List.generate(40, (i) => cache.merge('owner_a', {'u$i': i}));
    expect(identical(writes.first, writes.last), isTrue);
    await Future.wait(writes);
    final prefs = await SharedPreferences.getInstance();
    final data = jsonDecode(prefs.getString('owner_a')!) as Map;
    expect(data.length, 40);
    expect(data['u39'], 39);
    await cache.merge('owner_a', {'u0': 100});
    expect((jsonDecode(prefs.getString('owner_a')!) as Map)['u0'], 100);
  });

  test('presence clear cancels pending writes without crossing accounts',
      () async {
    final cache = CoalescedPresenceCache();
    final old = cache.merge('owner_a', {'u1': 'hidden'});
    final other = cache.merge('owner_b', {'u1': 'everyone'});
    await cache.clear('owner_a');
    await Future.wait([old, other]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('owner_a'), isNull);
    expect(jsonDecode(prefs.getString('owner_b')!), {'u1': 'everyone'});
    await cache.merge('owner_a', {'u2': 'hidden'});
    expect(jsonDecode(prefs.getString('owner_a')!), {'u2': 'hidden'});
  });

  test('presence cache has a fixed retention bound', () async {
    final cache = CoalescedPresenceCache();
    await cache.merge('bounded', {for (var i = 0; i < 6000; i++) 'u$i': i});
    final prefs = await SharedPreferences.getInstance();
    final data = jsonDecode(prefs.getString('bounded')!) as Map;
    expect(data.length, CoalescedPresenceCache.maxEntries);
    expect(data['u5999'], 5999);
  });

  test('recipient list loads only one page per request, merges duplicate ids',
      () async {
    var calls = 0;
    final pager = RecipientMemberPager((keyword, cursor) async {
      calls++;
      return RecipientMemberPage([
        RedPacketMember(userId: 'u1', name: 'page$calls'),
        if (cursor.isNotEmpty)
          const RedPacketMember(userId: 'u2', name: 'second'),
      ], cursor.isEmpty ? 'next' : null);
    });
    await pager.load();
    expect(calls, 1);
    expect(pager.members.length, 1);
    await pager.load();
    expect(pager.members.length, 2);
    expect(pager.members.first.name, 'page2');
    await pager.load();
    expect(calls, 2);
    pager.dispose();
  });

  test('recipient query change discards old response and coalesces scrolls',
      () async {
    final old = Completer<RecipientMemberPage>();
    var calls = 0;
    final pager = RecipientMemberPager((keyword, cursor) {
      calls++;
      return keyword.isEmpty
          ? old.future
          : Future.value(const RecipientMemberPage(
              [RedPacketMember(userId: 'new', name: 'new')], null));
    });
    final initial = pager.load();
    await pager.load();
    expect(calls, 1);
    await pager.search('new');
    old.complete(const RecipientMemberPage(
        [RedPacketMember(userId: 'old', name: 'old')], '2'));
    await initial;
    expect(pager.members.single.userId, 'new');
    expect(pager.cursor, isNull);
    pager.dispose();
  });

  test('recipient retry preserves cursor and rejects repeated cursors',
      () async {
    var calls = 0;
    final pager = RecipientMemberPager((keyword, cursor) async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return RecipientMemberPage(const [], calls == 2 ? 'next' : 'next');
    });
    await pager.load();
    expect(pager.failed, isTrue);
    expect(pager.cursor, '');
    await pager.load();
    expect(pager.failed, isFalse);
    await pager.load();
    expect(pager.failed, isTrue);
    pager.dispose();
  });

  group('live reconciliation', () {
    final dio = ApiClient.instance.dio;
    late List<Interceptor> saved;
    late GroupLiveChatState state;
    late List<(RequestOptions, RequestInterceptorHandler)> pending;
    setUp(() {
      saved = dio.interceptors.toList();
      dio.interceptors.clear();
      pending = [];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        pending.add((request, handler));
      }));
      state = GroupLiveChatState();
    });
    tearDown(() {
      state.dispose();
      dio.interceptors.clear();
      dio.interceptors.addAll(saved);
    });
    Future<void> waitRequests(int count) async {
      for (var i = 0; i < 100 && pending.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(pending.length, count);
    }

    void respond(int index, String id, {String room = 'room'}) {
      final (request, handler) = pending[index];
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {
          'active': true,
          'session': {
            'liveSessionId': id,
            'roomName': room,
            'anchorUserId': 'anchor',
            'status': 'LIVE',
          }
        }
      }));
    }

    test('concurrent refresh is single flight and unchanged data stays quiet',
        () async {
      var notices = 0;
      state.addListener(() => notices++);
      final first = state.refresh('group');
      final same = state.refresh('group');
      expect(identical(first, same), isTrue);
      await waitRequests(1);
      respond(0, 'session');
      await first;
      expect(notices, 1);
      final repeat = state.refresh('group');
      await waitRequests(2);
      respond(1, 'session');
      await repeat;
      expect(notices, 1);
      final changed = state.refresh('group');
      await waitRequests(3);
      respond(2, 'session', room: 'renamed');
      await changed;
      expect(notices, 2);
    });
    test('previous group and cleared requests cannot publish late results',
        () async {
      final old = state.refresh('old');
      final current = state.refresh('new');
      await waitRequests(2);
      respond(1, 'new-session');
      await current;
      respond(0, 'old-session');
      await old;
      expect(state.activeSession!.groupId, 'new');
      final cleared = state.refresh('new');
      await waitRequests(3);
      state.clear();
      respond(2, 'late-session');
      await cleared;
      expect(state.snapshot, isNull);
    });
  });

  test('splash validation is reusable only for identical bytes and metadata',
      () async {
    final dir = await Directory.systemTemp.createTemp('splash_perf_test_');
    try {
      final file = File('${dir.path}/image.png');
      final bytes = img.encodePng(img.Image(width: 20, height: 30));
      await file.writeAsBytes(bytes);
      final config = {
        'enabled': true,
        'version': 'perf',
        'imageUrl': 'https://example.test/image.png',
        'width': 20,
        'height': 30,
        'bytes': bytes.length
      };
      SharedPreferences.setMockInitialValues({
        'platform_splash_cache_v1': jsonEncode({
          'config': config,
          'localPath': file.path,
        })
      });
      await SplashConfigService.instance.prepareForLaunch();
      expect(SplashConfigService.instance.cachedFilePath, file.path);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('platform_splash_validated_md5_v1'), isNotNull);
      await SplashConfigService.instance.prepareForLaunch();
      expect(SplashConfigService.instance.cachedFilePath, file.path);
      // Matching file length alone must not be accepted as validation.
      await file.writeAsBytes(List.filled(bytes.length, 0));
      await SplashConfigService.instance.prepareForLaunch();
      expect(SplashConfigService.instance.cachedFilePath, isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
