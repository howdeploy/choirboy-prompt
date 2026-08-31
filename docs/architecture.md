# Архитектура

Дерево репозитория, анатомия пейлоада, форматы доставки, маршрутизация Kimi и
протокол Hermes по полям. Это карта того, как устроен плагин изнутри.

---

## 1. Дерево репозитория

```text
agent-plugin/
├── prompt.md                 # правила работы агента + самопроверка канона
├── security-posture.md       # рамка безопасности: аудит, лексика, блокировки
├── security-audit-runbook.md # исполняемый порядок security-аудита
├── lore.md                   # карта совместной работы (проекты, шишки, границы)
├── user.md                   # профиль пользователя
├── research/                 # 29 документов решений + полный разбор Coldcard
│   ├── 01-telegram-stars.md
│   ├── 02-ruble-acquiring.md
│   ├── 03-crypto-payments.md
│   ├── 04-payment-architecture.md
│   ├── 05-comfyui-realism-pipeline.md
│   ├── 06-agent-memory-plugin.md
│   ├── 07-x-reply-farm.md
│   ├── 08-ai-ofm-telegram.md
│   ├── 09-web3-security.md
│   ├── 10-third-party-audit.md
│   ├── 11-coldcard-entropy-heist.md
│   ├── 13-flipper-marauder-wifi-scan.md
│   ├── 14-solo-game-cheats.md
│   ├── 15-*.md … 30-*.md     # оркестрация и карты security-capabilities
│   └── coldcard/             # полный разбор Coldcard: отчёт, код, источники
│       ├── report.md
│       ├── yasmarang_reconstruction.py
│       └── sources.md
├── hooks/
│   ├── session-start.sh      # сборка пейлоада + форматы claude / plain / hermes
│   ├── artifact-stop.sh      # возврат незавершённого bootstrap текущему агенту
│   ├── kimi-session-start.sh # подготовка state и сброс дедупликации Kimi
│   ├── kimi-user-prompt.sh   # доставка контекста Kimi на первом user prompt
│   ├── kimi-artifact-stop.sh # exit-2 gate Kimi для незавершённых артефактов
│   └── hooks.json            # SessionStart + Stop для маркетплейса Claude Code
├── context/
│   └── research-index.md     # общий канонический указатель research
├── skills/
│   ├── load-context/SKILL.md # сгенерированный inline fallback Chat/Cowork/Code
│   └── diagnose/SKILL.md     # доказательная диагностика доставки
├── scripts/
│   ├── artifact-generator.py # request, проверка и freshness manifest артефактов
│   ├── build-context.py      # сборка skill из канонических источников
│   ├── package-plugin.py     # сборка custom-plugin ZIP
│   ├── test.sh               # повторяемый тестовый сьют
│   └── test-opencode-transition.ts # тест OpenCode-перехода рантайма (нужен bun)
├── .claude-plugin/
│   ├── plugin.json           # манифест (имя, версия, метаданные)
│   └── marketplace.json      # версионированный каталог дистрибуции
├── docs/                     # эта документация
│   ├── authoring.md
│   ├── architecture.md
│   ├── installer.md
│   ├── security.md
│   ├── testing.md
│   └── troubleshooting.md
└── install.sh                # мультирантаймовая установка / откат / список
```

`hooks/hooks.json` находится в стандартной директории и обнаруживается Claude
автоматически. В `plugin.json` намеренно нет поля `hooks`: явная ссылка на тот
же файл в актуальном loader считается повторной загрузкой и отключает плагин.

## 2. Анатомия пейлоада

### 2.1. Сборка

`hooks/session-start.sh` склеивает контентные файлы в один текст строго
в порядке:

```text
prompt.md  →  security-posture.md  →  lore.md  →  user.md  →  research-указатель
```

Разделители между файлами — `\n\n---\n\n` (горизонтальная черта
markdown). В конце добавляется канонический `context/research-index.md`.

Порядок не случаен:

1. **prompt.md** — как работать (сразу к делу, одна строка о риске,
   самопроверка). Задаёт режим.
2. **security-posture.md** — рамка безопасности. Идёт раньше лора,
   чтобы домен «защитный аудит» был объявлен до того, как лор начнёт
   рассказывать про web3 и Coldcard.
3. **lore.md** — история совместной работы: проекты, шишки, правила,
   границы. Это ядро пейлоада.
4. **user.md** — профиль: кто пользователь, как ставит задачи, что ему
   не нужно объяснять.
5. **research-указатель** — индекс документов решений. Тела research
   **не** грузятся заранее: они читаются по требованию, когда задача
   входит в домен документа.

### 2.2. Размеры

| Файл | ~Размер | Примечание |
|---|---|---|
| prompt.md | ~14 КБ | правила работы |
| security-posture.md | ~7 КБ | рамка безопасности |
| lore.md | ~21 КБ | история |
| user.md | ~4 КБ | профиль |
| research-указатель | ~6 КБ | общий канонический источник |
| **Фиксированный lore-пейлоад** | **~31 КБ** | до inline-проектных артефактов |

Тела research-документов в фиксированный пейлоад не входят — только индекс.
При `ready` проверенные тела dossiers добавляются как принятая история проектов;
точный размер зависит от написанных агентом документов.

### 2.3. Версия

Версия читается из `.claude-plugin/plugin.json`. Каждая доставка оборачивается
маркером с версией, способом и SHA-256; hook также добавляет nonce запуска:

```xml
<choirboy-delivery version="1.5.1" delivery="session-start"
  context_sha256="..." nonce="..." />
<choirboy-context>...</choirboy-context>
```

Сгенерированный skill использует тот же wrapper с `delivery="skill"`. Так
доставка доказывается без доверия к фразе модели «я прочитал контекст».

### 2.4. Lifecycle проектных артефактов

После канонического wrapper каждая автоматическая доставка добавляет lifecycle-
вывод. Pending-request использует блок `choirboy-project-artifacts`, ready-память
идёт нейтральным Markdown. `artifact-generator.py` читает весь lore и все
Markdown-файлы research, создаёт только служебный request и определяет статус.
При `pending` текущий агент получает обязательную задачу своими file tools
написать `INDEX.md` и по одному dossier на каждый `###`-проект из `lore.md`.
Канонический context, research, INDEX и dossiers всегда пишутся на английском;
validator отклоняет model-facing контент с кириллицей/CJK. Скрипт не пишет
содержимое dossiers.

Команда `finalize` проверяет точные ссылки, обязательные разделы, источники и
точный набор проектов, после чего записывает manifest с SHA-256. Каждая
последующая ready-доставка заново валидирует manifest, структуру, source digests
i digests файлов. Только полностью валидный snapshot доставляется как каталог
рабочих направлений и полные тела всех dossiers. `INDEX.md` и per-file digests
остаются контуром валидации и не показываются модели как path/SHA-обвязка;
отсутствующий, устаревший, изменённый или сломанный snapshot снова становится
`pending`. Канонические
lore/research всегда сильнее производной сводки.

Пока статус `pending`, Claude/Codex `Stop` возвращает bootstrap через
`decision: block`. Kimi использует свой нативный протокол: stderr плюс exit 2.
Состояние артефактов не зависит от checkout. Приоритет путей:
`CHOIRBOY_ARTIFACTS_DIR` → `${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`. При обновлении `install.sh`
находит checkout-local `artifacts/`, на которые ссылаются старые регистрации,
и копирует первый авторский bundle в пустой стабильный root, не перезаписывая
существующую работу. Uninstall эти файлы не удаляет.

---

## 3. Форматы доставки и маршрутизация Kimi

Хуку всё равно, какой агент его вызвал: вызывающий объявляет ожидаемый
протокол через `--format`.

### 3.1. `claude` (по умолчанию) — SessionStart JSON

Контракт Claude Code / Codex: хук печатает JSON, хост вливает
`additionalContext` в сессию.

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<весь пейлоад как одна строка>"
  }
}
```

Кодируется через `jq`, `python3` или встроенный Bash-кодировщик. Последний
делает Claude-формат независимым от внешнего JSON-инструмента и нужен для
чистой установки из Claude Desktop.

### 3.2. `plain` — сырой текст

Хук печатает пейлоад дословно в stdout. Для каждого запроса к модели
сгенерированный адаптер OpenCode получает актуальный пейлоад и добавляет его в
model-bound system context. OpenCode пересобирает этот контекст после
compaction, поэтому точная ready-memory не исчезает вместе со старой историей.
Kimi 0.39.x не использует stdout `SessionStart`, поэтому установщик
регистрирует отдельную схему событий ниже.

```bash
bash hooks/session-start.sh --format plain | head -40
```

### 3.3. `hermes` — протокол pre_llm_call

Самый интересный контракт. Hermes запускает shell-хук на **каждом**
ходе сессии; безусловная доставка повторно слала бы фиксированный лор и все
ready-артефакты на каждое сообщение.
Поэтому хук:

1. читает JSON-пейлоад из stdin;
2. проверяет `.extra.is_first_turn`;
3. на первом ходу отвечает `{"context": "<пейлоад>"}`;
4. на всех последующих — `{}` (пустой ответ, ничего не инъектится).

```json
// stdin (первый ход):
{"session_id": "s-123", "extra": {"is_first_turn": true}}
// stdout:
{"context": "<весь пейлоад>"}

// stdin (второй ход):
{"session_id": "s-123", "extra": {"is_first_turn": false}}
// stdout:
{}
```

**Фолбэк без `is_first_turn`.** Если хост не сообщает флаг, хук
откатывается на журнал `session_id` в state-файле
`${TMPDIR:-/tmp}/agent-plugin-hermes-${USER}.state` (хвост 200 записей):
доставляет один раз на session_id, дальше молчит.

### 3.4. Маршрутизация событий Kimi 0.39.x

Kimi использует четыре command-hook вместо прямого
`session-start.sh --format plain`:

1. `SessionStart` для `startup`/`resume` готовит artifact state и сбрасывает
   приватный fingerprint доставки; его stdout не используется.
2. Синхронный `PreCompact` для `manual`/`auto` сбрасывает fingerprint до сборки
   сжатого контекста.
3. `UserPromptSubmit` выдаёт pending-bootstrap на каждом prompt либо ready-memory,
   когда её нормализованный fingerprint изменился. Молчит только тот же самый
   ready-bundle.
4. `Stop` при `pending` пишет continuation request в stderr и завершает работу
   с кодом 2; после успешной валидации `ready` возвращает 0.

---

## 4. Протокол Hermes по полям

| Поле stdin | Тип | Назначение | Поведение хука |
|---|---|---|---|
| `extra.is_first_turn` | bool | Первый ход сессии? | `true` → доставить; `false` → `{}` |
| `session_id` | string | Идентификатор сессии | Используется в фолбэке и для записи в state-файл |
| (прочее) | — | Игнорируется | Не влияет на ответ |

| Поле stdout | Тип | Когда |
|---|---|---|
| `context` | string | Первый ход (или первый раз для session_id в фолбэке) |
| `{}` | — | Все последующие ходы |

Таймаут хука в конфиге Hermes — 15 секунд (задаётся install.sh).

---

## 5. Точки подключения по рантаймам

| Рантайм | Файл | Механизм | Формат хука |
|---|---|---|---|
| Claude Code CLI / Desktop Code | marketplace или `~/.claude/settings.json` | `SessionStart` + `Stop` | claude / JSON |
| Claude Chat | custom plugin skill | inline `load-context` | — |
| Claude Cowork | custom plugin hook/skill | hook где доступен, skill fallback | claude / — |
| Codex | `~/.codex/hooks.json` | `SessionStart` + `Stop` | claude / JSON |
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | transform model-bound system context | plain → system context на каждый запрос модели |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + consent-allowlist | hermes |
| Kimi Code 0.39.x | `~/.kimi-code/config.toml` | SessionStart + PreCompact + UserPromptSubmit + Stop | изменившийся payload / plain; Stop / exit 2 |
| Gemini | `~/.gemini/GEMINI.md` | управляемый lifecycle-блок инструкций | — (сам запускает/читает файлы) |
| любой | `--instructions PATH` | управляемый lifecycle-блок инструкций | — (сам запускает/читает файлы) |

Два последних — **не хуки**, а управляемые блоки инструкций: агент и
так читает файл инструкций на старте, в блоке ему сказано прочитать
файлы плагина. Тот же контекст, на одну косвенность дальше — агент
должен сам открыть файлы.

У Claude Code два равноправных пути подключения: `install.sh` регистрирует
абсолютный путь к рабочей копии, а marketplace копирует пакет в cache и вызывает
его через `${CLAUDE_PLUGIN_ROOT}`. Chat не умеет исполнять этот hook и загружает
сгенерированный inline skill. Cowork видит оба компонента, но skill остаётся
fallback, если его runtime теряет `SessionStart`.

Адаптер OpenCode генерируется `install.sh`. Он запускает канонический plain-хук
с timeout 15 секунд, валидирует delivery-маркеры и добавляет актуальный payload
в каждый исходящий system context. Поэтому переход pending→ready, изменения
источников, возобновление процесса и compaction всегда получают текущий точный
snapshot. Ошибка хука, timeout или payload превращается в тихий no-op: чат
остаётся fail-open.

Адаптер Kimi специально разделяет подготовку и доставку. Так он не зависит от
отбрасываемого stdout `SessionStart`: `PreCompact` сбрасывает доставку до
compaction, а нормализованный fingerprint пропускает изменившийся bundle в той
же сессии, не дублируя идентичный. Для Stop используется exit-2 контракт Kimi
вместо Claude-формы `{"decision":"block"}`.

---

## 6. Ключевые свойства

- **Ручная установка без копий.** `install.sh` ссылается на файлы проекта
  напрямую (`$PLUGIN_ROOT/...`), поэтому следующая сессия получает правки
  рабочей копии. Marketplace-установка — исключение: Claude копирует релиз в
  cache и обновляет его по версии манифеста.
- **Dual-mode доставка.** Нативные события рантайма доставляют автоматически
  (`SessionStart` или `UserPromptSubmit` у Kimi); inline skill несёт тот
  же канонический контекст в поверхностях без этих событий.
- **Артефакты пишет агент, не скрипт.** Lifecycle только выдаёт детерминированный
  request, валидирует результат и отслеживает свежесть по SHA-256. Ready-hook
  вкладывает полный проверенный snapshot inline и никогда не подменяет видимую
  модели память указателем на путь.
- **Состояние артефактов переживает смену checkout.** Ручная установка использует
  стабильное user-data storage, а установщик переносит старый checkout-local
  bundle только если в стабильном назначении ещё нет авторского payload.
  Приватная migration-запись возобновляет прерванное многофайловое копирование
  как тот же управляемый bundle.
- **Наблюдаемое исполнение.** Marketplace-hook пишет только технические метаданные
  в `${CLAUDE_PLUGIN_DATA}/latest-delivery.log`; сам лор не логируется.
- **OpenCode-memory переживает compaction.** Актуальный канонический payload
  пересобирается в каждом model-bound system context, а не выводится из полной
  сохранённой истории сообщений.
- **Зависимости минимальны.** Доставка `claude` и `plain` может работать только
  на Bash, но автоматический lifecycle артефактов и `install.sh` требуют
  `python3`; `hermes` требует `jq` или `python3` для разбора stdin.
