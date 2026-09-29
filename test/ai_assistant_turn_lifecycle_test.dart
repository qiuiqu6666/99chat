// Regression coverage uses actual API/page with injected transport and platform boundaries.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list_for_us/scrollable_positioned_list_for_us.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

class AuditTheme extends ChangeNotifier implements DefaultThemeData {
  @override
  TUITheme get theme => DefTheme.getTheme(ThemeType.blue);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuditPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles(
          {String? dialogTitle,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Function(FilePickerStatus)? onFileLoading,
          bool allowCompression = true,
          int compressionQuality = 30,
          bool allowMultiple = false,
          bool withData = false,
          bool withReadStream = false,
          bool lockParentWindow = false,
          bool readSequential = false}) async =>
      FilePickerResult([
        PlatformFile(
            name: 'audit.csv',
            size: 3,
            bytes: Uint8List.fromList([65, 66, 67])),
      ]);
}

Uint8List eventBytes(String text) => Uint8List.fromList(
    utf8.encode('event: delta\ndata: ${jsonEncode({'text': text})}\n\n'));

Response<ResponseBody> sseResponse(
        RequestOptions request, Stream<Uint8List> body) =>
    Response<ResponseBody>(
        requestOptions: request,
        statusCode: 200,
        headers: Headers.fromMap({
          'content-type': ['text/event-stream']
        }),
        data: ResponseBody(body, 200, headers: {
          'content-type': ['text/event-stream']
        }));

class AiHarness {
  final streams = <StreamController<Uint8List>>[];
  final cancelledStreams = <int>{};
  RequestInterceptorHandler? uploadHandler;
  RequestOptions? uploadRequest;
  final dio = ApiClient.instance.dio;
  late List<Interceptor> saved;
  void Function(FlutterErrorDetails)? originalError;

  Future<void> mount(WidgetTester tester, {int history = 0}) async {
    SharedPreferences.setMockInitialValues({});
    originalError = FlutterError.onError;
    TIMUIKitCore.getInstance();
    FlutterError.onError = originalError;
    saved = dio.interceptors.toList();
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/stream')) {
        final index = streams.length;
        final stream = StreamController<Uint8List>(
            onCancel: () => cancelledStreams.add(index));
        streams.add(stream);
        handler.resolve(sseResponse(request, stream.stream));
      } else if (request.path.endsWith('/files') && request.method == 'POST') {
        uploadHandler = handler;
        uploadRequest = request;
      } else {
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'data': {
            'hasMore': false,
            'items': [
              for (var i = 0; i < history; i++)
                {
                  'id': '$i',
                  'role': 'user',
                  'content': 'History $i',
                  'status': 'complete',
                  'capability': 'chat',
                  'createdAt': 1718452800000
                }
            ]
          }
        }));
      }
    }));
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<DefaultThemeData>(create: (_) => AuditTheme()),
      ChangeNotifierProvider<LoginUserInfo>(create: (_) => LoginUserInfo()),
    ], child: const MaterialApp(home: AiAssistantPage())));
    // This route contains animated loading/cursor widgets. Advance only the
    // injected startup work instead of waiting for every animation to stop.
    await ticks(tester);
    FlutterError.onError = originalError;
  }

  dynamic bar(WidgetTester tester) => tester.widget(find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_InputBar')) as dynamic;
  dynamic lastAssistant(WidgetTester tester) => (tester.widget(find
          .byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_AssistantBubble')
          .last) as dynamic)
      .message;
  Future<void> ticks(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    FlutterError.onError = originalError;
  }

  Future<void> send(WidgetTester tester, String text) async {
    bar(tester).controller.text = text;
    bar(tester).onSubmit();
    await ticks(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final stream in streams) {
      if (!stream.isClosed) {
        // A fixture controller with no remaining listener need not deliver a
        // done event. Do not let its close future mask the behavior assertion.
        unawaited(stream.close());
      }
    }
    await tester.pump();
    dio.interceptors
      ..clear()
      ..addAll(saved);
    FlutterError.onError = originalError;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A01 actual API preserves every UTF8 split boundary', () async {
    final bytes = eventBytes('中文🙂');
    var failed = 0;
    var passed = 0;
    for (var split = 1; split < bytes.length; split++) {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(sseResponse(
            request,
            Stream.fromIterable([
              Uint8List.sublistView(bytes, 0, split),
              Uint8List.sublistView(bytes, split)
            ])));
      }));
      try {
        final events =
            await AiAssistantApi(dio: dio).stream(content: 'audit').toList();
        expect(events.single.text, '中文🙂');
        passed++;
      } on AiAssistantException catch (error) {
        failed++;
        expect(error.code, 'MAIN_UNAVAILABLE');
        expect(bytes[split] & 0xc0, 0x80);
      } finally {
        dio.close();
      }
    }
    expect(failed, 0);
    expect(passed, 41);
  });

  testWidgets('A13 stop after delta is terminal and permits next request',
      (tester) async {
    final h = AiHarness();
    await h.mount(tester);
    try {
      await h.send(tester, 'first');
      h.streams.single.add(eventBytes('partial'));
      await h.ticks(tester);
      h.bar(tester).onStop();
      await h.ticks(tester);
      expect(h.bar(tester).replying, isFalse);
      expect(h.lastAssistant(tester).status, 'stopped');
      await h.send(tester, 'second');
      expect(h.streams.length, 2);
      expect(h.bar(tester).controller.text, '');
    } finally {
      await h.dispose(tester);
    }
  });

  testWidgets('A13 stop before delta allows another request control',
      (tester) async {
    final h = AiHarness();
    await h.mount(tester);
    try {
      await h.send(tester, 'first');
      h.bar(tester).onStop();
      await h.ticks(tester);
      await h.send(tester, 'second');
      expect(h.streams.length, 2);
    } finally {
      await h.dispose(tester);
    }
  });

  testWidgets('A13 stale upload failure cannot corrupt the next active reply',
      (tester) async {
    final h = AiHarness();
    await h.mount(tester);
    FilePicker.platform = AuditPicker();
    try {
      h.bar(tester).onAttach();
      await h.ticks(tester);
      await h.send(tester, 'read file');
      expect(h.uploadHandler, isNotNull);
      expect(h.uploadRequest!.cancelToken, isNotNull);
      h.bar(tester).onStop();
      await h.ticks(tester);
      await h.send(tester, 'new request');
      expect(h.streams.length, 1);
      h.streams.single.add(eventBytes('new partial'));
      await h.ticks(tester);
      expect(h.lastAssistant(tester).text, 'new partial');
      h.uploadHandler!.reject(DioError(
          requestOptions: h.uploadRequest!,
          type: DioErrorType.other,
          error: 'injected old upload failure'));
      await h.ticks(tester);
      expect(h.lastAssistant(tester).status, 'streaming');
      expect(h.lastAssistant(tester).text, 'new partial');
      expect(h.bar(tester).replying, isTrue);
    } finally {
      await h.dispose(tester);
    }
  });

  testWidgets('A14 incoming delta preserves a reader browsing older history',
      (tester) async {
    final h = AiHarness();
    await h.mount(tester, history: 60);
    try {
      await h.send(tester, 'reply');
      h.streams.single.add(eventBytes('initial'));
      await h.ticks(tester);
      var list = tester.widget<ScrollablePositionedList>(
          find.byType(ScrollablePositionedList));
      list.itemScrollController!.jumpTo(index: 30);
      await h.ticks(tester);
      expect(
          find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_AssistantBubble'),
          findsNothing);
      h.streams.single.add(eventBytes(' update'));
      await h.ticks(tester);
      list = tester.widget<ScrollablePositionedList>(
          find.byType(ScrollablePositionedList));
      expect(
          find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_AssistantBubble'),
          findsNothing);
    } finally {
      await h.dispose(tester);
    }
  });

  testWidgets('EOF after partial text releases the turn and allows retry',
      (tester) async {
    final h = AiHarness();
    await h.mount(tester);
    try {
      await h.send(tester, 'first');
      h.streams.single.add(eventBytes('partial'));
      await h.ticks(tester);
      await h.streams.single.close();
      await h.ticks(tester);
      expect(h.bar(tester).replying, isFalse);
      expect(h.lastAssistant(tester).status, 'interrupted');
      expect(h.lastAssistant(tester).text, 'partial');
      await h.send(tester, 'second');
      expect(h.streams.length, 2);
    } finally {
      await h.dispose(tester);
    }
  });

  test('actual API rejects truncated UTF8 and incomplete SSE at EOF', () async {
    for (final bytes in [
      Uint8List.fromList([0xe4, 0xb8]),
      Uint8List.fromList(utf8.encode('event: delta\ndata: {"text":"cut"}'))
    ]) {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
          handler.resolve(sseResponse(request, Stream.value(bytes)));
        }));
      await expectLater(
          AiAssistantApi(dio: dio).stream(content: 'x').toList(),
          throwsA(isA<AiAssistantException>()
              .having((e) => e.code, 'code', 'MAIN_UNAVAILABLE')));
      dio.close();
    }
  });

  testWidgets('session boundary ends old turn without disposing retained route',
      (tester) async {
    final h = AiHarness();
    await h.mount(tester);
    try {
      await h.send(tester, 'old request');
      h.streams.single.add(eventBytes('old partial'));
      await h.ticks(tester);
      SessionIdentityService.instance.invalidate(reason: 'test_account_switch');
      // Deliver the actual notifier used by SessionManager after its identity
      // boundary; leave this route mounted to exercise the dangerous case.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      SessionManager.instance.notifyListeners();
      await h.ticks(tester);
      expect(h.bar(tester).replying, isFalse);
      expect(find.text('old partial'), findsNothing);
      h.bar(tester).controller.text = 'new draft';
      // A second state publication after teardown must not erase new input.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      SessionManager.instance.notifyListeners();
      await h.ticks(tester);
      expect(h.bar(tester).controller.text, 'new draft');
      await h.send(tester, 'new request');
      expect(h.streams, hasLength(2));
      // A later notification for this same new identity cannot stop its turn.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      SessionManager.instance.notifyListeners();
      h.streams.first.add(eventBytes('stale tail'));
      h.streams.last.add(eventBytes('new partial'));
      await h.ticks(tester);
      expect(h.lastAssistant(tester).text, 'new partial');
      expect(h.bar(tester).replying, isTrue);
    } finally {
      await h.dispose(tester);
    }
  });

  test('actual API preserves whitespace across delta boundaries', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(sseResponse(request,
            Stream.fromIterable(['Hello ', 'world', '\n  code\n'].map(eventBytes))));
      }));
    try {
      final events =
          await AiAssistantApi(dio: dio).stream(content: 'x').toList();
      expect(events.map((event) => event.text).join(), 'Hello world\n  code\n');
    } finally {
      dio.close();
    }
  });

  test('canceling actual API stream releases underlying body subscription',
      () async {
    final cancelled = Completer<void>();
    final body =
        StreamController<Uint8List>(onCancel: () => cancelled.complete());
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(sseResponse(request, body.stream));
      }));
    final received = Completer<void>();
    final subscription = AiAssistantApi(dio: dio)
        .stream(content: 'x')
        .listen((_) => received.complete());
    body.add(eventBytes('text'));
    await received.future;
    await subscription.cancel();
    await cancelled.future;
    await body.close();
    dio.close();
  });

  testWidgets(
      'burst updates only active reply; done flushes every token and releases UI',
      (tester) async {
    final h = AiHarness();
    await h.mount(tester);
    try {
      await h.send(tester, 'burst');
      final inputBefore = h.bar(tester);
      for (var i = 0; i < 100; i++) {
        h.streams.single.add(eventBytes('$i,'));
      }
      await h.ticks(tester);
      expect(identical(inputBefore, h.bar(tester)), isTrue);
      expect(h.lastAssistant(tester).text,
          List.generate(100, (i) => '$i,').join());
      h.streams.single.add(eventBytes('tail'));
      h.streams.single
          .add(Uint8List.fromList(utf8.encode('event: done\ndata: {}\n\n')));
      await h.ticks(tester);
      expect(h.lastAssistant(tester).text, endsWith('tail'));
      expect(h.lastAssistant(tester).status, 'complete');
      expect(h.bar(tester).replying, isFalse);
      expect(h.cancelledStreams, contains(0));
    } finally {
      await h.dispose(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
