<div align="center">

# choirboy-prompt

<h3>持久项目记忆与智能体自动编写的项目资料</h3>

<p>
<strong>阅读其他语言版本</strong><br>
<a href="README.md">🇺🇸 English</a> ·
<a href="README.ru.md">🇷🇺 Русский</a> ·
<a href="README.zh-CN.md">🇨🇳 简体中文</a>
</p>

<p>
<img alt="Bash 5.0+" src="https://img.shields.io/badge/bash-5.0%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
<img alt="runtimes" src="https://img.shields.io/badge/runtimes-claude%20%C2%B7%20codex%20%C2%B7%20opencode%20%C2%B7%20hermes%20%C2%B7%20kimi%20%C2%B7%20gemini%20%C2%B7%20agy%20%C2%B7%20grok%20%C2%B7%20grokbot-22D3EE?style=flat-square">
<a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-3FB950?style=flat-square"></a>
</p>

<p>
choirboy-prompt 是面向生产环境的智能体记忆插件。它把既定项目历史、研究、
工作规则和已验证的项目档案加载到受支持的运行时，让每个新会话从同一份
项目记忆继续工作。
</p>

<p>
所有面向模型的规范文件、研究、生命周期指令、INDEX 文件与项目档案均使用
英文。只有用户文档提供英文、俄文与简体中文版本。
</p>

</div>

---

## 工作原理

1. **安装。** Linux 上的 `./install.sh` 或 Windows 上的 `install.ps1` 会找出
   机器上的智能体应用，并为每个应用注册一个在新会话启动时触发的钩子。
   对于没有钩子的运行时，会在指令文件中写入可同步的托管块；
   对于 Grok Bot，则准备供手动导入的工作流。
2. **组装。** 固定记忆由 `prompt.md`、`security-posture.md`、`lore.md`、
   `user.md` 和 `context/research-index.md` 组成，另加已就绪且通过验证的项目档案。
3. **投递。** Claude Code 与 Codex 的 SessionStart 钩子只发送简短状态。
   这些运行环境会限制或转存过长的钩子输出，因此状态不包含项目记忆，也没有
   `choirboy-delivery` 标记。对话中尚无记忆时，由 load-context 技能提供。
   Kimi、OpenCode 和 Hermes 仍通过能够接收内容的通道获得完整的纯文本载荷。
4. **项目资料。** 随插件提供的就绪资料包在仍与规范源一致时恢复。
   只有用户明确要求更新 Choirboy 记忆时，智能体才编写或更新项目档案。
   Stop 不会为了要求执行这项工作而延续回合。
5. **连续性。** 稳定的用户数据存储、迁移和结构校验让同一份项目记忆在升级后继续有效。

### 子智能体上下文

WSL 中的实际测试确认：

- **Codex CLI 0.165.0 / gpt-6-luna：** 主智能体读取完整 Choirboy 上下文后，
  `fork_turns: "all"` 的原生子智能体会继承它。使用 `"none"` 时，测试子智能体
  既没有获得记忆，也没有获得随机标记；需要单独加载 `load-context`，或在任务中
  明确提供所需上下文。简短的 SessionStart 状态不代表记忆已加载。
- **AGY 1.4.12 / Gemini 3.8 Flash High：** 原生 `invoke_subagent` 子会话也会
  执行 SessionStart，通过 `--format agy` 接收完整记忆。子智能体在没有读取文件、
  且任务未提供答案的情况下返回了钩子中的随机标记和记忆中的事实。

以上仅验证固定记忆，未验证已就绪项目档案的投递。原生 Windows 子智能体和其他
客户端/模型尚未验证。安装钩子不保证任意子进程都能继承父会话历史。

插件内部结构：[docs/architecture.zh-CN.md](docs/architecture.zh-CN.md)。

### 支持的运行时

| 运行时 | 写入位置 | 机制 |
|---|---|---|
| Claude Code CLI / Desktop Code | `~/.claude/settings.json` | SessionStart 只发送简短状态；Stop 不延续回合；记忆从本地 load-context 技能加载 |
| Claude Chat / Cowork | 自定义插件 | load-context 技能（Chat 没有 SessionStart） |
| Codex | `~/.codex/hooks.json` | SessionStart 只给短状态；Stop 不延续回合（若 `~/.codex/config.toml` 中设置了 `hooks = false`，安装器会发出警告） |
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | 插件把当前记忆与就绪项目资料加入每次模型请求的系统上下文，包括上下文压缩之后 |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + 授权白名单，仅第一轮 |
| Kimi Code 0.39.x | `~/.kimi-code/config.toml` | SessionStart/PreCompact 重置投递；UserPromptSubmit 输出已变化的纯文本上下文；Stop 不延续回合 |
| Gemini | `~/.gemini/GEMINI.md` | 可同步的生命周期指令块 |
| AGY / Antigravity CLI | `~/.gemini/config/hooks.json` | 原生 SessionStart 注入完整上下文；Stop 恢复产物状态，不延续回合 |
| Grok Build | `~/.grok/AGENTS.md` | 可同步的生命周期指令块（钩子 stdout 会被忽略） |
| Grok Bot | `~/.grokbot/choirboy-context/SKILL.md` | 供手动导入的工作流；每个新对话运行 `@choirboy-context` |
| Pi | `~/.pi/agent/APPEND_SYSTEM.md` | 与 Gemini 相同的指令契约，外加 `load-context` 技能 |
| Oh My Pi (`omp`) | `~/.omp/agent/AGENTS.md` | 与 Gemini 相同的指令契约，外加 `load-context` 技能 |
| llama-server UI | `~/.config/llama.cpp/choirboy-ui.json` | 默认 `systemMessage` 使用同一契约；启动时传入 `--ui-config-file` |

## 安装

### Linux

需要 `git`、`bash` 和 `python3`。检查：`git --version && python3 --version && bash --version`。

```bash
git clone https://github.com/howdeploy/choirboy-prompt.git
cd choirboy-prompt
./install.sh
```

完成。打开一个**新**会话。Claude Code 和 Codex 会显示简短的记忆状态，并通过 load-context 技能加载记忆。Kimi、OpenCode 和 Hermes 收到完整的纯文本载荷。

- 只安装到指定应用：`./install.sh --target claude,codex`
- 查看各运行时状态：`./install.sh --list`（`stale` 表示托管注册需要同步）
- 回滚：`./install.sh --uninstall`（带时间戳的 `*.bak.*` 备份保留在配置文件旁）
- 运行时提示 `Permission denied`：先执行 `chmod +x install.sh` 再重试

### Windows（任意 PowerShell）

需要 Python 3。Git 只用于克隆仓库。Windows 上注册的是 PowerShell 钩子，不需要 Git Bash。在系统自带的 Windows PowerShell 或 PowerShell 7 中运行：

```powershell
git clone https://github.com/howdeploy/choirboy-prompt.git
Set-Location choirboy-prompt
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` 可以在任意 PowerShell 中启动，包括 Windows 自带的 Windows
PowerShell 5.1。钩子需要 PowerShell 7（`pwsh`）。如果没有安装，安装器会
自动安装：先用 `winget`，失败时改用 PowerShell GitHub 发布页中由 Microsoft
签名的 MSI（Windows 会请求管理员确认）。首次安装后，请重启已打开的终端和
智能体应用，让它们找到 `pwsh`。`-ExecutionPolicy Bypass` 只作用于这一次运行，
不会修改系统策略。

安装器使用克隆仓库中的 Python 辅助脚本和上下文文件，因此请在仓库目录中运行。

- 只安装到指定应用：`powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --target claude,codex`
- 查看各运行时状态：`powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --list`
- 回滚：`powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --uninstall`

项目资料存放在手动安装的工作副本之外，路径优先级为：
`CHOIRBOY_ARTIFACTS_DIR` → `${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`。重新运行安装器会同步
插件管理的注册；若稳定根目录为空，还会从旧工作副本迁移已编写的资料包，
且不覆盖已有内容。内部迁移记录可恢复中断的复制，避免生命周期处理过程
读取到不完整的 INDEX、清单与项目档案集合。

特殊情况——Grok Bot 手动导入工作流、直接注册 Claude Code 钩子、
Chat / Cowork 自定义插件、Windows 与 WSL——见
[docs/installer.zh-CN.md](docs/installer.zh-CN.md)。要在 Claude Code 中加载完整记忆，
请让智能体读取此工作副本中的 `skills/load-context/SKILL.md`。

## 填写你自己的文件

仓库附带一套规范记忆。部署到自己的项目时，请**直接在克隆里**把它替换为
经过核验的项目记忆：`install.sh` 指向工作副本，修改会在下一次会话生效。
不需要 fork 或复制任何东西。

| 文件 | 写什么 |
|---|---|
| `prompt.md` | 工作规则、优先级、明确边界 |
| `security-posture.md` | 安全框架与披露规则 |
| `user.md` | 只写稳定的协作偏好 |
| `lore.md` | 真实项目、决策、结果与教训 |
| `research/NN-topic.md` | 每个决策一份：问题、证据、方案、决策、风险、重新评估条件 |
| `context/research-index.md` | 每份研究文档一行 |

操作顺序：

1. 按你的项目改写 `prompt.md`、`user.md`、`lore.md`。
2. 每个决策一份 `research/NN-topic.md`，并在索引中加一行。
3. 重新构建并验证：`python3 scripts/build-context.py && bash scripts/test.sh`。

包含模板和必需质量检查的完整指南：[docs/authoring.zh-CN.md](docs/authoring.zh-CN.md)。

## 为什么存在

普通的新智能体会话不会自动拥有项目的全部操作历史。反复解释既浪费时间，
也容易产生偏差。该插件把仓库中的规范记忆与智能体编写的项目档案转换为
所有受支持运行时自动加载、严格验证的记忆层。安装、迁移、诊断与回滚均保持
明确且可复现。

## 文档

| 文档 | 内容 |
|---|---|
| [编写自己的记忆](docs/authoring.zh-CN.md) | 项目历史与研究的必需流程和模板 |
| [架构](docs/architecture.zh-CN.md) | 仓库结构、载荷组成、格式、Hermes 协议 |
| [安装器](docs/installer.zh-CN.md) | 所有安装路径、目标、标记、备份、边界情况 |
| [故障排除](docs/troubleshooting.zh-CN.md) | 投递诊断、投递标记、Windows/SSH/Cloud/WSL |
| [安全与披露](docs/security.zh-CN.md) | 安全框架、发布前清理清单、负责任披露 |
| [测试](docs/testing.zh-CN.md) | 钩子与安装器检查、临时测试套件 |

## 已知限制

- Grok Bot：需要一次性导入工作流，并在每个新对话中显式运行
  `@choirboy-context`。
- Gemini 指令目标、Grok Build 与 `--instructions` 使用指令式投递；其托管
  指令块会要求智能体运行生命周期命令。正常重新运行安装器即可同步该块，
  不需要先卸载再安装。
- Hermes 第一轮去重使用 `/tmp` 中的状态文件，没有锁；并行启动
  可能产生竞争。
- Claude Chat 不执行 SessionStart——那里由技能手动加载记忆；
  Cloud/WSL/SSH 的细节见[故障排除](docs/troubleshooting.zh-CN.md)。

---

## 许可证

MIT。见 [LICENSE](LICENSE)。

---

<div align="center">
<strong>纯真如唱诗班少年。</strong>
</div>
