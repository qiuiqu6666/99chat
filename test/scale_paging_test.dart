import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/ledger_page_progress.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_friends_lookup_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_sync_collector.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_member_loader.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_member.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'ledger resume is isolated and invalidated when the head or page size changes',
      () async {
    SharedPreferences.setMockInitialValues({});
    await LedgerPageProgress.save(
        owner: 'a', scope: 'all', size: 100, head: 'head1', next: 20);
    expect(
        await LedgerPageProgress.read(
            owner: 'a', scope: 'all', size: 100, head: 'head1'),
        20);
    expect(
        await LedgerPageProgress.read(
            owner: 'b', scope: 'all', size: 100, head: 'head1'),
        1);
    expect(
        await LedgerPageProgress.read(
            owner: 'a', scope: 'all', size: 100, head: 'head2'),
        1);
    expect(
        await LedgerPageProgress.read(
            owner: 'a', scope: 'all', size: 50, head: 'head1'),
        1);
    await LedgerPageProgress.clear('a');
    expect(
        await LedgerPageProgress.read(
            owner: 'a', scope: 'all', size: 100, head: 'head1'),
        1);
  });
  test('10k group members consume only the visit budget and resume next cursor',
      () async {
    final cursors = <String>[];
    final loader = GroupLiveMemberLoader((cursor) async {
      cursors.add(cursor);
      final start = int.parse(cursor);
      return GroupLiveMemberPage(
          List.generate(
              100,
              (i) => RedPacketMember(
                  userId: '${start + i}', name: 'Member ${start + i}')),
          '${start + 100}');
    });
    await loader.load();
    expect(cursors, ['0', '100']);
    expect(loader.members.length, 200);
    expect(loader.complete, isFalse);
    await loader.load();
    expect(cursors, ['0', '100', '200', '300']);
    loader.dispose();
  });
  test(
      'contacts publish the first batch and cancellation stops remaining requests',
      () async {
    var cancelled = false;
    var calls = 0;
    final contacts = List.generate(
        10000,
        (i) => LocalContactRecord(
            localContactId: '$i',
            displayName: 'Member $i',
            phones: ['138${i.toString().padLeft(8, '0')}'],
            fingerprint: '$i'));
    final result = await ContactFriendsLookupService.matchEntries(contacts,
        matchBatch: (_) async {
          calls++;
          return {};
        },
        onPartial: (entries) {
          expect(entries.length, 500);
          cancelled = true;
        },
        isCancelled: () => cancelled);
    expect(calls, 1);
    expect(result.length, 500);
  });
}
