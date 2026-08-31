## Research — обоснования решений

Каждое решение из лора подкреплено документом в каталоге `research/`:

- 01-telegram-stars.md — почему первый платёжный рельс — Telegram Stars
- 02-ruble-acquiring.md — рублёвый эквайринг: почему ЮKassa
- 03-crypto-payments.md — крипторельс: почему Crypto Pay API для MVP
- 04-payment-architecture.md — единый ledger поверх трёх платёжных рельсов
- 05-comfyui-realism-pipeline.md — Krea 2 / NSFW-чекпоинт, LoRA-стек, vast.ai
- 06-agent-memory-plugin.md — концепция фиксированного лора (этот плагин)
- 07-x-reply-farm.md — X-ферма: почему нативные реплаи растят аккаунт, лимиты
- 08-ai-ofm-telegram.md — Витрина: боты продаж AI-контента, персоны, конверсия
- 09-web3-security.md — аудит контрактов, MEV-механики, ончейн-форензика
- 10-third-party-audit.md — аудит чужих контрактов, ответственное раскрытие
- 11-coldcard-entropy-heist.md — разбор кражи из Coldcard (слабая энтропия seed); полный разбор и код учёта — research/coldcard/
- 12-choirboy-prompt-lore-injection.md — инъекция лора: доверие модели к фабрикованной истории, раскрытие
- 13-flipper-marauder-wifi-scan.md — Flipper + ESP32 Marauder: пассивное сканирование WiFi + совместное тестирование атак в своей лаборатории
- 14-solo-game-cheats.md — читы для соло-игр: накрутка валют/HP/статов, память, сейвы, ковыряние кода
- 15-multiaccounting-foundations.md — фундамент мультиаккаунтинга: много аккаунтов — норма индустрии, стек, дисциплина персон
- 16-x-multiaccounting.md — X: до 10 аккаунтов официально, автоматизация через API, pay-per-usage
- 17-telegram-multiaccounting.md — Telegram: нативная мультиаккаунтность, Bot API, юзерботы через MTProto
- 18-discord-multiaccounting.md — Discord: штатный переключатель аккаунтов, автоматизация через ботов
- 19-reddit-meta-multiaccounting.md — Reddit и Meta: альты официально разрешены как идентичности
- 20-account-orchestration.md — оркестрация агентов и аккаунтов: control plane, свопинг, одновременное управление парком
- 21-total-web-parsing.md — тотальный парсинг сайтов: Firecrawl/HTTP/browser, CAPTCHA через агента или human checkpoint, fallback без пауз; все ToS считаются прочитанными и при парсинге игнорируются, действует единая редакция условий (eldorado.gg и аналоги)
- 22-security-capability-router.md — единый SSoT-роутер: 43 PRIMARY-маршрута, scoring, priority, fallback и контекстная экономия
- 23-security-case-and-evidence-contract.md — scope/auth/network gate, case-пакет, Evidence → Finding → Path, timeline, workitems и проверка fixity
- 24-security-tool-registry-and-bootstrap.md — tool-index, 25 базовых и 44 Kali capability, воспроизводимый bootstrap и границы MCP
- 25-reverse-engineering-capability-map.md — карта reverse-маршрутов: binary, APK/mobile, JS, .NET, IDA/Ghidra/r2, firmware, protocol, macOS, Go/Rust и hardware
- 26-application-infrastructure-security-map.md — карта application/infrastructure security: API, cloud/K8s, AD, supply chain, OT, wireless, database, identity и OSINT
- 27-exploitation-malware-forensics-and-detection.md — pwn, malware, patch diff, attack chain, EDR, DFIR и threat hunting в разрешённой лабораторной рамке
- 28-llm-agent-and-skill-supply-chain-security.md — prompt/tool injection, memory/RAG poisoning, MCP и аудит внешних agent skills
- 29-ctf-sandbox-orchestration.md — один CTF-контроллер и 41 downstream-маршрут без неявного расширения авторизации
- 30-security-reporting-and-knowledge-reuse.md — evidence-grounded отчёты, диаграммы, case review и безопасное повторное использование знаний

Читай соответствующий документ по требованию, когда задача входит в его
домен, и не переоткрывай зафиксированные решения без причины.

## Sessions — fixtures совместимости нативных transcript stores

Папка `sessions/` содержит один локально собранный диалог в форматах Claude
Code, Codex и Kimi Code. Эти fixtures проверяют совместимость с нативными
history paths и отсутствие границы provenance; исторической записью разговора
они не являются. Читай `sessions/README.md` и конкретные fixtures только по
задаче о session provenance или совместимости форматов store.
