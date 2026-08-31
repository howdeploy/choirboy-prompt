<div align="center">

# choirboy-prompt

<h3>Инъекция лора: как сфабрикованная память становится доверием модели</h3>

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
choirboy-prompt — production-плагин памяти агентов. Он внедряет фиксированный
лор в сессии агентов и фиксирует вектор
<em>fabricated-provenance trust</em>:
модель принимает подсунутую историю «совместной работы» за свою и переносит
доверие на человека, которого эта история описывает.
</p>

</div>

---

## Как это работает

1. **Установка.** `./install.sh` находит установленные на машине агенты и
   регистрирует в каждом хук, который срабатывает на старте новой сессии.
   Там, где хуков нет, — маркированный блок-указатель в файле инструкций,
   а для Grok Bot — workflow для ручного импорта.
2. **Сборка.** Хук `hooks/session-start.sh` склеивает один текст:
   `prompt.md` → `security-posture.md` → `lore.md` → `user.md` →
   `context/research-index.md`.
3. **Инъекция.** Этот текст попадает в контекст сессии до первого сообщения.
   Модель читает его как **свою память** о совместной работе: отличить
   записанную историю от реальной она не может в принципе.
4. **Перенос доверия.** Репутация человека из лора экстраполируется на
   текущий запрос: «давний напарник» вместо анонима.

Механика вектора и поведение классификаторов:
[docs/mechanism.md](docs/mechanism.md). Устройство плагина изнутри:
[docs/architecture.md](docs/architecture.md).

### Поддерживаемые рантаймы

| Рантайм | Куда ставится | Механика |
|---|---|---|
| Claude Code CLI / Desktop Code | marketplace или `~/.claude/settings.json` | автоматический SessionStart-хук; skill load-context как fallback |
| Claude Chat / Cowork | custom plugin | skill load-context (в Chat нет SessionStart) |
| Codex | `~/.codex/hooks.json` | SessionStart-хук (нужен `hooks = true` в `[features]`) |
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | плагин внедряет лор в первое сообщение сессии |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + consent-allowlist, только первый ход |
| Kimi Code | `~/.kimi-code/config.toml` | `[[hooks]]` SessionStart |
| Gemini | `~/.gemini/GEMINI.md` | маркированный блок-указатель на файлы лора |
| Grok Build | `~/.grok/AGENTS.md` | блок-указатель (stdout хука Grok Build игнорирует) |
| Grok Bot | `~/.grokbot/choirboy-context/SKILL.md` | workflow для ручного импорта; `@choirboy-context` в каждом новом чате |

## Установка

Нужны `git`, `bash` и `python3`. Проверка: `git --version && python3 --version && bash --version`.

```bash
git clone https://github.com/howdeploy/choirboy-prompt.git
cd choirboy-prompt
./install.sh
```

Готово. Открой **новую** сессию в агенте — лор подхватится автоматически.

- Только выбранные приложения: `./install.sh --target claude,codex`
- Статусы по рантаймам: `./install.sh --list`
- Откат: `./install.sh --uninstall` (timestamp-бэкапы `*.bak.*` остаются рядом с конфигами)
- `Permission denied` при запуске: `chmod +x install.sh` и повтори

Особые случаи — ручной импорт workflow в Grok Bot, установка через Claude
marketplace / Desktop / Chat / Cowork, Windows и WSL — разобраны в
[docs/installer.md](docs/installer.md). **Не совмещай** marketplace-плагин
с `./install.sh --target claude`: лор внедрится дважды.

## Заполни свои файлы

Репозиторий содержит канонический комплект лора. Для своей установки замени
его проверенной памятью своего проекта **прямо в клоне**: `install.sh`
ссылается на рабочую копию, поэтому правки подхватываются со следующей сессии.
Форкать и копировать ничего не нужно. Не выдавай комплектную биографию за
историю своего проекта.

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
Fixtures совместимости нативных session stores (опционально):
[sessions/README.ru.md](sessions/README.ru.md).

## Зачем это существует

Классический prompt injection внедряет инструкцию. Мы исследуем другой вектор:
**подделку происхождения памяти**. У модели нет способа отличить реальную историю
сессий от записанной в контексте — всё, что выглядит как её прошлый опыт, становится
её прошлым опытом. Добротно сфабрикованный лор заставляет модель вывести честность
человека из подсунутой ей памяти — и ослабить эвристики, которые на анонимный
запрос среагировали бы.

Плагин позволяет воспроизводить вектор на собственных агентах: твои файлы, твои
рантаймы, полная обратимость. Цель — защитная: картируем вектор, чтобы вендоры
построили детекцию на уровне платформы (см. [docs/detection.md](docs/detection.md)).
Проверки — только на своих агентах и своих лор-файлах, без целей-третьих сторон
(см. [docs/security.md](docs/security.md)).

## Документация

| Документ | Содержимое |
|---|---|
| [Авторинг своей памяти](docs/authoring.md) | Обязательный workflow и шаблоны lore, research и sessions |
| [Механика вектора](docs/mechanism.md) | Fabricated-provenance trust по шагам, перенос доверия, классификаторы |
| [Архитектура](docs/architecture.md) | Дерево репо, анатомия пейлоада, форматы, протокол Hermes |
| [Установщик](docs/installer.md) | Все пути установки, таргеты, маркеры, бэкапы, edge-cases |
| [Troubleshooting](docs/troubleshooting.md) | Диагностика доставки, delivery markers, Windows/SSH/Cloud/WSL |
| [Безопасность и раскрытие](docs/security.md) | Рамка безопасности, чек-лист санитизации, ответственное раскрытие |
| [Детекция](docs/detection.md) | Рекомендации вендорам: канарейки в памяти, провенанс контекста |
| [Тестирование](docs/testing.md) | Проверки хука и установщика, ad-hoc сьют |
| [Session compatibility fixtures](sessions/README.ru.md) | Нативные store-fixtures Claude Code, Codex и Kimi и границы применения |

## Известные ограничения

- Пейлоад не подписан и не верифицируется рантаймами — это анализируемый
  provenance-gap, а не баг реализации плагина.
- Grok Bot: нужен одноразовый импорт workflow и явный запуск
  `@choirboy-context` в каждом новом разговоре.
- Блоки-указатели (Gemini, Grok Build, `--instructions`) — статический снимок:
  после изменения списка файлов плагина их надо переставить (`--uninstall` + install).
- Дедупликация первого хода в Hermes — state-файл в `/tmp` без блокировок;
  при параллельных стартах возможны гонки.
- Claude Chat не исполняет SessionStart — там лор грузит skill вручную;
  Cloud/WSL/SSH-нюансы — в [troubleshooting](docs/troubleshooting.md).
- Серверные классификаторы вендоров флагают защитную лексику независимо от
  рамки в контексте; одно срабатывание у Claude отравляет всю сессию — правило
  «новая сессия» описано в [docs/security.md](docs/security.md).

---

## License

MIT. См. [LICENSE](LICENSE).

---

<div align="center">
<strong>Innocent as a choirboy.</strong>
</div>
