import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';

void main() {
  test(
    'ordinary group archive fetch is disabled at the provider boundary',
    () async {
      var fetcherCalled = false;
      ArchiveHistoryProvider.register((request) async {
        fetcherCalled = true;
        return ArchiveHistoryResult.empty;
      });

      expect(ArchiveHistoryProvider.isAvailable, isTrue);
      final result = await ArchiveHistoryProvider.fetchOlder(
        const ArchiveHistoryRequest(
          isGroup: true,
          conversationID: '@TGS#ordinary',
          count: 40,
        ),
      );

      expect(result.messages, isEmpty);
      expect(result.hasMore, isFalse);
      expect(fetcherCalled, isFalse);
      ArchiveHistoryProvider.register(null);
    },
  );

  test('Community archive fetch reaches the registered provider', () async {
    var fetcherCalled = false;
    ArchiveHistoryProvider.register((request) async {
      fetcherCalled = true;
      return ArchiveHistoryResult.empty;
    });

    await ArchiveHistoryProvider.fetchOlder(
      const ArchiveHistoryRequest(
        isGroup: true,
        isCommunity: true,
        conversationID: '@TGS#_mcCommunity',
        count: 40,
      ),
    );

    expect(fetcherCalled, isTrue);
    ArchiveHistoryProvider.register(null);
  });
}
