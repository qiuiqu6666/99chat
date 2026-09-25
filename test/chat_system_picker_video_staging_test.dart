import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Test fake for the existing path_provider plugin interface.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

class _PickerPaths extends PathProviderPlatform {
  _PickerPaths(this.cachePath, this.supportPath);

  final String cachePath;
  final String supportPath;

  @override
  Future<String?> getTemporaryPath() async => cachePath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory cache;
  late PathProviderPlatform original;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chat_picker_stage_');
    cache = await Directory('${root.path}/picker_cache').create();
    final support = await Directory('${root.path}/support').create();
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PickerPaths(cache.path, support.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = original;
    await root.delete(recursive: true);
  });

  test('moves a system picker cache video into durable staging', () async {
    final source = File('${cache.path}/picked.mov');
    final bytes = List<int>.generate(4096, (index) => index % 256);
    await source.writeAsBytes(bytes);

    final stagedPath = await stageSystemPickerVideoForChatSend(source.path);

    expect(stagedPath, isNotNull);
    expect(isStagedChatVideoSendPath(stagedPath!), isTrue);
    expect(await source.exists(), isFalse);
    expect(await File(stagedPath).readAsBytes(), bytes);
  });

  test('keeps an external source and copies it into durable staging', () async {
    final source = File('${root.path}/external.mov');
    await source.writeAsBytes([1, 2, 3, 4]);

    final stagedPath = await stageSystemPickerVideoForChatSend(source.path);

    expect(stagedPath, isNotNull);
    expect(await source.exists(), isTrue);
    expect(await File(stagedPath!).readAsBytes(), [1, 2, 3, 4]);
  });
}
