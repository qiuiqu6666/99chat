import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';

void main() {
  test('loginInfo is safe before asynchronous login bootstrap', () {
    final core = CoreServicesImpl();

    expect(core.loginInfo.sdkAppID, 0);
    expect(core.loginInfo.userID, isEmpty);
    expect(core.loginInfo.userSig, isEmpty);
    expect(core.loginInfo.loginUser, isNull);
  });
}
