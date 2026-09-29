import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production feed has one snapshot renderer and SDK page source', () {
    final feed =
        File('lib/src/widgets/conversation_feed/conversation_feed_body.dart')
            .readAsStringSync();
    final tabs =
        File('lib/src/services/conversation_local/conversation_tab_store.dart')
            .readAsStringSync();
    expect(feed, contains('_buildFeedListView('));
    expect(feed, isNot(contains('_buildVirtualFeedListView')));
    expect(tabs, contains('getConversationListByFilter('));
    expect(tabs, isNot(contains('_loadCommittedViewPage')));
  });
}
