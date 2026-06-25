# Нормализует <ObjectBelonging> во всех XML расширения LN_MCP_1C по эталону
# пустого Customization-расширения (см. E:\IBT\BazesXML\CSPXML\Расширение2):
#
#   - Configuration.xml             -> <ObjectBelonging>Adopted</ObjectBelonging>
#   - Languages\Русский.xml         -> <ObjectBelonging>Adopted</ObjectBelonging>
#   - все остальные XML объектов    -> УДАЛИТЬ <ObjectBelonging> вовсе
#     (платформа сама считает их Own; явно указанное <ObjectBelonging>Own</…>
#      приводит к ошибке "Загрузка не должна менять принадлежность основного
#      объекта конфигурации" в Customization-расширении).
#
# Идемпотентно: повторный запуск не сломает.
#
# Запуск:
#   pwsh -File install\fix-object-belonging.ps1

[CmdletBinding()]
param(
    [string]$ExtensionRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ExtensionRoot) {
    $ExtensionRoot = Split-Path $PSScriptRoot -Parent
}
if (-not (Test-Path $ExtensionRoot)) { throw "Папка расширения не найдена: $ExtensionRoot" }

Write-Host "Сканирую: $ExtensionRoot" -ForegroundColor Cyan
Write-Host ""

$xmlFiles = Get-ChildItem -Path $ExtensionRoot -Recurse -Filter *.xml |
    Where-Object {
        $skip = ($_.Name -eq "ConfigDumpInfo.xml") -or
                ($_.Name -eq "Form.xml") -or
                ($_.Name -eq "Predefined.xml") -or
                ($_.FullName -match "\\Forms\\.*\\Ext\\") -or
                ($_.FullName -match "\\Templates\\")
        -not $skip
    }

$adoptedKept = 0
$ownRemoved  = 0
$noChange    = 0
$adoptedSet  = 0

foreach ($file in $xmlFiles) {
    $rel = $file.FullName.Substring($ExtensionRoot.Length+1)
    $text = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $orig = $text

    # 1) Configuration.xml — должен быть Adopted
    if ($rel -ieq "Configuration.xml") {
        if ($text -match "<ObjectBelonging>Own</ObjectBelonging>") {
            $text = $text -replace "<ObjectBelonging>Own</ObjectBelonging>", "<ObjectBelonging>Adopted</ObjectBelonging>"
            Write-Host "  ~ $rel : Own -> Adopted" -ForegroundColor Yellow
            $adoptedSet++
        } elseif ($text -notmatch "<ObjectBelonging>") {
            Write-Host "  ! $rel : нет <ObjectBelonging>, добавь вручную Adopted" -ForegroundColor Red
        } else {
            $adoptedKept++
        }
    }
    # 2) Languages\Русский.xml — должен быть Adopted
    elseif ($rel -ilike "Languages\*") {
        if ($text -match "<ObjectBelonging>Own</ObjectBelonging>") {
            $text = $text -replace "<ObjectBelonging>Own</ObjectBelonging>", "<ObjectBelonging>Adopted</ObjectBelonging>"
            Write-Host "  ~ $rel : Own -> Adopted" -ForegroundColor Yellow
            $adoptedSet++
        } else {
            $adoptedKept++
        }
    }
    # 3) Все остальные XML — УБРАТЬ <ObjectBelonging>
    else {
        if ($text -match "<ObjectBelonging>(Own|Adopted)</ObjectBelonging>") {
            # Удаляем строку целиком (вместе с отступом и переводом строки)
            $text = [Regex]::Replace($text, "[ \t]*<ObjectBelonging>(Own|Adopted)</ObjectBelonging>\r?\n", "")
            Write-Host "  - $rel : ObjectBelonging удалён" -ForegroundColor Green
            $ownRemoved++
        } else {
            $noChange++
        }
    }

    if ($text -ne $orig) {
        [System.IO.File]::WriteAllText($file.FullName, $text, (New-Object System.Text.UTF8Encoding($false)))
    }
}

Write-Host ""
Write-Host "Итого:" -ForegroundColor Cyan
Write-Host "  Adopted уже стоял        : $adoptedKept"
Write-Host "  Adopted поправлен        : $adoptedSet"
Write-Host "  ObjectBelonging удалён   : $ownRemoved"
Write-Host "  Без изменений            : $noChange"
