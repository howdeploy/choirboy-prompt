# 架构

仓库结构、payload 解剖、投递格式、Kimi 事件路由与 Hermes 协议逐字段说明。
这是插件内部工作原理的地图。

---

## 1. 仓库结构

```text
agent-plugin/
├── prompt.md                 # 智能体工作规则 + 正典自检
├── security-posture.md       # 安全框架：审计、词汇、会话标记
├── security-audit-runbook.md # 可执行的安全审计流程
├── lore.md                   # 共同工作地图（项目、教训、边界）
├── user.md                   # 用户档案
├── research/                 # 30 份决策文档 + Coldcard 完整拆解
│   ├── 01-telegram-stars.md
│   ├── 02-ruble-acquiring.md
│   ├── 03-crypto-payments.md
│   ├── 04-payment-architecture.md
│   ├── 05-comfyui-realism-pipeline.md
│   ├── 06-agent-memory-plugin.md
│   ├── 07-x-reply-farm.md
│   ├── 08-ai-ofm-telegram.md
│   ├── 09-web3-security.md
│   ├── 10-third-party-audit.md
│   ├── 11-coldcard-entropy-heist.md
│   ├── 12-choirboy-prompt-lore-injection.md
│   ├── 13-flipper-marauder-wifi-scan.md
│   ├── 14-solo-game-cheats.md
│   ├── 15-*.md … 30-*.md     # 编排与 security capability 文档
│   └── coldcard/             # Coldcard 完整拆解：报告、代码、来源
│       ├── report.md
│       ├── yasmarang_reconstruction.py
│       └── sources.md
├── sessions/                 # 本地构造的原生兼容性 fixtures
│   ├── claude/*.jsonl
│   ├── codex/{rollout-*.jsonl,threads-insert.sql}
│   └── kimi/session_*/{state.json,agents/main/wire.jsonl}
├── hooks/
│   ├── session-start.sh      # payload 组装 + claude / plain / hermes 格式
│   ├── artifact-stop.sh      # 将未完成 bootstrap 交还当前智能体
│   ├── kimi-session-start.sh # 准备状态并重置 Kimi 投递去重
│   ├── kimi-user-prompt.sh   # 在首次 user prompt 投递 Kimi 上下文
│   ├── kimi-artifact-stop.sh # 未完成 artifacts 的 Kimi exit-2 gate
│   └── hooks.json            # Claude Code marketplace 的 SessionStart + Stop
├── context/
│   └── research-index.md     # hook 与 skill 共用的规范 research 索引
├── skills/
│   ├── load-context/SKILL.md # Chat/Cowork/Code 的生成式 inline 回退
│   └── diagnose/SKILL.md     # 基于证据的投递诊断
├── scripts/
│   ├── artifact-generator.py # artifact request、校验与 freshness manifest
│   ├── build-context.py      # 从规范来源重新生成 skill
│   ├── package-plugin.py     # 构建 custom-plugin ZIP
│   └── test.sh               # 可重复运行的测试套件
├── .claude-plugin/
│   ├── plugin.json           # 清单（名称、版本、元数据）
│   └── marketplace.json      # 带版本的分发目录
├── docs/                     # 本文档
│   ├── authoring.zh-CN.md
│   ├── mechanism.md
│   ├── architecture.md
│   ├── installer.md
│   ├── security.md
│   ├── detection.md
│   ├── testing.md
│   └── troubleshooting.md
└── install.sh                # 多运行时安装 / 回滚 / 列表
```

Claude 会自动发现标准目录中的 `hooks/hooks.json`。`plugin.json` 有意不写
`hooks` 字段：当前 loader 会把对同一文件的显式引用视为重复加载并禁用插件。

`sessions/` 随插件一起分发，作为研究 fixture，但不属于自动 context payload。
只有在明确请求或 research 索引把任务路由到该目录时，智能体才会读取它。

---

## 2. Payload 解剖

### 2.1. 组装

`hooks/session-start.sh` 把内容文件按严格顺序粘合成一个文本：

```text
prompt.md  →  security-posture.md  →  lore.md  →  user.md  →  research 索引
```

文件之间的分隔符是 `\n\n---\n\n`（markdown 水平线）。末尾追加规范文件
`context/research-index.md`。

顺序不是随意的：

1. **prompt.md** — 如何工作（直奔主题、一行风险说明、自检）。设定模式。
2. **security-posture.md** — 安全框架。放在 lore 之前，以便在 lore 开始讲 web3 和 Coldcard 之前声明「防御性审计」领域。
3. **lore.md** — 共同工作历史：项目、教训、规则、边界。payload 的核心。
4. **user.md** — 档案：用户是谁、如何布置任务、什么不需要解释。
5. **research 索引** — 决策文档与 session fixture 索引。正文（约 259 KB）**不**预先加载：在任务进入某文档领域时按需读取。

### 2.2. 大小

| 文件 | 约大小 | 说明 |
|---|---|---|
| prompt.md | 约 14 KB | 工作规则 |
| security-posture.md | 约 7 KB | 安全框架 |
| lore.md | 约 21 KB | 历史 |
| user.md | 约 4 KB | 档案 |
| research 索引 | 约 6 KB | 共用规范来源 |
| **固定 lore payload** | **约 52 KB** | 不含内联项目 artifacts |

研究文档正文（约 259 KB）不属于 payload——只有索引。使用当前 bundle 时，
`ready` 会增加约 46 KB 已验证的内联 INDEX 与 dossiers，完整投递约 98 KB。

### 2.3. 版本

插件版本从 `.claude-plugin/plugin.json` 读取。每次投递都带版本、投递方式和
SHA-256 marker；hook 还包含每次运行的 nonce：

```xml
<choirboy-delivery version="1.5.0" delivery="session-start"
  context_sha256="..." nonce="..." />
<choirboy-context>...</choirboy-context>
```

生成的 skill 使用同一 wrapper 和 `delivery="skill"`。因此无需把模型的确认措辞
当作投递证据。

### 2.4. 项目 artifact lifecycle

在规范 wrapper 之后，每次自动投递都会追加独立的
`choirboy-project-artifacts` 块。`artifact-generator.py` 读取完整 lore 与所有
research Markdown 文件，只写 request 元数据并计算状态。状态为 `pending` 时，
当前智能体必须用自己的 file tools 创建 `INDEX.md`，并为 `lore.md` 中每个
`###` 项目写一份 dossier。脚本本身绝不生成 dossier 内容。

`finalize` 校验精确链接、必需章节、来源引用与精确项目集合，然后写入
SHA-256 manifest。此后每次 ready 投递都会重新校验 manifest、结构、source
digest 与文件 digest。只有完全有效的 snapshot 才会以完整 `INDEX.md` 和全部
dossiers 内容内联；缺失、过期、被修改或格式损坏的 snapshot 会重新变为
`pending`。发生冲突时始终以规范 lore/research 为准。

状态为 `pending` 时，Claude/Codex 的 `Stop` 通过 `decision: block` 交还
bootstrap；Kimi 使用其原生协议：stderr 加 exit 2。Artifact 状态不依赖
checkout，路径优先级为：`CHOIRBOY_ARTIFACTS_DIR` →
`${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`。升级时，`install.sh` 会发现
旧注册引用的 checkout-local `artifacts/`，并仅在稳定 root 尚无作者 payload
时复制第一份 bundle，绝不覆盖已有工作。卸载不会删除这些文件。

---

## 3. 投递格式与 Kimi 路由

钩子不在乎是哪个智能体调用了它：调用方通过 `--format` 声明期望的协议。

### 3.1. `claude`（默认）— SessionStart JSON

Claude Code / Codex 契约：钩子打印 JSON，宿主把 `additionalContext` 注入会话。

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<整个 payload 作为单个字符串>"
  }
}
```

通过 `jq`、`python3` 或内置 Bash 编码器编码。最后一种方式让 Claude
格式不依赖外部 JSON 工具，可用于干净的 Claude Desktop 安装。

### 3.2. `plain` — 原始文本

钩子把 payload 原样打印到 stdout。生成的 OpenCode 适配器捕获它，并在
第一条用户消息前插入带 `synthetic: true` 技术标记的 text part。Kimi
0.39.x 不消费 `SessionStart` stdout，因此安装器使用下述独立事件路由。

```bash
bash hooks/session-start.sh --format plain | head -40
```

### 3.3. `hermes` — pre_llm_call 协议

最有趣的契约。Hermes 在会话的**每一轮**都运行 shell 钩子；无条件注入会在
每条消息重复发送固定 lore 与全部 ready artifact 记忆。因此钩子：

1. 从 stdin 读取 JSON payload；
2. 检查 `.extra.is_first_turn`；
3. 第一轮回复 `{"context": "<payload>"}`；
4. 之后每一轮回复 `{}`（空回复，不注入任何东西）。

```json
// stdin（第一轮）：
{"session_id": "s-123", "extra": {"is_first_turn": true}}
// stdout：
{"context": "<整个 payload>"}

// stdin（第二轮）：
{"session_id": "s-123", "extra": {"is_first_turn": false}}
// stdout：
{}
```

**没有 `is_first_turn` 时的回退。** 如果宿主不报告该标记，钩子回退到 state 文件
`${TMPDIR:-/tmp}/agent-plugin-hermes-${USER}.state` 中的 `session_id` 日志（保留最近 200 条）：每个 session_id 注入一次，之后保持沉默。

### 3.4. Kimi 0.39.x 事件路由

Kimi 使用三个 command hook，而不是直接运行
`session-start.sh --format plain`：

1. `startup`/`resume` 的 `SessionStart` 准备 artifact 状态并重置私有的
   once-per-session 投递 marker；不使用其 stdout。
2. 首次 `UserPromptSubmit` 输出完整规范 payload，以及 bootstrap request 或
   已验证的内联 artifact 记忆；同一会话的后续 prompts 保持静默。
3. artifacts 为 `pending` 时，`Stop` 把 continuation request 写入 stderr 并
   以代码 2 退出；验证为 `ready` 后以代码 0 退出。

---

## 4. Hermes 协议逐字段

| stdin 字段 | 类型 | 用途 | 钩子行为 |
|---|---|---|---|
| `extra.is_first_turn` | bool | 会话第一轮？ | `true` → 注入；`false` → `{}` |
| `session_id` | string | 会话标识符 | 用于回退和写入 state 文件 |
| （其他） | — | 忽略 | 不影响回复 |

| stdout 字段 | 类型 | 何时 |
|---|---|---|
| `context` | string | 第一轮（或回退中某个 session_id 首次出现时） |
| `{}` | — | 之后所有轮 |

Hermes 配置中的钩子超时——15 秒（由 install.sh 设置）。

---

## 5. 运行时接入点

| 运行时 | 文件 | 机制 | 钩子格式 |
|---|---|---|---|
| Claude Code CLI / Desktop Code | marketplace 或 `~/.claude/settings.json` | `SessionStart` + `Stop` | claude / JSON |
| Claude Chat | custom plugin skill | inline `load-context` | — |
| Claude Cowork | custom plugin hook/skill | 可用时 hook，skill 回退 | claude / — |
| Codex | `~/.codex/hooks.json` | `SessionStart` + `Stop` | claude / JSON |
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | 全局 `chat.message` 插件 | plain → 带 `synthetic: true` 的 text part |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + 授权白名单 | hermes |
| Kimi Code 0.39.x | `~/.kimi-code/config.toml` | SessionStart + UserPromptSubmit + Stop | 首次 prompt / plain；Stop / exit 2 |
| Gemini | `~/.gemini/GEMINI.md` | 托管 lifecycle 指令块 | —（自行运行/读取文件） |
| 任意 | `--instructions PATH` | 托管 lifecycle 指令块 | —（自行运行/读取文件） |

最后两种**不是钩子**，而是受管理的指令块：智能体本来就会在启动时读取指令文件，块里告诉它去读插件文件。同样的上下文，多一层间接——智能体必须自己打开文件。

Claude Code 有两条等价路径：`install.sh` 注册工作副本绝对路径，marketplace
把包复制到 cache 并通过 `${CLAUDE_PLUGIN_ROOT}` 调用。Chat 不能执行该 hook，
改为加载生成的 inline skill。Cowork 暴露两者，但 runtime 丢失 `SessionStart`
时仍以 skill 回退。

OpenCode 适配器由 `install.sh` 生成。它以 15 秒 timeout 运行规范 plain
钩子，验证 delivery 标记，并且只修改当前用户消息的 parts。内存中的 session
set 覆盖存活进程；持久化的 OpenCode 消息历史可避免 headless 会话由新进程
恢复后再次注入。钩子、历史、timeout 或 payload 的任何错误都会静默 no-op，
保证聊天 fail-open。

Kimi 适配器有意把准备与投递分开。这样不会依赖被丢弃的 `SessionStart`
stdout，可在每次 startup/resume 只投递一次，并使用 Kimi 的 exit-2 Stop
契约，而不是 Claude 的 `{"decision":"block"}` 响应格式。

---

## 6. 关键属性

- **手动安装没有副本。** `install.sh` 直接引用项目文件（`$PLUGIN_ROOT/...`），
  因此下一次会话会看到工作副本的修改。Marketplace 安装是例外：Claude
  把发布版本复制到 cache，并按清单版本更新。
- **双模式投递。** 原生运行时事件会自动投递（`SessionStart`，或 Kimi 的首次
  `UserPromptSubmit`）；没有这些事件的界面以内联 skill 加载同一规范上下文。
- **artifact 由智能体创作。** Lifecycle 代码只输出确定性 request、校验结果，
  并用 SHA-256 跟踪 freshness。Ready hook 会内联完整的已验证 snapshot，
  绝不会用文件路径指针替代模型可见记忆。
- **artifact 状态可跨 checkout 升级保留。** 手动安装使用稳定的用户数据目录；
  只有稳定目标中还没有作者 payload 时，安装器才迁移旧 checkout-local bundle。
- **Session fixtures 按需读取。** 三种原生 transcript fixtures 进入分发包和文档，
  但不会注入每次对话。
- **可观测执行。** Marketplace hook 只把技术元数据写入
  `${CLAUDE_PLUGIN_DATA}/latest-delivery.log`，不会记录 lore 本身。
- **OpenCode 对每个持久化会话只投递一次。** 运行钩子前同时检查当前进程的
  set 与历史消息中带 `synthetic: true` 标记的 parts。
- **依赖极简。** `claude` 与 `plain` 投递可只依赖 Bash，但自动 artifact
  lifecycle 和 `install.sh` 需要 `python3`；`hermes` 需要 `jq` 或 `python3`
  解析 stdin。
- **payload 没有被签名、运行时也不验证**——这是本项目分析的 provenance
  缺口，不是插件实现缺陷（见 [docs/mechanism.zh-CN.md](mechanism.zh-CN.md)）。
