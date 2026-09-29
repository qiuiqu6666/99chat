const fs = require('fs'), cp = require('child_process'), crypto = require('crypto');
const root = 'artifacts/chat-round1-fixes-2026-09-25/';
const summary = {};
for (const name of ['round1-focused-final', 'profile-reader-tests', 'legacy-suite-final', 'profile-flag-tests', 'baseline-regressions']) {
  const rows = fs.readFileSync(root + name + '.jsonl', 'utf8').split(/\r?\n/)
      .flatMap(s => {try { return [JSON.parse(s)]; } catch {return [];}});
  const tests = new Map(rows.filter(r => r.type === 'testStart').map(r => [r.test.id, r.test]));
  const passed = rows.filter(r => r.type === 'testDone' && r.result === 'success' && !r.hidden);
  summary[name] = {done: rows.find(r => r.type === 'done'), passed: passed.length,
    passedByFile: {}, errors: rows.filter(r => r.type === 'error').map(r => ({
      name: tests.get(r.testID)?.name, error: r.error.slice(0, 220), stack: r.stackTrace?.slice(0, 300)}))};
  for (const result of passed) {
    const file = tests.get(result.testID)?.url;
    if (file) summary[name].passedByFile[file] = (summary[name].passedByFile[file] || 0) + 1;
  }
}
const baseline = JSON.parse(fs.readFileSync(root + 'baseline.json', 'utf8'));
const originalInput = fs.readFileSync(root + 'before/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart.snapshot', 'utf8');
const cleanHead = file => cp.execFileSync('git', ['show', 'HEAD:' + file], {encoding: 'utf8'});
const readFiles = ['lib/src/services/im/read_outbox_store.dart', 'lib/src/services/im/read_receipt_outbox_store.dart'];
summary.legacyBaselineEvidence = {
  keyboardAssertionPresentBefore: originalInput.includes('KeyboardViewportTransitionCoordinator.active?.isAnimating == true'),
  boundedReadRetryAssertion: readFiles.map(file => ({file,
    presentAtHEAD: cleanHead(file).includes('maxRetryAttempts = 10'),
    unchangedFromHEAD: cleanHead(file).replace(/\r\n/g, '\n') === fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n')})),
  enumSourceUnchangedFromHEAD: cleanHead('third_party/tencent_cloud_chat_uikit/lib/ui/controllers/record_input_state.dart').replace(/\r\n/g, '\n') ===
      fs.readFileSync('third_party/tencent_cloud_chat_uikit/lib/ui/controllers/record_input_state.dart', 'utf8').replace(/\r\n/g, '\n'),
};
const manifest = JSON.parse(fs.readFileSync(root + 'review-manifest.json', 'utf8'));
summary.unexpectedChangesToCapturedBaseline = baseline.snapshots.filter(s => !manifest.some(m => m.file === s.path))
    .filter(s => crypto.createHash('sha256').update(fs.readFileSync(s.path)).digest('hex') !== s.sha256).map(s => s.path);
fs.writeFileSync(root + 'validation-summary.json', JSON.stringify(summary, null, 2));
console.log(JSON.stringify(Object.fromEntries(Object.entries(summary).map(([k,v]) => [k, v.passed === undefined ? v : {passed:v.passed,done:v.done,errors:v.errors.map(e=>e.name)}])),null,2));
