const fs=require('fs'),cp=require('child_process'),crypto=require('crypto');
const dir='artifacts/chat-round2-correctness-2026-09-25';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const manifest=JSON.parse(fs.readFileSync(dir+'/round2-delivery-manifest.json','utf8'));
const failures=[];
for(const f of manifest.files){
 if(hash(fs.readFileSync(f.path))!==f.afterSha256)failures.push('working tree drift '+f.path);
 if(hash(fs.readFileSync(dir+'/'+f.afterSnapshot))!==f.afterSha256)failures.push('after snapshot '+f.path);
 if(f.beforeSnapshot&&hash(fs.readFileSync(dir+'/'+f.beforeSnapshot))!==f.beforeSha256)failures.push('before snapshot '+f.path);
}
if(hash(fs.readFileSync(dir+'/round2-only.patch'))!==manifest.patchSha256)failures.push('patch hash');
const report=fs.readFileSync(dir+'/审计与修复报告.md','utf8');
const links=[...report.matchAll(/^\[[^\]]+\]: <([^>]+)>$/gm)].map(m=>m[1]);
for(const link of links){const p=link.replace(/:\d+$/,'');if(!fs.existsSync(p))failures.push('missing link '+link);}
const graph=JSON.parse(fs.readFileSync(dir+'/detect-changes-final.json','utf8'));
if(graph.partial===true||graph.truncated===true||graph.changed_symbols.length!==graph.summary.changed_count)failures.push('incomplete detect_changes');
const head=cp.execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
if(head!==manifest.head)failures.push('head changed');
cp.execFileSync('git',['apply','--reverse','--check',dir+'/round2-only.patch'],{stdio:'pipe'});
const result={checkedAt:new Date().toISOString(),files:manifest.files.length,reportLocalLinks:links.length,head,patchSha256:manifest.patchSha256,reportSha256:hash(Buffer.from(report)),graph:{summary:graph.summary,partial:graph.partial??false,truncated:graph.truncated??false,note:'Whole dirty tree, not exclusive round 2. Index flow coverage is incomplete.'},failures};
fs.writeFileSync(dir+'/delivery-verification.json',JSON.stringify(result,null,2));
console.log(JSON.stringify(result,null,2));
if(failures.length)process.exitCode=1;
