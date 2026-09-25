import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';

void main() {
  testWidgets('send diagnostics distinguish socket readiness from UI handshake',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = LocalSetting();
    await tester
        .pump(); // Finish the settings constructor's async preference load.
    ImConnectStatusService.instance.attach(settings);
    ImConnectStatusService.resetLaunchSession();
    try {
      expect(ImConnectStatusService.diagnosticState,
          ImConnectionDiagnosticState.unknown);
      ImConnectStatusService.beginSocketHandshake();
      expect(ImConnectStatusService.diagnosticState,
          ImConnectionDiagnosticState.connecting);
      ImConnectStatusService.onSdkConnectSuccess();
      expect(ImConnectStatusService.isHandshakePending, isTrue);
      expect(ImConnectStatusService.diagnosticState,
          ImConnectionDiagnosticState.connected);
      ImConnectStatusService.markSocketDisconnected();
      expect(ImConnectStatusService.diagnosticState,
          ImConnectionDiagnosticState.offline);
      ImConnectStatusService.onSdkConnecting();
      expect(ImConnectStatusService.diagnosticState,
          ImConnectionDiagnosticState.reconnecting);
      var notifications = 0;
      void listener() => notifications++;
      ImConnectStatusService.instance.addListener(listener);
      for (var i = 0; i < 10; i++) {
        expect(ImConnectStatusService.diagnosticState,
            ImConnectionDiagnosticState.reconnecting);
      }
      ImConnectStatusService.instance.removeListener(listener);
      expect(notifications, 0);
    } finally {
      ImConnectStatusService.resetLaunchSession();
      settings.dispose();
    }
    await tester.pump(const Duration(seconds: 3));
  });
}
