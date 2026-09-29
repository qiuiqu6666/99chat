import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_result_entrance.dart';

void main() {
  testWidgets('same key and generation does not replay after finishing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SearchResultEntrance(
          animate: true,
          generation: 1,
          child: Text('row'),
        ),
      ),
    );
    var opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 0);

    await tester.pump(SearchResultEntrance.duration);
    opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 1);

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchResultEntrance(
          animate: true,
          generation: 1,
          child: Text('row'),
        ),
      ),
    );
    await tester.pump();
    opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 1);
  });

  testWidgets('generation change can play again', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SearchResultEntrance(
          animate: true,
          generation: 1,
          child: Text('row'),
        ),
      ),
    );
    await tester.pump(SearchResultEntrance.duration);

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchResultEntrance(
          animate: true,
          generation: 2,
          child: Text('row'),
        ),
      ),
    );
    await tester.pump();
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 0);

    await tester.pump(SearchResultEntrance.duration);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  testWidgets('animate false shows the child immediately', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SearchResultEntrance(
          animate: false,
          generation: 1,
          child: Text('row'),
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });
}
