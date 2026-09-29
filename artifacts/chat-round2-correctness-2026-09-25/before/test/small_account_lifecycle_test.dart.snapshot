import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/chat_header_state_controller.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_header_title.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_inline_watch_banner.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_video_progress_bar.dart';

class AttachmentChanges extends ValueNotifier<int> {
  AttachmentChanges() : super(0);
  bool get hasSubscribers => hasListeners;
}

class TestPresence extends PresenceProvider {
  int listenerCount = 0;
  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount--;
    super.removeListener(listener);
  }

  void ping() => notifyListeners();
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  testWidgets(
      'header ignores unrelated notifications and refreshes after hiding',
      (tester) async {
    final presence = TestPresence();
    final settings = LocalSetting(autoLoad: false)..isShowOnlineStatus = false;
    final header = ChatHeaderStateController();
    final visible = ValueNotifier<bool>(true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PresenceProvider>.value(value: presence),
        ChangeNotifierProvider<LocalSetting>.value(value: settings),
      ],
      child: MaterialApp(
          home: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, value, child) =>
            RouteVisibility(isVisible: value, child: child!),
        child: ChatHeaderTitle(
            peerUserId: null,
            conversationID: 'group',
            conversationFaceUrl: '',
            title: 'Before',
            headerState: header,
            convType: ConvType.group,
            theme: TUITheme()),
      )),
    ));
    await tester.pump();
    final rowFinder = find
        .descendant(
            of: find.byType(ChatHeaderTitle), matching: find.byType(Row))
        .first;
    final row = tester.widget(rowFinder);
    final visibleListeners = presence.listenerCount;
    presence.ping();
    await tester.pump();
    expect(identical(row, tester.widget(rowFinder)), isTrue);
    visible.value = false;
    await tester.pump();
    expect(presence.listenerCount, visibleListeners - 1);
    header.setSnapshot(conversationFaceUrl: '', titleText: 'After');
    await tester.pump();
    expect(find.text('Before'), findsOneWidget);
    visible.value = true;
    await tester.pump();
    expect(presence.listenerCount, visibleListeners);
    expect(find.text('After'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    presence.dispose();
    settings.dispose();
    header.dispose();
    visible.dispose();
  });

  testWidgets('event-driven video attachment has no endless polling',
      (tester) async {
    final changes = AttachmentChanges();
    final key = GlobalKey<TIMUIKitVideoPlayerState>();
    await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
      MediaPreviewVideoProgressBar(playerKey: key, attachmentChanges: changes),
    ])));
    changes.value++;
    await tester.pump(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    changes.value++;
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    expect(changes.hasSubscribers, isFalse);
    changes.dispose();
  });

  testWidgets('hidden live request cannot restart polling; resume loads once',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final errorHandler = FlutterError.onError;
    addTearDown(() => FlutterError.onError = errorHandler);
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    final pending = <(RequestOptions, RequestInterceptorHandler)>[];
    dio.interceptors.clear();
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) => pending.add((r, h))));
    final visible = ValueNotifier<bool>(true);
    try {
      await tester.pumpWidget(MaterialApp(
          home: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, value, child) =>
            RouteVisibility(isVisible: value, child: child!),
        child: GroupLiveInlineWatchBanner(
            session: const GroupLiveSession(
                liveSessionId: 'live',
                groupId: 'group',
                roomName: 'Room',
                anchorUserId: 'host',
                status: GroupLiveStatus.scheduled),
            onClose: () {}),
      )));
      await tester.pump();
      FlutterError.onError = errorHandler;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        FlutterError.onError = errorHandler;
      }
      expect(pending.length, 1);
      visible.value = false;
      await tester.pump();
      FlutterError.onError = errorHandler;
      void respond(int index) {
        final (r, h) = pending[index];
        h.resolve(Response(requestOptions: r, statusCode: 200, data: {
          'code': 0,
          'data': {'liveSessionId': 'live', 'status': 'SCHEDULED'},
        }));
      }

      respond(0);
      await tester.pump();
      FlutterError.onError = errorHandler;
      await tester.pump(const Duration(seconds: 30));
      FlutterError.onError = errorHandler;
      expect(pending.length, 1);
      visible.value = true;
      await tester.pump();
      FlutterError.onError = errorHandler;
      await tester.pump();
      FlutterError.onError = errorHandler;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        FlutterError.onError = errorHandler;
      }
      expect(pending.length, 2);
      respond(1);
      await tester.pump();
      FlutterError.onError = errorHandler;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      FlutterError.onError = errorHandler;
      expect(pending.length, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        FlutterError.onError = errorHandler;
      }
      expect(pending.length, 3);
      respond(2);
      await tester.pump();
      FlutterError.onError = errorHandler;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    } finally {
      dio.interceptors
        ..clear()
        ..addAll(saved);
      visible.dispose();
    }
  });
}
