import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_inline_watch_banner.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_watch_float.dart';

void main() {
  testWidgets('closing and reopening the float keeps its loaded banner state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dio = ApiClient.instance.dio;
    final originalInterceptors = dio.interceptors.toList();
    var requests = 0;
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        requests++;
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'code': 0,
            'data': {'liveSessionId': 'live-1', 'status': 'SCHEDULED'},
          },
        ));
      }));
    addTearDown(() {
      dio.interceptors
        ..clear()
        ..addAll(originalInterceptors);
    });

    const session = GroupLiveSession(
      liveSessionId: 'live-1',
      groupId: 'group-1',
      roomName: 'Room',
      anchorUserId: 'host',
      status: GroupLiveStatus.scheduled,
    );
    Future<void> show(bool visible) => tester.pumpWidget(MaterialApp(
          home: RouteVisibility(
              isVisible: true,
              child: Scaffold(
                body: Stack(children: [
                  GroupLiveWatchFloat(
                    session: session,
                    visible: visible,
                    onClose: () {},
                  ),
                ]),
              )),
        ));

    final banner = find.byType(GroupLiveInlineWatchBanner, skipOffstage: false);
    await show(true);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    final originalState = tester.state(banner);
    expect(requests, 1);

    await show(false);
    expect(find.byType(GroupLiveInlineWatchBanner), findsNothing);
    expect(tester.state(banner), same(originalState));

    await show(true);
    expect(tester.state(banner), same(originalState));
    expect(requests, 1);
  });
}
