import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_scroll_physics.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  test('a historical window cannot become bottom before SDK continuity', () {
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = '@TGS#sdk_scroll_continuity';
    final model = TUIChatSeparateViewModel()..conversationID = conv;
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    model.haveMoreLatestData = true;
    expect(global.memoryWindowMissingNewer(conv), isTrue);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    expect(global.getMessageListPosition(conv),
        HistoryMessagePosition.notShowLatest);

    // Reaching the last SDK page changes coverage, not where the reader is.
    model.haveMoreLatestData = false;
    expect(global.memoryWindowMissingNewer(conv), isFalse);
    expect(global.getMessageListPosition(conv),
        HistoryMessagePosition.notShowLatest);
    model.dispose();
  });

  for (final split in [false, true]) {
    testWidgets(
        'both paging directions preserve the visible row (split=$split)',
        (tester) async {
      final controller = ScrollController(initialScrollOffset: 120);
      final rows = ValueNotifier(List.generate(30, (i) => 30 - i));
      final newerRows = ValueNotifier(<int>[]);
      final centerKey = GlobalKey();
      var loadingNewer = false;
      Widget row(int id) =>
          SizedBox(key: ValueKey(id), height: 60, child: Text('message $id'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([rows, newerRows]),
            builder: (_, __) => CustomScrollView(
              controller: controller,
              reverse: true,
              center: split ? centerKey : null,
              physics: HistoryPaginationScrollPhysics(
                shouldCompensate: () => !loadingNewer,
                shouldPreserveNewestInsertExtent: () => loadingNewer,
              ),
              slivers: [
                if (split)
                  SliverList.list(children: newerRows.value.map(row).toList()),
                SliverList(
                  key: centerKey,
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => row(rows.value[index]),
                    childCount: rows.value.length,
                    findChildIndexCallback: (key) {
                      final index =
                          rows.value.indexOf((key as ValueKey<int>).value);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      final target = find.text('message 25');
      final before = tester.getCenter(target).dy;
      rows.value = [...rows.value, for (var n = 0; n > -20; n--) n];
      await tester.pump();
      expect(tester.getCenter(target).dy, closeTo(before, 1));
      // The next direction is requested by a new scroll gesture. Let lazy
      // slivers update their estimates before admitting that request.
      controller.jumpTo(controller.offset + 60);
      await tester.pump();
      controller.jumpTo(controller.offset - 60);
      await tester.pump();
      expect(tester.getCenter(target).dy, closeTo(before, 1));
      loadingNewer = true;
      if (split) {
        newerRows.value = List.generate(20, (i) => 31 + i);
      } else {
        rows.value = [for (var n = 50; n > 30; n--) n, ...rows.value];
      }
      await tester.pump();
      expect(tester.getCenter(target).dy, closeTo(before, 1));
      expect(controller.offset, isNot(controller.position.minScrollExtent));
      loadingNewer = false;
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      rows.dispose();
      newerRows.dispose();
    });
  }

  testWidgets(
      'center-front inserts keep the visible row without newest-insert physics',
      (tester) async {
    final controller = ScrollController(initialScrollOffset: 120);
    final rows = ValueNotifier(List.generate(30, (i) => 30 - i));
    final newerRows = ValueNotifier(<int>[]);
    final centerKey = GlobalKey();
    Widget row(int id) =>
        SizedBox(key: ValueKey(id), height: 60, child: Text('message $id'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([rows, newerRows]),
          builder: (_, __) => CustomScrollView(
            controller: controller,
            reverse: true,
            center: centerKey,
            physics: HistoryPaginationScrollPhysics(
              shouldCompensate: () => false,
              shouldPreserveNewestInsertExtent: () => false,
            ),
            slivers: [
              SliverList.list(children: newerRows.value.map(row).toList()),
              SliverList(
                key: centerKey,
                delegate: SliverChildBuilderDelegate(
                  (_, index) => row(rows.value[index]),
                  childCount: rows.value.length,
                  findChildIndexCallback: (key) {
                    final index =
                        rows.value.indexOf((key as ValueKey<int>).value);
                    return index < 0 ? null : index;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    final target = find.text('message 25');
    final before = tester.getCenter(target).dy;
    newerRows.value = List.generate(8, (i) => 31 + i);
    await tester.pump();
    expect(tester.getCenter(target).dy, closeTo(before, 1));
    expect(controller.offset, isNot(controller.position.minScrollExtent));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    rows.dispose();
    newerRows.dispose();
  });

  test('Community pagination uses the same SDK cursor lane as ordinary groups',
      () {
    const base = 'third_party/tencent_cloud_chat_uikit/lib/';
    final runner = File('${base}business_logic/separate_models/'
            'tui_chat_history_pagination_load.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(runner, isNot(contains('allowArchiveFallback')));
    // Fallback cursor, source and request-count behavior is covered by
    // history_filtered_sdk_page_regression_test; keep only lane boundaries here.
    expect(runner, isNot(contains('_usesCommunityBackendOlderHistory')));
    expect(runner, isNot(contains('_loadCommunityOlderHistory')));
    expect(runner, contains('final cached = await _tryLoadHistoryWindowPage'));
    expect(runner, contains('final isPaginatedLoad = sdkPagination'));
    final c2c = TUIChatSeparateViewModel()..conversationType = ConvType.c2c;
    final group = TUIChatSeparateViewModel()..conversationType = ConvType.group;
    final unknown = TUIChatSeparateViewModel()
      ..conversationType = ConvType.none;
    expect(c2c.usesOfficialSdkHistory, isTrue);
    expect(group.usesOfficialSdkHistory, isTrue);
    expect(unknown.usesOfficialSdkHistory, isFalse);
    c2c.dispose();
    group.dispose();
    unknown.dispose();
    final list = File('${base}ui/views/TIMUIKitChat/TIMUIKItMessageList/'
            'tim_uikit_chat_history_message_list.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final page = list.substring(list.indexOf('  Future<void> _loadLatest('),
        list.indexOf('  bool _renderObjectNeedsLayout'));
    expect(page, contains('lastMsg: anchor.message'));
    expect(page, isNot(contains('reloadNewestMessageWindow')));
    expect(page, isNot(contains('drainRound')));
    expect(page, isNot(contains('minScrollExtent')));
    expect(list, isNot(contains('_shouldAutoLoadLatest')));
    expect('_scheduleLoadLatest('.allMatches(list).length, 2);
    final reading = list.substring(list.indexOf('  bool _isReadingHistory('),
        list.indexOf('  Map<String, Object?> _readingHistoryScrollSnapshot'));
    expect(reading, contains('widget.model.haveMoreLatestData'));
    expect(
        reading, contains('globalModel.isSearchJumpPending(conversationID)'));
    expect(reading, contains('HistoryMessagePosition.notShowLatest'));
    final cursor = list.substring(
        list.indexOf('  _PreviousLoadAnchor? _anchorForLatestLoad('),
        list.indexOf('  bool _isSearchJumpHistoryMode'));
    expect(
        cursor,
        contains(
            'TUIChatGlobalModel.compareMessagesChronological(item, picked)'));
    expect(cursor, isNot(contains('_messageSortTime')));
  });
}
