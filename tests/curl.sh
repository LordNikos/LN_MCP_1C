#!/usr/bin/env bash
# Smoke-тесты LN_MCP_1C через curl (Linux/macOS/Git Bash).
# Использование:
#   BASE_URL=http://localhost/mcp_cspxml ./curl.sh
#   USER=admin PASSWORD=secret BASE_URL=... ./curl.sh
set -euo pipefail

BASE_URL=${BASE_URL:-http://localhost/mcp_cspxml}
USER_OPT=""
if [ -n "${USER:-}" ]; then
    USER_OPT="-u ${USER}:${PASSWORD:-}"
fi

call_rpc() {
    local method="$1"; local params="$2"
    local id=$(uuidgen 2>/dev/null || echo "$$-$RANDOM")
    curl -s ${USER_OPT} -X POST "${BASE_URL}/hs/mcp/rpc" \
         -H 'Content-Type: application/json; charset=utf-8' \
         -d "{\"jsonrpc\":\"2.0\",\"id\":\"${id}\",\"method\":\"${method}\",\"params\":${params}}"
    echo
}

echo "=== 1. /health ==="
curl -s ${USER_OPT} "${BASE_URL}/hs/mcp/health"
echo

echo "=== 2. tools/list ==="
call_rpc "tools/list" "{}"

echo "=== 3. execute_query: SELECT 1 ==="
call_rpc "tools/call" '{"name":"execute_query","arguments":{"query":"ВЫБРАТЬ 1 КАК Один"}}'

echo "=== 4. get_configuration ==="
call_rpc "tools/call" '{"name":"get_configuration","arguments":{}}'

echo "=== 5. list_extensions (TOON) ==="
curl -s ${USER_OPT} -X POST "${BASE_URL}/hs/mcp/rpc?format=toon" \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":"t","method":"tools/call","params":{"name":"list_extensions","arguments":{}}}'
echo

echo "[OK] curl smoke OK"
