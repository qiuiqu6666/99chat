import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility_host.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_visibility.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';

class _ReadingModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
}

class _Bitmap extends ImageProvider<_Bitmap> {
  const _Bitmap(this.image);
  final ui.Image image;
  @override
  Future<_Bitmap> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Bitmap key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

V2TimMessage _row(String conv, int seq) => V2TimMessage.fromJson({
      'message_msg_id': 'preview-$seq',
      'message_risk_type_identified': 0,
    })
      ..groupID = conv
      ..seq = '$seq'
      ..timestamp = seq
      ..isSelf = false
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'message $seq');

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final mode in ['latest', 'history', 'fling']) {
      for (final closeMode in ['back', 'button', 'slide']) {
        final readingHistory = mode != 'latest';
        testWidgets('$platform $mode preview $closeMode keeps bubbles painted',
            (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            tester.view.physicalSize = const Size(400, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final handler = FlutterError.onError;
            addTearDown(() => FlutterError.onError = handler);
            Future<void> frame([int ms = 16]) async {
              await tester.pump(Duration(milliseconds: ms));
              FlutterError.onError = handler;
            }

            await serviceLocator.unregister<TUIChatGlobalModel>();
            final global = TUIChatGlobalModel();
            serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
            const conv = '@preview-return';
            final model = _ReadingModel()
              ..conversationID = conv
              ..conversationType = ConvType.group
              ..chatConfig = const TIMUIKitChatConfig(
                  isAutoReportRead: false,
                  isShowReadingStatus: false,
                  isUseDraft: false)
              ..suppressReadReporting = true
              ..haveMoreData = false
              ..haveMoreLatestData = false;
            global.configureMessageWriterScope(
                ownerUserID: 'preview-owner',
                accountGeneration: 1,
                domainGeneration: 1);
            global.chatConfig = model.chatConfig;
            global.setCurrentConversation(
                CurrentConversation(conv, ConvType.group),
                notify: false);
            final messages = [for (var i = 80; i > 0; i--) _row(conv, i)];
            global.setMessageList(conv, messages,
                replace: true, applyMemoryWindow: false);
            global.markInitialHistoryLoaded(conv);
            final scroll = AutoScrollController();
            final controller =
                TIMUIKitHistoryMessageListController(scrollController: scroll);
            final navigator = GlobalKey<NavigatorState>();
            late BuildContext chatContext;
            await tester.pumpWidget(MultiProvider(
              providers: [
                ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
                ChangeNotifierProvider<TUIChatSeparateViewModel>.value(
                    value: model),
              ],
              child: MaterialApp(
                  navigatorKey: navigator,
                  home: RouteVisibilityHost(
                    child: Builder(builder: (context) {
                      chatContext = context;
                      return TickerMode(
                        enabled: RouteVisibility.isRouteVisible(context),
                        child: Scaffold(
                            body: TIMUIKitHistoryMessageListSelector(
                          conversationID: conv,
                          builder: (_, rows, __) => TIMUIKitHistoryMessageList(
                            key: const Key('history'),
                            model: model,
                            conversation: V2TimConversation(
                                conversationID: 'group_$conv',
                                groupID: conv,
                                type: 2,
                                unreadCount: 0,
                                lastMessage: messages.first),
                            controller: controller,
                            messageList: rows,
                            onLoadMore: (_, __, [count, seq, message]) async =>
                                false,
                            itemBuilder: (_, message) => SizedBox(
                              key: ValueKey('row-${message?.msgID}'),
                              height: message?.elemType == 11 ? 24 : 64,
                              child: PreviewHero(
                                  tag: message?.msgID ?? 'divider',
                                  child: ColoredBox(
                                      color: Colors.blue,
                                      child: Text('seq:${message?.seq}'))),
                            ),
                          ),
                        )),
                      );
                    }),
                  )),
            ));
            FlutterError.onError = handler;
            for (var i = 0; i < 30; i++) {
              await frame(30);
            }
            if (readingHistory) {
              await tester.drag(
                  find.byType(CustomScrollView), const Offset(0, 900));
              for (var i = 0; i < 20; i++) {
                await frame(30);
              }
            }
            for (var cycle = 0; cycle < 2; cycle++) {
              if (mode == 'fling') {
                await tester.fling(
                    find.byType(CustomScrollView), const Offset(0, 200), 1600);
                await frame();
                expect(scroll.position.isScrollingNotifier.value, isTrue);
              }
              final originalPosition = scroll.position;
              final originalPixels = scroll.offset;
              final originalState =
                  tester.state(find.byKey(const Key('history')));
              expect(
                  tester
                      .widget<ChatHistoryVisibility>(
                          find.byType(ChatHistoryVisibility))
                      .visible,
                  isTrue);
              final recorder = ui.PictureRecorder();
              Canvas(recorder).drawColor(Colors.red, BlendMode.src);
              final picture = recorder.endRecording();
              final bitmap = picture.toImageSync(100, 100);
              picture.dispose();
              addTearDown(bitmap.dispose);
              global.saveScrollBeforeMediaPreview(conv);
              await frame();
              expect(scroll.position.isScrollingNotifier.value, isFalse);
              await tester.drag(
                  find.byType(CustomScrollView), const Offset(0, 160),
                  warnIfMissed:
                      false); // The preview lock deliberately absorbs this pointer.
              await frame(50);
              expect(scroll.offset, closeTo(originalPixels, .5),
                  reason:
                      'preview lock absorbs touches and stops an existing fling');
              var pageIndex = 0;
              final preview = pushMediaPreview<void>(
                context: chatContext,
                enableGestureBack: false,
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                restoreChatScrollConversationID: conv,
                child: ChatMediaGalleryScreen(
                    enableHero: false,
                    initialIndex: 0,
                    onGalleryIndexChanged: (value) => pageIndex = value,
                    items: [
                      for (var i = 0; i < 40; i++)
                        ChatMediaPreviewItem(
                            message: messages[i],
                            type: ChatMediaPreviewType.image,
                            heroTag: messages[i].msgID!,
                            imageProvider: _Bitmap(bitmap),
                            placeholderImageProvider: _Bitmap(bitmap)),
                    ]),
              );
              for (var i = 0; i < 10; i++) {
                await frame(30);
              }
              await tester.drag(
                  find.byType(ChatMediaGalleryScreen), const Offset(-320, 0));
              for (var i = 0; i < 20; i++) {
                await frame(30);
              }
              expect(pageIndex, 1,
                  reason: 'the real gallery must swipe to the second image');
              expect(
                  MediaPreviewHeroRegistry.instance
                      .isHidden(messages[1].msgID!),
                  isFalse,
                  reason:
                      'A no-Hero preview must leave source bubbles painted');
              var previewClosed = false;
              unawaited(preview.then((_) => previewClosed = true));
              if (closeMode == 'back') {
                navigator.currentState!.pop();
              } else if (closeMode == 'button') {
                await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
              } else {
                await tester.timedDrag(find.byType(ChatMediaGalleryScreen),
                    const Offset(0, 280), const Duration(milliseconds: 350));
              }
              // Also inspect the underlying list while slide-dismiss exposes it.
              for (var i = 0; !previewClosed && i < 60; i++) {
                await frame();
                expect(scroll.offset, closeTo(originalPixels, .5));
                expect(
                    MediaPreviewHeroRegistry.instance
                        .isHidden(messages[1].msgID!),
                    isFalse);
              }
              expect(previewClosed, isTrue);
              for (var i = 0; i < 12; i++) {
                await frame();
                expect(tester.state(find.byKey(const Key('history'))),
                    same(originalState));
                expect(
                    tester
                        .widget<ChatHistoryVisibility>(
                            find.byType(ChatHistoryVisibility))
                        .visible,
                    isTrue,
                    reason: 'return frame $i must not hide the message list');
                expect(scroll.offset, closeTo(originalPixels, .5),
                    reason: 'return frame $i');
                final visibleRows = tester
                    .elementList(find.textContaining('seq:'))
                    .where((element) {
                  final box = element.findRenderObject() as RenderBox;
                  return (box.localToGlobal(Offset.zero) & box.size)
                      .overlaps(const Rect.fromLTWH(0, 0, 400, 800));
                }).toList();
                expect(visibleRows, isNotEmpty,
                    reason: 'return frame $i must contain visible rows');
                for (final row in visibleRows) {
                  row.visitAncestorElements((element) {
                    final widget = element.widget;
                    if (widget is Opacity) {
                      expect(widget.opacity, 1,
                          reason:
                              'return frame $i must paint every visible bubble');
                    }
                    return true;
                  });
                }
              }
              expect(scroll.position, same(originalPosition),
                  reason:
                      'preview lock must retain the existing ScrollPosition');
              expect(global.shouldLockChatScrollForMediaPreview, isFalse);
              await tester.drag(
                  find.byType(CustomScrollView), const Offset(0, 100));
              await frame(100);
              expect(scroll.offset, greaterThan(originalPixels + 20),
                  reason:
                      'normal chat scrolling resumes after closing preview');
            }
            await tester.pumpWidget(const SizedBox.shrink());
            global.clearActiveChatScrollController(conversationID: conv);
            model.dispose();
            global.clearData();
            controller.dispose();
            scroll.dispose();
            await frame(2000);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    }
  }
}
