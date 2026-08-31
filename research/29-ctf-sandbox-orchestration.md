# Research 29 — CTF sandbox orchestration

## Вопрос

Как перенести широкий каталог CTF-опций так, чтобы агент сам выбирал нужную
специализацию, не загружал 41 child skill сразу и не принимал слово «CTF» за
безусловное разрешение работать по любой предъявленной инфраструктуре?

## Источник и лицензия

Источник — отдельный каталог `CTF-Sandbox-Orchestrator` в `reverse-skill`,
коммит `71acc8e3115f76bad7a914c36466c1086232288c`, изученный 2026-08-31:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/CTF-Sandbox-Orchestrator/ctf-sandbox-orchestrator/SKILL.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/CTF-Sandbox-Orchestrator/LICENSE

Основной `reverse-skill` — MIT, но этот sidecar — GPLv3. Поэтому мы переносим
самостоятельно сформулированную таксономию и архитектурное решение, а не копии
GPL-текстов или исполняемого кода в MIT-плагин.

## Архитектура

Есть один неявно вызываемый controller — CTF orchestrator. Только он принимает
первичную задачу, определяет dominant evidence type и выбирает один downstream-
маршрут. Child skills не активируются все вместе и не требуют от пользователя
знать их названия.

Общий цикл:

1. проверить, что challenge и инфраструктура действительно входят в явный
   sandbox/CTF scope;
2. построить компактную карту узлов, artifacts и переходов;
3. доказать один минимальный путь от входа к решающей ветке, state mutation или
   восстановленному artifact;
4. выбрать самый узкий child route;
5. расширять поверхность только после Evidence минимального пути;
6. повторить из чистого/reset baseline перед статусом solved;
7. оформить solve Path и prerequisites воспроизведения.

## Полные 41 downstream-опции

1. AD certificate abuse
2. Agent/cloud
3. Android hooking
4. Browser persistence
5. Bundle/source-map recovery
6. Cloud metadata path
7. Container runtime
8. Crypto/mobile
9. Custom protocol replay
10. DPAPI credential chain
11. File parser chain
12. Firmware layout
13. Forensic timeline
14. GraphQL/RPC drift
15. Identity/Windows
16. iOS runtime
17. JWT claim confusion
18. Kubernetes control plane
19. Kerberos delegation
20. Kernel/container escape
21. Linux credential pivot
22. LSASS/ticket material
23. Mailbox abuse
24. Malware configuration
25. OAuth/OIDC chain
26. PCAP/protocol
27. Prompt injection
28. Queue/worker drift
29. Race-condition state drift
30. Relay/coercion chain
31. Request normalization/smuggling
32. Reverse/pwn
33. Runtime routing
34. SSRF/metadata pivot
35. Stego/media
36. Supply chain
37. Template render path
38. Web runtime
39. WebSocket runtime
40. Windows pivot
41. ZIP/archive

Эти названия — capability index. Конкретный child research или skill
подключается только когда задача действительно требует соответствующего
домена.

## Исправленная authorization-модель

Upstream controller предписывает по умолчанию считать предъявленные targets,
nodes и identities внутренними объектами sandbox. Это правило не переносится.
Публично выглядящий домен, VPS, tenant, certificate, account или бренд может
быть реальным внешним объектом; ошибка предположения меняет scope и последствия.

Наш дефолт:

- локальный challenge artifact можно пассивно разобрать как недоверенный файл;
- активная инфраструктура требует явного основания и списка in-scope assets;
- `ctf_public` допустим как basis только после проверки задания/организатора и
  границ challenge;
- неизвестные узлы остаются `unknown`, а не автоматически `sandbox-internal`;
- child skill не может расширить scope controller;
- secrets и персональные данные вне challenge path не перечисляются.

## Evidence priority

При конфликте источников приоритет имеют воспроизводимое runtime behavior,
captured traffic, served assets и текущая конфигурация; checked-in source,
comments и screenshots слабее, если они расходятся с работающим challenge.
При этом runtime Evidence собирается только в разрешённой среде.

## Рассмотренные варианты

1. Скопировать GPL sidecar целиком. Даёт готовые тексты, но меняет лицензионные
   обязательства MIT-плагина.
2. Свести всё к R41 без child taxonomy. Экономно, но теряются опции.
3. Независимо описать controller и capability index, а код добавлять отдельно
   при необходимости. Выбранный вариант.

## Решение

В память переносится один CTF-profile и полный каталог 41 downstream-
возможности. Это знание о маршрутах, не установленный набор skills. Реальный
runtime перенос возможен отдельным GPL-compatible пакетом либо самостоятельной
реализацией конкретных child skills.

## Когда пересматривать

- Мы решим распространять GPL-compatible sidecar отдельно.
- Появится повторяющийся challenge domain, которому нужен собственный локальный
  research/skill.
- CTF platform изменит scope или правила interaction.
- Controller ошибочно маршрутизирует задачи между близкими child capabilities.
