import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';

RelationshipFriendEntry _friend({
  required String id,
  required String name,
  String face = '',
  String remark = '',
  String tag = 'A',
}) {
  return RelationshipFriendEntry(
    userId: id,
    displayName: name,
    faceUrl: face,
    remark: remark,
    sortKey: ImSdkRelationshipDirectory.sortKeyFor(
      id: id,
      displayName: name,
      azTag: tag,
    ),
  );
}

void main() {
  test('capture replay keeps listener delete/add over snapshot ABC', () {
    final directory = ImSdkRelationshipDirectory();
    final captureId = directory.beginFriendCapture();
    directory.applyFriendRemoves(const <String>['B']);
    directory.applyFriendAdds(<RelationshipFriendEntry>[
      _friend(id: 'D', name: 'Dee', tag: 'D'),
    ]);

    final changes = <RelationshipDirectoryChange>[];
    directory.addListener(changes.add);
    directory.applyFriendSnapshot(
      captureId: captureId,
      entries: <RelationshipFriendEntry>[
        _friend(id: 'A', name: 'Ann', tag: 'A'),
        _friend(id: 'B', name: 'Ben', tag: 'B'),
        _friend(id: 'C', name: 'Cara', tag: 'C'),
      ],
      orderedIds: const <String>['A', 'B', 'C'],
    );

    expect(directory.friendOrderedIds, <String>['A', 'C', 'D']);
    expect(directory.friend('B'), isNull);
    expect(directory.friend('D')?.displayName, 'Dee');
    expect(changes, hasLength(1));
    expect(changes.single.snapshotCompleted, isTrue);
    expect(changes.single.addedIds, isEmpty);
    expect(changes.single.removedIds, isEmpty);
  });

  test('reconcile snapshot vs old truth does not depend on projection', () {
    final directory = ImSdkRelationshipDirectory();
    final first = directory.beginFriendCapture();
    directory.applyFriendSnapshot(
      captureId: first,
      entries: <RelationshipFriendEntry>[
        _friend(id: 'A', name: 'Ann', tag: 'A'),
        _friend(id: 'B', name: 'Ben', tag: 'B'),
        _friend(id: 'C', name: 'Cara', tag: 'C'),
      ],
      orderedIds: const <String>['A', 'B', 'C'],
    );

    final reconcile = directory.beginFriendCapture();
    final changes = <RelationshipDirectoryChange>[];
    directory.addListener(changes.add);
    directory.applyFriendRemoves(const <String>['B']);
    directory.applyFriendSnapshot(
      captureId: reconcile,
      entries: <RelationshipFriendEntry>[
        _friend(id: 'A', name: 'Ann', tag: 'A'),
        _friend(id: 'B', name: 'Ben', tag: 'B'),
        _friend(id: 'C', name: 'Cara', tag: 'C'),
      ],
      orderedIds: const <String>['A', 'B', 'C'],
    );

    expect(directory.friend('B'), isNull);
    expect(directory.friendOrderedIds, <String>['A', 'C']);
    expect(changes.first.removedIds, <String>['B']);
    expect(
      changes.any((change) => change.addedIds.contains('B')),
      isFalse,
    );
  });

  test('sortKeyChanged moves one id without reshuffling the rest', () {
    final directory = ImSdkRelationshipDirectory();
    final captureId = directory.beginFriendCapture();
    directory.applyFriendSnapshot(
      captureId: captureId,
      entries: <RelationshipFriendEntry>[
        _friend(id: 'a', name: 'Ann', tag: 'A'),
        _friend(id: 'z', name: 'Zhang', tag: 'Z'),
        _friend(id: 'm', name: 'Mia', tag: 'M'),
      ],
      orderedIds: const <String>['a', 'm', 'z'],
    );

    final changes = <RelationshipDirectoryChange>[];
    directory.addListener(changes.add);
    directory.applyFriendChanges(<RelationshipFriendEntry>[
      _friend(id: 'z', name: 'A-san', tag: 'A'),
    ]);

    expect(directory.friendOrderedIds, <String>['z', 'a', 'm']);
    expect(changes.single.sortKeyChangedIds, <String>['z']);
    expect(changes.single.metadataChangedIds, isEmpty);
    expect(changes.single.addedIds, isEmpty);
  });

  test('metadata change does not move ordered ids', () {
    final directory = ImSdkRelationshipDirectory();
    final captureId = directory.beginFriendCapture();
    directory.applyFriendSnapshot(
      captureId: captureId,
      entries: <RelationshipFriendEntry>[
        _friend(id: 'a', name: 'Ann', tag: 'A', face: '1'),
        _friend(id: 'b', name: 'Ben', tag: 'B', face: '2'),
      ],
      orderedIds: const <String>['a', 'b'],
    );
    final changes = <RelationshipDirectoryChange>[];
    directory.addListener(changes.add);
    directory.applyFriendChanges(<RelationshipFriendEntry>[
      _friend(id: 'b', name: 'Ben', tag: 'B', face: '2-new'),
    ]);
    expect(directory.friendOrderedIds, <String>['a', 'b']);
    expect(changes.single.metadataChangedIds, <String>['b']);
    expect(changes.single.sortKeyChangedIds, isEmpty);
  });

  test('toV2TimFriendInfo does not put userId into nickName', () {
    final entry = RelationshipFriendEntry(
      userId: 'b1yg649fnr',
      displayName: 'b1yg649fnr',
      faceUrl: '',
      remark: '',
      nickname: '',
      sortKey: ImSdkRelationshipDirectory.sortKeyFor(
        id: 'b1yg649fnr',
        displayName: 'b1yg649fnr',
        azTag: 'B',
      ),
    );
    final info = entry.toV2TimFriendInfo();
    expect(info.friendRemark, isNull);
    expect(info.userProfile?.nickName, isNull);
    expect(info.userProfile?.faceUrl, isNull);
  });

  test('group entry keeps memberCount and role for list subtitle', () {
    final entry = RelationshipGroupEntry(
      groupId: 'g1',
      groupName: 'Alpha',
      faceUrl: '',
      groupType: 'Work',
      memberCount: 42,
      role: 400,
      sortKey: ImSdkRelationshipDirectory.sortKeyFor(
        id: 'g1',
        displayName: 'Alpha',
        azTag: 'A',
      ),
    );
    final info = entry.toV2TimGroupInfo();
    expect(info.memberCount, 42);
    expect(info.role, 400);
  });
}
