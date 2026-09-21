import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_folder_swipe_region.dart';

void main() {
  group('conversationFolderSwipeDirection', () {
    test('left and right decisive swipes map to adjacent directions', () {
      expect(
        conversationFolderSwipeDirection(
          deltaX: -270,
          deltaY: 12,
          viewportWidth: 360,
        ),
        1,
      );
      expect(
        conversationFolderSwipeDirection(
          deltaX: 270,
          deltaY: 12,
          viewportWidth: 360,
        ),
        -1,
      );
    });

    test('vertical and short horizontal movement do not switch folders', () {
      expect(
        conversationFolderSwipeDirection(
          deltaX: 80,
          deltaY: 100,
          viewportWidth: 360,
        ),
        0,
      );
      expect(
        conversationFolderSwipeDirection(
          deltaX: 250,
          deltaY: 2,
          viewportWidth: 360,
        ),
        0,
      );
    });

    test('row action distance does not switch folders on a wide pane', () {
      expect(
        conversationFolderSwipeDirection(
          deltaX: -360,
          deltaY: 4,
          viewportWidth: 740,
        ),
        0,
      );
      expect(
        conversationFolderSwipeDirection(
          deltaX: -540,
          deltaY: 4,
          viewportWidth: 740,
        ),
        1,
      );
    });
  });

  group('conversationFolderAfterSwipe', () {
    const folders = <String>['work', 'family'];

    test('moves through all and folders in display order', () {
      expect(
        conversationFolderAfterSwipe(
          folderIds: folders,
          selectedFolderId: null,
          direction: 1,
        ),
        (changed: true, folderId: 'work'),
      );
      expect(
        conversationFolderAfterSwipe(
          folderIds: folders,
          selectedFolderId: 'work',
          direction: 1,
        ),
        (changed: true, folderId: 'family'),
      );
      expect(
        conversationFolderAfterSwipe(
          folderIds: folders,
          selectedFolderId: 'work',
          direction: -1,
        ),
        (changed: true, folderId: null),
      );
    });

    test('stops at both ends and recovers a removed selection', () {
      expect(
        conversationFolderAfterSwipe(
          folderIds: folders,
          selectedFolderId: null,
          direction: -1,
        ).changed,
        isFalse,
      );
      expect(
        conversationFolderAfterSwipe(
          folderIds: folders,
          selectedFolderId: 'family',
          direction: 1,
        ).changed,
        isFalse,
      );
      expect(
        conversationFolderAfterSwipe(
          folderIds: folders,
          selectedFolderId: 'removed',
          direction: 1,
        ),
        (changed: true, folderId: 'work'),
      );
    });
  });

  testWidgets('swipe region observes a decisive swipe over a row gesture',
      (tester) async {
    var direction = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 640,
            child: ConversationFolderSwipeRegion(
              enabled: true,
              onSwipe: (value) => direction = value,
              child: GestureDetector(
                onHorizontalDragEnd: (_) {},
                child: const ColoredBox(
                  key: ValueKey<String>('swipe-target'),
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('swipe-target')),
      const Offset(-280, 8),
      touchSlopY: 0,
    );
    await tester.pump();
    expect(direction, 1);
  });

  testWidgets('row action swipe does not switch folders', (tester) async {
    var direction = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 640,
            child: ConversationFolderSwipeRegion(
              enabled: true,
              onSwipe: (value) => direction = value,
              child: GestureDetector(
                onHorizontalDragEnd: (_) {},
                child: const ColoredBox(
                  key: ValueKey<String>('row-action-target'),
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.fling(
      find.byKey(const ValueKey<String>('row-action-target')),
      const Offset(-220, 4),
      3000,
    );
    await tester.pump();
    expect(direction, 0);
  });
}
