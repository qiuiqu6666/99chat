import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_preview_center_loading_indicator.dart';

void main() {
  testWidgets('missing chunk totals do not reset progress or recreate painter element', (tester) async {
    Future<void> show(double? progress, {String id = 'same-image'}) => tester.pumpWidget(
      MaterialApp(home: Center(child: ImagePreviewCenterLoadingIndicator(
        key: ValueKey(id), progress: progress))));
    Finder paint() => find.descendant(of: find.byType(ImagePreviewCenterLoadingIndicator), matching: find.byType(CustomPaint));
    await show(null);
    final element = tester.element(paint());
    for (final progress in <double?>[0.25, null, 0.6, null, 1]) {
      await show(progress);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.element(paint()), same(element));
      expect(tester.takeException(), isNull);
      final dynamic painter = tester.widget<CustomPaint>(paint()).painter;
      expect(painter.determinate, isTrue);
      if (progress != null) expect(painter.progress, progress);
      if (progress == null) expect(painter.progress, greaterThan(0));
    }
    await show(null, id: 'new-image');
    final dynamic painter = tester.widget<CustomPaint>(paint()).painter;
    expect(painter.determinate, isFalse);
    expect(painter.progress, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
