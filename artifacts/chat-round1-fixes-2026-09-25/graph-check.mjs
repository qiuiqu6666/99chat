import fs from 'node:fs';
process.env.GITNEXUS_STORAGE_PATH = 'D:/codex-task-cache/99999999-chat-round1-20260925';
const {LocalBackend} = await import('file:///D:/nvm/v20.19.3/node_modules/gitnexus/dist/mcp/local/local-backend.js');
const backend = new LocalBackend();
if (!await backend.init()) throw Error('GitNexus backend unavailable');
const result = await backend.callTool('detect_changes', {scope: 'all', repo: '.'});
fs.writeFileSync('artifacts/chat-round1-fixes-2026-09-25/graph/detect-changes-structured.json', JSON.stringify(result, null, 2));
fs.writeSync(1, JSON.stringify({summary: result.summary, partial: result.partial,
    truncated: result.truncated, changedSymbols: result.changed_symbols?.length,
    processes: result.affected_processes?.length, error: result.error}) + '\n');
await backend.dispose();
