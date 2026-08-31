# Тестирование

Проверки hook, skills, installer, диагностики и пакета. Канонический runner —
`bash scripts/test.sh`; разделы ниже объясняют отдельные assertions.

---

## 1. Принцип

- Каждая проверка — отдельная bash-команда с явным PASS/FAIL.
- Сьют запускается из корня репозитория; временные файлы — под `/tmp` с
  префиксом `choirboy-test.`.
- После прогона временные файлы удаляются. Чтобы сохранить их и вывести точный
  путь для проверки, задай `CHOIRBOY_TEST_KEEP_TMP=1`.
- Пейлоад проверяется **в том виде, в каком его получит рантайм**, а
  не «по наитию».

---

## 2. Проверки хука

### 2.1. Manifests и версия

```bash
python3 -c 'import json; d=json.load(open(".claude-plugin/plugin.json")); print(d["name"], d["version"])'
claude plugin validate .
```

Ожидание: оба манифеста валидны, имя и версия печатаются, Claude validator
сообщает `Validation passed`. Версия в `plugin.json` — источник версии плагина;
то же значение записывается в marketplace и печатается в пейлоаде.

### 2.2. Claude-формат — валидный JSON с контекстом

```bash
bash hooks/session-start.sh --format claude \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "additionalContext" in d["hookSpecificOutput"]; print("OK")'
```

Ожидание: `OK`. Дополнительно проверить первый заголовок `prompt.md` и marker
`choirboy-delivery` с версией, способом доставки, SHA-256 и nonce.

### 2.3. Claude-формат без jq и python3

```bash
PYTHON_BIN="$(command -v python3)"
TMP_BIN="$(mktemp -d)"
for cmd in cat date dirname head mkdir mv sed; do
  src="$(command -v "$cmd")"
  printf '#!/bin/bash\nexec "%s" "$@"\n' "$src" > "$TMP_BIN/$cmd"
  chmod +x "$TMP_BIN/$cmd"
done
PATH="$TMP_BIN" /bin/bash hooks/session-start.sh --format claude \
  | "$PYTHON_BIN" -c 'import json,sys; json.load(sys.stdin); print("OK")'
rm -rf "$TMP_BIN"
```

Ожидание: `OK`. Тест принудительно убирает `jq` и `python3` из `PATH` и
проверяет встроенный Bash-кодировщик, который используется при установке из
Claude Desktop на чистую систему.

### 2.4. Plain-формат — человекочитаемый пейлоад

```bash
bash hooks/session-start.sh --format plain | head -40
```

Ожидание: заголовки prompt → posture → lore → user → research-указатель
в правильном порядке, разделители `---`.

### 2.5. Hermes: первый ход внедряет

```bash
SID="hook-check-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":true}}' "$SID" \
  | bash hooks/session-start.sh --format hermes | head -c 120
```

Ожидание: `{"context": "..."` — пейлоад пришёл.

### 2.6. Hermes: второй ход молчит

```bash
SID="hook-check-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":false}}' "$SID" \
  | bash hooks/session-start.sh --format hermes
```

Ожидание: `{}`.

### 2.7. Hermes: фолбэк без флага — один раз на session_id

```bash
SID="hook-check-fb-$(date +%s)"
printf '{"session_id":"%s"}' "$SID" \
  | bash hooks/session-start.sh --format hermes | head -c 120   # → context
printf '{"session_id":"%s"}' "$SID" \
  | bash hooks/session-start.sh --format hermes                 # → {}
```

Ожидание: первый вызов — `{"context": ...`, второй — `{}`.

> Питфолл: после теста почистить sid из state-файла
> `${TMPDIR:-/tmp}/agent-plugin-hermes-${USER}.state`, иначе фолбэк
> «запомнит» sid и следующий прогон с тем же sid вернёт `{}`.

### 2.8. Hermes: пустой stdin не роняет хук

```bash
printf '' | bash hooks/session-start.sh --format hermes
```

Ожидание: `{}` (не ошибка). Причина: `input="$(cat 2>/dev/null || true)"`.

---

## 3. Проверки установщика

### 3.0. Marketplace-установка в изолированный Claude config

```bash
VERIFY_CFG="$(mktemp -d)"
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin marketplace add "$PWD"
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin install choirboy-prompt@choirboy-prompt
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin list | grep 'Status: ✔ enabled'
find "$VERIFY_CFG" -depth -delete
```

Ожидание: marketplace добавлен, версия плагина установлена во временный cache,
статус — `enabled`, ошибок загрузки хука нет. Локальный `$PWD` используется
только для проверки неопубликованной рабочей копии; пользовательский путь из
README добавляет тот же marketplace с GitHub.

### 3.1. --list

```bash
./install.sh --list
```

Ожидание: колонки TARGET/STATUS/LOCATION; статусы `absent`/`detected`/
`installed`.

### 3.2. Идемпотентность

```bash
./install.sh --target hermes ; ./install.sh --target hermes
```

Ожидание: второй запуск печатает `already present — skipped` /
`unchanged`; файлы не дублируются.

### 3.3. Бэкапы

После установки в существующий файл проверить:

```bash
ls -la ~/.hermes/config.yaml.bak.*
```

Ожидание: бэкап с timestamp существует.

### 3.4. Откат

```bash
./install.sh --uninstall --target hermes
./install.sh --list | grep hermes   # → detected (не installed)
```

Ожидание: блок удалён, маркер `agent-plugin:vibe-lore` в конфиге
отсутствует.

### 3.5. Хук не падает без контент-файлов

Имитация свежего клона (без `prompt.md`/`lore.md`/`user.md`):

```bash
TMP=$(mktemp -d)
cp -r hooks .claude-plugin "$TMP/"
# контент-файлов в TMP нет
bash "$TMP/hooks/session-start.sh" --format plain >/dev/null 2>&1
echo "exit=$?"   # ожидание: 0 (graceful-режим: файлы пропущены с предупреждением в stderr)
rm -rf "$TMP"
```

Graceful-режим реализован в `hooks/session-start.sh`: отсутствующие
контент-файлы пропускаются с предупреждением в stderr, хук не падает
с `set -euo pipefail` (см. `docs/security.md` §3.3).

### 3.6. Переезд папки плагина

Установить, переместить папку, установить снова:

```bash
./install.sh --target claude
mv /path/to/plugin /path/to/plugin-moved
/path/to/plugin-moved/install.sh --target claude
```

Ожидание: в `~/.claude/settings.json` одна запись нашего хука (не две);
старая заменилась новой — `json_hook` матчит по имени скрипта.

### 3.7. Жизненный цикл адаптера OpenCode

Канонический сьют устанавливает адаптер в изолированный `HOME`, повторяет
установку, проверяет `--list`, обновляет намеренно изменённый маркированный
plugin с бэкапом и откатывает его с ещё одним бэкапом. Отдельно проверяется, что
чужой немаркированный файл `~/.config/opencode/plugins/agent-plugin.ts` никогда
не перезаписывается.

Ожидание: проверки `OpenCode install, list, idempotent refresh, backup, and
rollback` и `OpenCode foreign-plugin guard` печатают `PASS`. Сгенерированный
адаптер должен использовать `chat.message`, сохранённую историю сессии,
text-part с техническим флагом `synthetic: true`, канонический plain-хук и
fail-open обработку ошибок.

---

## 4. Проверки контента (санитизация)

Перед любой публикацией:

```bash
# запрещённые идентификаторы (имена NSFW/refusal-моделей, пути к
# приватным проектам). Конкретный список имён — приватный чек-лист,
# вне репо; здесь — обобщённый паттерн:
grep -rniE "(nsfw-(checkpoint|lora)|refusal-reduction|private-research)" --include="*.md" --include="*.sh" .
# полные адреса
grep -rnoE "bc1[a-zA-Z0-9]{20,}|0x[a-fA-F0-9]{40}" .
# замыкание: все ссылки на файлы существуют
for f in $(grep -rhoE "(research/[0-9]+-[a-z-]+\.md|research/coldcard/[a-z_.]+\.(md|py))" --include="*.md" . | sort -u); do
  [ -f "$f" ] || echo "BROKEN: $f"
done
```

Ожидание: grep'ы пустые; замыкание без BROKEN.

---

## 5. Канонический сьют и пакет

```bash
bash scripts/test.sh
python3 scripts/package-plugin.py
```

---

## 6. Когда запускать

- После любой правки `hooks/session-start.sh` — п. 2.2–2.8.
- После правки `.claude-plugin/plugin.json` или `marketplace.json` — п. 2.1 и 3.0.
- После правки `install.sh` — п. 3.1–3.7.
- После правки контентных файлов — `python3 scripts/build-context.py`, затем
  канонический сьют и п. 4 (замыкание, санитизация).
- После правки `instruction_block` — grep по маркеру в установленных
  файлах (см. `docs/installer.md` §3.3).

---

## 7. Session fixtures

Канонический сьют проверяет парсинг всех JSON/JSONL-записей, ожидаемые
IDs/parent chains трёх рантаймов, отсутствие посторонних threads в Codex SQL и
наличие `sessions/` в релизном ZIP.

Точечная проверка JSONL:

```bash
for file in sessions/claude/*.jsonl sessions/codex/*.jsonl \
  sessions/kimi/session_*/agents/main/wire.jsonl; do
  python3 -c 'import json,sys; [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]' "$file"
done
```

Запускайте её после любой правки fixture, затем проходите publication gate из
[docs/authoring.md](authoring.md).
