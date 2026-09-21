import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_media_staging.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';

void main() {
  late Directory sandbox;
  late Directory support;
  late Directory source;
  late OutgoingMediaStager stager;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('im_media_staging_');
    support = Directory(p.join(sandbox.path, 'support'));
    source = Directory(p.join(sandbox.path, 'source'));
    await support.create(recursive: true);
    await source.create(recursive: true);
    stager = OutgoingMediaStager(
      supportDirectoryProvider: () async => support,
    );
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  test('copies every SDK media path to one durable operation directory',
      () async {
    final image = await _file(source, 'picked.jpg', 'image');
    final video = await _file(source, 'picked.mp4', 'video');
    final snapshot = File(p.join(source.path, 'snapshot.jpg'));
    await snapshot.writeAsBytes([0xff, 0xd8, 0xff, ...List.filled(256, 0), 0xff, 0xd9]);
    final sound = await _file(source, 'picked.m4a', 'sound');
    final document = await _file(source, 'picked.pdf', 'file');
    final message = _message()
      ..imageElem = V2TimImageElem(path: image.path)
      ..videoElem = V2TimVideoElem(
        videoPath: video.path,
        snapshotPath: snapshot.path,
      )
      ..soundElem = V2TimSoundElem(path: sound.path)
      ..fileElem = V2TimFileElem(path: document.path);

    final result = await stager.stageMessage(
      message: message,
      operationId: 'owner:conversation:message',
    );

    expect(result.succeeded, isTrue);
    expect(result.hadLocalMedia, isTrue);
    expect(result.rootPath, isNotNull);
    final root = result.rootPath!;
    expect(p.isWithin(p.join(support.path, 'im_outbox_media'), root), isTrue);
    for (final path in <String?>[
      message.imageElem?.path,
      message.videoElem?.videoPath,
      message.videoElem?.snapshotPath,
      message.soundElem?.path,
      message.fileElem?.path,
    ]) {
      expect(p.isWithin(root, path!), isTrue);
      expect(File(path).existsSync(), isTrue);
    }

    await stager.cleanup(root);
    expect(Directory(root).existsSync(), isFalse);
    expect(image.existsSync(), isTrue);
  });

  test('missing media blocks staging without mutating a valid source path',
      () async {
    final image = await _file(source, 'picked.jpg', 'image');
    final message = _message()
      ..imageElem = V2TimImageElem(path: image.path)
      ..fileElem = V2TimFileElem(path: p.join(source.path, 'missing.pdf'));

    final result = await stager.stageMessage(
      message: message,
      operationId: 'missing-media',
    );

    expect(result.shouldBlock, isTrue);
    expect(message.imageElem?.path, image.path);
    expect(
      Directory(p.join(support.path, 'im_outbox_media', 'missing-media'))
          .existsSync(),
      isFalse,
    );
  });

  test('cleanup ignores paths outside the owned media root', () async {
    final outside = await _file(source, 'keep.txt', 'keep');
    await stager.cleanup(source.path);
    await stager.cleanup(outside.path);
    expect(outside.existsSync(), isTrue);
  });
}

Future<File> _file(Directory directory, String name, String contents) async {
  final file = File(p.join(directory.path, name));
  await file.writeAsString(contents);
  return file;
}

V2TimMessage _message() {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_server_time': 1700000000,
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
  return message;
}
