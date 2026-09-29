import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/picker_recovery_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/picker_recovery');
  late Directory root;
  late Directory sources;
  late PickerRecoveryCoordinator coordinator;
  var owner = const PickerRecoveryOwner('A', 1);
  Map<String, dynamic> native = {};
  String? operation;
  int acks = 0;
  PickerRecoveryCoordinator create() =>
      PickerRecoveryCoordinator(channel: channel)
        ..configure(directory: root, owner: () async => owner);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('recovery_journal_');
    sources = await Directory.systemTemp.createTemp('recovery_source_');
    owner = const PickerRecoveryOwner('A', 1);
    native = {};
    operation = null;
    acks = 0;
    coordinator = create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'begin') {
        operation = call.arguments['operationId'] as String;
        expect(
            await File('${root.path}/$operation/intent.json').exists(), isTrue);
        return true;
      }
      if (call.method == 'peek') return native;
      if (call.method == 'ack') {
        expect(call.arguments['token'], native['token']);
        final draft = File('${root.path}/${native['operationId']}/draft.json');
        expect(await draft.exists(), isTrue);
        final json = jsonDecode(await draft.readAsString());
        for (final path in json['paths']) {
          expect(await File(path).exists(), isTrue);
        }
        acks++;
        native = {};
        return true;
      }
      return true;
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
    await sources.delete(recursive: true);
  });
  Future<List<XFile>> selected() async {
    final paths = <String>[];
    for (final name in ['second.png', 'first.mov']) {
      final file = await File('${sources.path}/$name').writeAsString(name);
      paths.add(file.path);
    }
    native = {'operationId': operation, 'token': 'result-1', 'paths': paths};
    return paths.map(XFile.new).toList();
  }

  test(
      'intent precedes launch; copy and journal precede ack; successful handoff is consumed',
      () async {
    final files = (await coordinator.pick(
        entry: 'chat.gallery', destination: 'c2c:alice', launch: selected))!;
    expect(acks, 1);
    expect(await files[0].readAsString(), 'second.png');
    expect(await files[1].readAsString(), 'first.mov');
    expect(await coordinator.drafts(),
        isEmpty); // live handoff is not a recovery prompt
    await coordinator.completePaths(files);
    expect(await create().drafts(), isEmpty);
  });
  test(
      'restart before handoff recovers same order once; different account sees nothing',
      () async {
    await coordinator.pick(
        entry: 'chat.gallery', destination: 'c2c:alice', launch: selected);
    coordinator = create();
    owner = const PickerRecoveryOwner('B', 2);
    expect(await coordinator.drafts(), isEmpty);
    owner = const PickerRecoveryOwner('A', 3);
    final drafts = await coordinator.drafts(destination: 'c2c:alice');
    expect(drafts, hasLength(1));
    expect(await coordinator.claim(drafts.single), isTrue);
    expect(await coordinator.claim(drafts.single), isFalse);
    expect(await create().drafts(), isEmpty);
    expect(
        (await create().drafts(includeClaimed: true)).single.claimed, isTrue);
  });
  test(
      'failure to copy never acknowledges native cache, retry succeeds after restart',
      () async {
    await expectLater(
        coordinator.pick(
            entry: 'chat.gallery',
            launch: () async {
              final files = await selected();
              await Directory('${root.path}/$operation/000.png.pending')
                  .create();
              return files;
            }),
        throwsA(isA<FileSystemException>()));
    expect(acks, 0);
    expect(native, isNotEmpty);
    await Directory('${root.path}/$operation/000.png.pending').delete();
    coordinator = create();
    await Future.wait([coordinator.recover(), coordinator.recover()]);
    expect(acks, 1);
    expect(await coordinator.drafts(), hasLength(1));
  });
  test(
      'pre-login picker works but recovered files are never assigned to next account',
      () async {
    owner = const PickerRecoveryOwner('', 1);
    await coordinator.pick(entry: 'registration.avatar', launch: selected);
    owner = const PickerRecoveryOwner('B', 2);
    expect(await create().drafts(), isEmpty);
  });
  test(
      'missing native source becomes a visible error draft instead of blocking every future picker',
      () async {
    await expectLater(coordinator.pick(
        entry: 'chat.gallery',
        launch: () async {
          final selectedFiles = await selected();
          await File(selectedFiles.first.path).delete();
          return selectedFiles;
        }), throwsStateError);
    expect(acks, 1);
    final restored = (await create().drafts()).single;
    expect(restored.error, 'source_files_missing:1');
    expect(await restored.files.single.readAsString(), 'first.mov');
  });
  test(
      'switching account while native picker is open preserves draft without returning files',
      () async {
    await expectLater(
        coordinator.pick(
            entry: 'chat.gallery',
            launch: () async {
              final files = await selected();
              owner = const PickerRecoveryOwner('B', 2);
              return files;
            }),
        throwsStateError);
    expect(await create().drafts(), isEmpty);
    owner = const PickerRecoveryOwner('A', 3);
    expect(await create().drafts(), hasLength(1));
  });
}
