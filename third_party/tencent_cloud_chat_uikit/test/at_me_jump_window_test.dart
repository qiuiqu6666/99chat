import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/at_me_jump.dart';

void main() {
  group('AtMeJump.parseTargetSeq', () {
    test('parses plain and trimmed seq', () {
      expect(AtMeJump.parseTargetSeq('1081'), 1081);
      expect(AtMeJump.parseTargetSeq(' 42 '), 42);
      expect(AtMeJump.canonicalSeqString(' 0042 '), '42');
    });

    test('rejects empty and non-int', () {
      expect(AtMeJump.parseTargetSeq(null), isNull);
      expect(AtMeJump.parseTargetSeq(''), isNull);
      expect(AtMeJump.parseTargetSeq('   '), isNull);
      expect(AtMeJump.parseTargetSeq('abc'), isNull);
      expect(AtMeJump.canonicalSeqString('nope'), isNull);
    });
  });

  group('AtMeJump.pickVisibleIndex', () {
    test('hits exact seq', () {
      expect(AtMeJump.pickVisibleIndex(const [null, 40, 41, 42], 41), 2);
    });

    test('picks nearest positive seq when exact is missing', () {
      expect(AtMeJump.pickVisibleIndex(const [10, 20, 50], 41), 2);
      expect(AtMeJump.pickVisibleIndex(const [10, 20, 50], 11), 0);
    });

    test('returns null when every slot is empty', () {
      expect(AtMeJump.pickVisibleIndex(const [null, null], 41), isNull);
      expect(AtMeJump.pickVisibleIndex(const <int?>[], 41), isNull);
    });

    test('ignores null divider slots', () {
      expect(AtMeJump.pickVisibleIndex(const [null, 10, null, 80], 40), 1);
    });
  });
}
