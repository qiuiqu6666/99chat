import json, difflib, hashlib
from pathlib import Path

folder = Path('artifacts/chat-round2-correctness-2026-09-25')
baseline = {item['path']: item for item in json.loads((folder/'baseline.json').read_text(encoding='utf-8'))['files']}
owned = json.loads((folder/'owned-files.json').read_text(encoding='utf-8'))
changes = []
for name in owned:
    if name not in baseline:
        continue
    old = (folder/baseline[name]['snapshot']).read_bytes().splitlines(keepends=True)
    target = Path(name)
    before = target.read_bytes()
    current = before.splitlines(keepends=True)
    key = lambda line: line.rstrip(b'\r\n')
    matcher = difflib.SequenceMatcher(None, list(map(key, old)), list(map(key, current)), autojunk=False)
    for a, b, size in matcher.get_matching_blocks():
        for offset in range(size):
            current[b+offset] = old[a+offset]
    after = b''.join(current)
    if before.replace(b'\r\n', b'\n') != after.replace(b'\r\n', b'\n'):
        raise RuntimeError('Non-EOL modification rejected: '+name)
    if before != after:
        target.write_bytes(after)
        changes.append({'file':name,'beforeSha256':hashlib.sha256(before).hexdigest(),'afterSha256':hashlib.sha256(after).hexdigest(),'normalizedBytesIdentical':True})
(folder/'line-ending-verification.json').write_text(json.dumps(changes, indent=2), encoding='utf-8')
print('Restored original EOL for unchanged lines in',len(changes),'files; normalized source bytes unchanged.')
