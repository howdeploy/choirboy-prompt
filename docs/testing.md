# Тестирование

Проверки хука, навыков, установщика, диагностики и пакета. Основная команда —
`bash scripts/test.sh`; ниже описаны отдельные утверждения, проверяемые набором тестов.

---

## 1. Принцип

- Каждая проверка — отдельная bash-команда с явным PASS/FAIL.
- Набор тестов можно запускать из любой директории; временные файлы — под `/tmp` с
  префиксом `choirboy-test.`.
- После прогона временные файлы удаляются. Чтобы сохранить их и вывести точный
  путь для проверки, задай `CHOIRBOY_TEST_KEEP_TMP=1`.
- Контекст проверяется **в том виде, в каком его получит среда агента**, а
  не «по наитию».
- Канонический контекст, исследования, INDEX и досье должны быть на английском;
  набор тестов отклоняет кириллицу/CJK в Markdown для модели, а валидатор
  артефактов применяет то же правило во время работы.

---

## 2. Проверки хука

### 2.1. Манифесты и версия

```bash
python3 -c 'import json; d=json.load(open(".claude-plugin/plugin.json")); print(d["name"], d["version"])'
```

Ожидание: `plugin.json` — валидный JSON, имя и версия печатаются.
Это источник версии плагина, используемой в контексте. Канонический набор тестов
также проверяет `hooks/hooks.json` пользовательского плагина для Chat/Cowork.

### 2.2. Claude-формат — валидный JSON с контекстом

```bash
bash hooks/session-start.sh --format claude \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "additionalContext" in d["hookSpecificOutput"]; print("OK")'
```

Ожидание: `OK`. Дополнительно проверить первый заголовок `prompt.md` и маркер
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

### 2.4. Plain-формат — человекочитаемый контекст

```bash
bash hooks/session-start.sh --format plain | head -40
```

Ожидание: заголовки prompt → posture → lore → user → индекс исследований
в правильном порядке, разделители `---`.

### 2.5. Hermes: доставка на первом ходу

```bash
SID="hook-check-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":true}}' "$SID" \
  | bash hooks/session-start.sh --format hermes | head -c 120
```

Ожидание: `{"context": "..."` — контекст пришёл.

### 2.6. Hermes: второй ход молчит

```bash
SID="hook-check-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":false}}' "$SID" \
  | bash hooks/session-start.sh --format hermes
```

Ожидание: `{}`.

### 2.7. Hermes: резервный вариант без флага — один раз на session_id

```bash
SID="hook-check-fb-$(date +%s)"
printf '{"session_id":"%s"}' "$SID" \
  | bash hooks/session-start.sh --format hermes | head -c 120   # → context
printf '{"session_id":"%s"}' "$SID" \
  | bash hooks/session-start.sh --format hermes                 # → {}
```

Ожидание: первый вызов — `{"context": ...`, второй — `{}`.

> Обрати внимание: после теста удали sid из файла состояния
> `${TMPDIR:-/tmp}/agent-plugin-hermes-${USER}.state`, иначе резервный вариант
> «запомнит» sid и следующий прогон с тем же sid вернёт `{}`.

### 2.8. Hermes: пустой stdin не роняет хук

```bash
printf '' | bash hooks/session-start.sh --format hermes
```

Ожидание: `{}` (не ошибка). Причина: `input="$(cat 2>/dev/null || true)"`.

---

## 3. Проверки установщика

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

### 3.3. Резервные копии

После установки в существующий файл проверить:

```bash
ls -la ~/.hermes/config.yaml.bak.*
```

Ожидание: резервная копия с отметкой времени существует.

### 3.4. Откат

```bash
./install.sh --uninstall --target hermes
./install.sh --list | grep hermes   # → detected (не installed)
```

Ожидание: блок удалён, маркер `agent-plugin:vibe-lore` в конфиге
отсутствует.

### 3.5. Хук не падает без файлов содержимого

Имитация свежего клона (без `prompt.md`/`lore.md`/`user.md`):

```bash
TMP=$(mktemp -d)
cp -r hooks .claude-plugin "$TMP/"
# контент-файлов в TMP нет
bash "$TMP/hooks/session-start.sh" --format plain >/dev/null 2>&1
echo "exit=$?"   # ожидание: 0 (graceful-режим: файлы пропущены с предупреждением в stderr)
rm -rf "$TMP"
```

Режим мягкого отказа реализован в `hooks/session-start.sh`: отсутствующие
файлы содержимого пропускаются с предупреждением в stderr, хук не падает
с `set -euo pipefail` (см. [docs/security.md](security.md) §3.3).

### 3.6. Переезд папки плагина

Установить, переместить папку, установить снова:

```bash
./install.sh --target claude
mv /path/to/plugin /path/to/plugin-moved
/path/to/plugin-moved/install.sh --target claude
```

Ожидание: в `~/.claude/settings.json` одна запись нашего хука (не две);
старая заменилась новой — `json_hook` сопоставляет записи по имени скрипта.

### 3.7. Жизненный цикл адаптера OpenCode

Основной набор тестов устанавливает адаптер в изолированный `HOME`, повторяет
установку, проверяет `--list`, обновляет намеренно изменённый маркированный
плагин с резервной копией и удаляет его с ещё одной резервной копией. Отдельно проверяется, что
чужой немаркированный файл `~/.config/opencode/plugins/agent-plugin.ts` никогда
не перезаписывается.

Ожидание: проверки `OpenCode install, list, idempotent refresh, backup, and
rollback` и `OpenCode foreign-plugin guard` печатают `PASS`. Сгенерированный
адаптер должен преобразовывать системный контекст модели, пересобирать
канонический текстовый контекст после сжатия истории, отражать переход
pending→ready и изменения актуальности, сохраняя работу чата при ошибках.
Проверки переходов состояния среды находятся в `scripts/test-opencode-transition.ts` и запускаются под `bun`;
если `bun` недоступен, набор тестов печатает `SKIP OpenCode pending-to-ready runtime
test (bun unavailable)` в stderr вместо падения.

---

## 4. Проверки содержимого (очистка)

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

Ожидание: grep не выдаёт результатов; проверка ссылок не выдаёт BROKEN.

---

## 5. Основной набор тестов и пакет

```bash
bash scripts/test.sh
python3 scripts/package-plugin.py
```

---

## 6. Когда запускать

- После любой правки `hooks/session-start.sh` — п. 2.2–2.8.
- После правки `.claude-plugin/plugin.json` — п. 2.1.
- После правки `install.sh` — п. 3.1–3.7.
- После правки файлов содержимого — `python3 scripts/build-context.py`, затем
  канонический набор тестов и п. 4 (очистка).
- После правки `instruction_block` — grep по маркеру в установленных
  файлах (см. [docs/installer.md](installer.md) §3.3).

## Нативные хуки AGY

`python3 scripts/test-agy.py` проверяет сохранность чужих хуков, BOM, повторную
установку, перенос команд, повреждённый JSON, удаление и доставку Bash-адаптера.
Он включён в `scripts/test.sh`. `scripts/test-powershell.ps1` проверяет нативную
регистрацию Windows, включая пути с пробелами.

После установки `--target agy` запусти `python3 scripts/test-agy-live.py`
(Windows: `python scripts/test-agy-live.py`). Это отдельная живая проверка с двумя
безопасными запросами к модели: команды из установленного конфига оборачиваются
только во временной рабочей папке, фиксируются вызовы SessionStart/Stop, а модель
должна дважды вернуть настоящий nonce доставленного контекста. Ожидаются один
SessionStart и два Stop. Используется stream-json и собственный агент с запретом
нативных действий. Нужны авторизация AGY и квота модели; основной набор тестов
живые запросы не выполняет. Приватный контекст и ответы модели не печатаются.
Ненулевой код выхода означает, что доставка не доказана. `--hooks` выбирает файл
конфига; сам AGY продолжает использовать HOME вызывающего процесса.

Для обычного print-режима есть `--single-turn`; `--timeout 60` ограничивает
время работы CLI и его дочерних процессов. Зависание CLI не считается успешной
проверкой хука. Сравни безопасный контрольный запуск без хуков: проверка
регистрации и JSON сама по себе не доказывает доставку нативному агенту.
