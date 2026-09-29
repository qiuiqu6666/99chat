import { writeFileSync } from 'node:fs';
import { LocalBackend } from 'file:///D:/nvm/v20.19.3/node_modules/gitnexus/dist/mcp/local/local-backend.js';
const backend = new LocalBackend();
await backend.init();
const result = await backend.callTool('detect_changes', {scope: 'all', repo: '99chat-f01-f13-repair'});
writeFileSync('artifacts/audit-f01-f13-repair-2026-09-28/detect-changes-structured.json', JSON.stringify(result, null, 2));
process.exit(result.error || result.partial || result.truncated ? 1 : 0);
