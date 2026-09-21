import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('repeated realtime presence heartbeat does not revise the same row', () {
    final presence = PresenceProvider();
    addTearDown(presence.dispose);

    presence.applyPresenceChanged(
      peerUserId: 'peer-1',
      lastActiveAt: 123,
      lastActiveVisibility: 'everyone',
      online: true,
    );
    expect(presence.revisionFor('peer-1'), 1);

    presence.applyPresenceChanged(
      peerUserId: 'peer-1',
      lastActiveAt: 123,
      lastActiveVisibility: 'everyone',
      online: true,
    );
    expect(presence.revisionFor('peer-1'), 1);

    presence.applyPresenceChanged(
      peerUserId: 'peer-1',
      lastActiveAt: 123,
      lastActiveVisibility: 'everyone',
      online: false,
    );
    expect(presence.revisionFor('peer-1'), 2);
  });

  testWidgets('presence batch publishes at most six row revisions per frame',
      (tester) async {
    final presence = PresenceProvider();
    try {
      final lastSeen = <String, int>{
        for (var index = 0; index < 14; index++) 'peer-$index': 100 + index,
      };

      presence.applyPresenceBatch(lastSeen: lastSeen);
      int publishedRows() => lastSeen.keys
          .where((userId) => presence.revisionFor(userId) > 0)
          .length;

      expect(publishedRows(), 6);
      await tester.pump();
      expect(publishedRows(), 12);
      await tester.pump();
      expect(publishedRows(), 14);
    } finally {
      presence.dispose();
    }
  });

  testWidgets('full-screen back gesture is enabled after transition settles',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  AppMaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('detail')),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    await tester.dragFrom(const Offset(4, 300), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  test('expensive page work has explicit visibility gates', () {
    final profile = File('lib/src/profile.dart').readAsStringSync();
    final contacts = File(
      'lib/src/widgets/contact_list_with_presence.dart',
    ).readAsStringSync();
    final route = File(
      'lib/src/navigation/full_screen_back_route.dart',
    ).readAsStringSync();
    final home = File('lib/src/pages/home_page.dart').readAsStringSync();
    final tabScope = File(
      'lib/src/navigation/home_tab_activity.dart',
    ).readAsStringSync();
    final conversation = File(
      'lib/src/conversation.dart',
    ).readAsStringSync();
    final feed = File(
      'lib/src/widgets/conversation_feed/conversation_feed_body.dart',
    ).readAsStringSync();
    final historyList = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/'
      'TIMUIKitChat/TIMUIKItMessageList/'
      'tim_uikit_chat_history_message_list.dart',
    ).readAsStringSync();
    final historyContainer = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/'
      'TIMUIKitChat/TIMUIKItMessageList/'
      'tim_uikit_history_message_list_container.dart',
    ).readAsStringSync();

    expect(profile, contains('TickerMode.of(context)'));
    expect(profile, contains('WidgetsBindingObserver'));
    expect(profile, contains('child: RepaintBoundary('));

    expect(contacts, contains('if (!_workEnabled)'));
    expect(contacts, contains('_contactRowCache'));
    expect(contacts, contains('TickerMode.of(context)'));

    expect(route, contains('_stableGestureLayer'));
    expect(route, contains('AnimationStatusListener'));

    expect(tabScope, contains('class HomeTabActivity extends InheritedWidget'));
    expect(home, contains('isActive: active'));
    expect(conversation, contains('_previewProjectionRowsPerFrame = 6'));
    expect(
      RegExp('resolveFromChatVisibleProjection')
          .allMatches(conversation)
          .length,
      2,
    );
    expect(feed, contains('widget.workEnabled'));
    expect(historyList, contains('_initialMountRowsPerFrame = 12'));
    expect(historyContainer, contains('_messageRowCache'));
  });
}
