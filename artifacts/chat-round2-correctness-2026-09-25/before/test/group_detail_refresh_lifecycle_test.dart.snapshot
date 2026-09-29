import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'detail-lifecycle-owner';
  const group = '@TGS#_mcDetailLifecycle';
  late GroupMembershipSyncService sync;
  var calls = 0;
  final pending = <RequestInterceptorHandler>[];
  final options = <RequestOptions>[];
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    sync = GroupMembershipSyncService.forTest();
    calls = 0;
    pending.clear();
    options.clear();
    await GroupLocalStore.instance.clearForOwner(owner);
    await GroupLocalStore.instance.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson({
          'groupId': group,
          'groupType': 'Public',
          'updatedAt': 1710000000000,
        }));
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (r, h) {
        calls++;
        options.add(r);
        pending.add(h);
      },
    ));
  });
  tearDown(() async {
    ApiClient.instance.dio.interceptors.clear();
    await GroupLocalStore.instance.clearForOwner(owner);
  });
  Future<void> waitForCalls(int count) async {
    for (var i = 0; i < 100 && calls < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(calls, count);
  }

  void complete(int index, {int stamp = 1710000001000}) {
    pending[index].resolve(
        Response(requestOptions: options[index], statusCode: 200, data: {
      'data': {
        'groupId': group,
        'groupType': 'Public',
        'myRole': 400,
        'updatedAt': stamp,
      }
    }));
  }

  test('successful detail is briefly reused but forced refresh still runs',
      () async {
    final first = sync.refreshGroupDetail(group);
    final shared = sync.refreshGroupDetail(group);
    await waitForCalls(1);
    complete(0);
    await Future.wait([first, shared]);
    await sync.refreshGroupDetail(group);
    expect(calls, 1);
    final forced = sync.refreshGroupDetail(group, refresh: true);
    await waitForCalls(2);
    expect(options[1].queryParameters['refresh'], true);
    complete(1, stamp: 1710000002000);
    await forced;
  });

  test('service failure remains immediately retryable', () async {
    final failed = sync.refreshGroupDetail(group);
    await waitForCalls(1);
    pending[0].reject(DioError(requestOptions: options[0]));
    await failed;
    final retry = sync.refreshGroupDetail(group);
    await waitForCalls(2);
    complete(1);
    await retry;
  });

  test('same-account clear drops late data and queued forced continuation',
      () async {
    final old = sync.refreshGroupDetail(group);
    await waitForCalls(1);
    final forced = sync.refreshGroupDetail(group, refresh: true);
    await sync.clearSession();
    complete(0);
    await Future.wait([old, forced]);
    expect(calls, 1);
    final stored =
        await GroupLocalStore.instance.read(groupId: group, ownerUserId: owner);
    expect(stored?.updatedAt, 1710000000000);
    expect(MeGroupApi.instance.confirmedGroupDetail(group), isNull);
    final next = sync.refreshGroupDetail(group);
    await waitForCalls(2);
    complete(1);
    await next;
  });

  test(
      'UIKit bridge preserves duplicate output IDs while sharing missing detail',
      () async {
    await GroupLocalStore.instance.clearForOwner(owner);
    final loaded = sync.loadGroupsInfoForUIKit([group, group]);
    await waitForCalls(1);
    complete(0);
    final rows = await loaded;
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.resultCode == 0), true);
    expect(calls, 1);
  });
}
