import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/directory_list_row.dart';

void main() {
  testWidgets('directory actions share compact geometry and remain tappable',
      (tester) async {
    var primaryTaps = 0;
    var secondaryTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Row(
        children: [
          DirectoryActionButton(
            label: '同意',
            primaryColor: Colors.blue,
            onPressed: () => primaryTaps++,
          ),
          DirectoryActionButton(
            label: '拒绝',
            primaryColor: Colors.blue,
            tone: DirectoryActionTone.secondary,
            onPressed: () => secondaryTaps++,
          ),
        ],
      ),
    ));

    final stadiumMaterials = tester
        .widgetList<Material>(find.byType(Material))
        .where((material) => material.shape is StadiumBorder)
        .toList();
    expect(stadiumMaterials, hasLength(2));
    for (final material in stadiumMaterials) {
      final box = tester.getSize(find.byWidget(material));
      expect(box.height, 34);
      expect(box.width, greaterThanOrEqualTo(64));
    }
    await tester.tap(find.text('同意'));
    await tester.tap(find.text('拒绝'));
    expect(primaryTaps, 1);
    expect(secondaryTaps, 1);
  });

  testWidgets('all passive states use the same badge geometry', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Wrap(
        children: [
          for (final entry in const [
            ('已同意', DirectoryStatusKind.accepted),
            ('已拒绝', DirectoryStatusKind.rejected),
            ('待审批', DirectoryStatusKind.pending),
            ('通知', DirectoryStatusKind.notice),
          ])
            DirectoryStatusBadge(
              label: entry.$1,
              textColor: Colors.grey,
              backgroundColor: const Color(0xFFF1F2F6),
              kind: entry.$2,
            ),
        ],
      ),
    ));

    for (final label in ['已同意', '已拒绝', '待审批', '通知']) {
      final container = find
          .ancestor(
            of: find.text(label),
            matching: find.byType(Container),
          )
          .first;
      expect(tester.getSize(container).height, 30);
    }
    expect(find.byType(InkWell), findsNothing,
        reason: 'Status badges must not look or behave like actions.');
  });
}
