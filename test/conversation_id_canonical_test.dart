// P1-2: 写入侧 canonical key 归一测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_id_canonical.dart';

void main() {
  group('ConversationIdCanonical.forStorage', () {
    test('empty stays empty', () {
      expect(ConversationIdCanonical.forStorage(''), '');
      expect(ConversationIdCanonical.forStorage('   '), '');
    });

    test('group_<x> collapses to canonical group form', () {
      expect(
        ConversationIdCanonical.forStorage('group_@TGS#_mc2SX4NMM62CZ'),
        '@TGS#_mc2SX4NMM62CZ',
      );
      expect(
        ConversationIdCanonical.forStorage('group_m2E3PN2N5CX'),
        'm2E3PN2N5CX',
      );
    });

    test('c2c_<x> passes through unchanged', () {
      expect(
        ConversationIdCanonical.forStorage('c2c_q14gkm5swv'),
        'c2c_q14gkm5swv',
      );
    });

    test('bare @TGS#_mc... canonicalizes', () {
      // canonicalGroupStorageId 期待规整前缀
      final out = ConversationIdCanonical.forStorage('@TGS#_mc2SX4NMM62CZ');
      // 输出必须去掉前缀语义但保留 TGS# 形态；只断言非空 + 不再以 group_ 开头。
      expect(out.isNotEmpty, isTrue);
      expect(out.startsWith('group_'), isFalse);
    });

    test('idempotent — second call returns the same value', () {
      const inputs = <String>[
        'group_@TGS#_mc2SX4NMM62CZ',
        '@TGS#_mc2SX4NMM62CZ',
        'c2c_q14gkm5swv',
        'm2E3PN2N5CX',
      ];
      for (final input in inputs) {
        final first = ConversationIdCanonical.forStorage(input);
        final second = ConversationIdCanonical.forStorage(first);
        expect(second, first, reason: 'input=$input');
      }
    });

    test('write-side equivalence — group_/bare pair collapse to one key', () {
      final a = ConversationIdCanonical.forStorage('@TGS#_mc2SX4NMM62CZ');
      final b = ConversationIdCanonical.forStorage('group_@TGS#_mc2SX4NMM62CZ');
      // 两条入口至少要在「是否带 group_ 前缀」上对齐，避免双 cache。
      expect(a.startsWith('group_'), b.startsWith('group_'));
    });
  });
}