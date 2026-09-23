import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/create_group.dart';
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
      tester.widget<ContactList>(find.byType(ContactList)).contactList
          .map((item) => item.userID),
      ['ann', 'ben'],
    );
    tester.state<ContactListState>(find.byType(ContactList))
        .selectAllSelectable();
    await tester.pump();
    expect(find.text('2/2000'), findsOneWidget);

    directory.applyFriendRemoves(['ben']);
    directory.applyFriendAdds([friend('cara', 'Cara')]);
    await tester.pump();
    expect(
      tester.widget<ContactList>(find.byType(ContactList)).contactList
          .map((item) => item.userID),
      ['ann', 'cara'],
    );
    expect(find.text('1/2000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    presence.dispose();
    theme.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
}
