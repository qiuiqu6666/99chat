const fs=require('fs'), path=require('path'), cp=require('child_process'), crypto=require('crypto');
const base=path.resolve('artifacts/chat-round2-correctness-2026-09-25/crash-'+Date.now());
fs.mkdirSync(base,{recursive:true});
const runner='E:/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe';
const tool='E:/flutter/flutter/packages/flutter_tools/bin/flutter_tools.dart';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function run(scenario, mode, dir, nonce) {
 const log=fs.openSync(path.join(dir,mode+'.jsonl'),'w');
 const child=cp.spawn(runner,[tool,'test','--no-pub','test/round2_crash_worker_test.dart','--reporter','json',
   '--dart-define=CRASH_DIR='+dir.replaceAll('\\','/'),'--dart-define=CRASH_CASE='+scenario,
   '--dart-define=CRASH_MODE='+mode,'--dart-define=CRASH_NONCE='+nonce],{stdio:['ignore',log,log],windowsHide:true});
 const done=new Promise(resolve=>child.on('exit',code=>resolve(code)));
 if(mode==='write') {
   const ready=path.join(dir,'ready.json'); let info;
   for(let i=0;i<1800;i++) {
     if(child.exitCode!==null) throw Error('writer exited early '+scenario+' '+child.exitCode);
     if(fs.existsSync(ready)){try{info=JSON.parse(fs.readFileSync(ready));break;}catch{}}
     await sleep(50);
   }
   if(!info||info.nonce!==nonce||info.scenario!==scenario||!Number.isInteger(info.pid)||info.pid<=0) throw Error('unverified crash target');
   process.kill(info.pid,'SIGKILL');
 }
 const code=await done;fs.closeSync(log);
 if(mode==='verify'&&code!==0)throw Error('verification failed '+scenario);
}
(async()=>{
 const results=[];
 for(const scenario of ['before_commit','prepared','dispatch_intent','sdk_success_commit_failure']) {
   const dir=path.join(base,scenario),nonce=crypto.randomUUID();fs.mkdirSync(dir);
   await run(scenario,'write',dir,nonce);await run(scenario,'verify',dir,nonce);
   results.push(JSON.parse(fs.readFileSync(path.join(dir,'verified.json'),'utf8')));
   console.log('verified '+scenario);
 }
 fs.writeFileSync(path.join(base,'matrix.json'),JSON.stringify(results,null,2));
 console.log(base);
})().catch(error=>{console.error(error);process.exitCode=1;});
