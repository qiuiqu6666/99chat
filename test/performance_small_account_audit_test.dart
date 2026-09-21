// Diagnostic evidence for the September 2026 audit, not Android frame timings.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_chat_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('unchanged inactive live snapshot does not publish',
      () async {
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests++;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {'active': false}
      }));
    }));
    final state = GroupLiveChatState();
    var notifications = 0;
    state.addListener(() => notifications++);
    try {
      await state.refresh('audit_group');
      await state.refresh('audit_group');
      expect(state.activeSession, isNull);
      expect(requests, 2);
      expect(notifications, 0);
    } finally {
      state.dispose();
      dio.interceptors.clear();
      dio.interceptors.addAll(saved);
    }
  });

  test('audit: compare whole-group and keyed reads with 6000 cached members',
      () async {
    const owner = 'performance_audit_synthetic_owner';
    const group = '@TGS#performance_audit_synthetic';
    final store = GroupMemberLocalStore.instance;
    await store.clearForOwner(owner);
    try {
      await store.replaceSnapshot(
          ownerUserId: owner,
          groupId: group,
          records: List.generate(
              6000,
              (i) => GroupMemberRecord(
                  userId: 'audit_$i',
                  nickname: 'Member $i',
                  avatarUrl: '',
                  friendRemark: '',
                  nameCard: '',
                  role: 200,
                  joinedAt: i,
                  isSelf: false)));
      final samples = <String, List<double>>{
        'all6000': [],
        'keyed1': [],
        'patch1': []
      };
      for (var i = 0; i < 6; i++) {
        final watch = Stopwatch()..start();
        final all = await store.readAll(groupId: group, ownerUserId: owner);
        final allMs = watch.elapsedMicroseconds / 1000;
        expect(all.length, 6000);
        watch.reset();
        final one = await store.readRecordsByUserIds(
            groupId: group, ownerUserId: owner, userIds: ['audit_3000']);
        final oneMs = watch.elapsedMicroseconds / 1000;
        expect(one.length, 1);
        watch.reset();
        await store.patchUser(
            ownerUserId: owner,
            groupId: group,
            userId: 'audit_3000',
            transform: (row) => row.copyWith(nameCard: 'sample_$i'));
        final patchMs = watch.elapsedMicroseconds / 1000;
        watch.stop();
        if (i > 0) {
          samples['all6000']!.add(allMs);
          samples['keyed1']!.add(oneMs);
          samples['patch1']!.add(patchMs);
        }
      }
      final patched = await store.readRecord(
          groupId: group, ownerUserId: owner, userId: 'audit_3000');
      expect(patched!.nameCard, 'sample_5');
      expect(patched.nickname, 'Member 3000');
      expect(patched.joinedAt, 3000);
      expect(patched.role, 200);
      final neighbor = await store.readRecord(
          groupId: group, ownerUserId: owner, userId: 'audit_3001');
      expect(neighbor!.nameCard, isEmpty);
      var transformedMissing = false;
      await store.patchUser(
          ownerUserId: owner, groupId: group, userId: 'missing',
          transform: (row) { transformedMissing = true; return row; });
      expect(transformedMissing, isFalse);
      expect(await store.countMembers(groupId: group, ownerUserId: owner), 6000);
      await Directory('test_outputs').create(recursive: true);
      await File('test_outputs/android-small-account-audit-sqlite.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'scope':
            'Host Flutter test + SQLite FFI, synthetic 6000 member group; elapsed includes async DB wait, NOT Android UI blocking duration.',
        'milliseconds': samples,
      }));
    } finally {
      await store.clearForOwner(owner);
    }
  });
}
