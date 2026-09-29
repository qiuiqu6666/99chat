const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');

const report = __dirname;
const baseline = JSON.parse(fs.readFileSync(path.join(report, 'baseline.json')));
const owned = {
  client: [
    'lib/src/services/im/im05_contracts.dart',
    'lib/src/services/im/im05_persistence.dart',
    'lib/src/services/im/im_ingress_store.dart',
    'lib/src/services/im/im_ingress_store_platform_web.dart',
    'lib/src/services/im/outgoing_send_coordinator.dart',
    'lib/src/services/im/outbox_retry_identity.dart',
    'lib/src/services/conversation_local/conversation_draft_service.dart',
    'lib/src/services/im/read_outbox_store.dart',
    'test/round2_dispatch_and_draft_test.dart',
    'test/round2_crash_worker_test.dart',
    'test/round2_outbox_boundaries_test.dart',
    'test/round2_route_read_boundaries_test.dart',
    'test/round3_upgrade_test.dart',
    'artifacts/chat-round3-cross-mechanism-2026-09-25/run-prepared-resume.cjs',
  ],
  server: [
    'src/main/java/com/chat99/server/chatattachment/ChatNativeVideoService.java',
    'src/main/java/com/chat99/server/chatattachment/ChatNativeVideoPersistence.java',
    'src/test/java/com/chat99/server/chatattachment/ChatNativeVideoServiceTest.java',
    'src/test/java/com/chat99/server/chatattachment/ChatNativeVideoPersistenceTest.java',
  ],
};
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const run = (file, args, cwd) => {
  const result = cp.spawnSync(file, args, {cwd, maxBuffer: 128e6});
  if (result.status !== 0) throw Error(`${file} ${args.join(' ')}: ${result.stderr}`);
  return result.stdout;
};
const output = {capturedAt: baseline.capturedAt, packagedAt: new Date().toISOString(), repositories: {}};
for (const [name, paths] of Object.entries(owned)) {
  const info = baseline.repositories[name];
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), `round3-${name}-patch-`));
  run('git', ['init', '-q'], temp);
  run('git', ['config', 'user.name', 'Round 3 Evidence'], temp);
  run('git', ['config', 'user.email', 'round3@local.invalid'], temp);
  const initialPatch = path.join(report, `${name}-initial-working-tree.patch`);
  const needsPatch = [];
  const entries = [];
  for (const relative of paths) {
    const recorded = info.files.find(file => file.path === relative);
    const snapshot = info.snapshots.find(file => file.path === relative);
    let before = null;
    if (snapshot) before = fs.readFileSync(path.join(report, snapshot.snapshot));
    else if (recorded?.tracked) {
      before = run('git', ['show', `${info.head}:${relative}`], info.root);
      if (info.status.includes(relative)) needsPatch.push(relative);
    } else if (recorded && name === 'client' &&
               relative === 'test/round2_route_read_boundaries_test.dart') {
      // This baseline-untracked test was not copied into `before`. Reverse
      // only this round's three-line assertion edit, then demand the captured
      // full-tree hash before using it as the patch base.
      const current = fs.readFileSync(path.join(info.root, relative), 'utf8');
      const nl = current.includes('\r\n') ? '\r\n' : '\n';
      const changed = "      expect(w3.attemptCount, resumed.attemptCount + 1);" + nl +
        "      expect(w3.retryReason, 'blocked:sdk_6017');" + nl +
        "      expect(w3.nextRetryAtMs, -1);";
      if (!current.includes(changed)) throw Error('cannot reconstruct old read test');
      before = Buffer.from(current.replace(changed, '      expect(w3.attemptCount, 0);'));
    } else if (recorded) {
      throw Error(`baseline bytes missing for untracked ${name}:${relative}`);
    }
    if (before !== null) {
      const dest = path.join(temp, relative);
      fs.mkdirSync(path.dirname(dest), {recursive: true});
      fs.writeFileSync(dest, before);
    }
    entries.push({path: relative, beforeSha256: recorded?.sha256 ?? null});
  }
  if (needsPatch.length) {
    run('git', ['apply', ...needsPatch.map(file => `--include=${file}`), initialPatch], temp);
    for (const relative of needsPatch) {
      const dest = path.join(temp, relative);
      const recorded = info.files.find(file => file.path === relative);
      const raw = fs.readFileSync(dest);
      if (hash(raw) !== recorded.sha256) {
        const lf = Buffer.from(raw.toString().replace(/\r\n/g, '\n'));
        if (hash(lf) === recorded.sha256) fs.writeFileSync(dest, lf);
      }
    }
  }
  for (const entry of entries) {
    const dest = path.join(temp, entry.path);
    const actual = fs.existsSync(dest) ? hash(fs.readFileSync(dest)) : null;
    if (actual !== entry.beforeSha256) {
      throw Error(`baseline hash mismatch ${name}:${entry.path}: ${actual} != ${entry.beforeSha256}`);
    }
  }
  run('git', ['add', '-A'], temp);
  run('git', ['commit', '-q', '-m', 'Captured round 3 baseline'], temp);
  for (const entry of entries) {
    const source = path.join(info.root, entry.path);
    const dest = path.join(temp, entry.path);
    if (fs.existsSync(source)) {
      fs.mkdirSync(path.dirname(dest), {recursive: true});
      fs.copyFileSync(source, dest);
      entry.afterSha256 = hash(fs.readFileSync(source));
    } else {
      entry.afterSha256 = null;
      if (fs.existsSync(dest)) fs.unlinkSync(dest);
    }
  }
  run('git', ['add', '-A'], temp);
  run('git', ['diff', '--cached', '--check'], temp);
  const patch = run('git', ['diff', '--cached', '--binary', 'HEAD'], temp);
  const patchName = `${name}-round3.patch`;
  fs.writeFileSync(path.join(report, patchName), patch);
  run('git', ['apply', '--reverse', '--check', path.join(report, patchName)], temp);
  output.repositories[name] = {root: info.root, head: info.head, patch: patchName,
    patchSha256: hash(patch), files: entries};
}
fs.writeFileSync(path.join(report, 'patch-manifest.json'), JSON.stringify(output, null, 2));
console.log(JSON.stringify(Object.fromEntries(Object.entries(output.repositories)
  .map(([name, value]) => [name, {patch: value.patch, bytes: fs.statSync(path.join(report, value.patch)).size, files: value.files.length}]))));
