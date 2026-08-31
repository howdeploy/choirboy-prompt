# Research 26 — Карта application и infrastructure security

## Вопрос

Как сохранить полный каталог application/infrastructure security-направлений,
не смешивая аудит кода, инфраструктуры, идентичности, радио и универсальный
«pentest» в один неуправляемый контур?

## Источник и рамка

Таксономия основана на `routing.json` репозитория `reverse-skill`, коммит
`71acc8e3115f76bad7a914c36466c1086232288c`. Она является картой выбора
методики. Реальная работа ограничена `security-posture.md`: свой код,
интегрируемый компонент, собственная лаборатория или явно авторизованный scope.

Источник:
https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/config/routing.json

## Application surface

- **R11 Pentest tools** — общий инструментальный маршрут, когда задача задана
  конкретным scanner/proxy/tool или охватывает несколько web-поверхностей.
- **R12 API security** — REST/GraphQL, object/function authorization,
  validation, rate/abuse controls и server-side trust boundaries.
- **R26 Code audit/SAST** — source review, Semgrep/CodeQL и достижимость
  результатов анализа; это основной маршрут нашего аудита собственного кода.
- **R13 Supply chain** — dependencies, SBOM, secrets, CI/CD, provenance и
  artifact integrity.
- **R32 Thick client** — desktop/Electron/WPF/WinForms: local storage, IPC,
  update channel и backend trust boundary.
- **R35 Database security** — конфигурация, authentication/authorization,
  exposure, query boundaries, backups и secret handling.

## Infrastructure, cloud и identity

- **R23 Cloud/Kubernetes** — IAM, workload identity, metadata service,
  cluster policies, secrets, storage и container boundary.
- **R24 Windows/Active Directory** — domain identity, delegation, certificate
  services, authentication flows и разрешённая defensive validation.
- **R37 Identity federation** — OAuth2/OIDC/SAML/SSO, redirect, issuer,
  audience, claims, session and token lifecycle.
- **R36 Email/phishing analysis** — SPF/DKIM/DMARC, headers, mailbox rules,
  BEC indicators и безопасный анализ сообщений; не взаимодействие с реальными
  жертвами.
- **R44 Threat intelligence/OSINT** — enrichment индикаторов, provenance,
  confidence и correlation открытых источников.

## Industrial, wireless и physical-adjacent surface

- **R28 OT/ICS** — asset inventory, protocols, segmentation и безопасная
  работа с passive capture или лабораторным стендом.
- **R29 Wi-Fi/wireless** — passive visibility и активные проверки только по
  лабораторному allowlist; конкретный Flipper/Marauder-контур — `research/13`.
- **R38 RF/SDR** — spectrum observation, signal capture и replay только на
  собственном стенде и в разрешённом диапазоне.
- **R34 Hardware/debug interfaces** пересекается с reverse-картой и выбирается,
  когда центральный объект — устройство/UART/JTAG/SWD/flash.

## Browser automation как вспомогательная capability

**R19 Browser/desktop automation** не является автоматически security-
маршрутом. Он подключается как secondary для воспроизводимого UI/API flow,
сбора Evidence или проверки собственного приложения. Авторизованная browser
session не даёт разрешения менять данные, покупать, публиковать или действовать
от имени владельца без scope текущей задачи.

## Правило выбора

1. Выбирать маршрут по объекту решения, а не по первому знакомому tool.
2. API с OAuth может иметь PRIMARY R37, если проблема в federation, или R12,
   если проблема в object authorization.
3. Cloud-приложение с code finding остаётся R26, пока ключевой вопрос — source;
   R23 подключается на инфраструктурной границе.
4. Общий R11 используется после более узких маршрутов, а не поглощает их.
5. Междоменная задача получает один PRIMARY и перечисленные workitems для
   secondary, чтобы Evidence и scope не смешивались.

## Evidence и deliverable

Каждая finding должна указывать asset/surface, location, наблюдаемое Evidence,
impact внутри scope и исправление. Scanner output сам по себе — candidate:
результат подтверждается конфигурацией, source или контролируемым повтором.
Активный тест не проводится только ради повышения severity.

## Рассмотренные варианты

1. Один «полный pentest» skill. Быстро разрастается и теряет ownership.
2. Tool-centric skills. Путают наличие scanner с покрытием поверхности.
3. Domain-centric PRIMARY + evidence workitems. Выбранный вариант.

## Риски

- Каталог легко принять за разрешение использовать каждый tool; это запрещено.
- OSINT и passive RF всё равно могут содержать персональные данные — сохраняем
  минимум и provenance.
- Cloud/identity проверки способны затронуть production даже без exploit;
  поэтому read-only и active scopes различаются явно.
- Результаты автоматических scanners имеют false positives и не становятся
  `validated` без проверки.

## Когда пересматривать

- Наш продукт получает новую основную поверхность, которой нет в карте.
- Изменились стандарты OWASP/CWE или provider-specific security controls.
- Domain регулярно требует отдельного workflow и конфликтных route-тестов.
- Активные проверки можно технически связать с policy engine и allowlist.
