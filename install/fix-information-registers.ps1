# Добавляет блок <InternalInfo> с 7 <xr:GeneratedType> во все XML-манифесты
# InformationRegister'ов расширения LN_MCP_1C.
#
# Платформа 1С требует InternalInfo для информационных регистров — он описывает
# 7 связанных типов: Record, Manager, Selection, List, RecordSet, RecordKey,
# RecordManager. БЕЗ него /LoadConfigFromFiles падает с ошибкой:
#   "Отсутствует внутренняя информация (узел InternalInfo) для объекта InformationRegister"
#
# Идемпотентно: если InternalInfo уже есть — файл не трогается.
#
# Запуск:
#   pwsh -File install\fix-information-registers.ps1

[CmdletBinding()]
param(
    [string]$ExtensionRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ExtensionRoot) {
    $ExtensionRoot = Split-Path $PSScriptRoot -Parent
}
$registersDir = Join-Path $ExtensionRoot "InformationRegisters"
if (-not (Test-Path $registersDir)) { throw "InformationRegisters не найден: $registersDir" }

# Категории типов для информационного регистра.
$categories = @(
    "Record", "Manager", "Selection", "List", "RecordSet", "RecordKey", "RecordManager"
)

Write-Host "Сканирую: $registersDir" -ForegroundColor Cyan
Write-Host ""

$files = Get-ChildItem -Path $registersDir -Filter *.xml
$added = 0
$skipped = 0

foreach ($file in $files) {
    $rel = $file.FullName.Substring($ExtensionRoot.Length+1)
    $text = Get-Content -Path $file.FullName -Raw -Encoding UTF8

    # Уже есть <InternalInfo> с <xr:GeneratedType>? — пропускаем.
    if ($text -match "<InternalInfo>\s*<xr:GeneratedType") {
        Write-Host "  = $rel : уже есть" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    # Извлекаем имя регистра из <Name>...</Name>
    if ($text -notmatch "<InformationRegister[^>]*>") {
        Write-Host "  ! $rel : не InformationRegister, пропуск" -ForegroundColor Yellow
        $skipped++
        continue
    }
    if ($text -notmatch "<Name>([^<]+)</Name>") {
        Write-Host "  ! $rel : не найдено <Name>" -ForegroundColor Yellow
        $skipped++
        continue
    }
    $registerName = $matches[1]

    # Строим InternalInfo
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("`t`t<InternalInfo>`r`n")
    foreach ($cat in $categories) {
        $typeId  = ([guid]::NewGuid()).ToString()
        $valueId = ([guid]::NewGuid()).ToString()
        [void]$sb.Append("`t`t`t<xr:GeneratedType name=`"InformationRegister$cat.$registerName`" category=`"$cat`">`r`n")
        [void]$sb.Append("`t`t`t`t<xr:TypeId>$typeId</xr:TypeId>`r`n")
        [void]$sb.Append("`t`t`t`t<xr:ValueId>$valueId</xr:ValueId>`r`n")
        [void]$sb.Append("`t`t`t</xr:GeneratedType>`r`n")
    }
    [void]$sb.Append("`t`t</InternalInfo>`r`n")
    $internalInfoBlock = $sb.ToString()

    # Вставляем сразу перед <Properties> регистра (первое вхождение Properties в файле — корневое).
    # Узор: ровно "\t\t<Properties>" — это уровень в дереве объекта.
    if ($text -match "(?m)^\t\t<Properties>") {
        $newText = [Regex]::Replace($text, "(?m)^(\t\t<Properties>)", $internalInfoBlock + '$1', 1)
        [System.IO.File]::WriteAllText($file.FullName, $newText, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  + $rel : InternalInfo для '$registerName' добавлен" -ForegroundColor Green
        $added++
    } else {
        Write-Host "  ! $rel : не найдено корневое <Properties>" -ForegroundColor Red
        $skipped++
    }
}

Write-Host ""
Write-Host "Итого: добавлено=$added, пропущено=$skipped" -ForegroundColor Cyan
