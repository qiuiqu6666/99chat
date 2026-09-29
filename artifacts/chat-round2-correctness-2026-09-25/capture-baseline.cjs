const fs=require('fs'),cp=require('child_process'),path=require('path'),crypto=require('crypto');
const root='artifacts/chat-round2-correctness-2026-09-25/';
if(fs.existsSync(root+'baseline.json')) throw Error('Baseline already exists; never overwrite');
const git=(args,encoding='utf8')=>cp.execFileSync('git',args,{encoding,maxBuffer:128*1024*1024});
const tracked=git(['ls-files','-z']).split('\0').filter(Boolean);
const untracked=git(['ls-files','--others','--exclude-standard','-z']).split('\0').filter(p=>p&&!p.startsWith('artifacts/'));
const files=[];
for(const file of new Set([...tracked,...untracked])){
 if(!fs.existsSync(file)||!fs.statSync(file).isFile())continue;
 const data=fs.readFileSync(file), snapshot='before/'+file+'.snapshot';
 fs.mkdirSync(path.dirname(root+snapshot),{recursive:true});fs.writeFileSync(root+snapshot,data);
 files.push({path:file,snapshot,sha256:crypto.createHash('sha256').update(data).digest('hex'),tracked:tracked.includes(file)});
}
fs.writeFileSync(root+'initial-working-tree.patch',git(['diff','--binary','HEAD'],null));
fs.writeFileSync(root+'baseline.json',JSON.stringify({head:git(['rev-parse','HEAD']).trim(),branch:git(['branch','--show-current']).trim(),capturedAt:new Date().toISOString(),status:git(['status','--short']),scope:'All tracked files and untracked source/assets/config; prior artifacts excluded',files},null,2));
fs.mkdirSync(root+'graph',{recursive:true});
let helper=fs.readFileSync('artifacts/chat-round1-fixes-2026-09-25/impact.cjs','utf8').replaceAll('artifacts/chat-round1-fixes-2026-09-25/graph/','artifacts/chat-round2-correctness-2026-09-25/graph/');
fs.writeFileSync(root+'impact.cjs',helper);
console.log(JSON.stringify({files:files.length,head:git(['rev-parse','HEAD']).trim()}));
