import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/favorite_message_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/favorites/favorite_edit_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/favorites/widgets/favorite_editor_icon.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('favorite editor preserves draft and saves at $size/$scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dio = ApiClient.instance.dio;
        final original = List<Interceptor>.of(dio.interceptors);
        Map<String, dynamic>? saved;
        dio.interceptors..clear()..add(InterceptorsWrapper(onRequest: (request, handler) {
          saved = Map<String, dynamic>.from(request.data as Map);
          handler.resolve(Response(requestOptions: request, statusCode: 200,
            data: {...saved!, 'id': 'saved-note', 'favoritedAt': '2026-09-23T00:00:00Z'}));
        }));
        addTearDown(() => dio.interceptors..clear()..addAll(original));
        FavoriteMessageItem? result;
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async {
            result = await FavoriteEditPage.pushCreate(context);
          }, child: const Text('open')))),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byKey(const ValueKey('favorite-note')), '测试笔记🙂');
        FocusManager.instance.primaryFocus?.unfocus();
        for (final kind in ['type_image', 'type_video', 'type_text']) {
          final icon = find.byWidgetPredicate((w) => w is FavoriteEditorIcon && w.kind == kind);
          await tester.ensureVisible(icon);
          await tester.tap(icon);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(tester.widget<TextField>(find.byKey(const ValueKey('favorite-note'))).controller!.text, '测试笔记🙂');
        await tester.scrollUntilVisible(find.byKey(const ValueKey('favorite-remark')), 160, scrollable: find.byType(Scrollable).first);
        await tester.enterText(find.byKey(const ValueKey('favorite-remark')), '备注');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final save = find.byType(FilledButton).last;
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved?['text'], '测试笔记🙂');
        expect(saved?['sourceConvLabel'], '备注');
        expect(result?.id, 'saved-note');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
