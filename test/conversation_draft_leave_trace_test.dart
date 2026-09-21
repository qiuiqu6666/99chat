import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_leave_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';

void main() {
  test('empty draft hash is empty and draftLen is 0', () {
    expect(ConversationPerfGateLog.textHash(''), '');
    expect(ConversationPerfGateLog.textHash('   '), '');
    ConversationDraftLeaveTrace.stage(
      'probe_empty',
      conversationId: 'c2c_peer',
      draftText: '',
    );
    expect(ConversationDraftLeaveTrace.lastLineForTest['draftLen'], 0);
    expect(ConversationDraftLeaveTrace.lastLineForTest['draftHash'], '');
    expect(ConversationDraftLeaveTrace.lastLineForTest['empty'], isTrue);
  });

  test('nonempty trimmed hash is stable and not the raw text', () {
    const raw = ' abc ';
    final hash = ConversationPerfGateLog.textHash(raw);
    expect(hash, isNotEmpty);
    expect(hash, isNot(raw));
    expect(hash, isNot(raw.trim()));
    expect(hash, ConversationPerfGateLog.textHash('abc'));
    expect(hash.length, 12);
    ConversationDraftLeaveTrace.stage(
      'probe_nonempty',
      conversationId: 'c2c_peer',
      draftText: raw,
    );
    expect(ConversationDraftLeaveTrace.lastLineForTest['draftLen'], 3);
    expect(ConversationDraftLeaveTrace.lastLineForTest['draftHash'], hash);
    expect(ConversationDraftLeaveTrace.lastLineForTest['empty'], isFalse);
  });

  test('focus matches same conversation and rejects others', () {
    ConversationDraftLeaveTrace.focus('c2c_alice');
    expect(ConversationDraftLeaveTrace.isFocused('c2c_alice'), isTrue);
    expect(ConversationDraftLeaveTrace.isFocused('c2c_bob'), isFalse);
  });

  test('draftLeaveTraceEnabled stays on', () {
    expect(ConversationPerfFlags.draftLeaveTraceEnabled, isTrue);
  });
}
