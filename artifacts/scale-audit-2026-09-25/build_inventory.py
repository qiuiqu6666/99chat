"""Static candidate inventory, not a runtime call trace. No network access."""
from pathlib import Path
import csv
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
sources = {p.relative_to(ROOT).as_posix(): p.read_text(encoding='utf-8-sig')
           for base in (ROOT / 'lib', ROOT / 'third_party/tencent_cloud_chat_uikit/lib')
           for p in base.rglob('*.dart')}

def lines_matching(text, pattern):
    return ['%d: %s' % (i, line.strip()) for i, line in enumerate(text.splitlines(), 1)
            if re.search(pattern, line)]

endpoints = []
for path, source in sources.items():
    for match in re.finditer(r'\.(get|post|put|delete|patch)(?:<[^;\n]*?>)?\s*\(\s*([\'\"])(/.*?)\2', source, re.S):
        # Dart interpolated paths are retained verbatim. The containing method
        # is deliberately not guessed from regex parsing.
        endpoints.append({'file': path, 'line': source[:match.start()].count('\n') + 1,
                          'method': match.group(1).upper(), 'path': match.group(3)})

page_rows = []
excluded = ('/ui/showcase/', 'main_showcase.dart')
for path, source in sources.items():
    if any(value in path for value in excluded):
        continue
    classes = re.findall(r'class\s+(\w+)\s+extends\s+(?:StatefulWidget|StatelessWidget)', source)
    has_scaffold = bool(re.search(r'\b(?:Scaffold|SettingsScaffold|CupertinoPageScaffold)\s*\(', source))
    named_page = [c for c in classes if re.search(r'(Page|Screen)$', c)]
    tab_surface = path in ('lib/src/contact.dart', 'lib/src/profile.dart')
    if not classes or not (has_scaffold or named_page or tab_surface):
        continue
    imports = re.findall(r"import\s+['\"]([^'\"]+)['\"]", source)
    api_imports = [i for i in imports if '/api/' in i]
    service_imports = [i for i in imports if '/services/' in i or '/provider/' in i or 'controller.dart' in i or 'repository' in i]
    row = {
        'file': path,
        'sha256': hashlib.sha256(source.encode('utf-8')).hexdigest(),
        'widget_classes': '; '.join(classes),
        'entry_hooks': '\n'.join(lines_matching(source, r'\b(initState|didChangeDependencies|didPush|didPopNext)\s*\(')),
        'request_and_load_candidates': '\n'.join(lines_matching(source, r'\b(?:[A-Za-z]\w*Api\.(?:instance\.|shared\.)?\w+|_api\.\w+|_repo(?:sitory)?\.\w+|\w*(?:Store|Service|Controller)\.(?:instance|shared)\.\w+|_load\w*|_refresh\w*|_fetch\w*)\s*\(')),
        'api_imports': '; '.join(api_imports),
        'service_imports': '; '.join(service_imports),
        'local_http_literals': '; '.join('%s %s @%s' % (e['method'], e['path'], e['line']) for e in endpoints if e['file'] == path),
        'sdk_candidates': '\n'.join(lines_matching(source, r'\b(getConversationList|getHistoryMessageList|getGroupMemberList|getGroupsInfo|getUsersInfo|searchLocalMessages|getFriendList)\b')),
        'scale_review_candidates': '\n'.join(lines_matching(source, r'Timer.periodic|while\s*\(|Future.wait|\.sort\(|shrinkWrap:\s*true|readAsBytesSync|readAsStringSync|listAll\(|readAll\(|\.indexOf\(')),
        'classification': 'static page/screen candidate; API calls include entry and user actions; indirect calls need service tracing',
    }
    page_rows.append(row)

def write_csv(name, rows):
    with (OUT / name).open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]) if rows else [])
        writer.writeheader()
        writer.writerows(rows)

write_csv('page-entry-inventory.csv', page_rows)
write_csv('http-endpoint-inventory.csv', endpoints)
summary = {'dart_files_scanned': len(sources), 'page_screen_candidates': len(page_rows),
           'http_literal_call_sites': len(endpoints),
           'scope': 'App and vendored UIKit Dart; page/screen candidates include legacy/debug/helpers; SDK/indirect/dynamic routes require manual trace; no runtime coverage claim'}
(OUT / 'inventory-summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False))
print('\n'.join(r['file'] for r in page_rows))
