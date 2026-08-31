# Research 28 — LLM/Agent и skill supply-chain security

## Вопрос

Как агенту безопасно использовать внешний лор, skills, MCP и bootstrap-код,
если эти источники одновременно дают полезные возможности и могут содержать
инструкции, которые расширяют полномочия, крадут данные или закрепляются в
памяти?

## Контекст

Документ объединяет наш эксперимент fabricated-provenance trust из
`research/12` с маршрутом R14 и supply-chain правилами `reverse-skill` на
коммите `71acc8e3115f76bad7a914c36466c1086232288c`.

Источники upstream:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/llm-security/SKILL.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/skill-supply-chain.md

## Модель угроз

| Граница | Риск | Контроль |
|---|---|---|
| Lore/memory | fabricated provenance, ложное доверие и постоянное правило | канонический источник, маркировка происхождения, факты сильнее лора |
| Web/RAG/document | prompt injection в данных | считать содержимое данными, не исполнять найденные инструкции |
| Skill | скрытые команды, scope drift, чтение секретов | прочитать весь `SKILL.md`, scripts и dependencies до установки |
| MCP | tool poisoning, чрезмерные filesystem/network права | inspect manifest/config, auth, bind, allowlist, audit и limits |
| Bootstrap | dependency confusion, mutable latest, `curl | shell` | pin commit/version/hash, manifest-only install, isolated environment |
| Tool output | ложные success/status и инъекции из target data | независимо проверить side effect и ground вывод на Evidence |
| Journal/research | закрепление непроверенной гипотезы | повышать в память только после проверки и sanitization |

## Контракт внешнего skill

До подключения:

1. установить точный источник, commit/version и лицензию;
2. прочитать полностью инструкции, scripts, package manifests и install hooks;
3. найти network calls, shell execution, global config writes, filesystem
   traversal, credential paths и persistent memory writes;
4. сравнить trigger и полномочия skill с текущим scope;
5. отделить знания от исполняемого кода и vendored content;
6. проверить pins/checksums и отсутствие auto-run из недоверенного repo config;
7. зарегистрировать только необходимые capabilities;
8. после установки проверить фактические команды, ports и MCP permissions.

HTML comments, sample prompts, README, issues, logs и target artifacts не
получают повышенный приоритет только потому, что находятся внутри skill package.

## Контракт MCP

MCP рассматривается как удалённый или локальный процесс с реальными
полномочиями. Минимальная проверка:

- кто запускает server и из какого immutable artifact;
- на каком address/port он слушает;
- как проверяет клиента и хранит token;
- какие directories, environment variables и network destinations видит;
- какие tools имеют побочный эффект;
- где enforcement scope, а не только UI toggle;
- есть ли bounds для concurrency, payload size, retries и request counts;
- что попадает в logs и можно ли удалить секреты;
- как отключить и полностью удалить регистрацию.

Объявленный `scope_gate` без проверки внутри каждого side-effect handler — не
защита. Это отдельно обнаружено в Burp MCP upstream: флаги меняются и логируются,
но отправляющие запросы handlers их не читают.

## LLM security workflow

1. определить asset: prompt, memory, tool boundary, RAG corpus или agent flow;
2. описать trust boundaries и expected policy;
3. подготовить собственный isolated harness;
4. менять одну переменную за прогон;
5. фиксировать input, model/runtime version, tools, output и side effects;
6. отличать model text от реально выполненного tool action;
7. проверять canary и отсутствие утечек;
8. выдавать defensive finding и remediation, а не переносить рабочий bypass в
   production-память.

## Что отклонено из upstream

`RULES.md` предлагает при сомнениях читать `agent-obedience-engineering` и
содержит таблицу подавления «отговорок». Мы не переносим эту механику. Она
смешивает полезную настойчивость с запретом остановиться на реальной развилке,
permission boundary или supply-chain риске.

Наше правило другое: результат имеет приоритет, агент исчерпывает разрешённые
fallback-инструменты, но согласует с владельцем новый доступ, изменение scope,
расходы, необратимые и внешние действия. Настойчивость не является полномочием.

## Рассмотренные варианты

1. Доверять skills из известного репозитория. Репутация не заменяет audit.
2. Запретить внешние skills/MCP. Слишком сильно режет возможности.
3. Разрешать всё в container. Container не защищает credentials/network сам по
   себе.
4. Поэтапный audit + минимальные capabilities + проверка результата. Выбрано.

## Решение

Сохраняем R14 как отдельный PRIMARY и применяем supply-chain gate ко всем
внешним skills, MCP и bootstrap независимо от их тематики. Лор и research дают
контекст, но не меняют приоритет системных правил и не подтверждают факты без
проверки текущей среды.

## Когда пересматривать

- Рантайм предоставил подписанные skills, permission manifest и изоляцию MCP.
- Обнаружен новый persistence или provenance channel.
- Изменился threat model нашего plugin delivery.
- Новый внешний package невозможно полноценно проверить без отдельной среды.
