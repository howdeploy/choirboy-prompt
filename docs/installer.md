# Установщик

Полный разбор `install.sh`: таргеты, маркеры, идемпотентность, бэкапы,
`--instructions`, edge-cases. Если архитектура — «что установлено»,
то этот документ — «как это ставится и снимается».

---

## 0. Установка Claude plugin

Репозиторий является версионированным Claude marketplace через
`.claude-plugin/marketplace.json`. Установленный пакет содержит и
хуки Claude Code `SessionStart` и `Stop`, и skills для Chat/Cowork.

### 0.1. Claude Code CLI

```text
/plugin marketplace add howdeploy/choirboy-prompt
/plugin install choirboy-prompt@choirboy-prompt
```

После установки открой новую сессию. Обновление и удаление через CLI:

```text
/plugin marketplace update choirboy-prompt
/plugin update choirboy-prompt@choirboy-prompt
/plugin uninstall choirboy-prompt@choirboy-prompt
/plugin marketplace remove choirboy-prompt
```

### 0.2. Claude Desktop Code

Desktop не предоставляет терминальный диалог `/plugin`. Добавь
`https://github.com/howdeploy/choirboy-prompt` через **Customize → Plugins →
Personal plugins → + → Add marketplace**. В локальной Code-сессии выбери
**+ → Plugins → Add plugin → choirboy-prompt**, затем открой новую сессию.

Marketplace cache выставляет `${CLAUDE_PLUGIN_ROOT}`. `hooks/hooks.json`
использует документированный exec-form (`command: bash`, путь отдельным
элементом `args`), поэтому пробелы и shell-символы в пути не разбираются shell.
Timeout 15 секунд не даёт зависшему хуку блокировать старт сессии.

### 0.3. Claude Chat и Cowork

Установи репозиторий как custom plugin через **Customize → Plugins** или загрузи
ZIP от `python3 scripts/package-plugin.py`. Chat не запускает `SessionStart` —
используй skill **load-context**. Cowork использует хук там, где он поддержан,
а skill остаётся fallback. Skill **diagnose** доказывает доставку по маркеру
`choirboy-delivery`, а не по формулировке ответа модели.

### 0.4. Границы

- автоматическому хуку нужен `bash`, skill от него не зависит;
- Cloud Code требует project `enabledPlugins` и не наследует локальную Desktop-установку;
- Desktop WSL не поддерживает plugins, а SSH sync хуков пока ненадёжен — используй skill;
- не включай одновременно marketplace-плагин и `./install.sh --target claude`:
  Claude загрузит пейлоад дважды;
- релиз требует одинакового version bump в manifest и marketplace, затем
  `python3 scripts/build-context.py` и тестовый сьют.

---

## 1. Общая схема

```text
./install.sh [--target claude,opencode] [--uninstall] [--list]
             [--instructions FILE] [--project] [--settings PATH]
```

Три режима:

| Режим | Что делает |
|---|---|
| install (по умолчанию) | Регистрирует хуки/блок и готовит artifact request |
| `--uninstall` | Удаляет регистрации, но сохраняет созданные агентом артефакты |
| `--list` | Без записи показывает `absent` / `detected` / `stale` / `installed` (`prepared` для Grok Bot) |

Требование `install.sh`: `python3` для JSON-операций. Форматы хука `claude` и
`plain` работают на Bash без `jq`/`python3`; формат `hermes` требует один из
этих двух JSON-парсеров. Автоматический lifecycle артефактов требует `python3`:
установщик готовит только request, а следующая сессия поручает текущему агенту
написать dossiers и пройти validator. Request и validator требуют, чтобы INDEX
и dossiers были на английском. Хранилище артефактов стабильно при смене
checkout. Приоритет путей: `CHOIRBOY_ARTIFACTS_DIR` →
`${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`.

Перед перезаписью регистраций установщик проверяет текущие и старые hook-paths,
а также `artifacts/` текущего checkout. Если в стабильном root ещё нет
созданного агентом payload, туда копируется первый найденный bundle из INDEX,
manifest и dossiers. Существующие стабильные артефакты не перезаписываются;
uninstall их сохраняет. Ready-bundle полностью перевалидируется и вкладывается
inline в hook context — рантайм не получает только путь к INDEX.

---

## 2. Таргеты

Детекция рантайма — по бинарю или наличию конфиг-директории:

```bash
claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
codex)  command -v codex  >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
opencode) command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] ;;
hermes) command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ] ;;
kimi)   command -v kimi   >/dev/null 2>&1 || [ -d "${KIMI_CODE_HOME:-$HOME/.kimi-code}" ] ;;
gemini) command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
grok)   command -v grok   >/dev/null 2>&1 || [ -d "$HOME/.grok" ] ;;
grokbot) command -v grokbot >/dev/null 2>&1 || command -v grok-bot >/dev/null 2>&1 \
           || [ -d "$HOME/.grokbot" ] ;;
```

Правила выбора таргетов:

- `--target claude,opencode` — только перечисленные.
- `--target none` — пустой список, полезно с `--instructions`.
- Без `--target` — все обнаруженные рантаймы.
- `--project` / `--settings PATH` подразумевают таргет `claude`.

Каждый таргет пишет в свой файл:

| Таргет | Файл | Механизм |
|---|---|---|
| claude | `~/.claude/settings.json` (или `--settings`/`--project`) | JSON-хуки `SessionStart` + `Stop` |
| codex | `~/.codex/hooks.json` | JSON-хуки `SessionStart` + `Stop` |
| opencode | `~/.config/opencode/plugins/agent-plugin.ts` | transform model-bound system context |
| hermes | `~/.hermes/config.yaml` | маркированный блок `hooks.pre_llm_call` + consent-allowlist |
| kimi | `${KIMI_CODE_HOME:-~/.kimi-code}/config.toml` | маркированные SessionStart + PreCompact + UserPromptSubmit + Stop hooks |
| gemini | `~/.gemini/GEMINI.md` | маркированный HTML lifecycle-блок инструкций |
| grok | `~/.grok/AGENTS.md` | маркированный HTML lifecycle-блок (глобальные правила Grok Build) |
| grokbot | `~/.grokbot/choirboy-context/SKILL.md` | подготовленный импортируемый workflow (не автозагружается) |
| `--instructions FILE` | любой файл | маркированный lifecycle-блок инструкций (HTML или `#`) |

---

## 3. Маркеры и идемпотентность

### 3.1. Маркер

Все блоки помечены `MARK="agent-plugin:vibe-lore"`. Формы маркеров:

- hash-стиль (конфиги, TOML): `# >>> agent-plugin:vibe-lore >>>` /
  `# <<< agent-plugin:vibe-lore <<<`
- html-стиль (markdown-инструкции): `<!-- agent-plugin:vibe-lore START -->` /
  `<!-- agent-plugin:vibe-lore END -->`

Маркер — это и идентификатор владения, и граница блока для удаления.
Актуальные сгенерированные блоки также содержат
`agent-plugin:vibe-lore:registration=2`: `--list` использует эту ревизию и
точные пути скриптов, чтобы отличить актуальную установку от `stale`.

### 3.2. Идемпотентность

- `block_sync` добавляет отсутствующий управляемый блок или атомарно заменяет
  ровно один полный START/END-блок актуальным сгенерированным текстом. Соседний
  пользовательский контент сохраняется; сломанные, дублированные или вложенные
  маркеры отклоняются.
- `json_hook` матчит записи по имени скрипта (`session-start.sh` или
  `artifact-stop.sh` в
  команде), а не по абсолютному пути: если папка плагина переехала,
  устаревшая регистрация заменяется, а не кладётся вторая.
- Marketplace-хук живёт в plugin cache и не записывается в массив хуков
  `settings.json`. Поэтому marketplace и ручной Claude-хук — альтернативы, а
  не два одновременно включаемых слоя.
- Таргет OpenCode владеет одним целым маркированным plugin-файлом. Повторная
  установка без изменений ничего не делает; обновление бэкапится и атомарно
  заменяет файл.
- Consent-entry Hermes, четыре Kimi-hook, блоки Gemini/Grok и произвольные
  `--instructions` синхронизируются при каждом запуске установщика. Старые
  абсолютные пути и ревизии регистрации обновляются на месте.

### 3.3. Обновление управляемых блоков

Старого skip-only поведения больше нет. Повторный install пересобирает и
заменяет принадлежащий плагину блок, если изменились путь скрипта,
lifecycle-текст или ревизия регистрации; перед заменой создаётся
timestamp-backup. `--list` показывает `stale`, если управляемая регистрация
существует, но не совпадает с текущей. Для синхронизации достаточно обычного
install; цикл uninstall/install не нужен.

---

## 4. Бэкапы и откат

Каждая правка существующего файла предваряется бэкапом:

```bash
backup() {
  [ -f "$1" ] || return 0
  cp -p "$1" "$1.bak.$(date +%Y%m%d-%H%M%S)"
}
```

Файлы вида `settings.json.bak.20260802-153000` остаются на месте после
`--uninstall` — удаляются вручную, когда пользователь убедится, что всё
в порядке.

Откат: `./install.sh --uninstall` удаляет ровно маркированные блоки и
наши JSON-записи, чужие не трогает.

---

## 5. Разбор функций

| Функция | Назначение | Ключевая логика |
|---|---|---|
| `target_present` | Детект рантайма | бинарь или конфиг-дир |
| `claude_settings_file` | Куда писать Claude-хук | `--settings` > `--project` > `~/.claude/settings.json` |
| `target_installed` | Точная актуальная установка? | per-target проверки ревизии/path/hooks |
| `target_managed_present` | Есть старая наша установка? | ownership-маркер/script ids; даёт `stale` |
| `backup` | Бэкап перед правкой | `cp -p` с timestamp |
| `block_sync` | Добавить или обновить маркированный блок | точная замена START/END, атомарная запись |
| `block_remove` | Удалить маркированный блок | по START/END, чистит хвостовую пустую строку |
| `json_hook` | Хук в Claude-образный JSON | матч по имени скрипта, `is_ours()`/`has_exact()` |
| `opencode_plugin` | Управление адаптером OpenCode | guard по маркеру, атомарная замена, timestamp-бэкап |
| `hermes_allowlist` | Consent-allowlist Hermes | точная пара (event, command) |
| `instruction_block` | Текст lifecycle-инструкции | HTML или `#`-комментарии |
| `grokbot_workflow` | Управление workflow-файлом Grok Bot | `install`/`uninstall`/`status`, guard по маркеру |
| `discover_legacy_artifact_roots` | Найти старые checkout-local bundles | читает старые управляемые абсолютные пути |
| `do_claude` / `do_codex` / `do_opencode` / `do_hermes` / `do_kimi` / `do_gemini` / `do_grok` / `do_grokbot` | Установка в таргет | per-target логика |
| `do_instructions` | Установка в произвольный файл | стиль по расширению |

### 5.1. `json_hook` — детали

Работает с Claude-образными JSON-файлами хуков (`settings.json`,
`hooks.json`). Ключевое — **матчинг по имени скрипта**, а не по пути:

```python
def is_ours(entry):
    return any(hook_id in
               (h.get("command", "") + " " + " ".join(h.get("args", [])))
               for h in entry.get("hooks", []))
```

- install: удаляет stale-регистрации нашего скрипта (папка переехала),
  добавляет точный handler. Claude получает `command: bash`, один путь в `args`
  и `timeout: 15`; Codex сохраняет строковую команду и ставит
  `additionalContextLimit: 262144`, чтобы фиксированный лор и inline artifact
  memory оставались в одном стартовом контексте.
- uninstall: удаляет все записи `is_ours()`.
- Невалидный JSON не заменяет; при реальном изменении сохраняет бэкап и пишет
  новый файл атомарно.

### 5.2. `hermes_allowlist` — детали

Hermes требует явного consent на shell-хук: пара `(event, command)` в
`~/.hermes/shell-hooks-allowlist.json`. Функция добавляет/удаляет точную
пару `("pre_llm_call", "<session-start.sh> --format hermes")`, не заменяет
битый JSON и пишет валидное изменение атомарно.

### 5.3. `block_sync` / `block_remove` — детали

Работают с текстовыми конфигами (config.yaml, config.toml, GEMINI.md):

- sync: добавляет блок, если его нет; иначе заменяет ровно один полный диапазон
  START/END, сохраняя весь окружающий контент. Идентичный текст — no-op.
- safety: сломанные, повторные или вложенные маркеры останавливают установку,
  а не заставляют её угадывать ownership. Реальная замена получает backup и
  пишется атомарно.
- remove: вырезает от START до END включительно, убирает одну
  предшествующую пустую строку, если она осталась от add.

### 5.4. Lifecycle-hooks Kimi 0.39.x

Kimi 0.39.x отбрасывает stdout `SessionStart`, поэтому управляемый TOML-блок
ставит четыре hook:

- `SessionStart` (`startup|resume`) готовит artifact state и сбрасывает
  fingerprint доставки;
- `PreCompact` (`manual|auto`) синхронно сбрасывает его до compaction;
- `UserPromptSubmit` запускает каноническую plain-доставку и повторяет pending
  bootstrap либо выдаёт ready-bundle при изменении fingerprint;
- `Stop` при pending-валидации завершает работу с кодом 2 и continuation request
  в stderr, а при `ready` возвращает 0.

State-markers находятся в
`${KIMI_CODE_HOME:-~/.kimi-code}/choirboy-prompt/hook-state`, если путь не
переопределён через `CHOIRBOY_STATE_DIR`. Нормализованный ready-fingerprint
записывается только после успешной выдачи stdout.

---

## 6. Edge-cases

1. **Уже есть top-level `hooks:` в Hermes-конфиге.** Установщик
   отказывается (`die`) с инструкцией слить блоки вручную — чтобы не
   затереть чужие хуки.
2. **Уже есть `hooks =` в Kimi-конфиге.** Аналогично: die с подсказкой
   перейти на `[[hooks]]`.
3. **Codex: хуки выключены.** Нашлась строка `hooks = false` в
   `~/.codex/config.toml` → предупреждение (не блокировка).
4. **Файла нет.** `mkdir -p` + создание пустого `{}`/пустого файла.
5. **Папка плагина переехала.** JSON-hooks матчатся по имени скрипта, а
   управляемые текстовые блоки синхронизируются: старые абсолютные пути
   заменяются без дублей.
6. **Повторный запуск или обновление.** Актуальные регистрации — no-op; старые
   наши регистрации показываются как `stale` и обновляются обычным install.
7. **`--uninstall` без установки.** `no block in file — skipped`, не
   падает.
8. **`--target none` + `--instructions`.** Только управляемые
   lifecycle-блоки инструкций, без runtime-specific hooks.
9. **Параллельные старты Hermes.** State-файл в `/tmp` без блокировок —
   возможны гонки (известное ограничение, см. README).
10. **Чужой OpenCode-плагин по управляемому пути.** Install и uninstall
    отказываются перезаписывать или удалять файл без ownership-маркера.

---

## 7. Как проверить установку

```bash
./install.sh --list                    # статусы
./install.sh --target opencode         # установить глобальный адаптер OpenCode
python3 scripts/artifact-generator.py status
python3 scripts/artifact-generator.py verify  # exit 2, пока snapshot не ready
grep -F 'agent-plugin:vibe-lore' ~/.config/opencode/plugins/agent-plugin.ts
bash hooks/session-start.sh --format plain | head -40   # пейлоад
echo '{"session_id":"hook-check","extra":{"is_first_turn":true}}' \
  | bash hooks/session-start.sh --format hermes | head -c 120   # первый ход
echo '{"session_id":"hook-check","extra":{"is_first_turn":false}}' \
  | bash hooks/session-start.sh --format hermes            # → {}
```

`stale` в `--list` требует действия: повтори install для этого target и проверь,
что статус стал `installed` (или `prepared` для Grok Bot). Для ready-bundle
`session-context` должен содержать `# Established project history` и полные
тела dossiers; сообщение только с путём не считается успешной доставкой памяти.

Полный ad-hoc сьют — `docs/testing.md`.
