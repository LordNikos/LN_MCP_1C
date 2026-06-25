# LN_MCP_1C installer - load extension from XML sources into infobase.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install\install.ps1
#   powershell -ExecutionPolicy Bypass -File install\install.ps1 -Reset
#   powershell -ExecutionPolicy Bypass -File install\install.ps1 -ExportCfe
#
# Close Configurator before run.

[CmdletBinding()]
param(
    [string]$SourcesDir = "",
    [string]$PlatformPath = "",
    [string]$InfobasePath = "",
    [string]$ExtensionName = "LN_MCP_1C",
    [string]$User = "",
    [string]$Password = "",
    [string]$LogFile = "",
    [switch]$Reset,
    [switch]$SkipFixBelonging,
    [switch]$SkipLoad,
    [switch]$SkipUpdateDB,
    [switch]$ExportCfe,
    [string]$CfeOut = ""
)

$ErrorActionPreference = "Stop"

$ExtensionRoot = Split-Path $PSScriptRoot -Parent
# Standalone repo: .dev.env in extension root. Nested in monorepo: repo root .dev.env
$DevEnvPath = Join-Path $ExtensionRoot ".dev.env"
if (-not (Test-Path $DevEnvPath)) {
    $MaybeRepo = Split-Path $ExtensionRoot -Parent
    $DevEnvPath = Join-Path (Split-Path $MaybeRepo -Parent) ".dev.env"
}
if (-not $SourcesDir) { $SourcesDir = $ExtensionRoot }

function Get-DevEnv($name) {
    if (-not (Test-Path $DevEnvPath)) { return "" }
    $line = (Get-Content $DevEnvPath -Encoding UTF8) | Where-Object { $_ -match "^\s*$name\s*=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return ($line -replace "^\s*$name\s*=\s*", "").Trim()
}

if (-not $PlatformPath) { $PlatformPath = Get-DevEnv "PLATFORM_PATH" }
if (-not $InfobasePath) { $InfobasePath = Get-DevEnv "INFOBASE_PATH" }
if (-not $LogFile) { $LogFile = Join-Path $env:TEMP "1cv8-LN_MCP_1C.log" }

if (-not $PlatformPath) { throw "PLATFORM_PATH is not set" }
if (-not $InfobasePath) { throw "INFOBASE_PATH is not set" }
if (-not (Test-Path $SourcesDir)) { throw "Sources dir not found: $SourcesDir" }
if (-not (Test-Path (Join-Path $SourcesDir "Configuration.xml"))) {
    throw "Configuration.xml not found in $SourcesDir"
}

$Exe = Join-Path $PlatformPath "bin\1cv8.exe"
if (-not (Test-Path $Exe)) { throw "1cv8.exe not found: $Exe" }

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LN_MCP_1C installer"
Write-Host " Platform : $PlatformPath"
Write-Host " Infobase : $InfobasePath"
Write-Host " Sources  : $SourcesDir"
Write-Host " Extension: $ExtensionName"
Write-Host " Log      : $LogFile"
Write-Host "============================================================" -ForegroundColor Cyan

$AuthArgs = @()
if ($User) { $AuthArgs += @("/N`"$User`"") }
if ($Password) { $AuthArgs += @("/P`"$Password`"") }
$IbArgs = @("DESIGNER", "/F`"$InfobasePath`"") + $AuthArgs + @("/DisableStartupDialogs", "/DisableStartupMessages", "/Out`"$LogFile`"")

function Invoke-Designer($extraArgs, $label) {
    $args = $IbArgs + $extraArgs
    Write-Host "[$label] $Exe $($args -join ' ')" -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $Exe -ArgumentList $args -NoNewWindow -Wait -PassThru
    $tail = ""
    if (Test-Path $LogFile) {
        $tail = (Get-Content $LogFile -Encoding Default -ErrorAction SilentlyContinue | Select-Object -Last 40) -join "`n"
    }
    if ($proc.ExitCode -ne 0) {
        Write-Host "FAILED exit code $($proc.ExitCode)" -ForegroundColor Red
        if ($tail) { Write-Host "--- log tail ---`n$tail`n---" -ForegroundColor Yellow }
        throw "[$label] DESIGNER failed with exit code $($proc.ExitCode). Log: $LogFile"
    }
    Write-Host "OK" -ForegroundColor Green
}

if (-not $SkipFixBelonging) {
    Write-Host ""
    Write-Host "PRE-STEP-1: fix ObjectBelonging" -ForegroundColor Cyan
    $fixer = Join-Path $PSScriptRoot "fix-object-belonging.ps1"
    if (Test-Path $fixer) { & $fixer -ExtensionRoot $SourcesDir }

    Write-Host ""
    Write-Host "PRE-STEP-2: fix InformationRegister InternalInfo" -ForegroundColor Cyan
    $fixerIR = Join-Path $PSScriptRoot "fix-information-registers.ps1"
    if (Test-Path $fixerIR) { & $fixerIR -ExtensionRoot $SourcesDir }

    Write-Host ""
    Write-Host "PRE-STEP-3: sync extension Version and CompatibilityMode" -ForegroundColor Cyan
    $fixerManifest = Join-Path $PSScriptRoot "fix-extension-manifest.ps1"
    if (Test-Path $fixerManifest) { & $fixerManifest -ExtensionRoot $SourcesDir -RepoRoot $RepoRoot }
}

if ($Reset) {
    Write-Host ""
    Write-Host "STEP 0: delete existing extension $ExtensionName" -ForegroundColor Cyan
    try {
        Invoke-Designer @("/DeleteConfigurationExtension", $ExtensionName) "DeleteExt"
    } catch {
        Write-Host "  extension was not found, continue" -ForegroundColor Yellow
    }
}

if (-not $SkipLoad) {
    Write-Host ""
    Write-Host "STEP 1: LoadConfigFromFiles" -ForegroundColor Cyan
    Invoke-Designer @("/LoadConfigFromFiles", "`"$SourcesDir`"", "-Extension", $ExtensionName) "LoadCfg"
}

if (-not $SkipUpdateDB) {
    Write-Host ""
    Write-Host "STEP 2: UpdateDBCfg" -ForegroundColor Cyan
    Invoke-Designer @("/UpdateDBCfg", "-Extension", $ExtensionName) "UpdateDB"
}

if ($ExportCfe) {
    Write-Host ""
    Write-Host "STEP 3: DumpCfg to cfe" -ForegroundColor Cyan
    if (-not $CfeOut) { $CfeOut = Join-Path $RepoRoot "dist\$ExtensionName.cfe" }
    $cfeDir = Split-Path $CfeOut -Parent
    if (-not (Test-Path $cfeDir)) { New-Item -ItemType Directory -Force -Path $cfeDir | Out-Null }
    Invoke-Designer @("/DumpCfg", "`"$CfeOut`"", "-Extension", $ExtensionName) "DumpCfe"
    Write-Host "  exported: $CfeOut" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Log: $LogFile" -ForegroundColor Green
