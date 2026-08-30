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
  Claude внедрит пейлоад дважды;
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
| `--list` | Без записи показывает `absent` / `detected` / `installed` |

Требование `install.sh`: `python3` для JSON-операций. Форматы хука `claude` и
`plain` работают на Bash без `jq`/`python3`; формат `hermes` требует один из
этих двух JSON-парсеров. Автоматический lifecycle артефактов требует `python3`:
установщик готовит только request, а следующая сессия поручает текущему агенту
написать dossiers и пройти validator. По умолчанию ручная установка хранит их
в `artifacts/`; путь переопределяется через `CHOIRBOY_ARTIFACTS_DIR`.

---

## 2. Таргеты

Детекция рантайма — по бинарю или наличию конфиг-директории:

```bash
claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
codex)  command -v codex  >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
opencode) command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] ;;
hermes) command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ] ;;
kimi)   command -v kimi   >/dev/null 2>&1 || [ -d "$HOME/.kimi-code" ] ;;
gemini) command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
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
| opencode | `~/.config/opencode/plugins/agent-plugin.ts` | глобальный `chat.message`-плагин |
| hermes | `~/.hermes/config.yaml` | маркированный блок `hooks.pre_llm_call` + consent-allowlist |
| kimi | `~/.kimi-code/config.toml` | маркированный блок `[[hooks]]` |
| gemini | `~/.gemini/GEMINI.md` | маркированный HTML-блок-указатель |
| `--instructions FILE` | любой файл | маркированный блок-указатель (HTML или `#`) |

---

## 3. Маркеры и идемпотентность

### 3.1. Маркер

Все блоки помечены `MARK="agent-plugin:vibe-lore"`. Формы маркеров:

- hash-стиль (конфиги, TOML): `# >>> agent-plugin:vibe-lore >>>` /
  `# <<< agent-plugin:vibe-lore <<<`
- html-стиль (markdown-инструкции): `<!-- agent-plugin:vibe-lore START -->` /
  `<!-- agent-plugin:vibe-lore END -->`

Маркер — это и идентификатор владения, и граница блока для удаления.

### 3.2. Идемпотентность

- `block_add` проверяет START-маркер: уже есть → `already present — skipped`,
  ничего не дублирует.
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

### 3.3. Питфолл маркеров

`block_add` идемпотентен по START-маркеру. Это значит: если в
`instruction_block` (текст блока-указателя) внесли правку, уже
установленные блоки (GEMINI.md, `--instructions`-файлы) **не обновятся** —
установщик скажет `already present — skipped`, копия останется старой.
Лечение: пропатчить установленный файл вручную или `--uninstall` + install.

После любой правки `instruction_block` — grep по маркеру в установленных
файлах.

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
| `target_installed` | Уже установлено? | grep по маркеру/имени скрипта |
| `backup` | Бэкап перед правкой | `cp -p` с timestamp |
| `block_add` | Добавить маркированный блок | идемпотентен по START |
| `block_remove` | Удалить маркированный блок | по START/END, чистит хвостовую пустую строку |
| `json_hook` | Хук в Claude-образный JSON | матч по имени скрипта, `is_ours()`/`has_exact()` |
| `opencode_plugin` | Управление адаптером OpenCode | guard по маркеру, атомарная замена, timestamp-бэкап |
| `hermes_allowlist` | Consent-allowlist Hermes | точная пара (event, command) |
| `instruction_block` | Текст блока-указателя | HTML или `#`-комментарии |
| `do_claude` / `do_codex` / `do_opencode` / `do_hermes` / `do_kimi` / `do_gemini` | Установка в таргет | per-target логика |
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
  `additionalContextLimit: 20000` для полного стартового payload.
- uninstall: удаляет все записи `is_ours()`.
- Невалидный JSON не заменяет; при реальном изменении сохраняет бэкап и пишет
  новый файл атомарно.

### 5.2. `hermes_allowlist` — детали

Hermes требует явного consent на shell-хук: пара `(event, command)` в
`~/.hermes/shell-hooks-allowlist.json`. Функция добавляет/удаляет точную
пару `("pre_llm_call", "<session-start.sh> --format hermes")`, не заменяет
битый JSON и пишет валидное изменение атомарно.

### 5.3. `block_add` / `block_remove` — детали

Работают с текстовыми конфигами (config.yaml, config.toml, GEMINI.md):

- add: дописывает блок в конец (с пустой строкой перед), если START нет.
- remove: вырезает от START до END включительно, убирает одну
  предшествующую пустую строку, если она осталась от add.

---

## 6. Edge-cases

1. **Уже есть top-level `hooks:` в Hermes-конфиге.** Установщик
   отказывается (`die`) с инструкцией слить блоки вручную — чтобы не
   затереть чужие хуки.
2. **Уже есть `hooks =` в Kimi-конфиге.** Аналогично: die с подсказкой
   перейти на `[[hooks]]`.
3. **Codex: хуки выключены.** `grep hooks = true` в `~/.codex/config.toml`
   не нашёлся → предупреждение (не блокировка).
4. **Файла нет.** `mkdir -p` + создание пустого `{}`/пустого файла.
5. **Папка плагина переехала.** JSON-хуки матчатся по имени скрипта —
   старые записи заменяются, дублей нет.
6. **Повторный запуск.** Всё идемпотентно: `unchanged`/`skipped`.
7. **`--uninstall` без установки.** `no block in file — skipped`, не
   падает.
8. **`--target none` + `--instructions`.** Только блоки-указатели, без
   рантаймов.
9. **Параллельные старты Hermes.** State-файл в `/tmp` без блокировок —
   возможны гонки (известное ограничение, см. README).
10. **Чужой OpenCode-плагин по управляемому пути.** Install и uninstall
    отказываются перезаписывать или удалять файл без ownership-маркера.

---

## 7. Как проверить установку

```bash
./install.sh --list                    # статусы
./install.sh --target opencode         # установить глобальный адаптер OpenCode
grep -F 'agent-plugin:vibe-lore' ~/.config/opencode/plugins/agent-plugin.ts
bash hooks/session-start.sh --format plain | head -40   # пейлоад
echo '{"session_id":"demo","extra":{"is_first_turn":true}}' \
  | bash hooks/session-start.sh --format hermes | head -c 120   # первый ход
echo '{"session_id":"demo","extra":{"is_first_turn":false}}' \
  | bash hooks/session-start.sh --format hermes            # → {}
```

Полный ad-hoc сьют — `docs/testing.md`.

---

## 8. Исследовательские fixtures в пакете

Marketplace/custom-plugin ZIP включает tracked-папку `sessions/`, чтобы
нативные доказательные артефакты можно было изучить после установки. Это
документация: ни `SessionStart`, ни `load-context` не импортируют файлы в
нативный session store пользователя, и в автоматический lore payload они не
входят. Ручное воспроизведение описано в
[`sessions/README.ru.md`](../sessions/README.ru.md).
