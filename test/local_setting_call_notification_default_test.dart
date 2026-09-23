import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/models/notification_display_mode.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';

void main() {
  test('legacy disabled call notifications migrate to enabled', () async {
    SharedPreferences.setMockInitialValues({
      'notifyVoiceVideoCall': false,
    });
    final settings = LocalSetting(autoLoad: false);
    addTearDown(settings.dispose);

    await settings.loadSettingsFromLocal();
    expect(settings.notifyVoiceVideoCall, isTrue);
    expect((await SharedPreferences.getInstance())
        .getBool('notifyVoiceVideoCall'), isTrue);

    settings.applyRemoteNotificationPreferences(
      systemMessageNotificationEnabled: true,
      callNotificationEnabled: false,
      notificationDisplayContent: NotificationDisplayMode.full,
    );
    expect(settings.notifyVoiceVideoCall, isTrue);

    settings.notifyVoiceVideoCall = false;
    expect(settings.notifyVoiceVideoCall, isTrue);
  });
}
