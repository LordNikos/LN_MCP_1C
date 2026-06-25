# LN_MCP_1C regression suite (PowerShell 5.1+, UTF-8)
# Usage:
#   powershell -File tests/regression.ps1 -BaseUrl http://localhost:81/CSP_TEST/hs/mcp/rpc -Username Admin -Password pass

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $BaseUrl,
    [string] $Username = "",
    [string] $Password = "",
    [string] $Out = "",
    [int] $TimeoutSec = 60
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$global:ProgressPreference = "SilentlyContinue"

if (-not $Out) {
    $Out = Join-Path $PSScriptRoot "regression-report.md"
}
$CasesPath = Join-Path $PSScriptRoot "regression-cases.json"
if (-not (Test-Path $CasesPath)) { throw "Missing $CasesPath" }
$Cases = Get-Content $CasesPath -Raw -Encoding UTF8 | ConvertFrom-Json

$results = New-Object System.Collections.Generic.List[object]
$callId = 0

function Get-AuthHeaders {
    $headers = @{ "Accept" = "application/json" }
    if ($Username) {
        $pair = "$Username`:$Password"
        $bytes = [Text.Encoding]::UTF8.GetBytes($pair)
        $headers["Authorization"] = "Basic " + [Convert]::ToBase64String($bytes)
    }
    return $headers
}

function Invoke-MCPRaw {
    param([string] $BodyJson, [string] $Label, [switch] $ExpectToolError)
    $script:callId++
    $headers = Get-AuthHeaders
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    $err = ""
    $snippet = ""
    try {
        $bodyBytes = [Text.Encoding]::UTF8.GetBytes($BodyJson)
        $resp = Invoke-RestMethod -Method Post -Uri $BaseUrl -Headers $headers `
            -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec $TimeoutSec
        if ($resp.error) {
            $err = "$($resp.error.code): $($resp.error.message)"
        } else {
            $ok = $true
            $payload = $resp.result
            if ($payload -and $payload.PSObject.Properties.Name -contains "isError") {
                if ($payload.isError -and -not $ExpectToolError) {
                    $ok = $false
                    $err = "tool isError=true"
                    if ($payload.content -and $payload.content.Count -gt 0) {
                        $err += ": $($payload.content[0].text.Substring(0, [Math]::Min(180, $payload.content[0].text.Length)))"
                    }
                } elseif (-not $payload.isError -and $ExpectToolError) {
                    $ok = $false
                    $err = "expected tool error but isError=false"
                }
            }
            if ($payload) {
                $json = $payload | ConvertTo-Json -Depth 4 -Compress
                $snippet = $json.Substring(0, [Math]::Min(200, $json.Length))
            }
        }
    } catch {
        $err = $_.Exception.Message
    }
    $sw.Stop()
    $results.Add([pscustomobject]@{
        Method     = "rpc"
        Label      = $Label
        Ok         = $ok
        DurationMs = $sw.ElapsedMilliseconds
        Error      = $err
        Snippet    = $snippet
    })
    return $resp
}

function Invoke-RPC {
    param([string] $Method, [object] $Params, [string] $Label, [switch] $ExpectToolError)
    $body = @{ jsonrpc = "2.0"; id = $script:callId + 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    return Invoke-MCPRaw -BodyJson $body -Label $Label -ExpectToolError:$ExpectToolError
}

function Invoke-Tool {
    param([string] $Name, [object] $Arguments, [switch] $ExpectToolError, [switch] $ExpectValidFalse)
    $resp = Invoke-RPC -Method "tools/call" -Params @{ name = $Name; arguments = $Arguments } -Label $Name -ExpectToolError:$ExpectToolError
    if ($ExpectValidFalse -and $resp -and $resp.result -and -not $resp.result.isError) {
        $text = $resp.result.content[0].text
        if ($text -notmatch "valid.*false|'valid'\s*:\s*false") {
            $last = $results[$results.Count - 1]
            $last.Ok = $false
            $last.Error = "expected valid=false in response"
        }
    }
    return $resp
}

Write-Host "=== LN_MCP_1C regression ===" -ForegroundColor Cyan
Write-Host "Endpoint: $BaseUrl"

foreach ($rpc in $Cases.rpc) {
    Invoke-RPC -Method $rpc.method -Params $rpc.params -Label $rpc.label
}

$ExtensionRoot = Split-Path $PSScriptRoot -Parent
$RepoRoot = Split-Path (Split-Path $ExtensionRoot -Parent) -Parent
Invoke-Tool -Name "set_setting" -Arguments @{
    key = "config_dump_path"; value = $RepoRoot; description = "regression config dump path"
}

foreach ($tool in $Cases.tools) {
    $expectErr = [bool]$tool.expect_tool_error
    if ($tool.name -eq "execute_dcs") { $expectErr = $true }
    $expectValidFalse = [bool]$tool.expect_valid_false
    Invoke-Tool -Name $tool.name -Arguments $tool.arguments -ExpectToolError:$expectErr -ExpectValidFalse:$expectValidFalse
}

# batch JSON-RPC
$batch = @(
    @{ jsonrpc = "2.0"; id = 1001; method = "tools/list"; params = @{} },
    @{ jsonrpc = "2.0"; id = 1002; method = "resources/list"; params = @{} },
    @{ jsonrpc = "2.0"; id = 1003; method = "prompts/list"; params = @{} }
)
$batchJson = '[' + (($batch | ForEach-Object { $_ | ConvertTo-Json -Depth 12 -Compress }) -join ',') + ']'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$batchOk = $false
$batchErr = ""
$batchCount = 0
try {
    $headers = Get-AuthHeaders
    $batchBytes = [Text.Encoding]::UTF8.GetBytes($batchJson)
    $batchResp = Invoke-WebRequest -Method Post -Uri $BaseUrl -Headers $headers `
        -ContentType "application/json; charset=utf-8" -Body $batchBytes -TimeoutSec $TimeoutSec
    $content = $batchResp.Content.Trim()
    if ($content.StartsWith('[')) {
        $parsed = $content | ConvertFrom-Json
        $batchOk = $true
        $batchCount = @($parsed).Count
    } else { $batchErr = "response is not JSON array" }
} catch { $batchErr = $_.Exception.Message }
$sw.Stop()
$results.Add([pscustomobject]@{ Method = "batch"; Label = "batch x$batchCount"; Ok = $batchOk; DurationMs = $sw.ElapsedMilliseconds; Error = $batchErr; Snippet = "" })

# dynamic resources from index
try {
    $idxResp = Invoke-RPC -Method "resources/read" -Params @{ uri = "ln-mcp://ln/_index.json" } -Label "resource:ln_index_dyn"
    $idxText = $idxResp.result.contents[0].text
    $idx = $idxText | ConvertFrom-Json
    foreach ($key in @("common_modules", "roles", "dcs_schemas", "mxl_templates")) {
        $arr = $idx.$key
        if ($arr -and $arr.Count -gt 0 -and $arr[0].address) {
            Invoke-RPC -Method "resources/read" -Params @{ uri = $arr[0].address } -Label "resource:$key"
        }
    }
} catch {}

# health
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$healthOk = $false
$healthErr = ""
try {
    $healthUrl = $BaseUrl -replace "/hs/mcp/rpc$", "/hs/mcp/health"
    $h = Invoke-RestMethod -Method Get -Uri $healthUrl -Headers (Get-AuthHeaders) -TimeoutSec $TimeoutSec
    if ($h.status -eq "ok") { $healthOk = $true } else { $healthErr = "status=$($h.status)" }
} catch { $healthErr = $_.Exception.Message }
$sw.Stop()
$results.Add([pscustomobject]@{ Method = "GET"; Label = "health"; Ok = $healthOk; DurationMs = $sw.ElapsedMilliseconds; Error = $healthErr; Snippet = "" })

# report
$pass = ($results | Where-Object Ok).Count
$fail = ($results.Count - $pass)
$total = $results.Count
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# LN_MCP_1C regression report")
$lines.Add("")
$lines.Add("- Endpoint: $BaseUrl")
$lines.Add("- Timestamp: " + (Get-Date -Format "o"))
$lines.Add("- Total: $total | Pass: $pass | Fail: $fail")
$lines.Add("")
$lines.Add("| # | Label | OK | ms | Error |")
$lines.Add("|---|-------|----|----|-------|")
$i = 0
foreach ($r in $results) {
    $i++
    $status = if ($r.Ok) { "OK" } else { "FAIL" }
    $errCol = ($r.Error -replace "\|", "/" -replace "\r?\n", " ")
    $label = ($r.Label -replace "\|", "/")
    $lines.Add("| $i | $label | $status | $($r.DurationMs) | $errCol |")
}
$lines.Add("")
$lines.Add("## Failures detail")
foreach ($r in ($results | Where-Object { -not $_.Ok })) {
    $lines.Add("- **$($r.Label)**: $($r.Error)")
    if ($r.Snippet) { $lines.Add("  - snippet: ``$($r.Snippet)``") }
}
($lines -join [Environment]::NewLine) | Out-File -FilePath $Out -Encoding utf8

Write-Host ""
Write-Host "Report: $Out" -ForegroundColor Green
$color = if ($fail -gt 0) { "Yellow" } else { "Green" }
Write-Host "Pass:$pass Fail:$fail Total:$total" -ForegroundColor $color
if ($fail -gt 0) { exit 1 } else { exit 0 }
