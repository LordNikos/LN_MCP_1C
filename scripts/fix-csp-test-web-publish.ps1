# Fix CSP_TEST Apache publication when path contains a space.
# Symptom: POST /e1cib/login -> E:\C1\Bazes\ЦСП\1Cv8.1CD not found (truncated at space).
#Requires -Version 5.1
param(
    [string]$InfobasePath = "",
    [string]$JunctionPath = "E:\C1\Bazes\CSP_TEST",
    [string]$VrdPath = "E:\IBT\CSP_TEST_Web\default.vrd",
    [string]$ApacheHttpd = "C:\Program Files\Apache Software Foundation\Apache2.4\bin\httpd.exe"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DevEnv = Join-Path (Resolve-Path (Join-Path $ScriptDir "..\..\..")).Path ".dev.env"

if (-not $InfobasePath -and (Test-Path $DevEnv)) {
    Get-Content $DevEnv -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^\s*INFOBASE_PATH\s*=\s*(.+)$') { $InfobasePath = $Matches[1].Trim() }
    }
}

if (-not $InfobasePath) {
    throw "Set INFOBASE_PATH in .dev.env or pass -InfobasePath"
}

$dbFile = Join-Path $InfobasePath "1Cv8.1CD"
if (-not (Test-Path -LiteralPath $dbFile)) {
    throw "Infobase not found: $dbFile"
}

if (-not (Test-Path -LiteralPath $JunctionPath)) {
    New-Item -ItemType Junction -Path $JunctionPath -Target $InfobasePath -Force | Out-Null
    Write-Host "Created junction: $JunctionPath -> $InfobasePath"
} else {
    Write-Host "Junction exists: $JunctionPath"
}

if (-not (Test-Path $VrdPath)) {
    throw "Publication file not found: $VrdPath"
}

$vrd = Get-Content $VrdPath -Raw -Encoding UTF8
$newIb = 'ib="File=&quot;' + ($JunctionPath -replace '\\', '\') + '&quot;;"'
if ($vrd -match 'ib="File=&quot;[^"]*&quot;;"') {
    $vrd = [regex]::Replace($vrd, 'ib="File=&quot;[^"]*&quot;;"', $newIb, 1)
} else {
    throw "Could not find ib= attribute in $VrdPath"
}

$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($VrdPath, $vrd, $utf8Bom)
Write-Host "Updated: $VrdPath"
Write-Host "  ib -> File=`"$JunctionPath`";"

if (Test-Path $ApacheHttpd) {
    & $ApacheHttpd -k restart | Out-Null
    Write-Host "Apache restarted."
} else {
    Write-Host "Apache not found at $ApacheHttpd - restart manually."
}

Write-Host "Check: http://localhost:81/CSP_TEST/ru/"
