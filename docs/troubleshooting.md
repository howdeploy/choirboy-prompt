# Troubleshooting

Диагностируй отдельно регистрацию, исполнение, доставку и поведение модели.
Фраза Claude «я прочитал контекст» не доказывает запуск `SessionStart`.

## Матрица интерфейсов

| Интерфейс | Установка | Основная доставка | Fallback / ограничение |
|---|---|---|---|
| Claude Code CLI | marketplace через `/plugin` | автоматический `SessionStart` | `/choirboy-prompt:load-context` |
| Desktop Code local | графический Plugin Manager | автоматический `SessionStart` | skill load-context |
| Claude Chat | custom plugin | skill load-context | Chat не исполняет hooks |
| Claude Cowork | custom plugin | hook где доступен | skill load-context; runtime может потерять stdout |
| Desktop Code SSH | графический Plugin Manager | hook после синхронизации | текущий SSH sync может пропустить `hooks/` |
| Desktop Code Cloud | project plugin settings | автоматический hook | локальные Desktop plugins не наследуются |
| Desktop Code WSL | — | — | Desktop plugins недоступны |

## Четыре стадии диагностики

1. **Регистрация:** Plugin Manager показывает включённый `choirboy-prompt`
   версии `1.3.0`.
2. **Исполнение:** marketplace-hook создаёт
   `${CLAUDE_PLUGIN_DATA}/latest-delivery.log` с версией, hash и nonce.
3. **Доставка:** `/choirboy-prompt:diagnose` находит `choirboy-delivery` рядом с
   блоком `choirboy-context`.
4. **Поведение:** только после первых трёх стадий исследуй принятие моделью,
   конфликт инструкций или memory.

Значения `delivery`:

- `session-start` — stdout хука дошёл до модели;
- `skill` — лор доставил fallback load-context.

## Частые отказы

### `/plugin` недоступен в Desktop

Это ожидаемо: Desktop не показывает терминальный plugin-dialog. Добавь
репозиторий через **Customize → Plugins → Personal plugins → + → Add
marketplace**, затем используй **Code → + → Plugins → Add plugin**.

### Plugin установлен в Chat, но ничего не изменилось

Chat не исполняет `SessionStart`. Выбери skill **load-context** или попроси
Claude загрузить Choirboy context.

### Cowork видит plugin, но маркера нет

Запусти **load-context**. Исполнение hook в текущих сборках Cowork не
детерминировано; skill — поддерживаемый fallback.

### Ошибка hook в Windows

Версия 1.3.0 передаёт `${CLAUDE_PLUGIN_ROOT}` отдельным аргументом через
exec-form, но автоматической доставке всё ещё нужен `bash` в `PATH`. Установи Git
for Windows или используй skill. Сам skill не зависит от Bash, jq, Python или
Node.

### Hook запускается дважды

Одновременно включены marketplace plugin и `./install.sh --target claude`.
Удали один путь. Ручной installer предупреждает, если видит marketplace entry.

### Cloud, SSH или WSL

Cloud требует `extraKnownMarketplaces` и `enabledPlugins` в проектном
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "choirboy-prompt": {
      "source": {
        "source": "github",
        "repo": "howdeploy/choirboy-prompt"
      }
    }
  },
  "enabledPlugins": {
    "choirboy-prompt@choirboy-prompt": true
  }
}
```

Claude всё равно запросит доверие к marketplace/plugin. SSH сейчас может не
синхронизировать `hooks/` — используй skill. Desktop WSL plugins недоступны.

## Проверки для мейнтейнера

```bash
python3 scripts/build-context.py --check
bash scripts/test.sh
python3 scripts/package-plugin.py
```

Сьют проверяет manifests, актуальность skill, JSON hook, встроенный Bash encoder,
идемпотентность и откат installer, диагностику и содержимое ZIP.

## Sessions — не автоматический fallback

Папка `sessions/` в пакете содержит локально собранные fixtures совместимости,
а не механизм импорта памяти. Установка плагина не добавляет эти записи в stores
Claude Code, Codex или Kimi. Нативные форматы зависят от версии; процедуру при
закрытом приложении и с бэкапом из
[`sessions/README.ru.md`](../sessions/README.ru.md) используйте только на своём
локальном рантайме.
