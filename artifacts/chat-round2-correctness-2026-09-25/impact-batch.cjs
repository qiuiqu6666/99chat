const fs = require('fs'), cp = require('child_process');
const tasks = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const env = {...process.env, GITNEXUS_STORAGE_PATH:'D:/codex-task-cache/99999999-chat-round1-20260925'};
const run = args => {
  const raw = cp.execFileSync('D:/nvm/v20.19.3/node.exe', ['D:/nvm/v20.19.3/node_modules/gitnexus/dist/cli/index.js', ...args], {env, encoding:'utf8', maxBuffer:32*1024*1024});
  return JSON.parse(raw.slice(raw.indexOf('{')));
};
for (const [name,file] of tasks) {
  let r = run(['impact', name, '--file', file, '--direction','upstream','--repo','.']);
  const results = r.status === 'ambiguous' ? r.candidates.filter(x=>x.filePath===file).map(x=>run(['impact','--uid',x.uid,'--direction','upstream','--repo','.'])) : [r];
  fs.writeFileSync(`artifacts/chat-round2-correctness-2026-09-25/graph/${name.replace(/\W/g,'_')}-all.json`,JSON.stringify(results,null,2));
  console.log(JSON.stringify({name, results:results.map(x=>({risk:x.risk,count:x.impactedCount,error:x.error,partial:x.partial,truncated:x.pagination?.truncated}))}));
}
