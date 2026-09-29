const fs=require('fs'),path=require('path'),crypto=require('crypto');
const out=path.resolve('artifacts/chat-evidence-ab-2026-09-25');
const slash=p=>p.replaceAll('\\','/');
const text=p=>{const b=fs.readFileSync(p);return (b[0]===255&&b[1]===254?b.toString('utf16le'):b.toString('utf8')).replace(/^\uFEFF/,'')};
const json=p=>JSON.parse(text(p));
const manifest=json(out+'/source-manifest.json'),index=json(out+'/symbol-index.json');
const summaries=[];
for(const file of ['focused-tests.jsonl','draft-service-tests.jsonl']){
 const events=text(out+'/'+file).split(/\r?\n/).filter(x=>x.startsWith('{')).map(x=>{try{return JSON.parse(x)}catch{return {}}});
 const done=events.filter(x=>x.type==='testDone'&&!x.hidden);
 summaries.push({file,passed:done.filter(x=>x.result==='success'&&!x.skipped).length,failed:done.filter(x=>x.result!=='success'&&!x.skipped).length,skipped:done.filter(x=>x.skipped).length,completion:events.findLast(x=>x.type==='done'),errors:events.filter(x=>x.type==='error')});
}
fs.writeFileSync(out+'/focused-tests-summary.json',JSON.stringify(summaries,null,2));
for(const group of ['A','B']){
 let content='**'+group+' 包完整源码摘录**\n\n这些是当前工作树的原文快照，不是修改后的实现。用 Dart AST 边界提取完整方法/类型，保留原文件路径、起止行号和哈希；依赖导入和未摘录上下文可回到原文件核对。\n\n';
 const selected=manifest.filter(x=>x.group===group||x.group==='AB');
 selected.forEach((x,i)=>{content+=(i+1)+'. ['+x.selector+'](<'+slash(path.resolve(x.sourcePath))+':'+x.startLine+'>)，原文件 '+x.sourcePath+'，'+x.startLine+'–'+x.endLine+' 行。\n\n~~~dart\n'+text(out+'/'+x.snapshot)+'\n~~~\n\n'});
 fs.writeFileSync(out+'/'+group+'-source-complete.md',content);
}
const waits=[];
const seen=new Set();
for(const x of manifest.filter(x=>x.group==='A'||x.group==='AB')){
 const lines=text(x.sourcePath).split(/\r?\n/);
 for(let line=x.startLine;line<=x.endLine;line++){
  const value=lines[line-1]??'';
  if(!/\bawait\b|\bunawaited\s*\(|\bTimer(?:\.periodic)?\s*\(|\.timeout\s*\(|Future(?:<[^>]+>)?\.delayed|addPostFrameCallback|\bDuration\s*\(/.test(value))continue;
  if(value.trim().startsWith('//'))continue;
  const key=x.sourcePath+':'+line;if(seen.has(key))continue;seen.add(key);
  const owner=index.filter(v=>v.path===x.sourcePath&&v.start<=line&&v.end>=line).sort((a,b)=>(a.end-a.start)-(b.end-b.start))[0];
  waits.push({path:x.sourcePath,line,symbol:owner?.selector??x.selector,kind:/\bunawaited/.test(value)?'detached':/\bawait\b/.test(value)?'await':/Duration/.test(value)?'budget':/addPostFrame/.test(value)?'post_frame':'timer_or_timeout',source:value.trim()});
 }
}
const cols=['path','line','symbol','kind','source'];
fs.writeFileSync(out+'/A-await-timer-inventory.csv','\uFEFF'+cols.join(',')+'\n'+waits.map(x=>cols.map(k=>'"'+String(x[k]).replaceAll('"','""')+'"').join(',')).join('\n'));
const inventory=[];let scanned=0;
function scan(dir){if(path.resolve(dir)===out)return;for(const e of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,e.name);if(e.isDirectory()){scan(p);continue}if(!/\.(log|jsonl|json|txt|trace|perfetto-trace)$/i.test(e.name))continue;scanned++;const content=text(p);if(!/\[Pipeline\]|\[ChatOpenPerf\]|"traceEvents"/.test(content))continue;inventory.push({path:slash(p),bytes:fs.statSync(p).size,hasFlutterTestHarness:/loading .*test[\\/]|"type":"testStart"|[+]\\d+:/.test(content),hasSourceSnapshot:/class .*State|static void markMessagesFirstVisible|\/\/\/ Pipeline/.test(content),markerMatches:(content.match(/\[Pipeline\]|\[ChatOpenPerf\]|"traceEvents"/g)||[]).length,qualification:'Not a verified device profile sample; device/mode/scenario/build attribution missing.'})}}
for(const dir of ['artifacts','test_outputs'])if(fs.existsSync(dir))scan(dir);
fs.writeFileSync(out+'/raw-log-inventory.json',JSON.stringify({scope:['artifacts/**','test_outputs/**'],excluded:slash(path.relative('.',out)),filesInspected:scanned,qualifiedDeviceRuns:0,candidates:inventory},null,2));
const mismatch=manifest.filter(x=>crypto.createHash('sha256').update(fs.readFileSync(x.sourcePath)).digest('hex')!==x.sourceSha256);
const snapshotMismatch=manifest.filter(x=>crypto.createHash('sha256').update(fs.readFileSync(out+'/'+x.snapshot)).digest('hex')!==x.excerptSha256);
fs.writeFileSync(out+'/evidence-integrity.json',JSON.stringify({checkedAtUtc:new Date().toISOString(),sourceFiles:new Set(manifest.map(x=>x.sourcePath)).size,snapshots:manifest.length,waitAndTimerLines:waits.length,changedSources:mismatch.map(x=>x.sourcePath),changedSnapshots:snapshotMismatch.map(x=>x.snapshot)},null,2));
console.log(JSON.stringify({tests:summaries.map(({errors,...x})=>x),sourceFiles:new Set(manifest.map(x=>x.sourcePath)).size,snapshots:manifest.length,waitAndTimerLines:waits.length,logsInspected:scanned,logCandidates:inventory.length,changedSources:mismatch.length,changedSnapshots:snapshotMismatch.length}));

