const fs = require('node:fs');
const path = require('node:path');
function readText(file) {
  const b = fs.readFileSync(file);
  return b[0] === 255 && b[1] === 254 ? b.subarray(2).toString('utf16le') : b.toString('utf8').replace(/^\uFEFF/, '');
}
function events(name) {
  return readText(path.join(__dirname, name)).split(/\r?\n/).flatMap(line => {
    try { return [JSON.parse(line)]; } catch { return []; }
  });
}
const batches = ['tests.jsonl', 'tests-2.jsonl', 'probes-final.jsonl'].map(file => {
  const all = events(file);
  const starts = new Map(all.filter(e => e.type === 'testStart').map(e => [e.test.id, e.test]));
  const cases = all.filter(e => e.type === 'testDone' && !e.hidden).map(e => ({
    name: starts.get(e.testID)?.name, result: e.result, skipped: e.skipped,
    errors: all.filter(x => x.type === 'error' && x.testID === e.testID).map(x => ({
      message: x.error.slice(0, 1500), stack: x.stackTrace.slice(0, 1000)
    }))
  }));
  return { file, suites: all.filter(e => e.type === 'suite').length,
    passed: cases.filter(c => c.result === 'success' && !c.skipped).length,
    failed: cases.filter(c => c.result !== 'success').length,
    skipped: cases.filter(c => c.skipped).length,
    completion: all.findLast(e => e.type === 'done'),
    failures: cases.filter(c => c.result !== 'success') };
});
fs.writeFileSync(path.join(__dirname, 'verification-summary.json'), JSON.stringify(batches, null, 2));
console.log(JSON.stringify(batches.map(({failures, ...s}) => ({...s, failures: failures.map(f => ({name:f.name, result:f.result, errors:f.errors.map(e=>e.message.slice(0,150))}))})), null, 2));
