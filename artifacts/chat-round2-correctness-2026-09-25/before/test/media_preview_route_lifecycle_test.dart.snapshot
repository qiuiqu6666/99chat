import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_overlay_route.dart';

class _PreviewProbe extends StatefulWidget {
  const _PreviewProbe({required this.onMount, required this.onDispose});
  final VoidCallback onMount;
  final VoidCallback onDispose;
  @override
  State<_PreviewProbe> createState() => _PreviewProbeState();
}

class _PreviewProbeState extends State<_PreviewProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.red);
}

void main() {
  for (final closeDuringEntrance in [false, true]) {
    testWidgets(
        'preview retains state through ${closeDuringEntrance ? 'interrupted entrance' : 'normal close'}',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      var mounts = 0, disposals = 0;
      await tester.pumpWidget(
          MaterialApp(navigatorKey: navigator, home: const SizedBox()));
      navigator.currentState!.push(MediaPreviewOverlayRoute<void>(
        enableGestureBack: false,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, animation, secondaryAnimation) => _PreviewProbe(
          onMount: () => mounts++,
          onDispose: () => disposals++,
        ),
      ));
      await tester.pump();
      await tester
          .pump(Duration(milliseconds: closeDuringEntrance ? 100 : 300));
      expect(mounts, 1);
      final state = tester.state(find.byType(_PreviewProbe));
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(mounts, 1,
          reason: 'Starting reverse must not create a second image page');
      expect(disposals, 0);
      expect(tester.state(find.byType(_PreviewProbe)), same(state));
      await tester.pumpAndSettle();
      expect(disposals, 1);
    });
  }
}
