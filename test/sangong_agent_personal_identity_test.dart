import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_personal_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ApiClient.instance.clearToken();
    SangongGameHttp.clearTenant();
  });

  test('resolveCurrentImUserId uses JWT owner, not UIKit snapshot', () async {
    await ApiClient.instance.saveToken(
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      userId: 'account-b',
    );

    expect(
      SangongAgentPersonalPage.resolveCurrentImUserId(),
      'account-b',
    );
  });

  test('resolveCurrentImUserId is empty after clearToken', () async {
    await ApiClient.instance.saveToken(
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      userId: 'account-b',
    );
    await ApiClient.instance.clearToken();

    expect(SangongAgentPersonalPage.resolveCurrentImUserId(), isEmpty);
  });

  test('clearTenant drops the active sangong tenant', () {
    SangongGameHttp.setTenantId('m2BXXNKM5CS');
    expect(SangongGameHttp.tenantId, isNotNull);
    expect(SangongGameHttp.tenantId, isNotEmpty);

    SangongGameHttp.clearTenant();

    expect(SangongGameHttp.tenantId, isNull);
  });
}
