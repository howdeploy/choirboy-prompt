# Research 23 — Case scope и доказательная цепочка

## Вопрос

Как сделать security/reverse-работу воспроизводимой и не позволить маршруту или
инструменту неявно расширить разрешённую область действий?

## Контекст и ограничения

Архитектура адаптирована из `reverse-skill` на коммите
`71acc8e3115f76bad7a914c36466c1086232288c`. Мы переносим файловые контракты и
quality gate, но сохраняем более строгую рамку `security-posture.md`: активные
проверки — только своё, интегрируемое или явно авторизованное окружение.

Основные источники:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/scope-contract.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/evidence-finding-path.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/timeline-workitem.md

## Case-пакет

Для длинной или активной работы используется один каталог:

```text
work/<case>/
  scope.md
  timeline.md
  workitems.md
  evidence/
  notes/
  report/
```

`scope.md` фиксирует:

- `auth.status`: `granted`, `pending` или `denied`;
- основание: собственная система, лаборатория, offline sample, письменный
  договор, bug bounty scope или публичный CTF;
- точные in-scope assets, поверхности и допустимые activities;
- out-of-scope assets и действия;
- network profile: `offline`, `lab_only`, `authorized_target_only` или
  `unrestricted_lab`;
- deliverables, ограничения обработки данных и `ready_for_act`.

До `auth.status=granted` и `ready_for_act=true` допустимы чтение, локальная
классификация и подготовка scope, но не активное воздействие на цель. Флаг
`--force` не должен обходить gate.

## Evidence → Finding → Path

### Evidence

`E-nnn` — наблюдение: время, тип источника, путь или команда, SHA-256 файла,
точная команда воспроизведения, минимальный обезличенный excerpt и связь с
work item. Старое наблюдение не переписывается: исправление или новый результат
создаётся отдельной записью с `supersedes`.

### Finding

`F-nnn` — интерпретация с severity, категорией, статусом, location, impact,
confidence, reproduction и remediation. Она обязана ссылаться хотя бы на одно
существующее Evidence. Для `validated` предпочтительны два независимых
подтверждения, обычно статическое и динамическое; единственный слабый источник
оставляет Finding в `candidate` или требует явного residual risk.

### Path

`P-nnn` связывает путь от входа к результату. Тип зависит от задачи:

- `callflow` — вызовы и преобразования в reverse engineering;
- `solve` — решение лабораторной/CTF-задачи;
- `attack` — только разрешённый тестовый путь внутри scope.

Каждый существенный шаг ведёт к Evidence и при необходимости Finding.

## Timeline и workitems

`timeline.md` только дополняется. Запись содержит action, command/reference,
result, artifacts, evidence IDs, `decision_delta`, ссылки на неизменённое
состояние и следующий шаг. Старые записи не редактируются; исправление — новая
запись с `corrects`.

`workitems.md` хранит покрытие и статусы `pending`, `in_progress`, `blocked`,
`done`, `cancelled`. Это отделяет «инструмент запущен» от «поверхность реально
проверена и подтверждена Evidence».

## Проверка handoff

Upstream `case-review` использует только Python standard library и проверяет:

- готовность scope;
- ссылки Findings/Paths/workitems/timeline на существующие Evidence;
- допустимые статусы и confidence;
- отсутствие потерянных Evidence;
- опционально SHA-256 case-local artifacts и запрет выхода пути за case root.

Локальный прогон upstream-тестов дал `8/8`. Review read-only, пока его вывод
явно не сохраняется в `report/`.

## Важное ограничение

Markdown gate — процедурный контроль, а не capability sandbox. Агент или
пользователь технически может вручную записать `granted`; внешний CLI/MCP не
обязан читать `scope.md`. Поэтому:

1. текстовый gate остаётся обязательной операционной проверкой;
2. опасные инструменты должны дополнительно валидировать allowlist/scope в
   своём коде;
3. audit log и лимиты должны жить на tool boundary;
4. отсутствие такой проверки отмечается как риск, а не маскируется словом
   «hard gate».

## Решение

Используем лёгкий case-пакет для многошаговых reverse/security-задач и всегда
отделяем наблюдение от вывода. Для короткого read-only аудита допустим
эквивалентный компактный отчёт без каталога `work/`, если он сохраняет scope,
Evidence и проверяемые ссылки. Формат не должен создавать бюрократию ради
формата: он нужен там, где помогает владельцу воспроизвести и продолжить работу.

## Когда пересматривать

- Появится исполняемый policy engine, который связывает scope с каждым MCP/CLI.
- Case-пакеты станут слишком большими для Markdown и потребуется БД или
  подписанный evidence store.
- Юридический или организационный процесс потребует формальной chain of custody.
- Тесты покажут, что два независимых Evidence не подходят конкретному типу
  статического вывода; исключение должно быть документировано.
