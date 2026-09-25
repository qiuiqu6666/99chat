import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_list_sync_notifier.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/connect_status_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalSetting settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    settings = LocalSetting();
    ImConnectStatusService.instance.attach(settings);
    ImConnectStatusService.resetLaunchSession();
    ImConnectStatusService.debugIsImLoggedInOverride = () async => false;
    NetworkStatusService.instance.status.value = NetworkReachability.online;
    await ApiClient.instance.saveToken(
      'eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjQxMDI0NDQ4MDB9.c2lnbmF0dXJl',
    );
  });

  tearDown(() async {
    ImConnectStatusService.resetLaunchSession();
    ImConnectStatusService.debugIsImLoggedInOverride = null;
    AuthBootstrapService.instance.backgroundSyncing.value = false;
    ConversationListSyncNotifier.instance.clearSession();
    LoginCoordinator.instance.markLoggedOut();
    NetworkStatusService.instance.status.value = NetworkReachability.unknown;
    settings.dispose();
    await ApiClient.instance.clearToken();
  });

  for (final transient in [ConnectStatus.connecting, ConnectStatus.failed]) {
    testWidgets('notifies UI when pending $transient recovers before debounce',
        (tester) async {
      settings.connectStatus = ConnectStatus.success;
      await tester.pump();
      final observed = <ConnectStatus>[];
      settings.addListener(() => observed.add(settings.connectStatusForUi));

      settings.connectStatus = transient;
      await tester.pump();
      expect(settings.connectStatus, ConnectStatus.success);
      expect(observed.last, transient);

      settings.connectStatus = ConnectStatus.success;
      await tester.pump();
      expect(observed, [transient, ConnectStatus.success]);
      await tester.pump(const Duration(seconds: 3));
      expect(settings.connectStatusForUi, ConnectStatus.success);
    });
  }

  testWidgets('connected title stays ready during background data sync',
      (tester) async {
    LoginCoordinator.instance.markImReady(isHomeEntered: true);
    ImConnectStatusService.onSdkConnectSuccess();
    await tester.pump();
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);

    AuthBootstrapService.instance.backgroundSyncing.value = true;
    ConversationListSyncNotifier.instance.setAwaitingServerSync(true);
    ConversationListSyncNotifier.instance.setDraining(true);
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);

    NetworkStatusService.instance.status.value = NetworkReachability.offline;
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);
    // onSdkConnectSuccess also starts recovery. Drain its zero-delay database
    // scheduling yield before the widget test checks for leaked timers.
    await tester.pumpAndSettle();
  });

  testWidgets('disconnect ends pending handshake and reconnect recovers',
      (tester) async {
    LoginCoordinator.instance.markImReady(isHomeEntered: true);
    ImConnectStatusService.onSdkConnectSuccess();
    ImConnectStatusService.beginSocketHandshake();
    expect(ImConnectStatusService.isHandshakePending, isTrue);

    ImConnectStatusService.markSocketDisconnected();
    expect(ImConnectStatusService.isHandshakePending, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(ImConnectStatusService.isSocketReady, isFalse);
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.failed);

    ImConnectStatusService.onSdkConnecting();
    ImConnectStatusService.onSdkConnectSuccess();
    await tester.pump(const Duration(seconds: 3));
    expect(ImConnectStatusService.isSocketReady, isTrue);
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);
  });

  testWidgets('SDK reconnect during resume cannot lose its timeout',
      (tester) async {
    LoginCoordinator.instance.markImReady(isHomeEntered: true);
    ImConnectStatusService.onSdkConnectSuccess();
    ImConnectStatusService.beginSocketHandshake();
    // The app resumes with an existing socket, then the SDK reports that
    // it is reconnecting before the title's minimum display timer fires.
    ImConnectStatusService.onSdkConnecting();
    await tester.pump(const Duration(seconds: 3));
    expect(ImConnectStatusService.isHandshakePending, isTrue);
    expect(ImConnectStatusService.isSocketReady, isFalse);

    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 3));
    expect(ImConnectStatusService.isHandshakePending, isFalse);
    expect(settings.connectStatusForUi, ConnectStatus.failed);

    ImConnectStatusService.onSdkConnectSuccess();
    await tester.pump();
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);
  });

  testWidgets('repeated resume and SDK events preserve the original deadline',
      (tester) async {
    ImConnectStatusService.onSdkConnecting();
    for (var attempt = 0; attempt < 5; attempt++) {
      await tester.pump(const Duration(seconds: 2));
      ImConnectStatusService.beginSocketHandshake();
      ImConnectStatusService.onSdkConnecting();
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    expect(ImConnectStatusService.isHandshakePending, isFalse);
    expect(settings.connectStatusForUi, ConnectStatus.failed);
  });

  testWidgets('resume with a live socket does not require another SDK callback',
      (tester) async {
    LoginCoordinator.instance.markImReady(isHomeEntered: true);
    ImConnectStatusService.onSdkConnectSuccess();
    await tester.pump();
    for (var resume = 0; resume < 3; resume++) {
      settings.connectStatus = ConnectStatus.connecting;
      ImConnectStatusService.refreshSocketStatus();
      expect(ImConnectStatusService.isHandshakePending, isFalse);
      expect(settings.connectStatusForUi, ConnectStatus.success);
      expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
          ConversationTabConnectIndicator.ready);
      await tester.pump(const Duration(seconds: 3));
    }
  });

  testWidgets('resume with no socket times out without claiming success',
      (tester) async {
    ImConnectStatusService.refreshSocketStatus();
    expect(ImConnectStatusService.isHandshakePending, isTrue);
    expect(ImConnectStatusService.isSocketReady, isFalse);
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 3));
    expect(settings.connectStatusForUi, ConnectStatus.failed);
    expect(ImConnectStatusService.isSocketReady, isFalse);
  });

  testWidgets('session reset cancels the old handshake deadline',
      (tester) async {
    ImConnectStatusService.onSdkConnecting();
    await tester.pump(const Duration(seconds: 6));
    ImConnectStatusService.resetLaunchSession();
    ImConnectStatusService.onSdkConnecting();
    await tester.pump(const Duration(seconds: 7));
    expect(ImConnectStatusService.isHandshakePending, isTrue);
    expect(settings.connectStatusForUi, ConnectStatus.connecting);
    ImConnectStatusService.onSdkConnectSuccess();
    await tester.pump(const Duration(seconds: 3));
    expect(settings.connectStatusForUi, ConnectStatus.success);
    await tester.pump(const Duration(seconds: 5));
    expect(settings.connectStatusForUi, ConnectStatus.success);
  });

  testWidgets(
      'connectivity blip does not stick the failed title while the socket stays up',
      (tester) async {
    LoginCoordinator.instance.markImReady(isHomeEntered: true);
    ImConnectStatusService.onSdkConnectSuccess();
    await tester.pump();
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);

    NetworkStatusService.instance.status.value = NetworkReachability.offline;
    settings.connectStatus = ConnectStatus.failed;
    await tester.pump();
    expect(ImConnectStatusService.isSocketReady, isTrue);
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);

    NetworkStatusService.instance.status.value = NetworkReachability.online;
    ImConnectStatusService.refreshSocketStatus();
    await tester.pump();
    expect(settings.connectStatusForUi, ConnectStatus.success);
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);
  });

  testWidgets(
      'true IM failure stays failed while the network is still online',
      (tester) async {
    NetworkStatusService.instance.status.value = NetworkReachability.online;
    settings.connectStatus = ConnectStatus.failed;
    await tester.pump();
    expect(ImConnectStatusService.isSocketReady, isFalse);
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.failed);
    await tester.pump(const Duration(seconds: 3));
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.failed);
  });

  testWidgets(
      'socket ready plus offline reachability without writing failed stays ready',
      (tester) async {
    LoginCoordinator.instance.markImReady(isHomeEntered: true);
    ImConnectStatusService.onSdkConnectSuccess();
    await tester.pump();
    NetworkStatusService.instance.status.value = NetworkReachability.offline;
    expect(settings.connectStatusForUi, isNot(ConnectStatus.failed));
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);
  });

  testWidgets(
      'handshake timeout recovers when SDK is already logged in',
      (tester) async {
    ImConnectStatusService.debugIsImLoggedInOverride = () async => true;
    ImConnectStatusService.refreshSocketStatus();
    expect(ImConnectStatusService.isHandshakePending, isTrue);
    expect(ImConnectStatusService.isSocketReady, isFalse);
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 3));
    expect(ImConnectStatusService.isSocketReady, isTrue);
    expect(settings.connectStatusForUi, ConnectStatus.success);
    expect(ConnectStatusUi.conversationTabConnectIndicator(settings),
        ConversationTabConnectIndicator.ready);
  });
}
