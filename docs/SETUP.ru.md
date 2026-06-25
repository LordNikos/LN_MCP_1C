# Установка LN_MCP_1C и подключение Cursor

Пошаговая инструкция для нового разработчика. Время: ~30–60 минут при первой установке.

## Что получится

- Расширение **LN_MCP_1C** в вашей информационной базе
- HTTP-эндпоинт MCP: `http://ваш-хост/публикация/hs/mcp/rpc`
- Cursor видит **27+ tools** и может работать с живой ИБ

## Требования

| Компонент | Минимум |
|-----------|---------|
| Платформа 1С | 8.3.20+ |
| Конфигурация | Любая, допускающая расширения |
| Веб-сервер | Apache 2.4 + `wsap24.dll` или IIS |
| Cursor | С поддержкой MCP HTTP (`url` + `headers`) |

## Шаг 1. Клонировать репозиторий

```powershell
git clone https://github.com/LordNikos/LN_MCP_1C.git
cd LN_MCP_1C
```

## Шаг 2. Подготовить окружение

```powershell
copy .dev.env.example .dev.env
notepad .dev.env
```

Заполните:

```ini
PLATFORM_PATH=C:\Program Files\1cv8\8.3.24.1691
INFOBASE_PATH=C:\Path\To\Your\Infobase
```

`IB_USER` / `IB_PASSWORD` — только если ИБ с аутентификацией.

## Шаг 3. Загрузить расширение в ИБ

**Закройте конфигуратор**, затем:

```powershell
powershell -ExecutionPolicy Bypass -File install\install.ps1
```

Или вручную в конфигураторе:

1. Конфигурация → Расширения → Добавить → Загрузить из файлов
2. Указать каталог с `Configuration.xml` (корень репозитория)
3. **F7** — обновить конфигурацию БД

### После смены VERSION

```powershell
powershell -File install\fix-extension-manifest.ps1
# затем F7
```

## Шаг 4. Права пользователя MCP

Пользователю, под которым ходит HTTP-публикация, назначьте роль:

**`LN_МСРРольПолныйДоступ`**

## Шаг 5. Веб-публикация

1. Скопируйте `publish\default.vrd.example` в каталог публикации как `default.vrd`
2. Отредактируйте:
   - **`base`** — префикс URL (например `/CSP_TEST`)
   - **`ib`** — строка подключения к ИБ
   - **`rootUrl="mcp"`** — не менять (совпадает с HTTP-сервисом расширения)

Пример итогового URL:

```
http://localhost:81/CSP_TEST/hs/mcp/rpc
```

3. Настройте Apache — см. `publish\httpd.conf.snippet`
4. Перезапустите веб-сервер

### Проверка health

```powershell
Invoke-RestMethod "http://localhost:81/CSP_TEST/hs/mcp/health"
```

Ожидание: `status: ok`

## Шаг 6. Подключить Cursor

В **корне вашего рабочего проекта** (не обязательно в репозитории LN_MCP_1C):

```powershell
mkdir .cursor -Force
copy path\to\LN_MCP_1C\.cursor\mcp.json.example .cursor\mcp.json
```

Отредактируйте `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "ln-mcp": {
      "url": "http://localhost:81/CSP_TEST/hs/mcp/rpc",
      "headers": {
        "Authorization": "Basic ВАШ_BASE64"
      }
    }
  }
}
```

### Base64 для Basic Auth

```powershell
$user = "Администратор"
$pass = ""
$bytes = [Text.Encoding]::UTF8.GetBytes("${user}:${pass}")
[Convert]::ToBase64String($bytes)
```

Подставьте результат в `"Authorization": "Basic ..."`.

**Важно:** используйте прямой `url` — без `mcp-remote`, без Node-прокси.

Reload Window в Cursor → MCP должен стать зелёным.

## Шаг 7. Диагностика

```powershell
powershell -File tests\diagnose-cursor-mcp.ps1 `
  -BaseUrl "http://localhost:81/CSP_TEST/hs/mcp/rpc" `
  -Username "Администратор" `
  -Password ""
```

| Результат | Значение |
|-----------|----------|
| GET → 405 | OK |
| initialize Cursor payload | OK |
| tools/list → 27+ | OK |

## Шаг 8. Начать работу

В новом чате Cursor:

> Используй MCP ln-mcp. Задача: …

Промпты и ресурсы настраивать не нужно — агент вызывает tools сам.

### Опциональные настройки (tool `set_setting`)

| Ключ | Зачем |
|------|-------|
| `config_dump_path` | Путь к XML-дампу конфигурации для `read_form_xml` |
| `execute_code_default_safe` | `"true"` — безопасный режим `execute_code` по умолчанию |

## Частые проблемы

| Проблема | Решение |
|----------|---------|
| Parse error при initialize | Загрузите расширение ≥ 1.0.18, F7, перезапуск веб |
| Connection closed | Прямой HTTP в mcp.json, проверьте Auth |
| 404 на /hs/mcp/rpc | Проверьте `base` и что сервис `mcp_APIBackend` опубликован |
| 28 tools вместо 27 | Старая версия в ИБ — F7 после pull |

## Для AI-агента в Cursor

Если просите агента установить MCP — укажите:

> Прочитай `AGENTS.md` и `.cursor/rules/ln-mcp-install.mdc` в репозитории LN_MCP_1C

## Полный regression-тест

```powershell
powershell -File tests\regression.ps1 `
  -BaseUrl "http://localhost:81/CSP_TEST/hs/mcp/rpc" `
  -Username "Администратор" `
  -Password ""
```
