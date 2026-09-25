import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/create_group.dart';
import 'package:tencent_cloud_chat_demo/src/pages/channel_intro_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });

  testWidgets('channel creation stays in a 90 percent bottom sheet',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    final theme = DefaultThemeData();
    final presence = PresenceProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: presence),
      ],
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: (context) => ElevatedButton(
          onPressed: () => ChannelIntroPage.show(context),
          child: const Text('open channel'),
        ))),
      ),
    ));
    await tester.tap(find.text('open channel'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey('channel-intro-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('channel-intro-create')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateGroup), findsOneWidget);
    expect(tester.getSize(find.byType(BottomSheet)).height,
        closeTo(852 * .9, 1));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Next').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('channel-avatar')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-introduction')), findsOneWidget);
    expect(tester.widget<TextField>(
        find.byKey(const ValueKey('channel-name'))).decoration!.filled, isFalse);
    expect(tester.widget<TextField>(
        find.byKey(const ValueKey('channel-introduction'))).decoration!.filled,
        isFalse);
    expect(find.byKey(const ValueKey('channel-next')), findsOneWidget);
    expect(tester.getSize(find.byType(BottomSheet)).height,
        closeTo(852 * .9, 1));
    expect(tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('channel-next'))).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('channel-name')), 'News');
    await tester.enterText(
        find.byKey(const ValueKey('channel-introduction')), 'Updates');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('channel-next'))).onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    presence.dispose();
    theme.dispose();
  });

  testWidgets('create group picker follows live friend add and delete',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    RelationshipFriendEntry friend(String id, String name) =>
        RelationshipFriendEntry(
          userId: id,
          displayName: name,
          faceUrl: '',
          remark: name,
          sortKey: ImSdkRelationshipDirectory.sortKeyFor(
            id: id,
            displayName: name,
            azTag: name[0],
          ),
        );
    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: [friend('ann', 'Ann'), friend('ben', 'Ben')],
    );
    final theme = DefaultThemeData();
    final presence = PresenceProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: presence),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CreateGroup(convType: GroupTypeForUIKit.public)),
      ),
    ));
    await tester.pump();
    expect(
      tester
          .widget<ContactList>(find.byType(ContactList))
          .contactList
          .map((item) => item.userID),
      ['ann', 'ben'],
    );
    tester
        .state<ContactListState>(find.byType(ContactList))
        .selectAllSelectable();
    await tester.pump();
    expect(find.text('2/6000'), findsOneWidget);

    directory.applyFriendRemoves(['ben']);
    directory.applyFriendAdds([friend('cara', 'Cara')]);
    await tester.pump();
    expect(
      tester
          .widget<ContactList>(find.byType(ContactList))
          .contactList
          .map((item) => item.userID),
      ['ann', 'cara'],
    );
    expect(find.text('1/6000'), findsOneWidget);
    directory.applyFriendRemoves(['ann', 'cara']);
    await tester.pump();
    expect(find.text('No contacts'), findsOneWidget);
    directory.applyFriendAdds([friend('dana', 'Dana')]);
    await tester.pump();
    expect(
      tester
          .widget<ContactList>(find.byType(ContactList))
          .contactList
          .map((item) => item.userID),
      ['dana'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    presence.dispose();
    theme.dispose();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('picker index includes contacts beyond the first 80',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    final entries = [
      for (var i = 0; i < 80; i++)
        RelationshipFriendEntry(
          userId: 'a${i.toString().padLeft(3, '0')}',
          displayName: 'Alice $i',
          faceUrl: '',
          remark: 'Alice $i',
          sortKey: ImSdkRelationshipDirectory.sortKeyFor(
            id: 'a${i.toString().padLeft(3, '0')}',
            displayName: 'Alice $i',
            azTag: 'A',
          ),
        ),
      RelationshipFriendEntry(
        userId: 'zoe',
        displayName: 'Zoe',
        faceUrl: '',
        remark: 'Zoe',
        sortKey: ImSdkRelationshipDirectory.sortKeyFor(
          id: 'zoe',
          displayName: 'Zoe',
          azTag: 'Z',
        ),
      ),
    ];
    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: entries,
    );
    final theme = DefaultThemeData();
    final presence = PresenceProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: presence),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CreateGroup(convType: GroupTypeForUIKit.public)),
      ),
    ));
    await tester.pump();
    final contacts = tester.widget<ContactList>(find.byType(ContactList));
    expect(contacts.contactList.length, 81);
    expect(contacts.contactList.last.userID, 'zoe');

    await tester.pumpWidget(const SizedBox.shrink());
    presence.dispose();
    theme.dispose();
  });

  testWidgets('create group picker explains an initially empty friend list',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    final theme = DefaultThemeData();
    final presence = PresenceProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: presence),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CreateGroup(convType: GroupTypeForUIKit.public)),
      ),
    ));
    await tester.pump();
    expect(find.text('No contacts'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    presence.dispose();
    theme.dispose();
  });
}
