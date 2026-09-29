import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';

class _Friend extends RelationshipFriendEntry {
  _Friend(String id, {String face = '', String? key})
      : super(
            userId: id,
            displayName: id,
            faceUrl: face,
            remark: '',
            sortKey: key ?? id);
  static int comparisons = 0;
  @override
  String get fingerprint {
    comparisons++;
    return super.fingerprint;
  }
}

class _Group extends RelationshipGroupEntry {
  _Group(String id, {int members = 1, String? key})
      : super(
            groupId: id,
            groupName: id,
            faceUrl: '',
            groupType: 'Work',
            sortKey: key ?? id,
            memberCount: members);
  static int comparisons = 0;
  @override
  String get fingerprint {
    comparisons++;
    return super.fingerprint;
  }
}

void main() {
  for (final size in [1000, 5000, 10000]) {
    test('$size entries: 200 updates compare only touched friends and groups',
        () {
      final directory = ImSdkRelationshipDirectory();
      final ids =
          List.generate(size, (i) => 'id${i.toString().padLeft(5, '0')}');
      directory.applyFriendSnapshot(
          captureId: directory.beginFriendCapture(),
          entries: ids.map((id) => _Friend(id)).toList(),
          orderedIds: ids);
      directory.applyGroupSnapshot(
          captureId: directory.beginGroupCapture(),
          entries: ids.map((id) => _Group(id)).toList(),
          orderedIds: ids);
      final changes = <RelationshipDirectoryChange>[];
      directory.addListener(changes.add);
      _Friend.comparisons = 0;
      _Group.comparisons = 0;
      directory.applyFriendChanges(
          ids.take(200).map((id) => _Friend(id, face: 'new')).toList());
      directory.applyGroupChanges(
          ids.take(200).map((id) => _Group(id, members: 2)).toList());
      expect(_Friend.comparisons, 400);
      expect(_Group.comparisons, 400);
      expect(changes, hasLength(2));
      for (final change in changes) {
        expect(change.metadataChangedIds, ids.take(200));
        expect(change.sortKeyChangedIds, isEmpty);
        expect(change.addedIds, isEmpty);
        expect(change.removedIds, isEmpty);
      }
      expect(directory.friendOrderedIds, ids);
      expect(directory.groupOrderedIds, ids);
      directory.applyFriendChanges(
          ids.take(200).map((id) => _Friend(id, face: 'new')).toList());
      expect(changes, hasLength(2)); // duplicate events do not re-notify
    });
  }

  test(
      'batched duplicate IDs, sort changes, removals and new IDs publish final truth',
      () {
    final directory = ImSdkRelationshipDirectory();
    directory.applyFriendSnapshot(
        captureId: directory.beginFriendCapture(),
        entries: [_Friend('a'), _Friend('b'), _Friend('c')]);
    final changes = <RelationshipDirectoryChange>[];
    directory.addListener(changes.add);
    directory.applyFriendChanges([
      _Friend('b', face: 'intermediate'),
      _Friend('b', face: 'final', key: '0'),
      _Friend('d')
    ]);
    expect(directory.friendOrderedIds, ['b', 'a', 'c', 'd']);
    expect(directory.friend('b')?.faceUrl, 'final');
    expect(changes.single.sortKeyChangedIds, ['b']);
    expect(changes.single.addedIds, ['d']);
    directory.applyFriendRemoves(['a', 'a', 'absent']);
    expect(changes.last.removedIds, ['a']);
    expect(directory.friendOrderedIds, ['b', 'c', 'd']);
  });
}
