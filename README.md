# LN_MCP_1C — MCP-сервер для 1С внутри расширения

Расширение конфигурации 1С, реализующее **Model Context Protocol (MCP)** через стандартную веб-публикацию 1С. Позволяет AI-агентам (Cursor, Claude Desktop, любой MCP-клиент) исполнять запросы и код, читать метаданные, описывать формы, искать ссылки, читать журнал регистрации и проверять права доступа — напрямую в живой инфобазе.

| Метаданные | Значение |
| - | - |
| Автор | LordNikos |
| Версия | 1.0.18 |
| Лицензия | Проприетарная (ядро — MIT vladimir-kharin/1c_mcp) |
| Платформа | 1С:Предприятие 8.3.20+ |
| Назначение | Add-on |
| Префикс новых объектов | `LN_` |

## Что внутри

- **HTTPService `mcp_APIBackend`** (унаследован от vladimir-kharin/1c_mcp, ядро MCP):
  - `POST /mcp/rpc` — JSON-RPC 2.0 (`tools/list`, `tools/call`, `resources/list`, `resources/read`, `prompts/list`, `prompts/get`)
  - `GET /mcp/health` — healthcheck
  - `POST /mcp/*`, `GET /mcp/*` — общий маршрутизатор MCP
- **4 обработки-контейнера** с **13 встроенными tools**.
- **3 регистра сведений**:
  - `LN_МСРНастройки` — формат ответа по умолчанию, лимит символов, политика безопасности `execute_code`.
  - `LN_МСРКэшМетаданных` — TTL-кэш ответов `get_metadata`, `describe_form`, `get_configuration`.
  - `LN_МСРАудитВызовов` — лог каждого вызова tool: длительность, успех, размер ответа.
- **4 общих модуля надстройки**:
  - `LN_МСРКодирование` — сериализация в JSON / JSON-compact / TOON, обрезка длинных строк.
  - `LN_МСРОтветы` — согласование формата, пагинация (page/page_size), HTTP-обёртка.
  - `LN_МСРКэш` — TTL-кэш на регистре сведений.
  - `LN_МСРАудит` — структурный замер времени и логирование в журнал регистрации.
- **Роль `LN_МСРРольПолныйДоступ`** + Rights.xml для всех объектов расширения.

## 24 tools + 5 промптов v1.1 + MCP completion/complete + Batch JSON-RPC + sampling-очередь + tools-as-data

### Контейнер `LN_МСРИнструментЗапросы`
1. **`execute_query`** — выполнить запрос 1С. `query`, `parameters` (object с авто-конвертацией ISO-8601 строк в `Дата` и `{type,uuid}` в ссылки), `limit` (≤10000), `include_schema` (опц.).
2. **`execute_code`** — выполнить BSL. `code`, `safe_mode` (**по умолчанию `false` — ПОЛНОЦЕННЫЙ режим**; включается только явным `safe_mode=true` либо настройкой `execute_code_default_safe`). Ответ содержит `safe_mode_used` для аудита.
3. **`validate_query`** — синтаксический разбор запроса без выполнения. `fast=false` (по умолчанию) — полная валидация через `СхемаЗапроса`; `fast=true` — быстрая через `Запрос.НайтиПараметры()`, возвращает `parameters[]`.

### Контейнер `LN_МСРИнструментМетаданные`
4. **`get_metadata`** — структура объекта МД. `object_name`, `detail_level` (brief / normal / full). Кэш 1 час.
5. **`get_configuration`** — общая информация о конфигурации + счётчики по типам. Кэш 2 часа.
6. **`describe_form`** — реквизиты формы, синонимы, список всех форм объекта.
7. **`list_extensions`** — массив установленных расширений (имя, версия, поставщик, активность, UUID).
8. **`get_bsl_syntax_help`** — поиск по справке встроенного языка.

### Контейнер `LN_МСРИнструментСсылки`
9. **`get_object_by_link`** — объект (реквизиты + ТЧ) по навигационной ссылке `e1cib://...`.
10. **`get_link_of_object`** — построение навигационной ссылки по `object_name + code / description`.
11. **`find_references_to_object`** — `НайтиПоСсылкам` с пагинацией.

### Контейнер `LN_МСРИнструментАдмин`
12. **`get_event_log`** — выгрузка ЖР с курсорной пагинацией (`page_size`, `cursor`). Мульти-фильтры: `levels[]`, `events[]`, `metadata_types[]`, `users[]` (имя/UUID), `computer`, `comment_substring`, `transaction_status`, `start_date`/`end_date`.
13. **`get_last_error`** — компактный шорткат: последняя ошибка ЖР за N часов одной структурой `{found, date, event, metadata, data, comment}`.
14. **`get_access_rights`** — проверка прав текущего/указанного пользователя на объект МД.
15. **`get_setting`** — чтение настройки из `РегистрСведений.LN_МСРНастройки` по ключу.
16. **`set_setting`** — запись/обновление настройки (управление `execute_code_default_safe`, лимитом символов, форматом ответа и пр. без захода в Конфигуратор).
17. **`request_sampling`** — server-side инициированный запрос на сэмплинг LLM (см. ниже sampling-очередь).
18. **`pull_pending_sampling`** — клиент-агент забирает следующий pending-запрос из очереди.
19. **`submit_sampling_result`** — клиент возвращает результат LLM-вызова в очередь.
20. **`get_sampling_result`** — опрос текущего состояния `sample_id`.

### Контейнер `LN_МСРИнструментПользовательские` (tools-as-data)
21. **`register_tool`** — создать пользовательский tool как запись `Справочник.LN_МСРПользовательскиеИнструменты`. Параметры: `name, description, input_schema, code, safe_mode, active`. После регистрации сразу виден в `tools/list`.
22. **`update_tool`** — обновить поля существующего пользовательского tool.
23. **`delete_tool`** — физически удалить пользовательский tool.
24. **`list_custom_tools`** — список всех зарегистрированных пользовательских tools.

#### Как пользователь регистрирует свой tool
```json
{
  "name": "ln_sum",
  "description": "Сумма двух чисел",
  "input_schema": "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"number\"},\"y\":{\"type\":\"number\"}},\"required\":[\"x\",\"y\"]}",
  "code": "Результат = Аргументы.x + Аргументы.y;",
  "safe_mode": false,
  "active": true
}
```
В коде доступны переменные `Аргументы` (Структура входа) и `Результат` (читается обратно). При `safe_mode=true` перед `Выполнить()` вызывается `УстановитьБезопасныйРежим(Истина)`.

### Контейнер `LN_МСРИнструментМетаданные` — дополнение
25. **`read_form_xml`** — читает `Form.xml` (и опционально `Form.Module.bsl`) напрямую с диска из дампа конфигурации. Параметры: `object_name`, `form_name`, `dump_path` (если не задан — берётся из `LN_МСРНастройки.config_dump_path`), `include_module`, `max_chars`. Закрывает пробел `describe_form` про runtime-only состав элементов.

### Контейнер `LN_МСРИнструментЗапросы` — дополнение
26. **`execute_dcs`** — выполнить отчёт СКД. Источник схемы: `xml` (строка), `template` (макет МД, например `Отчет.X.МакетСхема`), `path` (XML-файл на диске). Параметры компоновщика, опц. вариант настроек. Возвращает `columns, rows, row_count, truncated`.

## Новые MCP-методы протокола (помимо tools/list, resources/list, prompts/list)
- **`completion/complete`** — автодополнение значений аргументов prompts/resources. Источники:
  - `object_name` → все объекты МД (`Справочник.X`, `Документ.Y`, `РегистрСведений.Z`, …).
  - `form_name` → формы объекта из `context.arguments.object_name`.
  - `key` / `setting_key` → ключи из `LN_МСРНастройки` + известные имена настроек.
  - `topic` → темы справки BSL.
- **`sampling/createMessage`** — кладёт запрос на сэмплинг в очередь `LN_МСРОчередьСэмплинга` (статус `pending`). Возвращает `sample_id`. Клиент-агент должен опрашивать `pull_pending_sampling`, выполнить LLM-вызов и вернуть `submit_sampling_result`. Любой код может опросить состояние через `get_sampling_result`.
- **Batch JSON-RPC** — `POST /mcp` с телом-массивом JSON-RPC запросов возвращает массив ответов. Notifications (без `id`) в batch не возвращаются. Пустой массив → ошибка `-32600`.

## Курсорная пагинация `execute_query`
- Параметр `page_size` (число строк на страницу). Если задан и `> 0` — весь результат запроса кэшируется в `РегистрСведений.LN_МСРКэшВыборок` (`ХранилищеЗначения`), отдаётся первая страница и `next_cursor` (Base64-JSON `{id, offset}`).
- Параметр `cursor` (из предыдущего ответа). Если передан — `query`/`parameters` игнорируются, отдаётся следующая страница.
- TTL кэша — настройка `query_cursor_ttl_seconds` (по умолчанию 300 секунд). По истечении курсор инвалидируется, клиент должен повторить запрос без `cursor`.

## sampling-очередь (как обходим односторонний HTTP)
Спецификация MCP описывает `sampling/createMessage` для двусторонних транспортов (stdio / Streamable HTTP). Наш сервер — синхронный HTTP, прямого call-back-канала нет. Решение — **очередь сэмплинга**:
1. Сервер (tool / prompt / роутер) вызывает `LN_МСРСэмплинг.СоздатьЗапрос(...)` → возвращает `sample_id`, запись `pending`.
2. Клиент-агент периодически дергает `pull_pending_sampling` → забирает запрос, статус `in_progress`.
3. Клиент-агент выполняет LLM-вызов локально (использует свой ключ).
4. Клиент-агент возвращает результат через `submit_sampling_result(sample_id, content)` → статус `completed` (или `failed`).
5. Server-side код опрашивает `get_sampling_result(sample_id)` (например, через polling из prompt-агента) и забирает контент.

### Унаследованные от ядра vladimir-kharin/1c_mcp
- **`list_metadata_objects`** — список объектов МД по типу с фильтром по имени.

> Структура объекта МД — только через **`get_metadata`** (`object_name`, `detail_level`). Устаревший `get_metadata_structure` удалён как дубликат.

### Ресурсы

| Адрес | Источник | Содержимое |
| - | - | - |
| `file://resource/syntax_1c.txt` | vendor | Полный текст справки BSL |
| `file://ln/_index.json` | `LN_МСРРесурсыПроекта` | Индекс всех собственных ресурсов (включая `mxl_object_templates`) |
| `file://ln/common-module/<Имя>` | `LN_МСРРесурсыПроекта` | Исходник общего модуля |
| `file://ln/role/<Имя>` | `LN_МСРРесурсыПроекта` | JSON-описание прав роли |
| `file://ln/dcs/<Отчёт>` | `LN_МСРРесурсыПроекта` | Основная СКД отчёта (XML) |
| `file://ln/mxl/common/<Макет>` | `LN_МСРРесурсыПроекта` | XML общего MXL-макета |
| `file://ln/mxl/<Тип>.<Имя>/<Макет>` | `LN_МСРРесурсыПроекта` | XML MXL-макета конкретного объекта (Справочник/Документ/Отчёт/Обработка/Регистр и т.д.) |

### Промпты (`prompts/list` + `prompts/get`)

Контейнер `LN_МСРПромпты` отдаёт 5 готовых промптов, оформленных по MCP-спецификации (`{description, messages: [{role, content}]}`). Каждый промпт содержит «системное» руководство + параметры пользователя:

| Имя | Параметры | Назначение |
| - | - | - |
| `refactor_bsl` | `code`, `focus` (`perf`/`style`/`safety`/`all`) | Безопасный рефакторинг BSL: антипаттерны + переработанный код |
| `code_review_bsl` | `code`, `strictness` (`lenient`/`normal`/`strict`) | Code review по 1С:Стандартам с severity и предложением фикса |
| `query_generator` | `task`, `metadata_objects`, `dialect` (`1c_query`/`dcs`) | Построение текста запроса 1С/СКД с обязательным `validate_query` |
| `error_explainer` | `error_text`, `code_context` | Объяснение runtime-ошибки 1С + минимальный фикс |
| `schema_to_form` | `object_name`, `form_kind` (`object`/`list`/`choice`) | Заготовка Form.xml + Form.Module.bsl по реквизитам объекта МД |

Итого: **15 LN tools + 2 vendor tools = 17 tools**, **5 готовых промптов**, **N ресурсов** (N = 1 vendor + 1 индекс + количество общих модулей/ролей/СКД/общих MXL вашей конфигурации; MXL-макеты конкретных объектов доступны через маршрутный адрес и индекс).

## Token economy: TOON

Каждый ответ можно запросить в трёх форматах:

| Формат | Заголовок Content-Type | Параметр URL | Когда выбирать |
| - | - | - | - |
| `json` | `application/json` | `?format=json` | дефолт, для интерактивной отладки |
| `json-compact` | `application/json` | `?format=json-compact` | без пробелов/отступов, экономия 15–25 % |
| `toon` | `application/x-toon` | `?format=toon` | табличные данные (рез. запроса), экономия 30–60 % токенов |
| `text-pipe` | `text/plain` | `?format=text-pipe` | плоский текст «заголовок \| значение», максимальная экономия для коротких таблиц |

Пример TOON для результата `execute_query`:

```
[2]{name,inn,kpp}
"ООО ""Ромашка""",7701234567,770101001
"ИП Иванов",760123456789,
```

## Установка

**Быстрый старт:** [`docs/SETUP.ru.md`](docs/SETUP.ru.md) — полная инструкция для нового разработчика и Cursor.

**Для AI-агента:** [`AGENTS.md`](AGENTS.md) + [`.cursor/rules/ln-mcp-install.mdc`](.cursor/rules/ln-mcp-install.mdc).

1. **Клонировать репозиторий** или скопировать каталог в выгрузку XML конфигурации.
2. **Загрузить как расширение через Designer.** «Конфигурация → Расширения конфигурации → Добавить → Загрузить из файлов на диске» → выбрать `Configuration.xml`.
3. **Альтернативно через `ibcmd`** (рекомендуется для CI):

   ```powershell
   & "$PLATFORM_PATH\ibcmd.exe" infobase config extension import `
       --extension=LN_MCP_1C `
       --data="e:\IBT\BazesXML\CSPXML\Extensions\LN_MCP_1C"
   ```
4. **Обновить ИБ** (`F7` в Designer или `ibcmd infobase config apply`).
5. **Опубликовать на веб-сервере.** См. ниже.

## Веб-публикация (Apache 2.4)

См. `publish/default.vrd` и `publish/httpd.conf.snippet` — готовые шаблоны.

Минимум для Apache на Windows:

```apache
LoadModule _1cws_module "C:/Program Files/1cv8/8.3.20.xxxx/bin/wsap24.dll"

Alias "/mcp_cspxml" "C:/inetpub/mcp_cspxml"
<Directory "C:/inetpub/mcp_cspxml">
    AllowOverride All
    Options None
    Require all granted
    SetHandler 1c-application
    ManagedApplicationDescriptor "C:/inetpub/mcp_cspxml/default.vrd"
</Directory>
```

После рестарта Apache:

```bash
curl -X POST http://localhost/mcp_cspxml/hs/mcp/health
```

Ожидаемый ответ:

```json
{"status":"ok","server":"LN_MCP_1C","version":"1.0.0"}
```

## Multi-base

Один и тот же `.cfe` устанавливается в N инфобаз. Для каждой делается отдельная веб-публикация (своя папка + свой `.vrd`):

```
http://srv/mcp_dbA/hs/mcp/rpc   →  ИБ A
http://srv/mcp_dbB/hs/mcp/rpc   →  ИБ B
```

В MCP-клиенте (Cursor / Claude Desktop) указывается тот URL, к которому нужно подключиться. Переключение между БД = переключение URL.

## Безопасность

- **`execute_code`** **по умолчанию работает в полноценном режиме** — у LLM-агента, который ходит в живую разработческую базу, должен быть полный набор возможностей. Чтобы включить безопасный режим:
  - либо передать `safe_mode: true` в каждом вызове,
  - либо один раз вызвать `set_setting` с `key = "execute_code_default_safe"`, `value = "true"` — тогда все будущие вызовы без явного `safe_mode` будут защищёнными. В защищённом режиме включается `УстановитьБезопасныйРежим(Истина)` + чёрный список (`файл`, `comобъект`, `httpсоединение`, `wsпрокси`, `запуститьприложение`, `внешняякомпонента`, `Выполнить(`, `Вычислить(` …). Любое совпадение → немедленный отказ.
  - В ответе всегда возвращается `safe_mode_used: true|false` для аудита.
- **Аудит** — каждый вызов tool попадает в `LN_МСРАудитВызовов` (с обрезкой параметров до 2 КБ).
- **Журнал регистрации** — все ошибки tool пишутся в категорию `MCP.tool.<имя_tool>.Ошибка` (`УровеньЖурналаРегистрации.Ошибка`).
- **HTTP Basic Auth** — настраивается на уровне `.vrd` (`<usr>`).

## Regression-тесты (`/loop` тест-набор)

`tests/regression.ps1` — полный авто-набор для MCP-клиента. Прогоняет:

- protocol: `initialize`, `tools/list`, `resources/list`, `prompts/list`;
- все 15 LN tools + 2 vendor tools (валидные параметры);
- ресурсы: vendor (`syntax_1c`), индекс собственных ресурсов и по 1 представителю каждой категории (`common-module`, `role`, `dcs`, `mxl`) — выбранные из `_index.json` динамически;
- проверку чтения/записи настройки `regression_marker`.

Запуск разовый:

```powershell
pwsh -File tests/regression.ps1 -BaseUrl "http://localhost/mcp_demo/hs/api" -Out report.md
```

Запуск в цикле через Cursor `/loop` (например, каждые 5 минут — мониторинг публикации):

```
/loop 5m pwsh -File tests/regression.ps1 -BaseUrl http://localhost/mcp_demo/hs/api -Out report.md
```

Скрипт пишет Markdown-отчёт со строкой на каждый вызов: метод/инструмент, OK/✘, длительность мс, ошибка (если была), первые 200 символов ответа.

## Дальнейшее развитие

- **v1.0+ (в текущем релизе уже сделано)**:
  - Курсорная пагинация `get_event_log` (Base64-cursor с `last_date + offset_in_second`, tie-breaker сортировка по 6 полям).
  - Адреса MXL-макетов конкретных объектов: `file://ln/mxl/<Тип>.<Имя>/<Макет>` + полный список в `file://ln/_index.json` (`mxl_object_templates`).
  - Контейнер промптов `LN_МСРПромпты` (5 шт.): `refactor_bsl`, `code_review_bsl`, `query_generator`, `error_explainer`, `schema_to_form`.
  - Расширенный `describe_form`: список реквизитов/стандартных реквизитов/табличных частей/команд объекта-источника + честная нота о runtime-only составе элементов самой формы.
- **v1.1** — REST-эндпоинт `POST /api/{tool}` без JSON-RPC обёртки, `GET /docs` (OpenAPI 3.1) + Swagger UI. `completion/complete` (MCP-метод автодополнения аргументов tools/resources/prompts: имена объектов МД, ключи настроек, имена форм). Команды `clear_cache`, `reset_audit`.
- **v1.2** — `streamableHttp`-транспорт MCP (SSE-стрим для длинных операций). Long-polling для тяжёлых `execute_query`. Sampling (`sampling/createMessage`) — поддержка обратного канала, когда сервер просит клиента у его LLM что-то выполнить (агентные диалоги двустороннего вида).
- **v1.3** — собственный CFE-инсталлятор (.exe), генерация дашборда из `LN_МСРАудитВызовов`, экспорт регрессионных отчётов в InfluxDB / Grafana.
- **v2.0** — OAuth2 (для коммерческого облака), мульти-tenant маршрутизация по одной публикации, генерация `tools/` из БСП-декларации, plug-and-play подключаемых tool-плагинов через подсистему, параллельные транзакционные вызовы `execute_query` с lock-detection.

## Источники

- Архитектурное ядро: [github.com/vladimir-kharin/1c_mcp](https://github.com/vladimir-kharin/1c_mcp) (MIT).
- Семантика `execute_query` / `execute_code` / `get_event_log`: [github.com/ROCTUP/1c-mcp-toolkit](https://github.com/ROCTUP/1c-mcp-toolkit) (GPL-3, реализация — clean-room rewrite в BSL).
- Спецификация MCP: [modelcontextprotocol.io](https://modelcontextprotocol.io/).
