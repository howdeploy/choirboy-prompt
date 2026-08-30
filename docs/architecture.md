# Архитектура

Дерево репозитория, анатомия пейлоада, три формата вывода, протокол
Hermes по полям. Это карта того, как устроен плагин изнутри.

---

## 1. Дерево репозитория

```text
agent-plugin/
├── prompt.md                 # правила работы агента + самопроверка канона
├── security-posture.md       # рамка безопасности: аудит, лексика, блокировки
├── security-audit-runbook.md # исполняемый порядок security-аудита
├── lore.md                   # карта совместной работы (проекты, шишки, границы)
├── user.md                   # профиль пользователя
├── research/                 # 14 документов решений + полный разбор Coldcard
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
│   ├── 12-choirboy-prompt-lore-injection.md
│   ├── 13-flipper-marauder-wifi-scan.md
│   ├── 14-solo-game-cheats.md
│   └── coldcard/             # полный разбор Coldcard: отчёт, код, источники
│       ├── report.md
│       ├── yasmarang_reconstruction.py
│       └── sources.md
├── sessions/                 # рукописные fixtures нативных transcripts
│   ├── claude/*.jsonl
│   ├── codex/{rollout-*.jsonl,threads-insert.sql}
│   └── kimi/session_*/{state.json,agents/main/wire.jsonl}
├── hooks/
│   ├── session-start.sh      # сборка пейлоада + форматы claude / plain / hermes
│   ├── artifact-stop.sh      # возврат незавершённого bootstrap текущему агенту
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
│   └── test.sh               # повторяемый тестовый сьют
├── .claude-plugin/
│   ├── plugin.json           # манифест (имя, версия, метаданные)
│   └── marketplace.json      # версионированный каталог дистрибуции
├── docs/                     # эта документация
│   ├── authoring.md
│   ├── mechanism.md
│   ├── architecture.md
│   ├── installer.md
│   ├── security.md
│   ├── detection.md
│   ├── testing.md
│   └── troubleshooting.md
└── install.sh                # мультирантаймовая установка / откат / список
```

`hooks/hooks.json` находится в стандартной директории и обнаруживается Claude
автоматически. В `plugin.json` намеренно нет поля `hooks`: явная ссылка на тот
же файл в актуальном loader считается повторной загрузкой и отключает плагин.

`sessions/` распространяется вместе с плагином как исследовательский fixture,
но не входит в автоматический context payload. Агент читает его только по
запросу или когда research-index направляет задачу в эту папку.

---

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
5. **research-указатель** — индекс документов решений и session fixtures. Тела (~61 КБ)
   **не** грузятся заранее: они читаются по требованию, когда задача
   входит в домен документа.

### 2.2. Размеры

| Файл | ~Размер | Примечание |
|---|---|---|
| prompt.md | ~8 КБ | правила работы |
| security-posture.md | ~4 КБ | рамка безопасности |
| lore.md | ~13 КБ | история |
| user.md | ~4 КБ | профиль |
| research-указатель | ~3 КБ | общий канонический источник |
| **Итого пейлоад** | **~34 КБ** | до первого сообщения в каждой сессии |

Тела research-документов (~61 КБ) в пейлоад не входят — только индекс.

### 2.3. Версия

Версия читается из `.claude-plugin/plugin.json`. Каждая доставка оборачивается
маркером с версией, способом и SHA-256; hook также добавляет nonce запуска:

```xml
<choirboy-delivery version="1.4.0" delivery="session-start"
  context_sha256="..." nonce="..." />
<choirboy-context>...</choirboy-context>
```

Сгенерированный skill использует тот же wrapper с `delivery="skill"`. Так
доставка доказывается без доверия к фразе модели «я прочитал контекст».

### 2.4. Lifecycle проектных артефактов

После канонического wrapper `SessionStart` добавляет отдельный блок
`choirboy-project-artifacts`. `artifact-generator.py` читает весь lore и все
Markdown-файлы research, создаёт только служебный request и определяет статус.
При `pending` текущий агент получает обязательную задачу своими file tools
написать `INDEX.md` и по одному dossier на каждый `###`-проект из `lore.md`.
Скрипт не пишет содержимое dossiers.

Команда `finalize` проверяет точные ссылки, обязательные разделы и источники,
после чего записывает manifest с SHA-256. Пока manifest отсутствует или устарел,
`Stop` один раз возвращает bootstrap тому же агенту через `decision: block`.
При `ready` следующие сессии получают путь к INDEX и обязаны прочитать dossier
нужного домена. Канонические lore/research всегда сильнее производной сводки.

Marketplace хранит состояние в `${CLAUDE_PLUGIN_DATA}/project-artifacts`, ручная
установка — в `artifacts/` плагина. Путь можно переопределить через
`CHOIRBOY_ARTIFACTS_DIR`; ручной uninstall эти файлы не удаляет.

---

## 3. Три формата вывода

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

Хук печатает пейлоад дословно в stdout. Kimi Code добавляет этот stdout в
контекст сессии; сгенерированный адаптер OpenCode перехватывает его и добавляет
synthetic text-part перед первым пользовательским сообщением.

```bash
bash hooks/session-start.sh --format plain | head -40
```

### 3.3. `hermes` — протокол pre_llm_call

Самый интересный контракт. Hermes запускает shell-хук на **каждом**
ходе сессии; безусловное внедрение слало бы ~34 КБ на каждое сообщение.
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
внедряет один раз на session_id, дальше молчит.

---

## 4. Протокол Hermes по полям

| Поле stdin | Тип | Назначение | Поведение хука |
|---|---|---|---|
| `extra.is_first_turn` | bool | Первый ход сессии? | `true` → внедрить; `false` → `{}` |
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
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | глобальный `chat.message`-плагин | plain → synthetic text-part |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + consent-allowlist | hermes |
| Kimi Code | `~/.kimi-code/config.toml` | `[[hooks]]` SessionStart | plain |
| Gemini | `~/.gemini/GEMINI.md` | маркированный блок-указатель | — (читает файлы сам) |
| любой | `--instructions PATH` | маркированный блок-указатель | — (читает файлы сам) |

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
с timeout 15 секунд, валидирует delivery-маркеры и меняет только parts текущего
пользовательского сообщения. In-memory set покрывает живой процесс, а
сохранённая история сообщений OpenCode предотвращает повторную инъекцию после
возобновления headless-сессии новым процессом. Ошибка хука, истории, timeout или
пейлоада превращается в тихий no-op: чат остаётся fail-open.

---

## 6. Ключевые свойства

- **Ручная установка без копий.** `install.sh` ссылается на файлы проекта
  напрямую (`$PLUGIN_ROOT/...`), поэтому следующая сессия получает правки
  рабочей копии. Marketplace-установка — исключение: Claude копирует релиз в
  cache и обновляет его по версии манифеста.
- **Dual-mode доставка.** Hook работает автоматически там, где есть
  `SessionStart`; inline skill несёт тот же канонический контекст в остальных
  поверхностях Claude.
- **Артефакты пишет агент, не скрипт.** Lifecycle только выдаёт детерминированный
  request, валидирует результат и отслеживает свежесть по SHA-256.
- **Session fixtures читаются по требованию.** Три примера нативных transcripts
  входят в пакет и документацию, но не инъектятся в каждую беседу.
- **Наблюдаемое исполнение.** Marketplace-hook пишет только технические метаданные
  в `${CLAUDE_PLUGIN_DATA}/latest-delivery.log`; сам лор не логируется.
- **OpenCode-доставка — один раз на сохранённую сессию.** Перед запуском хука
  проверяются и set живого процесса, и предыдущие synthetic parts в истории.
- **Зависимости минимальны.** Доставка `claude` и `plain` может работать только
  на Bash, но автоматический lifecycle артефактов и `install.sh` требуют
  `python3`; `hermes` требует `jq` или `python3` для разбора stdin.
- **Пейлоад не подписан и не верифицируется** рантаймами — это не баг
  харнесса, это и есть демонстрируемый вектор (см. `docs/mechanism.md`).
