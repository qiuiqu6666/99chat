import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_store.dart';

ConversationFolder _folder(String id, int sortOrder, {String? name}) =>
    ConversationFolder(
      folderId: id,
      name: name ?? id.toUpperCase(),
      sortOrder: sortOrder,
      members: const <String, int?>{},
    );

void main() {
  test('foldersAfterReorder moves an item using Flutter onReorder indexes', () {
    final folders = <ConversationFolder>[
      _folder('a', 0),
      _folder('b', 1),
      _folder('c', 2),
    ];

    final movedRight = ConversationFolderStore.foldersAfterReorder(
      folders: folders,
      oldIndex: 0,
      newIndex: 2,
    );
    expect(movedRight.map((f) => f.folderId).toList(), <String>['b', 'a', 'c']);
    expect(movedRight.map((f) => f.sortOrder).toList(), <int>[0, 1, 2]);

    final movedLeft = ConversationFolderStore.foldersAfterReorder(
      folders: folders,
      oldIndex: 2,
      newIndex: 0,
    );
    expect(movedLeft.map((f) => f.folderId).toList(), <String>['c', 'a', 'b']);
    expect(movedLeft.map((f) => f.sortOrder).toList(), <int>[0, 1, 2]);
  });

  test('foldersAfterReorder no-ops when the drop lands on the same slot', () {
    final folders = <ConversationFolder>[
      _folder('a', 0),
      _folder('b', 1),
    ];
    final same = ConversationFolderStore.foldersAfterReorder(
      folders: folders,
      oldIndex: 1,
      newIndex: 2,
    );
    expect(same.map((f) => f.folderId).toList(), <String>['a', 'b']);
    expect(same.map((f) => f.sortOrder).toList(), <int>[0, 1]);
  });

  test('resolveFolderBarDisplay keeps local while parent still has old order',
      () {
    final local = <ConversationFolder>[
      _folder('b', 0),
      _folder('a', 1),
      _folder('c', 2),
    ];
    final parentOld = <ConversationFolder>[
      _folder('a', 0),
      _folder('b', 1),
      _folder('c', 2),
    ];
    final pending = <String>['b', 'a', 'c'];

    final resolved = ConversationFolderStore.resolveFolderBarDisplay(
      local: local,
      parent: parentOld,
      pendingReorderIds: pending,
    );

    expect(
      resolved.folders.map((f) => f.folderId).toList(),
      <String>['b', 'a', 'c'],
    );
    expect(resolved.pendingReorderIds, pending);
  });

  test('resolveFolderBarDisplay adopts parent when it matches pending', () {
    final local = <ConversationFolder>[
      _folder('b', 0),
      _folder('a', 1),
      _folder('c', 2),
    ];
    final parentNew = <ConversationFolder>[
      _folder('b', 0, name: 'B2'),
      _folder('a', 1, name: 'A2'),
      _folder('c', 2, name: 'C2'),
    ];
    final pending = <String>['b', 'a', 'c'];

    final resolved = ConversationFolderStore.resolveFolderBarDisplay(
      local: local,
      parent: parentNew,
      pendingReorderIds: pending,
    );

    expect(
      resolved.folders.map((f) => f.folderId).toList(),
      <String>['b', 'a', 'c'],
    );
    expect(resolved.folders.map((f) => f.name).toList(), <String>['B2', 'A2', 'C2']);
    expect(resolved.pendingReorderIds, isNull);
  });

  test('resolveFolderBarDisplay adopts parent on external membership change',
      () {
    final local = <ConversationFolder>[
      _folder('b', 0),
      _folder('a', 1),
    ];
    final parentExternal = <ConversationFolder>[
      _folder('a', 0),
      _folder('b', 1),
      _folder('d', 2),
    ];
    final pending = <String>['b', 'a'];

    final resolved = ConversationFolderStore.resolveFolderBarDisplay(
      local: local,
      parent: parentExternal,
      pendingReorderIds: pending,
    );

    expect(
      resolved.folders.map((f) => f.folderId).toList(),
      <String>['a', 'b', 'd'],
    );
    expect(resolved.pendingReorderIds, isNull);
  });

  test('resolveFolderBarDisplay without pending adopts parent order change',
      () {
    final local = <ConversationFolder>[
      _folder('a', 0),
      _folder('b', 1),
    ];
    final parent = <ConversationFolder>[
      _folder('b', 0),
      _folder('a', 1),
    ];

    final resolved = ConversationFolderStore.resolveFolderBarDisplay(
      local: local,
      parent: parent,
      pendingReorderIds: null,
    );

    expect(
      resolved.folders.map((f) => f.folderId).toList(),
      <String>['b', 'a'],
    );
    expect(resolved.pendingReorderIds, isNull);
  });
}
