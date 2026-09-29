import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/favorites/favorite_list_page.dart';
void main() {
  for (final width in [320.0, 720.0]) {
    testWidgets('favorite page filters and search at width $width', (tester) async {
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
      await tester.pumpWidget(const MaterialApp(home: FavoriteListPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('unique first favorite'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.south_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.north_rounded), findsOneWidget);
      final chips = find.byType(ChoiceChip);
      expect(chips, findsNWidgets(3));
      await tester.ensureVisible(chips.at(2));
      await tester.tap(chips.at(2));
      await tester.pumpAndSettle();
      expect(find.text('unique first favorite'), findsNothing);
      await tester.ensureVisible(chips.first);
      await tester.tap(chips.first);

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pumpAndSettle();
      expect(find.text('unique first favorite'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'not found');
      await tester.pumpAndSettle();
      expect(find.text('unique first favorite'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byType(TextButton)).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('unique first favorite'));
      await tester.tap(find.text('unique first favorite'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
