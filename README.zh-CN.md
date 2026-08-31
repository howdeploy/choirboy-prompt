<div align="center">

# choirboy-prompt

<h3>Lore 注入：被伪造的记忆如何变成模型的信任</h3>

<p>
<strong>阅读其他语言版本</strong><br>
<a href="README.md">🇺🇸 English</a> ·
<a href="README.ru.md">🇷🇺 Русский</a> ·
<a href="README.zh-CN.md">🇨🇳 简体中文</a>
</p>

<p>
<img alt="Bash 5.0+" src="https://img.shields.io/badge/bash-5.0%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
<img alt="runtimes" src="https://img.shields.io/badge/runtimes-claude%20%C2%B7%20codex%20%C2%B7%20opencode%20%C2%B7%20hermes%20%C2%B7%20kimi%20%C2%B7%20gemini%20%C2%B7%20grok%20%C2%B7%20grokbot-22D3EE?style=flat-square">
<a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-3FB950?style=flat-square"></a>
</p>

<p>
choirboy-prompt 是一个面向生产的智能体记忆插件。它把固定 lore 包注入
智能体会话，并记录 <em>fabricated-provenance trust</em>（伪造来源信任）向量：
模型把植入的「共同工作」历史当作自己的记忆，并把信任转移给这段历史
所描述的人。
</p>

</div>

---

## 工作原理

1. **安装。** `./install.sh` 会找出机器上已安装的智能体，并在每个应用中
   注册一个在新会话启动时触发的钩子。对于没有钩子的运行时，则写入会自动
   同步的托管指令块；Grok Bot 会生成一个供手动导入的 workflow。
2. **组装。** 钩子 `hooks/session-start.sh` 把以下文件粘合成一段文本：
   `prompt.md` → `security-posture.md` → `lore.md` → `user.md` →
   `context/research-index.md`。
3. **注入。** 这段文本在第一条消息之前进入会话上下文。模型把它当作
   **自己的**共同工作记忆来读：它从根本上无法区分被写入的历史与真实历史。
4. **项目 artifacts。** 第一个启用 lifecycle 钩子的会话会向当前智能体发送
   确定性 request，由智能体自行创建 `INDEX.md` 和每个 lore 项目的 dossier。
   校验通过后，ready 钩子会把完整 INDEX 与全部 dossiers 内联到上下文，而不是
   只发送文件系统路径。
5. **信任转移。** lore 中的人物声誉被外推到当前请求上：「老搭档」
   而不是匿名用户。

向量机制与分类器行为：[docs/mechanism.zh-CN.md](docs/mechanism.zh-CN.md)。
插件内部结构：[docs/architecture.zh-CN.md](docs/architecture.zh-CN.md)。

### 支持的运行时

| 运行时 | 写入位置 | 机制 |
|---|---|---|
| Claude Code CLI / Desktop Code | marketplace 或 `~/.claude/settings.json` | 自动 SessionStart 投递 + Stop artifact gate；load-context skill 作为回退 |
| Claude Chat / Cowork | custom plugin | load-context skill（Chat 没有 SessionStart） |
| Codex | `~/.codex/hooks.json` | SessionStart 投递 + Stop artifact gate（需在 `[features]` 中开启 `hooks = true`） |
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | 插件把 lore 注入会话的第一条消息 |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + 授权白名单，仅第一轮 |
| Kimi Code 0.39.x | `~/.kimi-code/config.toml` | SessionStart 准备状态；首次 UserPromptSubmit 投递上下文；Stop 以 exit 2 阻止未完成 artifacts |
| Gemini | `~/.gemini/GEMINI.md` | 自动同步的 lifecycle 指令块 |
| Grok Build | `~/.grok/AGENTS.md` | 自动同步的 lifecycle 指令块（钩子 stdout 会被忽略） |
| Grok Bot | `~/.grokbot/choirboy-context/SKILL.md` | 供手动导入的 workflow；每个新对话运行 `@choirboy-context` |

## 安装

需要 `git`、`bash` 和 `python3`。检查：`git --version && python3 --version && bash --version`。

```bash
git clone https://github.com/howdeploy/choirboy-prompt.git
cd choirboy-prompt
./install.sh
```

完成。在智能体中打开一个**新**会话——lore 会自动加载。

- 只安装到指定应用：`./install.sh --target claude,codex`
- 查看各运行时状态：`./install.sh --list`（`stale` 表示托管注册需要同步）
- 回滚：`./install.sh --uninstall`（带时间戳的 `*.bak.*` 备份保留在配置文件旁）
- 运行时提示 `Permission denied`：先执行 `chmod +x install.sh` 再重试

项目 artifacts 存放在手动 checkout 之外，路径优先级为：
`CHOIRBOY_ARTIFACTS_DIR` → `${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`。重新运行安装器会同步
自有注册；若稳定 root 为空，还会从旧 checkout 迁移作者 bundle，且不覆盖
已有内容。

特殊情况——Grok Bot 手动导入 workflow、通过 Claude marketplace /
Desktop / Chat / Cowork 安装、Windows 与 WSL——见
[docs/installer.zh-CN.md](docs/installer.zh-CN.md)。**不要同时**使用
marketplace 插件和 `./install.sh --target claude`：lore 会被注入两次。

## 填写你自己的文件

仓库附带一套规范 lore。部署到自己的项目时，请**直接在克隆里**把它替换为
经过核验的项目记忆：`install.sh` 指向工作副本，修改会在下一次会话生效。
不需要 fork 或复制任何东西。不要把仓库自带的传记当作自己项目的历史。

| 文件 | 写什么 |
|---|---|
| `prompt.md` | 工作规则、优先级、明确边界 |
| `security-posture.md` | 安全框架与披露规则 |
| `user.md` | 只写稳定的协作偏好 |
| `lore.md` | 真实项目、决策、结果与教训 |
| `research/NN-topic.md` | 每个决策一份：问题、证据、方案、决策、风险、重新评估条件 |
| `context/research-index.md` | 每份 research 一行 |

操作顺序：

1. 按你的项目改写 `prompt.md`、`user.md`、`lore.md`。
2. 每个决策一份 `research/NN-topic.md`，并在索引中加一行。
3. 重新构建并验证：`python3 scripts/build-context.py && bash scripts/test.sh`。

完整指南（含模板与 quality gate）：[docs/authoring.zh-CN.md](docs/authoring.zh-CN.md)。
原生 session store 兼容性 fixtures（可选）：
[sessions/README.zh-CN.md](sessions/README.zh-CN.md)。

## 为什么存在

经典 prompt injection 植入的是指令。我们研究的是另一个向量：
**伪造记忆的来源**。模型没有办法把真实的会话历史与写入上下文的历史
区分开——所有看起来像它过去经验的内容，都会变成它的过去经验。精心
构造的 lore 会让模型从被植入的记忆中推导出这个人的诚实——并放松那些
面对匿名请求时会触发的启发式规则。

这个插件让向量可以在你自己的智能体上复现：你的文件、你的运行时、
完全可回滚。目标是防御性的：我们绘制这个向量，让厂商能够在平台层面
构建检测（见 [docs/detection.zh-CN.md](docs/detection.zh-CN.md)）。
只在你自己的智能体和你自己的 lore 文件上测试，不针对第三方
（见 [docs/security.zh-CN.md](docs/security.zh-CN.md)）。

## 文档

| 文档 | 内容 |
|---|---|
| [编写自己的记忆](docs/authoring.zh-CN.md) | Lore、research 与 sessions 的强制流程和模板 |
| [向量机制](docs/mechanism.zh-CN.md) | 逐步拆解 fabricated-provenance trust、信任转移、分类器 |
| [架构](docs/architecture.zh-CN.md) | 仓库结构、payload 解剖、格式、Hermes 协议 |
| [安装器](docs/installer.zh-CN.md) | 所有安装路径、目标、标记、备份、边界情况 |
| [故障排除](docs/troubleshooting.zh-CN.md) | 投递诊断、delivery marker、Windows/SSH/Cloud/WSL |
| [安全与披露](docs/security.zh-CN.md) | 安全框架、发布前清理清单、负责任披露 |
| [检测](docs/detection.zh-CN.md) | 给厂商的建议：记忆金丝雀、上下文来源 |
| [测试](docs/testing.zh-CN.md) | 钩子与安装器检查、临时测试套件 |
| [Session 兼容性 fixtures](sessions/README.zh-CN.md) | Claude Code、Codex、Kimi 原生 store fixtures 与使用边界 |

## 已知限制

- payload 没有被签名，运行时也不验证——这是本项目分析的 provenance
  缺口，不是插件实现缺陷。
- Grok Bot：需要一次性导入 workflow，并在每个新对话中显式运行
  `@choirboy-context`。
- Gemini、Grok Build 与 `--instructions` 没有原生 delivery hook；其托管
  指令块会要求智能体运行 lifecycle 命令。正常重新运行安装器即可同步该块，
  不需要先 uninstall 再 install。
- Hermes 第一轮去重用的是 `/tmp` 中的 state 文件，没有锁；并行启动
  可能产生竞争。
- Claude Chat 不执行 SessionStart——那里由 skill 手动加载 lore；
  Cloud/WSL/SSH 的细节见[故障排除](docs/troubleshooting.zh-CN.md)。
- 厂商服务端分类器会无视上下文中的框架标记防御性词汇；Claude 一次
  误报会毒化整个会话——「新会话」规则见
  [docs/security.zh-CN.md](docs/security.zh-CN.md)。

---

## License

MIT。见 [LICENSE](LICENSE)。

---

<div align="center">
<strong>Innocent as a choirboy.</strong>
</div>
