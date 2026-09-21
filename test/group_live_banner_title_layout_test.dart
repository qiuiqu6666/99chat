import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_top_banner.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  const title = '一二三四五六七八九十';
  for (final width in [280.0, 320.0, 375.0, 390.0, 430.0, 768.0]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('ten characters at width $width text scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 900), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: GroupLiveTopBanner(
            session: const GroupLiveSession(
                liveSessionId: 'test',
                groupId: '',
                roomName: title,
                description: '直播说明',
                anchorUserId: '',
                status: GroupLiveStatus.live),
            onTap: () => taps++,
          )),
        )));
        await tester.pump();
        final paragraph =
            tester.renderObject<RenderParagraph>(find.text(title));
        expect(paragraph.didExceedMaxLines, isFalse);
        final painted = MatrixUtils.transformRect(
            paragraph.getTransformTo(null), Offset.zero & paragraph.size);
        final banner = tester.getRect(find.byType(GroupLiveTopBanner));
        expect(painted.left, greaterThanOrEqualTo(banner.left));
        expect(painted.right, lessThanOrEqualTo(banner.right));
        expect(painted.top, greaterThanOrEqualTo(banner.top));
        expect(painted.bottom, lessThanOrEqualTo(banner.bottom));
        expect(painted.width, greaterThan(100));
        await tester.tapAt(banner.center);
        expect(taps, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
