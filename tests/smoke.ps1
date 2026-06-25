# =================================================================
#  Smoke-тесты LN_MCP_1C
#  Запуск:  pwsh -File tests/smoke.ps1 -BaseUrl http://localhost:81/CSP_TEST -User Admin -Password pass
#  PS 5.1: кириллица в BSL-запросах через Base64 (UTF-8), тело JSON — byte[]
# =================================================================
param(
    [Parameter(Mandatory = $true)] [string] $BaseUrl,
    [string] $User = $env:MCP_USER,
    [string] $Password = $env:MCP_PASSWORD
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Utf8([string] $s) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) }

# BSL literals (UTF-8 Base64) — без кириллицы в исходнике для Windows PowerShell 5.1
$QuerySelect1   = Utf8 '0JLQq9CR0KDQkNCi0KwgMSDQmtCQ0Jog0KfQuNGB0LvQviwgImhlbGxvIiDQmtCQ0Jog0KHRgtGA0L7QutCw'
$QueryBadSyntax = Utf8 '0JLQq9CR0KDQkNCi0Kwg0J/Qm9Ce0KXQntCZINCh0JjQndCi0JDQmtCh'
$CodeTwoPlusTwo = Utf8 '0KDQtdC30YPQu9GM0YLQsNGCID0gMiArIDI7'

$Headers = @{ 'Accept' = 'application/json' }
if ($User) {
    $pair = "$User`:$Password"
    $bytes = [Text.Encoding]::UTF8.GetBytes($pair)
    $Headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String($bytes)
}

function Invoke-MCP {
    param([string] $Method, [hashtable] $Params = @{})
    $payload = @{
        jsonrpc = '2.0'
        id      = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        method  = $Method
        params  = $Params
    } | ConvertTo-Json -Depth 12 -Compress
    Write-Host "-> $Method" -ForegroundColor DarkGray
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($payload)
    return Invoke-RestMethod -Method Post -Uri "$BaseUrl/hs/mcp/rpc" `
        -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $bodyBytes
}

function Test-JsonLikeText([string] $Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($Text -match '^\s*[\{\[]') { return $true }
    if ($Text.Length -gt 40 -and ($Text -match '"' -or $Text -match "'")) { return $true }
    return $false
}

function Assert-ToolText {
    param([object] $Result, [string] $Label, [scriptblock] $Check)
    if ($Result.isError) { throw "$Label : isError=true`n$($Result.content[0].text)" }
    $text = $Result.content[0].text
    if (-not (Test-JsonLikeText $text)) {
        throw "$Label : response is not JSON (load LN_MCP_1C 1.0.8+ from repo, F7). Text: $($text.Substring(0, [Math]::Min(120, $text.Length)))"
    }
    if (-not (& $Check $text)) { throw "$Label : unexpected text: $($text.Substring(0, [Math]::Min(200, $text.Length)))" }
    Write-Host "[OK] $Label" -ForegroundColor Green
}

Write-Host "=== 1. /health ===" -ForegroundColor Cyan
$h = Invoke-RestMethod -Method Get -Uri "$BaseUrl/hs/mcp/health" -Headers $Headers
$h | ConvertTo-Json -Compress

Write-Host "`n=== 2. tools/list ===" -ForegroundColor Cyan
$tools = Invoke-MCP -Method 'tools/list'
Write-Host ("tools: " + $tools.result.tools.Count)

Write-Host "`n=== 3. execute_query ===" -ForegroundColor Cyan
$q = Invoke-MCP -Method 'tools/call' -Params @{
    name      = 'execute_query'
    arguments = @{ query = $QuerySelect1; limit = 10 }
}
Assert-ToolText $q.result 'execute_query' { param($t) $t -match 'columns' -and $t -match 'rows' -and $t -match 'row_count' }
Write-Host ($q.result.content[0].text.Substring(0, [Math]::Min(300, $q.result.content[0].text.Length)))

Write-Host "`n=== 4. get_configuration ===" -ForegroundColor Cyan
$cfg = Invoke-MCP -Method 'tools/call' -Params @{ name = 'get_configuration'; arguments = @{} }
Assert-ToolText $cfg.result 'get_configuration' { param($t) $t -match 'name' -and $t -match 'version' -and $t -match 'counters' }
Write-Host ($cfg.result.content[0].text.Substring(0, [Math]::Min(300, $cfg.result.content[0].text.Length)))

Write-Host "`n=== 5. list_extensions ===" -ForegroundColor Cyan
$ext = Invoke-MCP -Method 'tools/call' -Params @{ name = 'list_extensions'; arguments = @{} }
Assert-ToolText $ext.result 'list_extensions' { param($t) $t -match '^\s*\[' -and $t -match 'name' -and $t -match 'version' }
Write-Host ($ext.result.content[0].text.Substring(0, [Math]::Min(300, $ext.result.content[0].text.Length)))

Write-Host "`n=== 6. execute_code ===" -ForegroundColor Cyan
$code = Invoke-MCP -Method 'tools/call' -Params @{
    name      = 'execute_code'
    arguments = @{ code = $CodeTwoPlusTwo; safe_mode = $true }
}
Assert-ToolText $code.result 'execute_code' { param($t) $t.Length -gt 0 -and $t -match '\d' }

Write-Host "`n=== 7. validate_query (bad syntax) ===" -ForegroundColor Cyan
$bad = Invoke-MCP -Method 'tools/call' -Params @{
    name      = 'validate_query'
    arguments = @{ query = $QueryBadSyntax }
}
# invalid query — ожидаем isError или текст с описанием ошибки
if (-not $bad.result.isError -and $bad.result.content[0].text -notmatch 'valid|error|syntax|invalid|false') {
    Write-Host "[WARN] validate_query: no obvious error marker" -ForegroundColor Yellow
} else {
    Write-Host "[OK] validate_query" -ForegroundColor Green
}

Write-Host "`n[OK] Smoke tests passed." -ForegroundColor Green
