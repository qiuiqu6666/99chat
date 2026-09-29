const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const root = path.resolve('artifacts/chat-round3-cross-mechanism-2026-09-25/prepared-resume-' + Date.now());
fs.mkdirSync(root, {recursive: true});
const dart = 'E:/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe';
const flutter = 'E:/flutter/flutter/packages/flutter_tools/bin/flutter_tools.dart';
const nonce = crypto.randomUUID();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function run(mode) {
  const fd = fs.openSync(path.join(root, mode + '.jsonl'), 'w');
  const child = cp.spawn(dart, [flutter, 'test', '--no-pub',
    'test/round2_crash_worker_test.dart', '--reporter', 'json',
    '--dart-define=CRASH_DIR=' + root.replaceAll('\\', '/'),
    '--dart-define=CRASH_CASE=prepared_resume',
    '--dart-define=CRASH_MODE=' + mode,
    '--dart-define=CRASH_NONCE=' + nonce],
    {stdio: ['ignore', fd, fd], windowsHide: true});
  const done = new Promise(resolve => child.on('exit', resolve));
  if (mode === 'write') {
    let ready;
    for (let i = 0; i < 1800; i++) {
      if (child.exitCode !== null) throw Error('writer exited before kill');
      const file = path.join(root, 'ready.json');
      if (fs.existsSync(file)) {
        try { ready = JSON.parse(fs.readFileSync(file, 'utf8')); break; } catch {}
      }
      await sleep(50);
    }
    if (!ready || ready.nonce !== nonce || ready.scenario !== 'prepared_resume' ||
        !Number.isInteger(ready.pid) || ready.pid <= 0) throw Error('unverified kill target');
    process.kill(ready.pid, 'SIGKILL');
  }
  const code = await done;
  fs.closeSync(fd);
  if (mode === 'verify' && code !== 0) throw Error('verify failed: ' + path.join(root, 'verify.jsonl'));
}
(async () => {
  await run('write');
  await run('verify');
  const result = JSON.parse(fs.readFileSync(path.join(root, 'verified.json'), 'utf8'));
  console.log(JSON.stringify({root, result}, null, 2));
})().catch(error => {console.error(error); process.exitCode = 1;});
