import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/ai_assistant_upload_mime.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_history_map.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_models.dart';

void main() {
  test('user history keeps fileIds for JWT download', () {
    const item = AiAssistantHistoryItem(
      id: 'u1',
      role: 'user',
      content: '这个是什么',
      capability: 'chat',
      analyzeType: '',
      analyzePeerUserId: '',
      analyzeGroupId: '',
      status: 'complete',
      compressed: false,
      sourceMessageCount: 0,
      createdAt: 0,
      imageUrl: '',
      fileIds: <String>['74e3a3ad-file'],
    );
    final message = AiAssistantHistoryMap.toMessage(item);
    expect(message.files, hasLength(1));
    expect(message.files.single.fileId, '74e3a3ad-file');
    expect(message.imageUrl, isNull);
  });

  test('assistant generated image uses imageUrl path not fileIds', () {
    const item = AiAssistantHistoryItem(
      id: '10',
      role: 'assistant',
      content: '',
      capability: 'image',
      analyzeType: '',
      analyzePeerUserId: '',
      analyzeGroupId: '',
      status: 'complete',
      compressed: false,
      sourceMessageCount: 0,
      createdAt: 0,
      imageUrl: '/ai-assistant/api/v1/chat/files/abc',
      fileIds: <String>[],
    );
    final message = AiAssistantHistoryMap.toMessage(item);
    expect(message.outputKind, AiAssistantOutputKind.image);
    expect(AiAssistantApi.fileIdFromUrl(message.imageUrl), 'abc');
    expect(message.files, isEmpty);
  });

  test('sniffMime reads jpeg png gif webp pdf headers', () {
    expect(
      AiAssistantUploadMime.sniffMime(
        Uint8List.fromList(const <int>[0xFF, 0xD8, 0xFF, 0x00]),
      ),
      'image/jpeg',
    );
    expect(
      AiAssistantUploadMime.isImageBytes(
        Uint8List.fromList(const <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]),
      ),
      isTrue,
    );
    expect(
      AiAssistantUploadMime.sniffMime(
        Uint8List.fromList(const <int>[0x25, 0x50, 0x44, 0x46]),
      ),
      'application/pdf',
    );
  });
}
