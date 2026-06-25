import fs from 'fs';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const { ListToolsResultSchema } = require('C:/Users/LordNikos/AppData/Local/Programs/cursor/resources/app/node_modules/@modelcontextprotocol/sdk/dist/cjs/types.js');

const raw = fs.readFileSync(process.argv[2], 'utf8').replace(/^\uFEFF/, '');
const data = JSON.parse(raw);
try {
  ListToolsResultSchema.parse(data.result);
  console.log('MCP ToolSchema: ALL OK', data.result.tools.length);
} catch (e) {
  console.log('MCP ToolSchema FAIL:', e.message?.slice(0, 800));
  if (e.errors) e.errors.slice(0, 8).forEach(err => console.log(' ', JSON.stringify(err)));
}
