import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_route_depth_transition.dart';

void main() {
  final pageTransitions = PageTransitionsTheme(
    builders: const {
      TargetPlatform.android: AppPageTransitionsBuilder(),
      TargetPlatform.iOS: AppPageTransitionsBuilder(),
    },
  );

  Finder depthOf(String page) => find.ancestor(
        of: find.byKey(ValueKey(page), skipOffstage: false),
        matching: find.byType(AppRouteDepthTransition, skipOffstage: false),
      );

  double activeDepthOf(WidgetTester tester, String page) => tester
      .widgetList<AppRouteDepthTransition>(depthOf(page))
      .map((transition) => transition.animation.value)
      .reduce((a, b) => a > b ? a : b);

  List<double> scrimOpacities(WidgetTester tester, String page) => tester
      .widgetList<ColoredBox>(
        find.descendant(
          of: depthOf(page),
          matching: find.byType(ColoredBox, skipOffstage: false),
        ),
      )
      .where((box) => box.color.r == 0 && box.color.g == 0 && box.color.b == 0)
      .map((box) => box.color.a)
      .toList();

  double routeScale(WidgetTester tester, String page) => tester
      .widgetList<Transform>(find.descendant(
        of: depthOf(page),
        matching: find.byType(Transform, skipOffstage: false),
      ))
      .map((transform) => transform.transform.entry(0, 0))
      .where((scale) => scale >= 0.9 && scale <= 1.0)
      .reduce((a, b) => a < b ? a : b);

  Future<Color> capturePixel(
    WidgetTester tester,
    GlobalKey captureKey,
    int x,
    int y,
  ) async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final frame = (await tester.runAsync(() => boundary.toImage()))!;
    final pixels = (await tester
        .runAsync(() => frame.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final offset = (y * frame.width + x) * 4;
    final color = Color.fromARGB(
      pixels.getUint8(offset + 3),
      pixels.getUint8(offset),
      pixels.getUint8(offset + 1),
      pixels.getUint8(offset + 2),
    );
    frame.dispose();
    return color;
  }

  testWidgets('edge and old page darken together through push, gesture, pop',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final captureKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: pageTransitions,
          scaffoldBackgroundColor: const Color(0xFFF4F4F4),
        ),
        onGenerateRoute: (_) => AppMaterialPageRoute<void>(
          builder: (_) =>
              const _ColorPage(name: 'light first', color: Color(0xFFF4F4F4)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final originalEdge = await capturePixel(tester, captureKey, 1, 300);
    expect(scrimOpacities(tester, 'light first'), contains(0));

    final second = AppMaterialPageRoute<void>(
      builder: (_) => const _ColorPage(name: 'blue second', color: Colors.blue),
    );
    navigatorKey.currentState!.push(second);
    await tester.pump();
    await tester.pump(AppRouteDepthTransition.transitionDuration ~/ 2);
    final pushEdge = await capturePixel(tester, captureKey, 1, 300);
    final pushPage = await capturePixel(tester, captureKey, 30, 300);
    final pushTopPage = await capturePixel(tester, captureKey, 750, 300);
    expect(pushEdge.r, lessThan(originalEdge.r * 0.8));
    expect(pushEdge.r, closeTo(pushPage.r, 0.02));
    expect(pushTopPage.b, greaterThan(0.9));
    expect(activeDepthOf(tester, 'light first'),
        closeTo(second.animation!.value, 0.001));

    await tester.pumpAndSettle();
    expect(scrimOpacities(tester, 'light first'),
        contains(closeTo(AppRouteDepthTransition.maximumScrimOpacity, 0.001)));

    final gesture = await tester.startGesture(const Offset(4, 300));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    final gestureEdge = await capturePixel(tester, captureKey, 1, 300);
    expect(second.animation!.value, inExclusiveRange(0, 1));
    expect(
        gestureEdge.r,
        greaterThan(originalEdge.r *
            (1 - AppRouteDepthTransition.maximumScrimOpacity)));
    expect(gestureEdge.r, lessThan(originalEdge.r));
    expect(activeDepthOf(tester, 'light first'),
        closeTo(second.animation!.value, 0.001));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(second.animation!.value, 1);
    expect(scrimOpacities(tester, 'light first'),
        contains(closeTo(AppRouteDepthTransition.maximumScrimOpacity, 0.001)));

    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(AppRouteDepthTransition.transitionDuration ~/ 2);
    final popEdge = await capturePixel(tester, captureKey, 1, 300);
    final popPage = await capturePixel(tester, captureKey, 30, 300);
    expect(popEdge.r, lessThan(originalEdge.r * 0.8));
    expect(popEdge.r, closeTo(popPage.r, 0.02));
    expect(activeDepthOf(tester, 'light first'),
        closeTo(second.animation!.value, 0.001));
    await tester.pumpAndSettle();
    final restoredEdge = await capturePixel(tester, captureKey, 1, 300);
    expect(restoredEdge.r, closeTo(originalEdge.r, 0.01));
    expect(scrimOpacities(tester, 'light first'), contains(0));
    expect(routeScale(tester, 'light first'), 1);
  });

  testWidgets('stacked routes share progress, reverse, and preserve page state',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final firstKey = GlobalKey<_ScrollableFirstPageState>();
    final captureKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: pageTransitions,
          scaffoldBackgroundColor: const Color(0xFFF4F4F4),
        ),
        onGenerateRoute: (_) => AppMaterialPageRoute<void>(
          builder: (_) => _ScrollableFirstPage(key: firstKey),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    firstKey.currentState!.scrollController.jumpTo(180);
    await tester.pump();

    final second = AppMaterialPageRoute<void>(
      builder: (_) => const _ColorPage(name: 'second', color: Colors.blue),
    );
    navigatorKey.currentState!.push(second);
    await tester.pump();
    await tester.pump(AppRouteDepthTransition.transitionDuration ~/ 2);

    expect(second.animation!.value, inExclusiveRange(0, 1));
    expect(activeDepthOf(tester, 'first'),
        closeTo(second.animation!.value, 0.001));
    expect(activeDepthOf(tester, 'second'), 0);
    expect(
        scrimOpacities(tester, 'first').any((opacity) => opacity > 0), isTrue);
    expect(scrimOpacities(tester, 'second').every((opacity) => opacity == 0),
        isTrue);
    expect(routeScale(tester, 'first'), inExclusiveRange(0.96, 1.0));
    expect(routeScale(tester, 'second'), 1.0);

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final frame = (await tester.runAsync(() => boundary.toImage()))!;
    final pixels = (await tester
        .runAsync(() => frame.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    Color pixelAt(int x, int y) {
      final offset = (y * frame.width + x) * 4;
      return Color.fromARGB(
        pixels.getUint8(offset + 3),
        pixels.getUint8(offset),
        pixels.getUint8(offset + 1),
        pixels.getUint8(offset + 2),
      );
    }

    final exposedEdgePixel = pixelAt(1, 300);
    final oldPagePixel = pixelAt(20, 300);
    final newPagePixel = pixelAt(750, 300);
    final depthProgress = AppRouteDepthTransition.defaultCurve
        .transform(second.animation!.value.clamp(0.0, 1.0));
    final backgroundChannel = 244 /
        255 *
        (1 - AppRouteDepthTransition.maximumScrimOpacity * depthProgress);
    expect(exposedEdgePixel.r, closeTo(backgroundChannel, 0.01));
    expect(exposedEdgePixel.g, closeTo(backgroundChannel, 0.01));
    expect(exposedEdgePixel.b, closeTo(backgroundChannel, 0.01));
    expect(oldPagePixel.r, greaterThan(oldPagePixel.g * 2));
    expect(oldPagePixel.r, greaterThan(oldPagePixel.b * 2));
    expect(newPagePixel.b, greaterThan(0.9));
    expect(newPagePixel.b, greaterThan(newPagePixel.g * 1.5));
    frame.dispose();

    await tester.pumpAndSettle();
    expect(routeScale(tester, 'first'), closeTo(0.96, 0.001));
    final third = AppMaterialPageRoute<void>(
      builder: (_) => const _ColorPage(name: 'third', color: Colors.green),
    );
    navigatorKey.currentState!.push(third);
    await tester.pump();
    await tester.pump(AppRouteDepthTransition.transitionDuration ~/ 2);
    expect(activeDepthOf(tester, 'second'),
        closeTo(third.animation!.value, 0.001));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(AppRouteDepthTransition.transitionDuration ~/ 2);
    expect(activeDepthOf(tester, 'second'),
        closeTo(third.animation!.value, 0.001));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('third')), findsNothing);

    final gesture = await tester.startGesture(const Offset(4, 300));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    expect(second.animation!.value, lessThan(1));
    expect(activeDepthOf(tester, 'first'),
        closeTo(second.animation!.value, 0.001));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('second')), findsOneWidget);
    expect(activeDepthOf(tester, 'first'), 1);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('second')), findsNothing);
    expect(activeDepthOf(tester, 'first'), 0);
    expect(routeScale(tester, 'first'), 1.0);
    expect(firstKey.currentState!.scrollController.offset, 180);
    await tester.tap(find.text('tap first'));
    expect(firstKey.currentState!.tapCount, 1);
  });

  testWidgets('MaterialPageRoute below an app route receives delegated depth',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(pageTransitionsTheme: pageTransitions),
      home: const _ColorPage(name: 'material first', color: Colors.red),
    ));

    final second = AppMaterialPageRoute<void>(
      builder: (_) => const _ColorPage(name: 'app second', color: Colors.blue),
    );
    navigatorKey.currentState!.push(second);
    await tester.pump();
    await tester.pump(AppRouteDepthTransition.transitionDuration ~/ 2);
    expect(activeDepthOf(tester, 'material first'),
        closeTo(second.animation!.value, 0.001));
    expect(
        scrimOpacities(tester, 'material first').any((opacity) => opacity > 0),
        isTrue);
    expect(
        scrimOpacities(tester, 'app second').every((opacity) => opacity == 0),
        isTrue);

    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material first')), findsOneWidget);
    expect(
        scrimOpacities(tester, 'material first')
            .every((opacity) => opacity == 0),
        isTrue);
  });

  testWidgets('app route below a MaterialPageRoute follows the same animation',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(pageTransitionsTheme: pageTransitions),
      onGenerateRoute: (_) => AppMaterialPageRoute<void>(
        builder: (_) => const _ColorPage(name: 'app first', color: Colors.red),
      ),
    ));
    await tester.pumpAndSettle();

    final second = MaterialPageRoute<void>(
      builder: (_) =>
          const _ColorPage(name: 'material second', color: Colors.blue),
    );
    navigatorKey.currentState!.push(second);
    await tester.pump();
    await tester.pump(AppRouteDepthTransition.transitionDuration ~/ 2);
    expect(activeDepthOf(tester, 'app first'),
        closeTo(second.animation!.value, 0.001));
    expect(scrimOpacities(tester, 'app first').any((opacity) => opacity > 0),
        isTrue);
    expect(
        scrimOpacities(tester, 'material second')
            .every((opacity) => opacity == 0),
        isTrue);

    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(activeDepthOf(tester, 'app first'), 0);
  });

  testWidgets('two MaterialPageRoutes use the themed depth transition',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(pageTransitionsTheme: pageTransitions),
      home: const _ColorPage(name: 'first material', color: Colors.red),
    ));

    final second = MaterialPageRoute<void>(
      builder: (_) =>
          const _ColorPage(name: 'second material', color: Colors.blue),
    );
    navigatorKey.currentState!.push(second);
    await tester.pump();
    await tester.pump(AppRouteDepthTransition.transitionDuration ~/ 2);
    expect(activeDepthOf(tester, 'first material'),
        closeTo(second.animation!.value, 0.001));
    expect(routeScale(tester, 'first material'), inExclusiveRange(0.96, 1.0));
    expect(routeScale(tester, 'second material'), 1.0);

    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(activeDepthOf(tester, 'first material'), 0);
  });
}

class _ColorPage extends StatelessWidget {
  const _ColorPage({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) => Scaffold(
        key: ValueKey(name),
        backgroundColor: color,
        body: Center(child: Text(name)),
      );
}

class _ScrollableFirstPage extends StatefulWidget {
  const _ScrollableFirstPage({super.key});

  @override
  State<_ScrollableFirstPage> createState() => _ScrollableFirstPageState();
}

class _ScrollableFirstPageState extends State<_ScrollableFirstPage> {
  final scrollController = ScrollController();
  int tapCount = 0;

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('first'),
        appBar: AppBar(
          actions: [
            TextButton(
              onPressed: () => setState(() => tapCount++),
              child: const Text('tap first'),
            ),
          ],
        ),
        body: ListView(
          controller: scrollController,
          children: const [
            SizedBox(height: 1600, child: ColoredBox(color: Colors.red))
          ],
        ),
      );
}
