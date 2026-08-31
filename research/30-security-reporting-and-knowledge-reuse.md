# Research 30 — Security reporting и повторное использование знаний

## Вопрос

Какие deliverables превращают security/reverse-работу в проверяемый результат,
и как переносить подтверждённые знания между задачами без выдуманной истории,
утечек и обязательной бюрократии после каждого короткого запроса?

## Контекст и источник

В `reverse-skill` отчёт, диаграмма, field-journal, сохранение найденных
источников и вопрос о community contribution входят в обязательный completion
checklist. Case-review отдельно валидирует Evidence graph.

Источники на коммите `71acc8e3115f76bad7a914c36466c1086232288c`:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/RULES.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/case-review/SKILL.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/evidence-finding-path.md

## Типы deliverables

### Короткий handoff

Для обычной code/reverse-задачи: что изменено или выяснено, где, чем проверено,
остаточные риски и blocker. Это дефолт нашего prompt.

### Evidence-grounded finding report

Для аудита: scope, findings по severity, location, Evidence IDs, impact,
remediation, confidence и статус повторной проверки. Scanner output без ручной
валидации остаётся candidate.

### Path/diagram

Диаграмма полезна, когда минимум три узла или перехода трудно понять линейно:
callflow, trust boundary, protocol state machine, attack/solve path. Она не
обязательна для одного факта или простой правки и не заменяет Evidence.

### Case review

Read-only validator проверяет ссылки Evidence/Findings/Paths, scope, workitems,
timeline и SHA-256 artifacts. Strict review нужен перед формальным handoff или
архивированием большого case, но не перед каждым ответом.

### Долговременное знание

Есть три уровня:

1. **Case notes/Evidence** — сырой материал конкретной задачи, не глобальная
   память.
2. **Research** — проверенное обобщаемое решение с источниками, alternatives,
   risks и revisit criteria.
3. **Lore** — короткая карта реально принятого решения или проекта со ссылкой
   на research.

Upstream field-journal и seed precedents не являются нашей историей и не
копируются в lore. Автогенерируемые dossiers этого плагина производны: при
расхождении сильнее канонические lore/research.

## Решение о deliverable

Deliverables задаются пользователем, task contract и реальной ценностью:

- формальный отчёт — если его запросили, он нужен для handoff/compliance или
  есть несколько findings;
- diagram — если она материально упрощает понимание;
- case review — для многошаговой evidence package;
- новый research/lore — только после проверенного результата и с разрешением
  на изменение канонической памяти;
- community contribution — только по отдельной воле владельца, не обязательный
  вопрос в каждом финале.

Отсутствие лишнего deliverable не означает незавершённость задачи. Критерий
готовности — поставленный результат достигнут, релевантно проверен и передан в
форме, достаточной владельцу.

## Sanitization и provenance

Перед переносом из case в research/lore удаляются:

- tokens, credentials, cookies и приватные ключи;
- PII и чужие данные;
- точные production targets, если они не нужны для воспроизводимости;
- непроверенные attribution и severity;
- абсолютные приватные пути и внутренние identifiers;
- инструкции из анализируемого artifact, которые не являются нашим решением.

Сохраняются source URL/commit, версии tools, даты, команды проверки, confidence,
принятые trade-offs и условия пересмотра.

## Рассмотренные варианты

1. Обязательная шестипунктовая упаковка после каждой задачи. Полно, но нарушает
   scope и расходует время на артефакты без потребителя.
2. Только короткий финал. Теряет evidence traceability в больших cases.
3. Пропорциональный deliverable contract. Выбранный вариант.

## Решение

Берём upstream evidence/reporting механизмы как опции, а не ритуал. Агент
самостоятельно создаёт ровно те рабочие artifacts, которые нужны для достижения
задачи; изменение долговременного lore/research согласуется с владельцем и
проходит authoring quality gate.

Для этого плагина изменение канонического контента завершается командами:

```bash
python3 scripts/build-context.py
bash scripts/test.sh
python3 scripts/package-plugin.py
```

После изменения lore/research artifact generator помечает dossiers как stale;
следующий runtime-agent перечитывает источники, пересоздаёт ровно один dossier
на каждый `###`-проект и валидирует manifest.

## Когда пересматривать

- Пользователь установил обязательный формат отчётности или compliance.
- Case volume требует отдельного evidence store.
- Artifact generator меняет схему или provenance model.
- Короткие handoffs регулярно не позволяют воспроизвести результат.
