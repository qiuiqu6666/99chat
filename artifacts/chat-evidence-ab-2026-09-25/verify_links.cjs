const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname);
const docs = ['README.md', 'A-first-screen.md', 'B-draft-send.md', 'A-source-complete.md', 'B-source-complete.md'];
const failures = [];
let checked = 0;
for (const file of docs) {
  const content = fs.readFileSync(path.join(root, file), 'utf8');
  for (const match of content.matchAll(/\]\(<([^>]+)>\)/g)) {
    const target = match[1];
    if (/^https?:/.test(target)) continue;
    const parsed = /^(.*?)(?::(\d+))?$/.exec(target);
    const local = path.isAbsolute(parsed[1]) ? parsed[1] : path.resolve(root, parsed[1]);
    checked++;
    if (!fs.existsSync(local)) {
      failures.push({file, target, reason: 'missing'});
    } else if (parsed[2]) {
      const lines = fs.readFileSync(local, 'utf8').split(/\r?\n/).length;
      if (+parsed[2] < 1 || +parsed[2] > lines) failures.push({file, target, reason: 'line outside source'});
    }
  }
}
const result = {checkedAtUtc: new Date().toISOString(), documents: docs.length, linksChecked: checked, failures};
fs.writeFileSync(path.join(root, 'link-validation.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result));
if (failures.length) process.exitCode = 1;
