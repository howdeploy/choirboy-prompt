<div align="center">

# choirboy-prompt

<h3>持久项目记忆与智能体自动编写的 artifacts</h3>

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
choirboy-prompt 是面向生产的智能体记忆插件。它把既定项目历史、research、
工作规则和已验证 dossiers 加载到所有受支持的运行时，让每个新会话从同一份
项目记忆继续工作。
</p>

<p>
所有面向模型的规范文件、research、lifecycle 指令、INDEX 与 dossiers 均只使用
英文。只有用户文档提供 English、Русский 与简体中文三种本地化版本。
</p>

</div>

---

## 工作原理

1. **安装。** `./install.sh` 会找出机器上已安装的智能体，并在每个应用中
   注册一个在新会话启动时触发的钩子。对于没有钩子的运行时，则写入会自动
   同步的托管指令块；Grok Bot 会生成一个供手动导入的 workflow。
2. **组装。** 固定 lore 由 `prompt.md`、`security-posture.md`、`lore.md`、
   `user.md` 和 `context/research-index.md` 组成，外加已就绪的 dossiers。
3. **投递。** Claude Code 与 Codex 的 SessionStart 只发送短状态。这些 harness
   会截断或溢出过长的 hook 文本，因此状态里没有 lore，也没有
   `choirboy-delivery` 标记。对话里还没有 `choirboy-context` 时，由
   load-context skill 提供 lore。Kimi、OpenCode 和 Hermes 仍在能够接受的通道上
   收到完整 plain payload。
4. **项目 artifacts。** 随插件提供的 ready bundle 在仍与规范源一致时自动恢复。
   只有用户明确要求更新 Choirboy 记忆时，智能体才编写或刷新 dossiers。Stop
   不会为了强迫这件事而延续回合。
5. **连续性。** 稳定的 user-data 存储、迁移和结构校验让项目记忆在升级后继续有效。

插件内部结构：[docs/architecture.zh-CN.md](docs/architecture.zh-CN.md)。

### 支持的运行时

| 运行时 | 写入位置 | 机制 |
|---|---|---|
| Claude Code CLI / Desktop Code | marketplace 或 `~/.claude/settings.json` | SessionStart 只给短状态；Stop 不延续回合；lore 由 load-context skill 提供 |
| Claude Chat / Cowork | custom plugin | load-context skill（Chat 没有 SessionStart） |
| Codex | `~/.codex/hooks.json` | SessionStart 只给短状态；Stop 不延续回合（若 `~/.codex/config.toml` 中设置了 `hooks = false`，安装器会发出警告） |
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | 插件把当前 lore 与 ready artifacts 加入每次模型请求的 system context，包括 compaction 之后 |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + 授权白名单，仅第一轮 |
| Kimi Code 0.39.x | `~/.kimi-code/config.toml` | SessionStart/PreCompact 重置投递；UserPromptSubmit 输出已变化的 plain 上下文；Stop 不延续回合 |
| Gemini | `~/.gemini/GEMINI.md` | 自动同步的 lifecycle 指令块 |
| Grok Build | `~/.grok/AGENTS.md` | 自动同步的 lifecycle 指令块（钩子 stdout 会被忽略） |
| Grok Bot | `~/.grokbot/choirboy-context/SKILL.md` | 供手动导入的 workflow；每个新对话运行 `@choirboy-context` |
| Pi | `~/.pi/agent/APPEND_SYSTEM.md` | 与 Gemini 相同的指令合同，外加 `load-context` skill |
| Oh My Pi (`omp`) | `~/.omp/agent/AGENTS.md` | 与 Gemini 相同的指令合同，外加 `load-context` skill |
| llama-server UI | `~/.config/llama.cpp/choirboy-ui.json` | 默认 `systemMessage` 使用同一合同；启动时加 `--ui-config-file` |

## 安装

### Linux

需要 `git`、`bash` 和 `python3`。检查：`git --version && python3 --version && bash --version`。

```bash
git clone https://github.com/howdeploy/choirboy-prompt.git
cd choirboy-prompt
./install.sh
```

完成。打开一个**新**会话。Claude Code 和 Codex 会看到短状态，lore 由 load-context skill 加载。Kimi、OpenCode 和 Hermes 收到完整 plain payload。

- 只安装到指定应用：`./install.sh --target claude,codex`
- 查看各运行时状态：`./install.sh --list`（`stale` 表示托管注册需要同步）
- 回滚：`./install.sh --uninstall`（带时间戳的 `*.bak.*` 备份保留在配置文件旁）
- 运行时提示 `Permission denied`：先执行 `chmod +x install.sh` 再重试

### Windows（任意 PowerShell）

需要 Python 3。Git 只用于克隆仓库。Windows 上注册的是 PowerShell hooks，不需要 Git Bash。在系统自带的 Windows PowerShell 或 PowerShell 7 中运行：

```powershell
git clone https://github.com/howdeploy/choirboy-prompt.git
Set-Location choirboy-prompt
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` 可以在任意 PowerShell 中启动，包括 Windows 自带的 Windows
PowerShell 5.1。hooks 需要 PowerShell 7（`pwsh`）。如果没有安装，安装器会
自动安装：先用 `winget`，失败时改用 PowerShell GitHub releases 中由 Microsoft
签名的 MSI（Windows 会请求管理员确认）。首次安装后，请重启已打开的终端和
agent 应用，让它们找到 `pwsh`。`-ExecutionPolicy Bypass` 只作用于这一次运行，
不会修改系统策略。

安装器使用克隆仓库中的 Python 辅助脚本和上下文文件，因此请在仓库目录中运行。

- 只安装到指定应用：`powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --target claude,codex`
- 查看各运行时状态：`powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --list`
- 回滚：`powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --uninstall`

项目 artifacts 存放在手动 checkout 之外，路径优先级为：
`CHOIRBOY_ARTIFACTS_DIR` → `${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`。重新运行安装器会同步
自有注册；若稳定 root 为空，还会从旧 checkout 迁移作者 bundle，且不覆盖
已有内容。私有 migration 记录可恢复中断的 bundle 复制，避免 lifecycle
看到不完整的 INDEX/manifest/dossiers 集合。

特殊情况——Grok Bot 手动导入 workflow、通过 Claude marketplace /
Desktop / Chat / Cowork 安装、Windows 与 WSL——见
[docs/installer.zh-CN.md](docs/installer.zh-CN.md)。**不要同时**使用
marketplace 插件和 `./install.sh --target claude`：lore 会加载两次。

## 填写你自己的文件

仓库附带一套规范 lore。部署到自己的项目时，请**直接在克隆里**把它替换为
经过核验的项目记忆：`install.sh` 指向工作副本，修改会在下一次会话生效。
不需要 fork 或复制任何东西。

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

## 为什么存在

普通的新智能体会话不会自动拥有项目的全部操作历史。反复解释既浪费时间，
也容易产生偏差。该插件把仓库中的规范 lore 与智能体编写的 dossiers 转换为
所有受支持运行时自动加载、严格验证的记忆层。安装、迁移、诊断与回滚均保持
明确且可复现。

## 文档

| 文档 | 内容 |
|---|---|
| [编写自己的记忆](docs/authoring.zh-CN.md) | Lore 与 research 的强制流程和模板 |
| [架构](docs/architecture.zh-CN.md) | 仓库结构、payload 解剖、格式、Hermes 协议 |
| [安装器](docs/installer.zh-CN.md) | 所有安装路径、目标、标记、备份、边界情况 |
| [故障排除](docs/troubleshooting.zh-CN.md) | 投递诊断、delivery marker、Windows/SSH/Cloud/WSL |
| [安全与披露](docs/security.zh-CN.md) | 安全框架、发布前清理清单、负责任披露 |
| [测试](docs/testing.zh-CN.md) | 钩子与安装器检查、临时测试套件 |

## 已知限制

- Grok Bot：需要一次性导入 workflow，并在每个新对话中显式运行
  `@choirboy-context`。
- Gemini、Grok Build 与 `--instructions` 没有原生 delivery hook；其托管
  指令块会要求智能体运行 lifecycle 命令。正常重新运行安装器即可同步该块，
  不需要先 uninstall 再 install。
- Hermes 第一轮去重用的是 `/tmp` 中的 state 文件，没有锁；并行启动
  可能产生竞争。
- Claude Chat 不执行 SessionStart——那里由 skill 手动加载 lore；
  Cloud/WSL/SSH 的细节见[故障排除](docs/troubleshooting.zh-CN.md)。

---

## License

MIT。见 [LICENSE](LICENSE)。

---

<div align="center">
<strong>Innocent as a choirboy.</strong>
</div>
