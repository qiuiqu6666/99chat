import 'dart:async';
import 'package:dio/dio.dart';
import 'package:tencent_chat_i18n_tool/language_json/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/muted_member_profile_resolver.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart';

class _Model extends TUIGroupProfileModel {
  int role = 400;
  @override
  String get groupID => '@TGS#profile-test';
  @override
  bool get hasLoadedManagementMembers => true;
  @override
  int? get backendSelfRole => role;
  @override
  V2TimGroupInfo get groupInfo =>
      V2TimGroupInfo(groupID: groupID, groupType: 'Public', isAllMuted: false);
  @override
  Future<void> loadGroupInfo(String id) async {}
  @override
  Future<void> loadManagementMembers() async {}
  void revoke() {
    role = 200;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    await ApiClient.instance.saveToken('token', userId: 'muted-widget-test');
  });
  Future<void> pump(WidgetTester tester, Widget child) async {
    final previous = FlutterError.onError;
    await tester.pumpWidget(
        TranslationProvider(child: MaterialApp(home: Scaffold(body: child))));
    FlutterError.onError = previous;
    await tester.pump();
    FlutterError.onError = previous;
  }

  for (final revoke in [false, true]) {
    testWidgets(
        revoke
            ? 'revoked permission rejects late profile'
            : 'API nickname is rendered without SDK lookup', (tester) async {
      final errorHandler = FlutterError.onError;
      final model = _Model();
      final gate =
          Completer<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>>();
      var calls = 0;
      final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
        handler
            .resolve(Response(requestOptions: options, statusCode: 200, data: {
          'members': [
            {
              'userId': 'alice',
              'muteUntilSec': 9999999999,
              if (!revoke) ...{'nickname': '真实昵称', 'avatarUrl': ''}
            }
          ],
          'isAllMuted': false,
        }));
      });
      ApiClient.instance.dio.interceptors.add(interceptor);
      addTearDown(
          () => ApiClient.instance.dio.interceptors.remove(interceptor));
      final resolver = MutedMemberProfileResolver(loader: (_, ids) {
        calls++;
        return gate.future;
      });
      await pump(
          tester,
          GroupProfileGroupManagePage(
              model: model,
              mutedProfileResolver: resolver,
              serverTimeLoader: () async => 1));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        FlutterError.onError = errorHandler;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        FlutterError.onError = errorHandler;
      }
      await tester.pumpAndSettle();
      FlutterError.onError = errorHandler;
      if (!revoke) {
        expect(find.text('真实昵称'), findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .join('|'));
        expect(calls, 0);
      } else {
        expect(calls, 1);
        model.revoke();
        gate.complete(V2TimValueCallback(code: 0, desc: 'ok', data: [
          V2TimGroupMemberFullInfo(
              userID: 'alice', nickName: '迟到昵称', faceUrl: '')
        ]));
        await tester.pump();
        FlutterError.onError = errorHandler;
        expect(find.text('迟到昵称'), findsNothing);
        expect(find.byKey(const ValueKey('muted-alice')), findsNothing);
      }
      await pump(tester, const SizedBox.shrink());
      model.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
