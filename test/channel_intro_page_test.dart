import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/channel_intro_page.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(393, 852)]) {
    testWidgets('channel introduction fits ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
              builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => ChannelIntroPage.show(context),
                      child: const Text('open'),
                    ),
                  )),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ChannelIntroPage)).height,
          closeTo(size.height * .9, 1));
      expect(
          find.byKey(const ValueKey('channel-intro-create')), findsOneWidget);
      expect(find.image(AssetImage('assets/img/channel_intro.png')),
          findsOneWidget);

      await tester
          .ensureVisible(find.byKey(const ValueKey('channel-intro-create')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelIntroPage), findsNothing);
    });
  }
}
