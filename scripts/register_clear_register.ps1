<#
.SYNOPSIS
  Регистрирует пользовательский MCP-tool "clear_register" в базе 1C с расширением LN_MCP_1C.

.PARAMETER BaseUrl
  URL веб-публикации базы, например http://localhost:81/PPKSIP_2
  (без /hs/mcp/... — скрипт сам подставит путь).

.PARAMETER User
  Логин пользователя 1C (Basic Auth).

.PARAMETER Password
  Пароль пользователя 1C.

.PARAMETER ToolName
  Имя tool'а. По умолчанию "clear_register". Можно задать своё, чтобы
  регистрировать несколько независимых копий.

.EXAMPLE
  .\register_clear_register.ps1 -BaseUrl "http://localhost:81/PPKSIP_2" -User IBT -Password "хъ"
  .\register_clear_register.ps1 -BaseUrl "http://localhost:81/OtherBase"  -User IBT -Password "secret"
#>
param(
    [Parameter(Mandatory=$true)] [string] $BaseUrl,
    [Parameter(Mandatory=$true)] [string] $User,
    [Parameter(Mandatory=$true)] [string] $Password,
    [string] $ToolName = "clear_register"
)

$ErrorActionPreference = "Stop"

$BaseUrl = $BaseUrl.TrimEnd('/')
$RpcUrl  = "$BaseUrl/hs/mcp/rpc"
$Health  = "$BaseUrl/hs/mcp/health"

$auth = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$User`:$Password"))
$headers = @{ Authorization = $auth; "Content-Type" = "application/json; charset=utf-8" }

function Invoke-Mcp([hashtable]$payload, [int]$timeoutSec = 120) {
    $json   = $payload | ConvertTo-Json -Depth 12 -Compress
    $bytes  = [Text.Encoding]::UTF8.GetBytes($json)
    $resp   = Invoke-WebRequest -Uri $RpcUrl -Method Post -Headers $headers -Body $bytes -TimeoutSec $timeoutSec -UseBasicParsing
    return ($resp.Content | ConvertFrom-Json)
}

# 1) Healthcheck
try {
    $h = Invoke-WebRequest -Uri $Health -Headers $headers -TimeoutSec 20 -UseBasicParsing
    Write-Host "Health: $($h.Content)" -ForegroundColor DarkGray
} catch {
    throw "Healthcheck failed on $Health : $($_.Exception.Message). Проверьте публикацию и доступность базы."
}

# 2) Код tool'а
$code = @'
Имя = Аргументы.name;
Если СтрНачинаетсяС(Имя, "РегистрСведений.") Тогда
    Имя = Сред(Имя, СтрДлина("РегистрСведений.") + 1);
КонецЕсли;
ИмяТипа = "РегистрСведенийНаборЗаписей." + Имя;
НЗ = Новый(Тип(ИмяТипа));
НЗ.Записать();
Запрос = Новый Запрос;
Запрос.Текст = "ВЫБРАТЬ КОЛИЧЕСТВО(*) КАК Осталось ИЗ РегистрСведений." + Имя;
Выборка = Запрос.Выполнить().Выбрать();
Выборка.Следующий();
Результат = Новый Структура("Регистр, Осталось", Имя, Выборка.Осталось);
'@

$schema = '{"type":"object","properties":{"name":{"type":"string","description":"Имя регистра сведений, например ВерсииОбъектов (можно с префиксом РегистрСведений.)"}},"required":["name"]}'

# 3) Регистрация (идемпотентно: update_tool если уже есть, иначе register_tool)
$toolArgs = @{
    name          = $ToolName
    description   = "Очистка регистра сведений по имени: удаляет все записи одной транзакцией через пустой НаборЗаписей без отбора. Возвращает имя регистра и сколько записей осталось."
    input_schema  = $schema
    code          = $code
    safe_mode     = $false
    active        = $true
}

$lst0 = Invoke-Mcp -payload @{ jsonrpc="2.0"; id=10; method="tools/call"; params=@{ name="list_custom_tools"; arguments=@{} } }
$exists = ($lst0.result.content[0].text -match "'name':\s*'$ToolName'")
$action = if ($exists) { "update_tool" } else { "register_tool" }
Write-Host "Action: $action (exists=$exists)" -ForegroundColor DarkGray

$payload = @{
    jsonrpc = "2.0"; id = 1; method = "tools/call"
    params  = @{ name = $action; arguments = $toolArgs }
}

$r = Invoke-Mcp -payload $payload
if ($r.result.isError) {
    Write-Host "$action FAILED:" -ForegroundColor Red
    Write-Host $r.result.content[0].text
    exit 1
}
Write-Host "$action -> $($r.result.content[0].text)" -ForegroundColor Green

# 4) Проверка — list_custom_tools
$lst = Invoke-Mcp -payload @{ jsonrpc="2.0"; id=2; method="tools/call"; params=@{ name="list_custom_tools"; arguments=@{} } }
Write-Host "Custom tools:" -ForegroundColor Cyan
$lst.result.content[0].text

# 5) Тестовый вызов на уже очищенном/пустом регистре (вернёт Осталось)
$test = Invoke-Mcp -payload @{ jsonrpc="2.0"; id=3; method="tools/call"; params=@{ name=$ToolName; arguments=@{ name="ВерсииОбъектов" } } } 600
Write-Host "Self-test call:" -ForegroundColor Cyan
$test.result.content[0].text

Write-Host "`nГотово. В Cursor добавьте в .cursor/mcp.json запись:" -ForegroundColor Yellow
Write-Host "  { `"url`": `"$RpcUrl`", `"transport`": `"http`", `"headers`": { `"Authorization`": `"$auth`" } }"
