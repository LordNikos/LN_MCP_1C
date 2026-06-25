# LN_MCP_1C — Agent onboarding

MCP server as a **1C configuration extension**. AI clients connect via **HTTP JSON-RPC** to a published infobase.

## When helping with setup

1. Read `docs/SETUP.ru.md` (user guide) and `.cursor/rules/ln-mcp-install.mdc` (checklist).
2. Never commit `.dev.env`, `.cursor/mcp.json`, or `publish/default.vrd` with real credentials.
3. Use **direct HTTP** in Cursor — no Node proxy unless user insists.
4. Verify with `tests/diagnose-cursor-mcp.ps1`.

## Key endpoints

| URL | Method | Purpose |
|-----|--------|---------|
| `{publish}/hs/mcp/rpc` | POST | JSON-RPC (tools, resources, prompts) |
| `{publish}/hs/mcp/health` | GET | Health check |

## Metadata tool choice

- **`get_metadata`** — primary ( `object_name`, `detail_level` )
- **`list_metadata_objects`** — list by English metaType + name mask
- `get_metadata_structure` — **removed** (duplicate)

## Version

Current release: see `VERSION` file. After changing `VERSION`, run `install/fix-extension-manifest.ps1` before F7.

## License

LN layer — proprietary (author LordNikos). Core from [vladimir-kharin/1c_mcp](https://github.com/vladimir-kharin/1c_mcp) (MIT).
