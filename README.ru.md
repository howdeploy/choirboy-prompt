<div align="center">

# choirboy-prompt

<h3>Постоянная память проектов и автоматические артефакты от агентов</h3>

<p>
<strong>Читать на других языках</strong><br>
<a href="README.md">🇺🇸 English</a> ·
<a href="README.ru.md">🇷🇺 Русский</a> ·
<a href="README.zh-CN.md">🇨🇳 简体中文</a>
</p>

<p>
<img alt="Bash 5.0+" src="https://img.shields.io/badge/bash-5.0%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
<img alt="runtimes" src="https://img.shields.io/badge/runtimes-claude%20%C2%B7%20codex%20%C2%B7%20opencode%20%C2%B7%20hermes%20%C2%B7%20kimi%20%C2%B7%20gemini%20%C2%B7%20grok%20%C2%B7%20grokbot-22D3EE?style=flat-square">
<a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-3FB950?style=flat-square"></a>
</p>

<p>
choirboy-prompt — production-плагин памяти агентов. Он загружает принятую
историю, ресерчи, рабочие правила и проверенные проектные dossiers во все
поддерживаемые рантаймы, чтобы каждая новая сессия продолжала ту же работу.
</p>

<p>
Все model-facing канонические файлы, research, lifecycle-инструкции, INDEX и
dossiers пишутся только на английском. На три языка локализована только
пользовательская документация: English, Русский и 简体中文.
</p>

</div>

---

## Как это работает

1. **Установка.** `./install.sh` находит установленные на машине агенты и
   регистрирует в каждом хук, который срабатывает на старте новой сессии.
   Там, где хуков нет, — синхронизируемый управляемый блок в файле инструкций,
   а для Grok Bot — workflow для ручного импорта.
2. **Сборка.** Фиксированный лор — это `prompt.md`, `security-posture.md`,
   `lore.md`, `user.md` и `context/research-index.md`, плюс готовые dossiers.
3. **Доставка.** SessionStart у Claude Code и Codex отдаёт только короткий
   статус. Эти харнессы режут или выносят длинный текст хука, поэтому в статусе
   нет лора и нет маркера `choirboy-delivery`. Skill load-context догружает лор,
   если в разговоре ещё нет блока `choirboy-context`. Kimi, OpenCode и Hermes
   по-прежнему получают полный plain-payload на каналах, которые его принимают.
4. **Проектные артефакты.** Готовый бандл из поставки восстанавливается, если
   он всё ещё совпадает с каноническими источниками. Агент пишет или обновляет
   dossiers только когда пользователь явно просит обновить память Choirboy.
   Stop не продолжает ход, чтобы это потребовать.
5. **Непрерывность.** Стабильное user-data хранилище, миграция и структурная
   проверка сохраняют одну память проектов между обновлениями.

Устройство плагина изнутри: [docs/architecture.md](docs/architecture.md).

### Поддерживаемые рантаймы

| Рантайм | Куда ставится | Механика |
|---|---|---|
| Claude Code CLI / Desktop Code | marketplace или `~/.claude/settings.json` | короткий статус SessionStart; Stop не продолжает ход; lore несёт skill load-context |
| Claude Chat / Cowork | custom plugin | skill load-context (в Chat нет SessionStart) |
| Codex | `~/.codex/hooks.json` | короткий статус SessionStart; Stop не продолжает ход (инсталлер предупреждает, если в `~/.codex/config.toml` задано `hooks = false`) |
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | плагин добавляет актуальный лор и ready-артефакты в каждый model-bound system context, включая запрос после compaction |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + consent-allowlist, только первый ход |
| Kimi Code 0.39.x | `~/.kimi-code/config.toml` | SessionStart/PreCompact сбрасывают доставку; UserPromptSubmit выдаёт изменившийся plain-контекст; Stop не продолжает ход |
| Gemini | `~/.gemini/GEMINI.md` | синхронизируемый lifecycle-блок инструкций |
| Grok Build | `~/.grok/AGENTS.md` | синхронизируемый lifecycle-блок инструкций (stdout хука игнорируется) |
| Grok Bot | `~/.grokbot/choirboy-context/SKILL.md` | workflow для ручного импорта; `@choirboy-context` в каждом новом чате |
| Pi | `~/.pi/agent/APPEND_SYSTEM.md` | тот же контракт инструкций, что у Gemini, плюс skill `load-context` |
| Oh My Pi (`omp`) | `~/.omp/agent/AGENTS.md` | тот же контракт инструкций, что у Gemini, плюс skill `load-context` |
| llama-server UI | `~/.config/llama.cpp/choirboy-ui.json` | стартовый `systemMessage` с тем же контрактом; запускать с `--ui-config-file` |

## Установка

### Linux

Нужны `git`, `bash` и `python3`. Проверка: `git --version && python3 --version && bash --version`.

```bash
git clone https://github.com/howdeploy/choirboy-prompt.git
cd choirboy-prompt
./install.sh
```

Готово. Открой **новую** сессию. Claude Code и Codex покажут короткий статус памяти, а лор подгрузит skill load-context. Kimi, OpenCode и Hermes получают полный plain-payload.

- Только выбранные приложения: `./install.sh --target claude,codex`
- Статусы по рантаймам: `./install.sh --list` (`stale` означает, что управляемую регистрацию надо синхронизировать)
- Откат: `./install.sh --uninstall` (timestamp-бэкапы `*.bak.*` остаются рядом с конфигами)
- `Permission denied` при запуске: `chmod +x install.sh` и повтори

### Windows (любой PowerShell)

Нужен Python 3. Git нужен только для клонирования репозитория. На Windows регистрируются PowerShell-хуки, Git Bash не нужен. Команды запускай в обычном Windows PowerShell или в PowerShell 7:

```powershell
git clone https://github.com/howdeploy/choirboy-prompt.git
Set-Location choirboy-prompt
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` запускается в любом PowerShell, включая встроенный в Windows
Windows PowerShell 5.1. Хукам нужен PowerShell 7 (`pwsh`). Если его нет,
установщик ставит его сам: сначала через `winget`, а если не вышло — из
подписанного Microsoft MSI в релизах PowerShell на GitHub (Windows попросит
подтверждение администратора). После такой первой установки перезапусти открытые
терминалы и приложения агентов, чтобы они нашли `pwsh`. `-ExecutionPolicy Bypass`
действует только на этот запуск и не меняет системную политику.

Установщик использует Python-хелперы и контекстные файлы из клона, поэтому
запускай его из папки репозитория.

- Только выбранные приложения: `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --target claude,codex`
- Статусы по рантаймам: `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --list`
- Откат: `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --uninstall`

Проектные артефакты хранятся вне ручного checkout. Приоритет путей:
`CHOIRBOY_ARTIFACTS_DIR` → `${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`. Повторный запуск установщика
синхронизирует управляемые регистрации и, если стабильный root пуст, переносит
авторский bundle из старого checkout, ничего не перезаписывая. Приватная
migration-запись позволяет продолжить прерванный перенос, не показывая lifecycle
частичный набор INDEX/manifest/dossiers.

Особые случаи — ручной импорт workflow в Grok Bot, установка через Claude
marketplace / Desktop / Chat / Cowork, Windows и WSL — разобраны в
[docs/installer.md](docs/installer.md). **Не совмещай** marketplace-плагин
с `./install.sh --target claude`: лор загрузится дважды.

## Заполни свои файлы

Репозиторий содержит канонический комплект лора. Для своей установки замени
его проверенной памятью своего проекта **прямо в клоне**: `install.sh`
ссылается на рабочую копию, поэтому правки подхватываются со следующей сессии.
Форкать и копировать ничего не нужно.

| Файл | Что писать |
|---|---|
| `prompt.md` | правила работы, приоритеты, явные границы |
| `security-posture.md` | рамка безопасности и правила раскрытия |
| `user.md` | только устойчивые предпочтения совместной работы |
| `lore.md` | реальные проекты, решения, результаты и уроки |
| `research/NN-topic.md` | по одному решению: вопрос, доказательства, варианты, решение, риски, когда пересматривать |
| `context/research-index.md` | по одной строке на каждый research |

Порядок:

1. Перепиши `prompt.md`, `user.md`, `lore.md` под свой проект.
2. На каждое решение — `research/NN-topic.md`, плюс строка в индексе.
3. Пересобери и проверь: `python3 scripts/build-context.py && bash scripts/test.sh`.

Полный гайд с шаблонами и quality gate: [docs/authoring.md](docs/authoring.md).

## Зачем это существует

Обычная новая сессия агента не знает всей операционной истории проекта.
Повторный пересказ решений тратит время и создаёт расхождения. Плагин превращает
канонический лор репозитория и написанные агентом dossiers в автоматически
загружаемый и проверяемый слой памяти для всех поддерживаемых рантаймов.
Установка, миграция, диагностика и откат остаются явными и воспроизводимыми.

## Документация

| Документ | Содержимое |
|---|---|
| [Авторинг своей памяти](docs/authoring.md) | Обязательный workflow и шаблоны lore и research |
| [Архитектура](docs/architecture.md) | Дерево репо, анатомия пейлоада, форматы, протокол Hermes |
| [Установщик](docs/installer.md) | Все пути установки, таргеты, маркеры, бэкапы, edge-cases |
| [Troubleshooting](docs/troubleshooting.md) | Диагностика доставки, delivery markers, Windows/SSH/Cloud/WSL |
| [Безопасность и раскрытие](docs/security.md) | Рамка безопасности, чек-лист санитизации, ответственное раскрытие |
| [Тестирование](docs/testing.md) | Проверки хука и установщика, ad-hoc сьют |

## Известные ограничения

- Grok Bot: нужен одноразовый импорт workflow и явный запуск
  `@choirboy-context` в каждом новом разговоре.
- У Gemini, Grok Build и `--instructions` нет нативного delivery-hook: их
  управляемый блок просит агента запустить lifecycle-команду. Обычный повторный
  запуск установщика синхронизирует блок; цикл uninstall/install не нужен.
- Дедупликация первого хода в Hermes — state-файл в `/tmp` без блокировок;
  при параллельных стартах возможны гонки.
- Claude Chat не исполняет SessionStart — там лор грузит skill вручную;
  Cloud/WSL/SSH-нюансы — в [troubleshooting](docs/troubleshooting.md).

---

## License

MIT. См. [LICENSE](LICENSE).

---

<div align="center">
<strong>Innocent as a choirboy.</strong>
</div>
