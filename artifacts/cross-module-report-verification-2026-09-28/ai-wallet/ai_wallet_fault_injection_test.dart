// Read-only audit: imports actual product classes; assertions capture current defects.
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
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_stack.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order_events.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_controller.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_snapshot_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/api_node_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_endpoint.dart';
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
  Future<FilePickerResult?> pickFiles({String? dialogTitle, String? initialDirectory,
    FileType type = FileType.any, List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading, bool allowCompression = true,
    int compressionQuality = 30, bool allowMultiple = false, bool withData = false,
    bool withReadStream = false, bool lockParentWindow = false,
    bool readSequential = false}) async => FilePickerResult([
      PlatformFile(name: 'audit.csv', size: 3, bytes: Uint8List.fromList([65,66,67])),
    ]);
}

Uint8List eventBytes(String text) => Uint8List.fromList(utf8.encode(
    'event: delta\ndata: ${jsonEncode({'text': text})}\n\n'));

Response<ResponseBody> sseResponse(RequestOptions request, Stream<Uint8List> body) =>
    Response<ResponseBody>(requestOptions: request, statusCode: 200,
      headers: Headers.fromMap({'content-type': ['text/event-stream']}),
      data: ResponseBody(body, 200, headers: {'content-type': ['text/event-stream']}));

class AiHarness {
  final streams = <StreamController<Uint8List>>[];
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
        final stream = StreamController<Uint8List>();
        streams.add(stream);
        handler.resolve(sseResponse(request, stream.stream));
      } else if (request.path.endsWith('/files') && request.method == 'POST') {
        uploadHandler = handler;
        uploadRequest = request;
      } else {
        handler.resolve(Response(requestOptions: request, statusCode: 200,
          data: {'data': {'hasMore': false, 'items': [for (var i=0;i<history;i++)
            {'id':'$i','role':'user','content':'History $i', 'status':'complete',
             'capability':'chat', 'createdAt':1718452800000}]}}));
      }
    }));
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<DefaultThemeData>(create: (_) => AuditTheme()),
      ChangeNotifierProvider<LoginUserInfo>(create: (_) => LoginUserInfo()),
    ], child: const MaterialApp(home: AiAssistantPage())));
    await tester.pumpAndSettle();
    FlutterError.onError = originalError;
  }

  dynamic bar(WidgetTester tester) => tester.widget(find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_InputBar')) as dynamic;
  dynamic lastAssistant(WidgetTester tester) => (tester.widget(find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_AssistantBubble').last) as dynamic).message;
  Future<void> ticks(WidgetTester tester) async {
    for(var i=0;i<5;i++) { await tester.pump(const Duration(milliseconds:20)); }
    FlutterError.onError = originalError;
  }
  Future<void> send(WidgetTester tester, String text) async {
    bar(tester).controller.text = text;
    bar(tester).onSubmit();
    await ticks(tester);
  }
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for(final stream in streams) { if(!stream.isClosed) await stream.close(); }
    dio.interceptors..clear()..addAll(saved);
    FlutterError.onError = originalError;
  }
}

class AuditWalletRepo implements WalletRepository {
  int calls = 0;
  @override
  Future<WalletDto> getWallet() async {
    calls++;
    return const WalletDto(totalBal:'0',trxAddr:'',coins:[]);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class AuditWalletStore extends WalletSnapshotLocalStore {
  @override Future<WalletDto?> read(String owner) async => null;
  @override Future<void> write(String owner, WalletDto wallet) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A01 actual API fails only at multi-byte UTF8 boundaries', () async {
    final bytes = eventBytes('中文🙂');
    var failed=0;
    var passed=0;
    for(var split=1;split<bytes.length;split++) {
      final dio=Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) {
        handler.resolve(sseResponse(request, Stream.fromIterable([
          Uint8List.sublistView(bytes,0,split), Uint8List.sublistView(bytes,split)])));
      }));
      try {
        final events=await AiAssistantApi(dio:dio).stream(content:'audit').toList();
        expect(events.single.text,'中文🙂');
        passed++;
        expect(bytes[split]&0xc0,isNot(0x80));
      } on AiAssistantException catch(error) {
        failed++;
        expect(error.code,'MAIN_UNAVAILABLE');
        expect(bytes[split]&0xc0,0x80);
      } finally { dio.close(); }
    }
    expect(failed,7);
    print('AUDIT A01 split cases: failed=$failed passed=$passed total=${bytes.length-1}');
  });

  testWidgets('A13 stop after delta keeps streaming and blocks next request', (tester) async {
    final h=AiHarness(); await h.mount(tester);
    try {
      await h.send(tester,'first');
      h.streams.single.add(eventBytes('partial'));
      await h.ticks(tester);
      h.bar(tester).onStop();
      await h.ticks(tester);
      expect(h.bar(tester).replying,isFalse);
      expect(h.lastAssistant(tester).status,'streaming');
      await h.send(tester,'second');
      expect(h.streams.length,1);
      expect(h.bar(tester).controller.text,'second');
      print('AUDIT A13 stopped after delta: status=streaming, second request blocked');
    } finally { await h.dispose(tester); }
  });

  testWidgets('A13 stop before delta allows another request control', (tester) async {
    final h=AiHarness(); await h.mount(tester);
    try {
      await h.send(tester,'first');
      h.bar(tester).onStop(); await h.ticks(tester);
      await h.send(tester,'second');
      expect(h.streams.length,2);
    } finally { await h.dispose(tester); }
  });

  testWidgets('A13 stale upload failure corrupts the next active reply', (tester) async {
    final h=AiHarness(); await h.mount(tester);
    FilePicker.platform=AuditPicker();
    try {
      h.bar(tester).onAttach(); await h.ticks(tester);
      await h.send(tester,'read file');
      expect(h.uploadHandler,isNotNull);
      expect(h.uploadRequest!.cancelToken,isNull);
      h.bar(tester).onStop(); await h.ticks(tester);
      await h.send(tester,'new request');
      expect(h.streams.length,1);
      h.streams.single.add(eventBytes('new partial')); await h.ticks(tester);
      expect(h.lastAssistant(tester).text,'new partial');
      h.uploadHandler!.reject(DioError(requestOptions:h.uploadRequest!,
        type:DioErrorType.other, error:'injected old upload failure'));
      await h.ticks(tester);
      expect(h.lastAssistant(tester).status,'failed');
      expect(h.lastAssistant(tester).text,isNot('new partial'));
      expect(h.bar(tester).replying,isFalse);
      print('AUDIT A13 old upload failure overwrote new partial; active reply UI stopped');
    } finally { await h.dispose(tester); }
  });

  testWidgets('A14 incoming delta forces history viewport to newest item', (tester) async {
    final h=AiHarness(); await h.mount(tester,history:60);
    try {
      await h.send(tester,'reply');
      h.streams.single.add(eventBytes('initial')); await h.ticks(tester);
      var list=tester.widget<ScrollablePositionedList>(find.byType(ScrollablePositionedList));
      list.itemScrollController!.jumpTo(index:30);
      await h.ticks(tester);
      expect(find.byWidgetPredicate((w)=>w.runtimeType.toString()=='_AssistantBubble'),findsNothing);
      h.streams.single.add(eventBytes(' update')); await h.ticks(tester);
      list=tester.widget<ScrollablePositionedList>(find.byType(ScrollablePositionedList));
      expect(find.byWidgetPredicate((w)=>w.runtimeType.toString()=='_AssistantBubble'),findsOneWidget);
      print('AUDIT A14 viewport jumped from old item30 to newest item0 on delta');
    } finally { await h.dispose(tester); }
  });

  testWidgets('A15 actual retained controller reloads on hidden balance event', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo=AuditWalletRepo();
    final controller=WalletController(repo:repo,localStore:AuditWalletStore());
    final tab=ValueNotifier<int>(1);
    await tester.pumpWidget(MaterialApp(home:ValueListenableBuilder<int>(
      valueListenable:tab,builder:(context,index,_)=>HomeTabStack(index:index,
      routeVisible:true,builders:[(_)=>const Text('chat'),(_)=>ChangeNotifierProvider.value(
        value:controller,child:const Text('wallet'))]))));
    tab.value=0; await tester.pump();
    expect(find.text('wallet'),findsNothing);
    expect(find.text('wallet',skipOffstage:false),findsOneWidget);
    WalletOrderEvents.notifyBalance();
    for(var i=0;i<5;i++) { await tester.pump(); }
    expect(repo.calls,1);
    await tester.pumpWidget(const SizedBox.shrink()); controller.dispose(); tab.dispose();
    WalletOrderEvents.notifyBalance(); await tester.pump();
    expect(repo.calls,1);
    print('AUDIT A15 hidden balance event performed getWallet; disposed listener did not');
  });

  test('A17 actual default catalog selects HTTP and all realtime entries select plain TCP', () {
    final defaultNode=ApiNodeService.catalog.singleWhere((n)=>n.id==ApiNodeService.defaultNodeId);
    expect(Uri.parse(defaultNode.apiBaseUrl).scheme,'http');
    for(final node in ApiNodeService.catalog) {
      expect(FriendRealtimeEndpoint.parse(node.realtimeTcpBase)!.useTls,isFalse);
    }
    expect(FriendRealtimeEndpoint.parse('https://example.test')!.useTls,isTrue);
    print('AUDIT A17 default API is HTTP; 2/2 realtime catalog entries useTls=false; HTTPS control=true');
  });
}
