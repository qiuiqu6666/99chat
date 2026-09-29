import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_file_kind.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_models.dart';

void main() {
  test('Report.PDF maps to pdf badge', () {
    expect(AiAssistantFileKinds.fromName('Report.PDF'), AiAssistantFileKind.pdf);
    expect(AiAssistantFileKinds.badge(AiAssistantFileKind.pdf), 'PDF');
  });

  test('office extensions map to word excel ppt', () {
    expect(AiAssistantFileKinds.fromName('a.Docx'), AiAssistantFileKind.word);
    expect(AiAssistantFileKinds.fromName('b.XLSX'), AiAssistantFileKind.excel);
    expect(AiAssistantFileKinds.fromName('c.Pptx'), AiAssistantFileKind.ppt);
  });

  test('media and archive extensions', () {
    expect(AiAssistantFileKinds.fromName('d.PNG'), AiAssistantFileKind.image);
    expect(AiAssistantFileKinds.fromName('e.MP4'), AiAssistantFileKind.video);
    expect(AiAssistantFileKinds.fromName('f.MP3'), AiAssistantFileKind.audio);
    expect(AiAssistantFileKinds.fromName('g.ZIP'), AiAssistantFileKind.archive);
    expect(AiAssistantFileKinds.fromName('h.TXT'), AiAssistantFileKind.text);
  });

  test('missing extension is unknown FILE', () {
    expect(AiAssistantFileKinds.fromName('noext'), AiAssistantFileKind.unknown);
    expect(AiAssistantFileKinds.fromName(''), AiAssistantFileKind.unknown);
    expect(AiAssistantFileKinds.fromName('.'), AiAssistantFileKind.unknown);
    expect(AiAssistantFileKinds.badge(AiAssistantFileKind.unknown), 'FILE');
  });

  test('compound name uses last segment', () {
    expect(
      AiAssistantFileKinds.fromName('a.b.c.webp'),
      AiAssistantFileKind.image,
    );
  });
}
