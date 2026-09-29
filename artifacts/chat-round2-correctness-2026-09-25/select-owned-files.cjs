const fs=require('fs'); const dir='artifacts/chat-round2-correctness-2026-09-25';
const list=JSON.parse(fs.readFileSync(dir+'/round2-files.json','utf8')).filter(f=>!['lib/src/create_group.dart','lib/src/widgets/app_hud.dart','test/media_preview_video_chrome_test.dart','test/media_preview_image_save_animation_test.dart'].includes(f.path)&&!f.path.startsWith('third_party/tencent_cloud_chat_uikit/lib/ui/widgets/'));
fs.writeFileSync(dir+'/owned-files.json',JSON.stringify(list.map(f=>f.path),null,2));
console.log(list.length);
