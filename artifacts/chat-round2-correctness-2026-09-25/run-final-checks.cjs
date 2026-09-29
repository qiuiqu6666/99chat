const fs=require('fs'), cp=require('child_process');
const dir='artifacts/chat-round2-correctness-2026-09-25';
const dart='E:/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe';
const tool='E:/flutter/flutter/packages/flutter_tools/bin/flutter_tools.dart';
const mode=process.argv[2]||'tests';
let args,log;
if(mode==='tests') {
 const events=fs.readFileSync(dir+'/focused-final-pass.jsonl','utf8').split(/\r?\n/).flatMap(s=>{try{return [JSON.parse(s)]}catch{return []}});
 const files=[...new Set(events.filter(e=>e.type==='suite').map(e=>e.suite.path.replaceAll('\\','/').replace(process.cwd().replaceAll('\\','/')+'/','')))];
 if(files.length!==20)throw Error('unexpected prior suite count '+files.length);
 args=[tool,'test','--no-pub',...files,'--reporter','json'];log='focused-release-final.jsonl';
 fs.writeFileSync(dir+'/final-test-files.json',JSON.stringify(files,null,2));
} else if(mode==='analyze') {
 const files=JSON.parse(fs.readFileSync(dir+'/owned-files.json','utf8')).filter(p=>p.endsWith('.dart')&&!p.startsWith('third_party/')&&!p.endsWith('im_ingress_store_platform_web.dart'));
 args=['analyze',...files];log='analyze-release-native.txt';
} else throw Error('unknown mode');
const fd=fs.openSync(dir+'/'+log,'w');
const child=cp.spawn(dart,args,{stdio:['ignore',fd,fd],windowsHide:true});
child.on('exit',code=>{fs.closeSync(fd);console.log(JSON.stringify({mode,code,log}));process.exitCode=code;});
