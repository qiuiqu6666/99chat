const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const root=process.cwd(),dir=path.join(root,'artifacts/chat-round2-correctness-2026-09-25');
const baseline=JSON.parse(fs.readFileSync(path.join(dir,'baseline.json'),'utf8'));
const owned=JSON.parse(fs.readFileSync(path.join(dir,'owned-files.json'),'utf8'));
const old=new Map(baseline.files.map(f=>[f.path,f]));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const stage=path.join(dir,'patch-stage-'+Date.now());
fs.mkdirSync(stage);
function git(args,cwd=stage){return cp.execFileSync('git',['-c','core.autocrlf=false',...args],{cwd,windowsHide:true,maxBuffer:64e6});}
git(['init','--quiet']);
for(const p of owned){const prior=old.get(p);if(!prior)continue;const bytes=fs.readFileSync(path.join(dir,prior.snapshot));if(sha(bytes)!==prior.sha256)throw Error('baseline corrupted '+p);fs.mkdirSync(path.dirname(path.join(stage,p)),{recursive:true});fs.writeFileSync(path.join(stage,p),bytes);}
git(['add','--all']);
const files=[];
for(const p of owned){
 const bytes=fs.readFileSync(path.join(root,p)),prior=old.get(p),hash=sha(bytes);
 if(prior?.sha256===hash)throw Error('owned file unchanged '+p);
 const after='after/'+p+'.snapshot';fs.mkdirSync(path.dirname(path.join(dir,after)),{recursive:true});fs.writeFileSync(path.join(dir,after),bytes);
 fs.mkdirSync(path.dirname(path.join(stage,p)),{recursive:true});fs.writeFileSync(path.join(stage,p),bytes);
 files.push({path:p,beforeSha256:prior?.sha256??null,afterSha256:hash,beforeSnapshot:prior?.snapshot??null,afterSnapshot:after});
}
git(['add','--intent-to-add','--all']);
const patch=git(['diff','--no-ext-diff','--binary','--full-index','--']);
fs.writeFileSync(path.join(dir,'round2-only.patch'),patch);
fs.writeFileSync(path.join(dir,'round2-only.stat.txt'),git(['diff','--stat','--']));
// Read-only applicability check. Do not alter the user's working tree.
const check=git(['apply','--reverse','--check',path.join(dir,'round2-only.patch')],root).toString();
fs.writeFileSync(path.join(dir,'patch-reverse-check.txt'),'PASS: git apply --reverse --check round2-only.patch\n'+check);
const manifest={capturedAt:new Date().toISOString(),baselineCapturedAt:baseline.capturedAt,head:baseline.head,branch:baseline.branch,baselineManifestSha256:sha(fs.readFileSync(path.join(dir,'baseline.json'))),patchSha256:sha(patch),fileCount:files.length,reverseCheck:'passed; no changes applied',note:'Only explicit owned-files are included; comparison is against the captured initial working tree, not HEAD. No commits created.',files};
fs.writeFileSync(path.join(dir,'round2-delivery-manifest.json'),JSON.stringify(manifest,null,2));
console.log(JSON.stringify({files:files.length,patchBytes:patch.length,patchSha256:manifest.patchSha256,reverseCheck:'passed'}));
