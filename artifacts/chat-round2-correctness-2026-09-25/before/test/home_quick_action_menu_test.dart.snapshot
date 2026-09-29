import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/home_quick_action_tile.dart';

void main() {
  testWidgets('quick menu fits a narrow screen and returns each action', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    const entries = {'searchAdd': '搜索添加', 'createGroup': '创建群聊', 'scanQRCode': '扫一扫'};
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      appBar: AppBar(actions: [IconButton(icon: const Icon(Icons.add), onPressed: () async {
        selected = await showMenu<String>(context: context,
          shape: const HomeQuickMenuShape(arrowX: 260),
          constraints: const BoxConstraints.tightFor(width: 288),
          menuPadding: const EdgeInsets.only(top: 24, bottom: 10),
          position: const RelativeRect.fromLTRB(16, 56, 16, 0),
          items: [for (final e in entries.entries) PopupMenuItem<String>(value: e.key,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: HomeQuickActionTile(id: e.key, title: e.value, divider: e.key != 'scanQRCode'))]);
      })]),
    ))));
    for (final e in entries.entries) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(e.value));
      await tester.tap(find.text(e.value));
      await tester.pumpAndSettle();
      expect(selected, e.key);
    }
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 620));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
}
