import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group previous / local fallback reject disconnected older pages', () {
    final continuity = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/'
      'history_pagination_continuity.dart',
    ).readAsStringSync();
    final pagination = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'separate_models/tui_chat_history_pagination_load.dart',
    ).readAsStringSync();
    final model = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'separate_models/tui_chat_separate_view_model.dart',
    ).readAsStringSync();
    final global = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'view_models/tui_chat_global_model.dart',
    ).readAsStringSync();

    expect(continuity.contains('class ContinuityDecision'), isTrue);
    expect(continuity.contains('canAppendOlderBatch'), isTrue);
    expect(continuity.contains('defaultMaxCloudSeqGap = 5'), isTrue);
    expect(continuity.contains('missingLowerSeq'), isTrue);
    expect(continuity.contains('missingUpperSeq'), isTrue);

    expect(pagination.contains('load_previous_rejected_seq_gap'), isTrue);
    expect(pagination.contains('union_older_local_rejected_gap'), isTrue);
    expect(pagination.contains('canAppendOlderBatch('), isTrue);
    expect(
      pagination.contains('不做 seq 邻接检查'),
      isFalse,
    );

    expect(model.contains('toward_local_skip_disconnected'), isTrue);
    expect(model.contains('canAppendOlderBatch('), isTrue);
    expect(
      model.contains(
        'final canMerge = isOfficialFill ||\n'
        '          RoamingContiguousWindow.shouldMergeOlderPage(',
      ),
      isFalse,
    );

    expect(global.contains('noteRejectedOlderPageGap'), isTrue);
  });
}
