import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_scroll_anchor.dart';

void main() {
  test('trim and prepend preserve pixels with interleaved non-chat rows', () {
    final before = <String?>[null, 'a', 'b', null, 'c', 'd'];
    final anchor = ConversationScrollAnchor.capture(before,
        offset: 4 * 88 + 17, extent: 88)!;
    expect(anchor.id, 'c');
    expect(anchor.restore([null, 'c', 'd'], extent: 88), 88 + 17);
    expect(anchor.restore([null, 'a', 'b', null, 'c', 'd'], extent: 88),
        4 * 88 + 17);
  });
  test('removed anchor falls back to adjacent row without jumping to top', () {
    final anchor = ConversationScrollAnchor.capture(['a', 'b', 'c', 'd'],
        offset: 72 + 12, extent: 72)!;
    expect(anchor.restore(['a', 'c', 'd'], extent: 72), 12);
    expect(anchor.restore(['x'], extent: 72), isNull);
  });
}
