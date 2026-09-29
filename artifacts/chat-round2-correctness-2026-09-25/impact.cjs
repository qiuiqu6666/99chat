const fs=require('fs'),cp=require('child_process');
const [target,file]=process.argv.slice(2);
const env={...process.env,GITNEXUS_STORAGE_PATH:'D:\\codex-task-cache\\99999999-chat-round1-20260925'};
const cli='D:/nvm/v20.19.3/node_modules/gitnexus/dist/cli/index.js';
const run=args=>{const raw=cp.execFileSync('D:/nvm/v20.19.3/node.exe',[cli,...args],{env,encoding:'utf8',maxBuffer:16*1024*1024});return JSON.parse(raw.slice(raw.indexOf('{')));};
let r=run(['impact',target,'--direction','upstream','--repo','.',...(file?['--file',file]:[])]);
if(r.status==='ambiguous'){
 let candidates=r.candidates.filter(x=>x.filePath===file);
 if(candidates.length>1 && candidates.some(x=>x.kind==='Class'))candidates=candidates.filter(x=>x.kind==='Class');
 if(candidates.length!==1)throw Error('unresolved impact '+JSON.stringify(r));
 r=run(['impact','--uid',candidates[0].uid,'--direction','upstream','--repo','.']);
}
if(r.error)throw Error(r.error);
fs.writeFileSync('artifacts/chat-round2-correctness-2026-09-25/graph/'+target.replace(/[^a-z0-9_-]/gi,'_')+'.json',JSON.stringify(r,null,2));
console.log(JSON.stringify({target,risk:r.risk,impactedCount:r.impactedCount,summary:r.summary,direct:r.byDepth?.['1'],processes:r.affected_processes,partial:r.partial,truncated:r.pagination?.truncated}));
