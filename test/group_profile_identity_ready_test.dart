// This lifecycle test observes existing notifier subscriptions without adding
// a production-only listener-count API.
// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/tim_uikit_group_profile.dart';

import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

class _Groups implements GroupServices {
  final counts = <int>[];
  @override
  Future<List<V2TimGroupInfoResult>?> getGroupsInfo({
    required List<String> groupIDList,
  }) async =>
      null;

  @override
  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> getGroupMemberList({
    required String groupID,
    required GroupMemberFilterTypeEnum filter,
    required String nextSeq,
    int count = 15,
    int offset = 0,
  }) async {
    counts.add(count);
    return V2TimValueCallback<V2TimGroupMemberInfoResult>(
      code: 0,
      desc: '',
      data: V2TimGroupMemberInfoResult(nextSeq: '0', memberInfoList: []),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations implements ConversationService {
  final responses = <Completer<V2TimConversation?>>[];

  @override
  Future<V2TimConversation?> getConversation({required String conversationID}) {
    final response = Completer<V2TimConversation?>();
    responses.add(response);
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pending = <MapEntry<RequestOptions, RequestInterceptorHandler>>[];
  final requests = <RequestOptions>[];
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    await ApiClient.instance
        .saveToken('test-token', userId: 'identity-ready-user');
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(_Groups());
    await serviceLocator.unregister<ConversationService>();
    serviceLocator.registerSingleton<ConversationService>(_Conversations());
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      pending.add(MapEntry(r, h));
    }));
  });

  Future<void> tick(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  bool _isMembersPath(String path) => path.contains('/members');

  void _resolveMembersPage(
      MapEntry<RequestOptions, RequestInterceptorHandler> request) {
    expect(request.key.queryParameters['role'], isNull);
    expect(request.key.queryParameters['refresh'], isNull);
    expect(request.key.queryParameters['limit'], 50);
    request.value.resolve(
      Response(
        requestOptions: request.key,
        statusCode: 200,
        data: {
          'data': {
            'groupId': 'identity-ready',
            'items': [
              {
                'userId': 'owner-1',
                'nickname': 'Owner',
                'role': 400,
                'isSelf': true,
              },
              {
                'userId': 'admin-1',
                'nickname': 'Admin',
                'role': 300,
                'isSelf': false,
              },
              {
                'userId': 'mem-1',
                'nickname': 'Member',
                'role': 200,
                'isSelf': false,
              },
            ],
            'total': 128,
            'limit': 50,
            'offset': 0,
          },
        },
      ),
    );
  }

  void _resolveDetail(
      MapEntry<RequestOptions, RequestInterceptorHandler> request) {
    request.value.resolve(
      Response(
        requestOptions: request.key,
        statusCode: 200,
        data: {
          'data': {
            'groupId': 'identity-ready',
            'groupType': 'Public',
            'groupName': 'REST group',
            'myRole': 400,
            'memberCount': 5000,
          },
        },
      ),
    );
  }

  Future<void> _waitForPending(
    WidgetTester tester, {
    required int minCount,
  }) async {
    for (var i = 0; pending.length < minCount && i < 40; i++) {
      await tick(tester);
    }
  }

  for (final failFirst in [false, true]) {
    testWidgets(
        'REST identity gates profile, one unfiltered members page, retry=$failFirst',
        (tester) async {
      SessionIdentityService.instance.invalidate();
      pending.clear();
      requests.clear();
      final groups = serviceLocator<GroupServices>() as _Groups;
      groups.counts.clear();
      final errorHandler = FlutterError.onError;
      addTearDown(() => FlutterError.onError = errorHandler);
      final renderedRoles = <int?>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TIMUIKitGroupProfile(
        groupID: 'identity-ready',
        builder: (_, info, __) {
          renderedRoles.add(info.role);
          return const Text('profile-ready');
        },
      ))));
      FlutterError.onError = errorHandler;
      final dynamic state = tester.state(find.byType(TIMUIKitGroupProfile));
      final TUIGroupProfileModel model = state.model;
      model.groupInfo =
          V2TimGroupInfo(groupID: 'identity-ready', groupType: 'Public');
      model.notifyListeners();
      await _waitForPending(tester, minCount: 2);
      FlutterError.onError = errorHandler;
      expect(find.text('profile-ready'), findsNothing);
      expect(renderedRoles, isEmpty);
      expect(pending.length, greaterThanOrEqualTo(2));
      expect(pending.every((entry) => entry.key.path.startsWith('/group/')),
          isTrue);
      expect(
          pending.where((entry) => _isMembersPath(entry.key.path)), isNotEmpty);
      expect(pending.where((entry) => !_isMembersPath(entry.key.path)),
          isNotEmpty);

      final queued =
          List<MapEntry<RequestOptions, RequestInterceptorHandler>>.from(
              pending);
      pending.clear();
      var rejectedDetailOnce = false;
      for (final request in queued) {
        if (_isMembersPath(request.key.path)) {
          _resolveMembersPage(request);
          continue;
        }
        if (failFirst && !rejectedDetailOnce) {
          rejectedDetailOnce = true;
          request.value.reject(DioError(requestOptions: request.key));
          continue;
        }
        _resolveDetail(request);
      }

      if (failFirst) {
        for (var i = 0; model.isGroupDetailLoading && i < 40; i++) {
          await tick(tester);
        }
        FlutterError.onError = errorHandler;
        expect(model.hasGroupDetailLoadError, isTrue);
        expect(find.byType(TextButton), findsOneWidget);
        await tester.tap(find.byType(TextButton));
        await _waitForPending(tester, minCount: 1);
        FlutterError.onError = errorHandler;
        final retry =
            List<MapEntry<RequestOptions, RequestInterceptorHandler>>.from(
                pending);
        pending.clear();
        for (final request in retry) {
          if (_isMembersPath(request.key.path)) {
            _resolveMembersPage(request);
          } else {
            _resolveDetail(request);
          }
        }
      }
      for (var i = 0;
          (model.isGroupDetailLoading || model.isGroupMemberListLoading) &&
              i < 40;
          i++) {
        await tick(tester);
      }
      FlutterError.onError = errorHandler;
      expect(find.text('profile-ready'), findsOneWidget);
      expect(renderedRoles, everyElement(400));
      expect(model.hasLoadedManagementMembers, isFalse);
      expect(groups.counts, isEmpty);
      expect(
        model.groupMemberList.map((member) => member?.role).toList(),
        [400, 300, 200],
      );
      final memberRequests =
          requests.where((request) => _isMembersPath(request.path)).toList();
      expect(memberRequests, isNotEmpty);
      expect(
        memberRequests
            .every((request) => request.queryParameters['role'] == null),
        isTrue,
        reason:
            'Profile loads one unfiltered members snapshot page, never role-filtered management pages',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tick(tester);
      FlutterError.onError = errorHandler;

      // Chat/profile REST confirmation is shared across route instances.
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TIMUIKitGroupProfile(
        groupID: 'identity-ready',
        builder: (_, info, __) => Text('reopened-role-${info.role}'),
      ))));
      FlutterError.onError = errorHandler;
      expect(find.text('reopened-role-400'), findsOneWidget);
      final dynamic reopened = tester.state(find.byType(TIMUIKitGroupProfile));
      final TUIGroupProfileModel reopenedModel = reopened.model;
      expect(reopenedModel.hasLoadedManagementMembers, isFalse);
      for (var i = 0; pending.isEmpty && i < 10; i++) {
        await tick(tester);
      }
      final leftover =
          List<MapEntry<RequestOptions, RequestInterceptorHandler>>.from(
              pending);
      pending.clear();
      for (final request in leftover) {
        if (_isMembersPath(request.key.path)) {
          _resolveMembersPage(request);
        } else {
          _resolveDetail(request);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tick(tester);
      FlutterError.onError = errorHandler;

      SessionIdentityService.instance.invalidate();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TIMUIKitGroupProfile(
        groupID: 'identity-ready',
        builder: (_, info, __) => const Text('unexpected-cached-profile'),
      ))));
      FlutterError.onError = errorHandler;
      expect(find.text('unexpected-cached-profile'), findsNothing);
      final afterInvalidate =
          List<MapEntry<RequestOptions, RequestInterceptorHandler>>.from(
              pending);
      pending.clear();
      for (final request in afterInvalidate) {
        if (_isMembersPath(request.key.path)) {
          _resolveMembersPage(request);
        } else {
          request.value.reject(DioError(requestOptions: request.key));
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tick(tester);
      FlutterError.onError = errorHandler;
      expect(tester.takeException(), isNull);
    });
  }
}
