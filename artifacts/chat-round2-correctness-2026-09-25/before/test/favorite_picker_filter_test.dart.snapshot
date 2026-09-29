import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/favorites/favorite_picker_sheet.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_chat_controller.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

class _Controller implements TIMUIKitChatController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [320.0, 720.0]) {
    testWidgets('favorite filters and search at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dio = ApiClient.instance.dio;
      final original = List<Interceptor>.of(dio.interceptors);
      dio.interceptors.clear();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
          'items': [
            {'id': 'one', 'type': 'TEXT', 'text': 'unique first favorite', 'sourceSenderName': 'Alice', 'favoritedAt': '2026-09-22T12:01:00Z'},
            {'id': 'two', 'type': 'IMAGE', 'sourceSenderName': 'Bob', 'favoritedAt': '2026-09-02T19:53:00Z'},
          ], 'total': 2,
        }));
      }));
      addTearDown(() { dio.interceptors..clear()..addAll(original); });
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
        alignment: Alignment.bottomCenter,
        child: FavoritePickerSheet(chatController: _Controller(), convId: 'test', convType: ConvType.c2c),
      ))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('unique first favorite'), findsOneWidget);
      final chips = find.byType(ChoiceChip);
      expect(chips, findsNWidgets(3));
      await tester.ensureVisible(chips.at(2));
      await tester.tap(chips.at(2));
      await tester.pumpAndSettle();
      expect(find.text('unique first favorite'), findsNothing);
      await tester.ensureVisible(chips.first);
      await tester.tap(chips.first);
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pumpAndSettle();
      expect(find.text('unique first favorite'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'not found');
      await tester.pumpAndSettle();
      expect(find.text('unique first favorite'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
