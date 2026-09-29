const fs = require('fs');
const cp = require('child_process');
const crypto = require('crypto');
const path = require('path');
const root = 'artifacts/chat-round1-fixes-2026-09-25/';
const baseline = JSON.parse(fs.readFileSync(root + 'baseline.json', 'utf8'));
const files = {
  'third_party/tencent_cloud_chat_uikit/lib/data_services/message/message_history_peek_loader.dart': '03-profile-trace',
  'lib/src/chat_page/chat_draft_controller.dart': '01-f1-draft',
  'lib/src/services/conversation_local/conversation_draft_service.dart': '01-f1-draft',
  'lib/src/chat.dart': '01-f1-draft',
  'third_party/tencent_cloud_chat_uikit/lib/business_logic/life_cycle/chat_life_cycle.dart': '01-f1-draft',
  'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart': '01-f1-draft',
  'test/chat_draft_submission_test.dart': '01-f1-draft',
  'test/chat_input_composition_guard_test.dart': '01-f1-draft',
  'lib/src/services/im/im05_contracts.dart': '02-f2-outbox',
  'lib/src/services/im/im05_persistence.dart': '02-f2-outbox',
  'lib/src/services/im/outgoing_send_coordinator.dart': '02-f2-outbox',
  'lib/src/services/chat_failed_message_retry_service.dart': '02-f2-outbox',
  'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart': '02-f2-outbox',
  'third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart': '02-f2-outbox',
  'test/outgoing_result_arbitration_test.dart': '02-f2-outbox',
  'test/chat_reliability_regression_test.dart': '02-f2-outbox',
  'lib/src/services/chat_open_perf_log.dart': '03-profile-trace',
  'lib/src/services/conversation_peek_service.dart': '03-profile-trace',
  'lib/src/services/chat_open_viewport_coordinator.dart': '03-profile-trace',
  'lib/src/navigation/app_chat_route.dart': '03-profile-trace',
  'lib/src/conversation.dart': '03-profile-trace',
  'test/chat_open_profile_trace_test.dart': '03-profile-trace',
  'test/app_chat_route_session_reuse_test.dart': '03-profile-trace',
};
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const groups = {};
const manifest = [];
for (const [file, group] of Object.entries(files)) {
  let prior = baseline.snapshots.find(s => s.path === file);
  let isNew = false;
  if (!prior) {
    // These files were clean at the captured baseline, or created in this task.
    if (baseline.gitStatus?.includes(file) || baseline.status?.includes(file))
      throw Error('Uncaptured dirty baseline: ' + file);
    const saved = cp.spawnSync('git', ['show', 'HEAD:' + file]);
    isNew = saved.status !== 0;
    const snapshot = 'before/' + file + '.snapshot';
    fs.mkdirSync(path.dirname(root + snapshot), {recursive: true});
    fs.writeFileSync(root + snapshot, isNew ? '' : saved.stdout);
    prior = {path: file, snapshot, sha256: sha(isNew ? '' : saved.stdout), source: isNew ? 'new' : 'clean_HEAD'};
  }
  const before = root + prior.snapshot;
  const diff = cp.spawnSync('git', ['diff', '--no-index', '--', before, file], {encoding: 'utf8'});
  if (diff.status > 1) throw Error(diff.stderr);
  const raw = diff.stdout.replace(/\r\n/g, '\n');
  const hunks = raw.split(/(?=^@@ )/m).slice(1);
  const header = `diff --git a/${file} b/${file}\n` +
      (isNew ? 'new file mode 100644\n--- /dev/null\n' : `--- a/${file}\n`) + `+++ b/${file}\n`;
  const byGroup = {};
  for (const hunk of hunks) {
    const actual = file.endsWith('tui_chat_global_model.dart') && /ownerSpan|withSpan\(ownerSpan/.test(hunk)
        ? '03-profile-trace' : group;
    (byGroup[actual] ??= []).push(hunk);
  }
  for (const [g, chunks] of Object.entries(byGroup)) (groups[g] ??= []).push(header + chunks.join(''));
  manifest.push({file, groups: Object.keys(byGroup), beforeSha256: prior.sha256,
      afterSha256: sha(fs.readFileSync(file)), baselineSnapshot: prior.snapshot, newFile: isNew});
}
for (const [g, chunks] of Object.entries(groups)) fs.writeFileSync(root + g + '.patch', chunks.join(''));
fs.writeFileSync(root + 'review-manifest.json', JSON.stringify(manifest, null, 2));
console.log(JSON.stringify({files: manifest.length, patches: Object.keys(groups)}));
