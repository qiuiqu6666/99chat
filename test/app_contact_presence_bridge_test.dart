import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/forward_pick_pages.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _RecordingPresenceProvider extends PresenceProvider {
  final List<List<String>> ensureCalls = [];

  @override
  void ensure(Iterable<String> userIds, {bool includeVisibility = true}) {
    ensureCalls.add(List<String>.from(userIds));
  }
}

void main() {
  late TUIChatGlobalModel global;
  late _RecordingPresenceProvider presence;
  late LocalSetting localSetting;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() {
    global = serviceLocator<TUIChatGlobalModel>();
    global.appContactPresenceBridgeBuilder = null;
    registerAppUIKitExtensions(global);
    presence = _RecordingPresenceProvider();
    localSetting = LocalSetting(autoLoad: false)..isShowOnlineStatus = true;
  });

  tearDown(() {
    presence.dispose();
  });

  test('registerAppUIKitExtensions installs presence bridge builder', () {
    expect(global.appContactPresenceBridgeBuilder, isNotNull);
  });

  Future<AppContactPresenceBridge> pumpBridge(WidgetTester tester) async {
    late AppContactPresenceBridge bridge;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PresenceProvider>.value(value: presence),
          ChangeNotifierProvider<LocalSetting>.value(value: localSetting),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              bridge = global.appContactPresenceBridgeBuilder!(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return bridge;
  }

  testWidgets('setting off hides labels and skips ensure', (tester) async {
    localSetting.isShowOnlineStatus = false;
    final bridge = await pumpBridge(tester);
    expect(identical(bridge.presenceListenable, presence), isTrue);
    expect(bridge.presenceLabelBuilder!('u1', false), '');
    expect(bridge.presenceLoadingChecker!('u1', false), isFalse);
    expect(bridge.presenceOnlineResolver!('u1', true), isFalse);
    bridge.onContactListLoaded!(['u1']);
    expect(presence.ensureCalls, isEmpty);
  });

  testWidgets('setting on uses listLabelFor and isMutualFriend loading',
      (tester) async {
    localSetting.isShowOnlineStatus = true;
    final friendship = serviceLocator<TUIFriendShipViewModel>();
    final bridge = await pumpBridge(tester);
    const userId = 'u1';
    const imOnline = false;
    final isMutual = friendCanMessage(friendship, userId);
    expect(
      bridge.presenceLabelBuilder!(userId, imOnline),
      presence.listLabelFor(
        userId: userId,
        imOnline: imOnline,
        isMutualFriend: isMutual,
      ),
    );
    expect(
      bridge.presenceLoadingChecker!(userId, imOnline),
      presence.isLastSeenLoading(
        userId: userId,
        imOnline: imOnline,
        isMutualFriend: isMutual,
      ),
    );
    expect(
      bridge.presenceOnlineResolver!(userId, imOnline),
      presence.shouldShowPresence(userId, isMutualFriend: isMutual) &&
          presence.resolveOnline(userId: userId, imOnline: imOnline),
    );
    bridge.onContactListLoaded!(['u1']);
    expect(presence.ensureCalls, [
      ['u1']
    ]);
  });
}
