const fs=require('fs'), cp=require('child_process'), crypto=require('crypto');
const dir='artifacts/chat-round2-correctness-2026-09-25';
const baseline=JSON.parse(fs.readFileSync(dir+'/baseline.json','utf8'));
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const files=cp.execFileSync('git',['ls-files','--cached','--others','--exclude-standard','-z'],{encoding:'utf8',maxBuffer:32e6}).split('\0').filter(p=>p&&!p.startsWith('artifacts/'));
const before=new Map(baseline.files.map(f=>[f.path,f])); const changed=[];
for(const p of new Set([...files,...before.keys()])) {
 const old=before.get(p), bytes=fs.existsSync(p)&&fs.statSync(p).isFile()?fs.readFileSync(p):null;
 if(old?.sha256===(bytes&&hash(bytes)))continue;
 changed.push({path:p,before:old?.sha256??null,after:bytes?hash(bytes):null,baselineSnapshot:old?.snapshot??null});
}
fs.writeFileSync(dir+'/round2-files.json',JSON.stringify(changed,null,2));
console.log(changed.map(f=>f.path).join('\n'));
