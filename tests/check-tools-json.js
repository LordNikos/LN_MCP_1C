const fs = require('fs');
const path = process.argv[2];
const raw = fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, '');
try {
  const j = JSON.parse(raw);
  const tools = j.result?.tools || [];
  console.log('parse OK tools=' + tools.length);
  for (const t of tools) {
    if (!t.name) console.log('MISSING name', JSON.stringify(t).slice(0, 80));
    if (typeof t.description !== 'string') console.log('BAD description', t.name);
    if (!t.inputSchema || typeof t.inputSchema !== 'object') console.log('BAD inputSchema', t.name);
    else if (t.inputSchema.type !== 'object') console.log('schema type not object', t.name, t.inputSchema.type);
  }
} catch (e) {
  console.log('PARSE FAIL:', e.message);
  const idx = raw.search(/'/);
  if (idx >= 0) console.log('single quote near:', raw.slice(Math.max(0, idx - 30), idx + 30));
}
