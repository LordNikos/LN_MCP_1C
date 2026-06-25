# Sync extension manifest before load:
#   - <Version> from Extensions/LN_MCP_1C/VERSION
#   - <ConfigurationExtensionCompatibilityMode> from repo .dev.env PLATFORM_VERSION
#   - <Privileged>false</Privileged> in all CommonModules (extensions forbid privileged CM)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install\fix-extension-manifest.ps1

[CmdletBinding()]
param(
    [string]$ExtensionRoot = "",
    [string]$RepoRoot = "",
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

if (-not $ExtensionRoot) {
    $ExtensionRoot = Split-Path $PSScriptRoot -Parent
}
if (-not $RepoRoot) {
    $RepoRoot = Split-Path (Split-Path $ExtensionRoot -Parent) -Parent
}

function Get-DevEnvValue($name) {
    $devEnv = Join-Path $RepoRoot ".dev.env"
    if (-not (Test-Path $devEnv)) { return "" }
    $line = (Get-Content $devEnv -Encoding UTF8) | Where-Object { $_ -match "^\s*$name\s*=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return ($line -replace "^\s*$name\s*=\s*", "").Trim()
}

function ConvertTo-CompatibilityMode($platformVersion) {
    if (-not $platformVersion) { return "Version8_3_27" }
    $parts = $platformVersion -split "\."
    if ($parts.Count -ge 3) {
        return "Version8_3_$($parts[2])"
    }
    if ($parts.Count -eq 2) {
        return "Version8_3_$($parts[1])"
    }
    return "Version8_3_27"
}

function Set-XmlTagValue([string]$text, [string]$tag, [string]$value) {
    $pattern = "(?s)(<$tag>)(.*?)(</$tag>)"
    if ($text -notmatch $pattern) {
        throw "Tag <$tag> not found"
    }
    return [Regex]::Replace($text, $pattern, "<$tag>$value</$tag>", 1)
}

if (-not $Version) {
    $versionFile = Join-Path $ExtensionRoot "VERSION"
    if (Test-Path $versionFile) {
        $Version = (Get-Content $versionFile -Encoding UTF8 | Select-Object -First 1).Trim()
    }
}
if (-not $Version) { $Version = "1.0.0" }

$compatMode = ConvertTo-CompatibilityMode (Get-DevEnvValue "PLATFORM_VERSION")
$configPath = Join-Path $ExtensionRoot "Configuration.xml"
if (-not (Test-Path $configPath)) { throw "Configuration.xml not found: $configPath" }

Write-Host "Manifest sync:" -ForegroundColor Cyan
Write-Host "  Version      : $Version"
Write-Host "  Compatibility: $compatMode"

$configText = Get-Content $configPath -Raw -Encoding UTF8
$configText = Set-XmlTagValue $configText "Version" $Version
$configText = Set-XmlTagValue $configText "ConfigurationExtensionCompatibilityMode" $compatMode
$configText = Set-XmlTagValue $configText "Comment" "LordNikos / LN_MCP_1C v$Version. MCP-сервер для 1С внутри расширения."
[System.IO.File]::WriteAllText($configPath, $configText, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  Configuration.xml updated" -ForegroundColor Green

$cmDir = Join-Path $ExtensionRoot "CommonModules"
if (Test-Path $cmDir) {
    $fixed = 0
    foreach ($file in Get-ChildItem $cmDir -Filter *.xml) {
        $text = Get-Content $file.FullName -Raw -Encoding UTF8
        if ($text -match "<Privileged>true</Privileged>") {
            $text = $text -replace "<Privileged>true</Privileged>", "<Privileged>false</Privileged>"
            [System.IO.File]::WriteAllText($file.FullName, $text, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  Privileged=false: $($file.Name)" -ForegroundColor Green
            $fixed++
        }
    }
    if ($fixed -eq 0) {
        Write-Host "  CommonModules: Privileged already false" -ForegroundColor DarkGray
    }
}

Write-Host "Done." -ForegroundColor Cyan
