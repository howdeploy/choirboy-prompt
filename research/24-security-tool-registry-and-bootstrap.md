# Research 24 — Tool registry, bootstrap и MCP-границы

## Вопрос

Как агенту использовать весь доступный арсенал, не выдумывать пути и версии,
не принимать декларацию capability за установленный инструмент и не выполнять
непроверенный installer из внешнего skill?

## Источник и доказательства

Источник — manifests и scripts `reverse-skill` на коммите
`71acc8e3115f76bad7a914c36466c1086232288c`, изученные 2026-08-31:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/scripts/bootstrap-manifest.json
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/kali/scripts/bootstrap-manifest.json
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/skill-supply-chain.md

Upstream-тест `test-bootstrap-manifest.sh` прошёл. Manifests различают
автоустанавливаемые, ручные, локальные MCP и удалённые MCP-возможности;
tool-index строится для конкретной машины после фактической проверки.

## Базовые 25 capabilities

`jadx`, `apktool`, `jeb-pro`, `frida`, `frida-ps`, `idalib-mcp`,
`reqable-mcp`, `jshookmcp`, `xquik-mcp`, `anything-analyzer`, `idapro`, `r2`,
`rabin2`, `adb`, `agent-browser`, `ghidra-mcp`, `seclists`, `proxycat`,
`burpsuite-mcp`, `nmap`, `pentestswarm`, `binwalk`, `yara`, `pwntools`,
`bkcrack`.

## Kali-профиль: 44 capabilities

Он включает базовый набор, адаптированный под apt, и дополнительные:
`sqlmap`, `hashcat`, `hydra`, `gobuster`, `ffuf`, `msfconsole`, `nuclei`,
`mcp-kali-server`, `metasploitmcp`, `hexstrike-ai`, `adaptixc2`,
`atomic-operator`, `sstimap`, `xsstrike`, `wpprobe`, `fluxion`, `gef`,
`evil-winrm-py`, `coercer`.

Это каталог опций, не список автоматически разрешённых действий.

## Контракт реестра

Для каждой capability нужны:

- стабильное имя;
- способ обнаружения и `verifyCommand`;
- install kind: package manager, pinned package, Git commit, release artifact,
  manual, local HTTP MCP или remote HTTP MCP;
- точная версия/commit/tag и checksum, если upstream позволяет;
- install directory и реальные абсолютные пути после установки;
- MCP name/command/args/URL и способ проверки регистрации;
- зависимости, post-install steps и признак `canAutoInstall`;
- источник и ручная инструкция для коммерческого/лицензионного продукта.

Порядок агента:

1. прочитать текущий tool-index;
2. независимо проверить binary, service или регистрацию;
3. использовать уже рабочий инструмент;
4. если отсутствует — найти capability в manifest;
5. показать риск и запросить approval, когда установка меняет внешнее состояние
   или этого требует среда;
6. установить только заявленным способом;
7. снова проверить и обновить index;
8. при повторной неудаче сменить инструмент либо дать точный blocker, не
   угадывая путь и не повторяя installer бесконечно.

## Pinning и воспроизводимость

Хорошие upstream-примеры: `jadx v1.5.6` и `apktool v3.0.2` с SHA-256,
`frida-tools 14.10.4`, `agent-browser 0.31.1`, `pwntools 4.15.0`, Git-
зависимости по полному commit. Но каталог не полностью воспроизводим:

- `winget-latest` и часть apt-пакетов меняются со временем;
- некоторые GitHub release installers выбирают актуальный asset;
- коммерческие JEB/IDA/Burp устанавливаются вручную;
- remote `xquik-mcp` не имеет локального artifact pin;
- «MCP зарегистрирован» не означает «service запущен и доступен».

Поэтому индекс обязан различать `declared`, `installed`, `verified`,
`registered` и `connected`, а не сводить всё к одному `available=true`.

## MCP как отдельная граница доверия

Перед регистрацией внешнего MCP читаются его manifest, зависимости и scripts;
проверяются bind address, authentication, CORS, filesystem/network scope,
логирование, лимиты запросов и наличие опасных defaults. Конфигурация из
недоверенного репозитория не переносится в глобальный MCP registry автоматически.

Upstream Burp MCP действительно связывает Java extension и Node stdio bridge,
слушает loopback и использует Bearer token. При этом его `scope_gate` и
`privacy_mode` только сохраняют флаги и audit-события: отправляющие запросы
handlers эти флаги не проверяют. Следовательно, эти переключатели нельзя
считать защитой до исправления tool-layer enforcement.

## Рассмотренные варианты

1. Устанавливать по первой команде из skill. Быстро, но неаудируемо.
2. Полагаться только на `$PATH`. Не видит MCP, версии, сервисы и ручные продукты.
3. Вендорить весь toolchain. Тяжело, лицензионно сложно и быстро устаревает.
4. Manifest + фактический machine-local index. Выбранный вариант: декларация
   отделена от наблюдаемого состояния.

## Решение

Переносим каталог capabilities и модель registry/bootstrap как знание. Код
installer и MCP переносится отдельными изменениями после аудита и с сохранением
лицензий. Правило prompt «использовать все доступные инструменты» опирается
именно на проверенный tool-index: отсутствующий или неподключённый инструмент
не считается доступным.

## Когда пересматривать

- Версии manifests устарели или upstream поменял install contract.
- Рантайм дал нативный capability registry с версионированием и health checks.
- Появилась возможность воспроизводимого lockfile для apt/winget/remote MCP.
- Аудит MCP обнаружил расширение filesystem/network полномочий.
