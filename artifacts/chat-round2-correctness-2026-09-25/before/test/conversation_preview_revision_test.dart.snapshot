import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_preview_revision.dart';

void main() {
  testWidgets('only mounted row builders request eager preview work',
      (tester) async {
    final revisions = List.generate(3000, (_) => ConversationPreviewRevision());
    final selection = ValueNotifier<int>(0);
    addTearDown(() {
      for (final revision in revisions) {
        revision.dispose();
      }
      selection.dispose();
    });
    Widget row(int index) => AnimatedBuilder(
          animation: Listenable.merge([revisions[index], selection]),
          builder: (_, __) => Text(
            '$index:${revisions[index].value}',
            textDirection: TextDirection.ltr,
          ),
        );
    final cachedRows = List.generate(3000, row);
    Widget viewport(int start) => Column(
          children: cachedRows.skip(start).take(12).toList(),
        );

    // Constructing/caching all row widgets must not make them active.
    expect(revisions.where((r) => r.isObserved), isEmpty);
    await tester.pumpWidget(viewport(0));
    expect(revisions.where((r) => r.isObserved), hasLength(12));

    await tester.pumpWidget(viewport(100));
    expect(revisions.take(12).any((r) => r.isObserved), isFalse);
    expect(revisions.where((r) => r.isObserved), hasLength(12));
    revisions[100].value++;
    await tester.pump();
    expect(find.text('100:1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(revisions.where((r) => r.isObserved), isEmpty);
    // A cached row mounts again with its latest revision and listener.
    revisions[100].value++;
    await tester.pumpWidget(viewport(100));
    expect(find.text('100:2'), findsOneWidget);
    expect(revisions[100].isObserved, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
