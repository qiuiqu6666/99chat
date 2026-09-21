import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_stable_overlay_stack.dart';

void main() {
  testWidgets('adding an async overlay preserves the primary chat State',
      (tester) async {
    var initCount = 0;
    var disposeCount = 0;

    Widget build({required bool showOverlay}) {
      return MaterialApp(
        home: Scaffold(
          body: ChatStableOverlayStack(
            primary: _LifecycleProbe(
              onInit: () => initCount++,
              onDispose: () => disposeCount++,
            ),
            overlays: <Widget>[
              if (showOverlay) const Positioned(child: Text('overlay')),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(build(showOverlay: false));
    expect(initCount, 1);
    expect(disposeCount, 0);

    await tester.pumpWidget(build(showOverlay: true));
    expect(find.text('overlay'), findsOneWidget);
    expect(initCount, 1);
    expect(disposeCount, 0);

    await tester.pumpWidget(build(showOverlay: false));
    expect(initCount, 1);
    expect(disposeCount, 0);
  });
}

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe({required this.onInit, required this.onDispose});

  final VoidCallback onInit;
  final VoidCallback onDispose;

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
