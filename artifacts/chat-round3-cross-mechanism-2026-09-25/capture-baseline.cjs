const fs=require('fs'),cp=require('child_process'),path=require('path'),crypto=require('crypto');
const dir=path.resolve('artifacts/chat-round3-cross-mechanism-2026-09-25');
if(fs.existsSync(path.join(dir,'baseline.json')))throw Error('round 3 baseline already captured');
const roots={client:process.cwd(),server:'C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server'};
const select={
 client:[
  'lib/src/services/im/im05_persistence.dart','lib/src/services/im/im05_contracts.dart',
  'lib/src/services/im/outgoing_send_coordinator.dart','lib/src/services/im/im_ingress_store.dart',
  'lib/src/services/im/outbox_state_version_schema.dart','lib/src/services/im/read_outbox_store.dart',
  'lib/src/services/im/conversation_read_policy.dart','lib/src/services/conversation_unread_clear_service.dart',
  'lib/src/services/conversation_local/conversation_draft_service.dart','lib/src/services/im/outbox_draft_submission.dart',
  'lib/src/services/im/message_core_store.dart','test/round2_dispatch_and_draft_test.dart',
  'test/round2_crash_worker_test.dart','test/round2_outbox_boundaries_test.dart'
 ],
 server:[
  'src/main/java/com/chat99/server/chatattachment/ChatNativeVideoService.java',
  'src/main/java/com/chat99/server/chatattachment/ChatAttachmentAuthService.java',
  'src/main/java/com/chat99/server/chatattachment/ChatAttachmentReferenceService.java',
  'src/main/java/com/chat99/server/chatattachment/ChatAttachmentOssClient.java',
  'src/main/java/com/chat99/server/chatattachment/ChatNativeVideoPersistence.java',
  'src/test/java/com/chat99/server/chatattachment/ChatNativeVideoServiceTest.java',
  'pom.xml'
 ]
};
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const manifest={capturedAt:new Date().toISOString(),repositories:{}};
for(const [name,root] of Object.entries(roots)){
 const git=(args,encoding='utf8')=>cp.execFileSync('git',args,{cwd:root,encoding,maxBuffer:128e6});
 const tracked=git(['ls-files','-z']).split('\0').filter(Boolean);
 const untracked=git(['ls-files','--others','--exclude-standard','-z']).split('\0').filter(p=>p&&!p.startsWith('artifacts/'));
 const files=[];
 for(const relative of new Set([...tracked,...untracked])){
  const full=path.join(root,relative);if(!fs.existsSync(full)||!fs.statSync(full).isFile())continue;
  const bytes=fs.readFileSync(full);files.push({path:relative,sha256:hash(bytes),tracked:tracked.includes(relative)});
 }
 const snapshots=[];
 for(const relative of select[name]){
  const full=path.join(root,relative);if(!fs.existsSync(full))continue;
  const bytes=fs.readFileSync(full),snapshot=path.join('before',name,relative+'.snapshot');
  fs.mkdirSync(path.dirname(path.join(dir,snapshot)),{recursive:true});fs.writeFileSync(path.join(dir,snapshot),bytes);
  snapshots.push({path:relative,snapshot:snapshot.replaceAll('\\','/'),sha256:hash(bytes)});
 }
 manifest.repositories[name]={root,head:git(['rev-parse','HEAD']).trim(),branch:git(['branch','--show-current']).trim(),status:git(['status','--short']),fileCount:files.length,files,snapshots};
 fs.writeFileSync(path.join(dir,`${name}-initial-working-tree.patch`),git(['diff','--binary','HEAD'],null));
}
fs.writeFileSync(path.join(dir,'baseline.json'),JSON.stringify(manifest,null,2));
console.log(JSON.stringify({capturedAt:manifest.capturedAt,clientFiles:manifest.repositories.client.fileCount,serverFiles:manifest.repositories.server.fileCount}));
