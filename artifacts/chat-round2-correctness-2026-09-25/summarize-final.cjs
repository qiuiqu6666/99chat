const fs=require('fs'), path=require('path');
const dir='artifacts/chat-round2-correctness-2026-09-25';
const logs=['focused-release-final.jsonl','profile-correct-flag.jsonl','retry-parent-final.jsonl','route-disposal-final.jsonl'];
const summary=[];
for(const log of logs){
 const rows=fs.readFileSync(path.join(dir,log),'utf8').split(/\r?\n/).flatMap(l=>{try{return [JSON.parse(l)]}catch{return []}});
 const starts=new Map(rows.filter(e=>e.type==='testStart').map(e=>[e.test.id,e.test]));
 const tests=rows.filter(e=>e.type==='testDone'&&!e.hidden&&starts.has(e.testID));
 summary.push({log,success:rows.findLast(e=>e.type==='done')?.success,suites:rows.filter(e=>e.type==='suite').length,tests:tests.length,passed:tests.filter(e=>e.result==='success'&&!e.skipped).length,failed:tests.filter(e=>e.result!=='success'&&!e.skipped).map(e=>starts.get(e.testID)?.name),skipped:tests.filter(e=>e.skipped).length,elapsedMs:rows.findLast(e=>e.type==='done')?.time});
}
const analyze=fs.readFileSync(dir+'/analyze-release-native.txt','utf8');
const analyzer={errors:(analyze.match(/^\s*error -/gm)||[]).length,warnings:(analyze.match(/^\s*warning -/gm)||[]).length,infos:(analyze.match(/^\s*info -/gm)||[]).length};
fs.writeFileSync(dir+'/verification-summary.json',JSON.stringify({createdAt:new Date().toISOString(),tests:summary,analyzer},null,2));
console.log(JSON.stringify({tests:summary,analyzer},null,2));
