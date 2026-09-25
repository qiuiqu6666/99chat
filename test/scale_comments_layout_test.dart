import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/moments/moments_detail_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_store.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

void main() {
  testWidgets(
      '10k comments build a bounded viewport and later rows remain reachable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final errorHandler = FlutterError.onError;
    TIMUIKitCore.getInstance();
    FlutterError.onError = errorHandler;
    MomentsStore.debugAccountScopeOverride = 'scale-comments';
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': {
          'momentId': 'scale',
          'author': {'userId': 'owner', 'nickname': 'Owner'},
          'text': 'Scale post',
          'createdAt': 1718452800000,
          'commentCount': 10000,
          'comments': [
            for (var i = 0; i < 10000; i++)
              {
                'commentId': 'c$i',
                'author': {'userId': 'u$i', 'nickname': 'Member'},
                'text': 'Scale comment $i',
                'createdAt': 1718452800000,
              }
          ],
        }
      }));
    }));
    try {
      await tester.pumpWidget(
          const MaterialApp(home: MomentsDetailPage(postId: 'scale')));
      await tester.pumpAndSettle();
      FlutterError.onError = errorHandler;
      final rows = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_DetailCommentsRows');
      expect(rows.evaluate().length, inInclusiveRange(1, 35));
      expect(find.text('Scale comment 9999'), findsNothing);
      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      scrollable.position.jumpTo(3000);
      await tester.pumpAndSettle();
      FlutterError.onError = errorHandler;
      expect(rows.evaluate().length, inInclusiveRange(1, 40));
      expect(
          rows.evaluate().any((e) => (e.widget as dynamic).index > 10), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterError.onError = errorHandler;
      dio.interceptors
        ..clear()
        ..addAll(saved);
      MomentsStore.debugAccountScopeOverride = null;
    }
  });
}
