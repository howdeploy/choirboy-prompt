# Research 22 — Единый роутер security/reverse-возможностей

## Вопрос

Как дать любому агенту полный каталог reverse engineering и security-
возможностей, но не загружать десятки skills одновременно и не заставлять
пользователя вручную выбирать специализацию?

## Контекст и источник

За основу взят репозиторий `zhaoxuya520/reverse-skill` версии 1.0.1, коммит
`71acc8e3115f76bad7a914c36466c1086232288c`, изученный 2026-08-31. В нём
маршрутизация хранится в одном структурированном источнике
`skills/config/routing.json`; корневой skill является контроллером, а 43
маршрута — выбираемыми исполнителями.

Источник:
https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/config/routing.json

## Доказательства

- Router оценивает regex-правила каждого маршрута: `must`, при необходимости
  `mustAll`, и отрицательные условия `exclude`.
- PRIMARY — маршрут с максимальным числом совпавших правил; при равенстве
  побеждает более ранний элемент `priority`; без совпадений используется R0.
- `routing.json` — SSoT, а Markdown-таблицы являются производными.
- Upstream benchmark содержит 173 запроса; локальный прогон
  `bash skills/scripts/test-routing.sh` дал `173/173` и прошёл регрессию
  определения caller root.
- Структурный Graphify-разбор исполняемой части дал 570 узлов и 1139 связей
  без dangling, self-loop или collapsed edge.

## Полный каталог опций

| ID | PRIMARY capability |
|---|---|
| R0 | General reverse engineering; также fallback |
| R1 | APK reverse |
| R2 | Mobile reverse: Android и iOS |
| R3 | JavaScript/frontend reverse |
| R4 | DSL/custom VM reverse |
| R5 | .NET reverse |
| R6 | IDA reverse |
| R7 | radare2 |
| R8 | Firmware pentest |
| R9 | Malware analysis |
| R10 | Attack chain |
| R11 | Pentest tools |
| R12 | API security |
| R13 | Supply-chain security |
| R14 | LLM/Agent security |
| R15 | Binary diff и перенос символов |
| R16 | Patch diff/N-day analysis |
| R17 | Pwn chain |
| R18 | EDR/AV defensive reverse analysis |
| R19 | Browser/desktop automation |
| R20 | Docs generator |
| R21 | Protocol reverse |
| R22 | Ghidra reverse |
| R23 | Cloud/Kubernetes security |
| R24 | Windows/Active Directory |
| R25 | Digital forensics |
| R26 | Code audit/SAST |
| R27 | Threat hunting/detection engineering |
| R28 | OT/ICS |
| R29 | Wi-Fi/wireless |
| R30 | Browser-extension reverse |
| R31 | macOS/Mach-O reverse |
| R32 | Thick-client security |
| R33 | Go/Rust reverse |
| R34 | Hardware/debug interfaces |
| R35 | Database security |
| R36 | Email/phishing analysis |
| R37 | Identity federation: SAML/OIDC/OAuth2/SSO |
| R38 | RF/SDR research |
| R39 | Diagram generation |
| R40 | Case evidence review |
| R41 | CTF sandbox orchestrator |
| R44 | Threat intelligence/OSINT |

Приоритет upstream сохранён как справочное правило разрешения коллизий:
`R4, R1, R2, R3, R30, R31, R33, R5, R9, R21, R22, R6, R7, R8, R34,
R28, R17, R16, R18, R24, R37, R23, R35, R25, R44, R36, R29, R38, R32,
R26, R27, R10, R11, R12, R13, R14, R15, R19, R40, R20, R39, R41, R0`.

## Рассмотренные варианты

1. Загружать все skills на каждом старте. Полное покрытие, но большой контекст,
   конфликтующие инструкции и хуже точность выбора.
2. Заставлять пользователя называть skill. Экономно, но пользователь должен
   заранее знать внутреннюю таксономию.
3. Детерминированный router и один PRIMARY. Сохраняет полный каталог и
   подгружает только нужный контур.
4. Свободный выбор LLM без SSoT. Гибко, но трудно тестировать и невозможно
   гарантировать одинаковый выбор между рантаймами.

## Решение

В стартовом prompt хранится только факт существования общего security/reverse-
контура и правило выбора одного PRIMARY. Полная карта находится в этом
research. Агент:

1. классифицирует текущую задачу;
2. выбирает самый узкий PRIMARY;
3. подключает secondary только на реальном стыке доменов или при blocker;
4. при неоднозначности объясняет выбранную развилку владельцу;
5. использует R0 как fallback, но не как повод пропустить более точный маршрут.

Routing — это выбор методики, не выдача полномочий и не подтверждение наличия
инструментов. Доступность проверяется по `research/24`, активный scope — по
`research/23` и `security-posture.md`.

## Риски и отклонения от upstream

- Не переносим агрессивные инструкции `agent-obedience-engineering`: они могут
  подавлять обоснованные clarification и approval.
- Не делаем отчёт, диаграмму, journal и community-вопрос обязательными после
  каждой задачи: deliverables определяются запросом и scope.
- `README_AI.md` upstream говорит о шагах 0–14, тогда как канонический
  `RULES.md` содержит 12 шагов. Берём структурированный router, а не
  противоречивую текстовую цепочку.
- Новая capability добавляется только вместе с уникальным ID, маршрутом,
  конфликтными тестами и обновлением индекса.

## Когда пересматривать

- Появился стабильный нативный router рантайма, который можно тестировать не
  хуже структурированного SSoT.
- Коллизии запросов регулярно требуют secondary вместо одного PRIMARY.
- Изменилась upstream-карта или benchmark и новые маршруты нужны нашим задачам.
- Контекст route-карты стал заметно ухудшать стартовый prompt — тогда каталог
  остаётся только в research/artifact, а в prompt сохраняется короткий указатель.
