# Research 25 — Карта reverse engineering-возможностей

## Вопрос

Какие reverse-маршруты должен видеть агент, как выбрать самый узкий из них и
какой общий инвариант сохранить между разными форматами, платформами и tools?

## Контекст

Карта переносит capability taxonomy из `reverse-skill` на коммите
`71acc8e3115f76bad7a914c36466c1086232288c`. Она дополняет существующий
`research/14` про собственные офлайн-игры, но не расширяет его на multiplayer
или чужие онлайн-системы.

Источник маршрутов:
https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/config/routing.json

## Capability-группы

### Общий и native binary

- **R0 General reverse engineering** — triage неизвестного binary, anti-debug,
  obfuscation, Unity/IL2CPP и fallback, когда точный формат ещё неизвестен.
- **R6 IDA**, **R22 Ghidra**, **R7 radare2** — альтернативные аналитические
  поверхности. Выбор зависит от реально доступного tool, лицензии, automation
  API и формата, а не от привычки агента.
- **R15 Binary diff/symbol migration** — сравнение версий, перенос имён и
  границ функций, подтверждение изменившихся путей.
- **R16 Patch diff/N-day** относится к security-анализу изменений и подробнее
  ограничен в `research/27`.

### Mobile и managed runtimes

- **R1 APK reverse** — APK, resources, manifest, DEX/smali, JNI, подпись и
  наблюдаемое runtime-поведение в своём устройстве/эмуляторе.
- **R2 Mobile reverse** — iOS/IPA и смешанные mobile-задачи; Android-only
  запросы должны уходить в R1.
- **R5 .NET reverse** — IL, metadata, managed resources и обфускация.
- **R33 Go/Rust reverse** — runtime metadata, восстановление символов и
  особенности stripped binaries.

### Web-клиент и расширения

- **R3 JS/frontend reverse** — bundles, source maps, frontend signing,
  protocol parameters и runtime наблюдение в браузере.
- **R30 Browser-extension reverse** — CRX/XPI, manifest, permissions,
  service worker/background, content scripts и message boundaries.
- **R32 Thick-client security** из соседней карты применяется, когда desktop
  приложение важнее языка реализации.

### Специализированные форматы и устройства

- **R4 DSL/custom VM reverse** — bytecode, opcode map, dispatcher и
  воспроизводимая семантика виртуальной машины.
- **R8 Firmware** — контейнер, filesystem, архитектура, конфигурация и
  эмуляция/лабораторный runtime.
- **R21 Protocol reverse** — PCAP, message framing, state machine, protobuf/
  gRPC и проверяемый decoder/dissector.
- **R31 macOS/Mach-O** — load commands, Objective-C/Swift metadata, signing,
  entitlements и XPC в собственной среде.
- **R34 Hardware/debug interfaces** — UART/JTAG/SWD, flash layout и USB device
  analysis только на собственном лабораторном железе.

## Общий workflow

Маршрут меняет инструменты и domain checklist, но не доказательную модель:

1. определить artifact, формат, архитектуру, упаковку и фактический runtime;
2. зафиксировать hashes и работать с производной копией;
3. сформулировать минимальную гипотезу;
4. получить статическое Evidence: imports, strings, metadata, CFG, resources;
5. получить динамическое Evidence в собственном runtime, если это возможно и
   нужно для уверенного вывода;
6. связать адреса, offsets, symbols, запросы или hook points с наблюдением;
7. построить `callflow` Path и оставить непроверенное как candidate;
8. после трёх действий без нового Evidence сменить гипотезу, stage или tool.

Декомпилятор — представление, а не источник истины. Runtime может показать
другую ветвь, загруженный модуль или served artifact; расхождение фиксируется,
а не заглаживается.

## Выбор tool

| Ситуация | Предпочтительный маршрут |
|---|---|
| Нужна коммерческая глубокая интерактивная работа и лицензия есть | IDA/JEB |
| Нужна воспроизводимая headless/opensource автоматизация | Ghidra/radare2 |
| APK resources + DEX | jadx + apktool, затем runtime при необходимости |
| Mobile instrumentation на своей среде | Frida/Objection после static anchor |
| Protocol из трафика | Wireshark/dissector + replay в лаборатории |
| Неизвестный firmware | hash → binwalk/layout → filesystem → lab/emulation |

Фактическая доступность определяется `research/24`; названия в этой таблице
не являются обещанием установки.

## Рассмотренные варианты

1. Один универсальный reverse skill. Проще, но теряет форматные инварианты.
2. Один skill на каждый tool. Привязывает методику к приложению и плодит
   дублирование.
3. Capability по домену, tools выбираются внутри маршрута. Выбранный вариант.

## Решение и границы

Сохраняем доменные маршруты и общий Evidence workflow. Работа ведётся на своих
артефактах, локальных samples, собственных устройствах и явно разрешённых
окружениях. Для игр действует `research/14`; для активной security-проверки —
`security-posture.md` и case contract из `research/23`.

Не переносим upstream binaries, payload dumps или field-journal как часть
памяти. Они могут быть отдельными внешними источниками после проверки, но не
доказательством нашей истории или автоматически доверенным кодом.

## Когда пересматривать

- Появился новый формат, не покрываемый существующим PRIMARY.
- Один tool стал недоступен или изменил automation API.
- Статическая и динамическая картины систематически расходятся.
- Нужен отдельный маршрут для engine/runtime, который сейчас перегружает R0.
