const fs=require('fs'),d='artifacts/chat-round2-correctness-2026-09-25/';
const ev=fs.readFileSync(d+'focused-verified.jsonl','utf8').split('\n').flatMap(l=>{try{return[JSON.parse(l)]}catch{return[]}}),names=new Map(ev.filter(e=>e.type==='testStart').map(e=>[e.test.id,e.test.name]));
console.log(JSON.stringify(ev.filter(e=>e.type==='error').map(e=>({name:names.get(e.testID),error:e.error.slice(0,170),stack:e.stackTrace.slice(-370)})),null,2));
const lines=fs.readFileSync(d+'analyze-final.txt','utf8').split('\n');const errors=lines.filter(l=>/^\s*error -/.test(l));console.log(JSON.stringify({analyzerErrors:errors.length,first:errors.slice(0,10)},null,2));
