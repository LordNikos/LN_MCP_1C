# Diagnose ln-mcp for Cursor (direct HTTP, no proxy)
param(
    [string]$BaseUrl = "http://localhost:8080/YOUR_PUBLISH/hs/mcp/rpc",
    [string]$Username = "",
    [string]$Password = "",
    [string]$Auth = ""
)

$ErrorActionPreference = "Continue"

if (-not $Auth -and $Username) {
    $pair = "${Username}:${Password}"
    $bytes = [Text.Encoding]::UTF8.GetBytes($pair)
    $Auth = "Basic " + [Convert]::ToBase64String($bytes)
}

$h = @{ Accept = "application/json, text/event-stream"; "Content-Type" = "application/json" }
if ($Auth) { $h["Authorization"] = $Auth }

$fail = $false

Write-Host "=== LN MCP Cursor diagnostic ===" -ForegroundColor Cyan
Write-Host "URL: $BaseUrl"

try {
    Invoke-WebRequest -Uri $BaseUrl -Method GET -Headers $h -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "FAIL: GET must be 405" -ForegroundColor Red
    $fail = $true
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 405) { Write-Host "OK: GET -> 405" -ForegroundColor Green }
    else { Write-Host "FAIL: GET -> $code" -ForegroundColor Red; $fail = $true }
}

$initSimple = '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cursor","version":"1.0"}}}'
try {
    $r = Invoke-RestMethod -Uri $BaseUrl -Method POST -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($initSimple))
    $ver = $r.result.serverInfo.version
    Write-Host "OK: initialize simple -> server version $ver" -ForegroundColor Green
} catch {
    Write-Host "FAIL: initialize simple -> $($_.Exception.Message)" -ForegroundColor Red
    $fail = $true
}

$initCursor = '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{"elicitation":{"form":{}},"roots":{"listChanged":false},"extensions":{"io.modelcontextprotocol/ui":{"mimeTypes":["text/html;profile=mcp-app"]}}},"clientInfo":{"name":"cursor","version":"1.0"}}}'
try {
    $rc = Invoke-RestMethod -Uri $BaseUrl -Method POST -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($initCursor))
    if ($rc.result) {
        Write-Host "OK: initialize Cursor payload -> protocol $($rc.result.protocolVersion)" -ForegroundColor Green
    } else {
        Write-Host "FAIL: Cursor initialize -> $($rc.error.message)" -ForegroundColor Red
        $fail = $true
    }
} catch {
    Write-Host "FAIL: Cursor initialize -> $($_.Exception.Message)" -ForegroundColor Red
    $fail = $true
}

try {
    $tools = Invoke-RestMethod -Uri $BaseUrl -Method POST -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes('{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'))
    $count = @($tools.result.tools).Count
    Write-Host "OK: tools/list -> $count tools" -ForegroundColor Green
} catch {
    Write-Host "FAIL: tools/list -> $($_.Exception.Message)" -ForegroundColor Red
    $fail = $true
}

if ($fail) {
    Write-Host ""
    Write-Host "Action: F7 extension LN_MCP_1C -> restart web -> Reload Cursor -> check Auth URL" -ForegroundColor Yellow
    exit 1
}
Write-Host ""
Write-Host "Server ready. Reload Cursor window, toggle MCP server." -ForegroundColor Green
