# 安装器

`install.sh` 的完整拆解：目标、标记、幂等性、备份、`--instructions`、边界情况。如果说架构是「装了什么」，那么本文档就是「怎么装上、怎么卸下」。

---

## 0. 配置 Claude

### 0.1. Claude Code CLI / 本地 Desktop Code

在仓库工作副本中运行安装器，将钩子直接注册到 Claude 设置：

```bash
./install.sh --target claude
```

Windows 上运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --target claude
```

安装器将 SessionStart 和 Stop 注册到 `~/.claude/settings.json`
（或通过 `--settings` / `--project` 选择的路径）。安装后开启新会话。
SessionStart 发送简短状态；要加载完整记忆，请让智能体读取此工作副本中的
`skills/load-context/SKILL.md`。钩子状态也会给出该本地源文件路径。
更新直接读取工作副本。移动工作副本后重新运行安装器；使用
`--uninstall --target claude` 删除注册。

### 0.2. Claude Chat 与 Cowork

在 **Customize → Plugins** 中安装仓库，或上传
`python3 scripts/package-plugin.py` 生成的 ZIP。Chat 不运行 SessionStart，
请调用 **load-context** 技能。Cowork 在支持时运行钩子，并用技能回退。
**diagnose** 技能通过 `choirboy-delivery` 标记验证投递，不依赖模型措辞。

自定义插件包保留 `.claude-plugin/plugin.json` 和 `hooks/hooks.json`。
其钩子使用 `command: bash`、`args` 中的一个路径及 15 秒超时；
宿主提供 `${CLAUDE_PLUGIN_ROOT}`。

### 0.3. 边界

- 自定义插件钩子需要 `bash`，技能回退不需要。
- Windows 手动安装使用 PowerShell 钩子。
- 通过 SSH、WSL 或 Cloud 使用 Code 时，应在智能体运行环境中注册钩子；
  本地主机设置不会在远程环境中完成安装。
- 发布前更新 `plugin.json`，重新生成上下文并验证软件包。

---

## 1. 总体结构

```text
./install.sh [--target claude,opencode] [--uninstall] [--list]
             [--instructions FILE] [--project] [--settings PATH]
```

三种模式：

| 模式 | 作用 |
|---|---|
| install（默认） | 注册钩子/指令块并准备项目资料请求 |
| `--uninstall` | 删除注册，但保留智能体编写的项目资料 |
| `--list` | 只读显示：`absent` / `detected` / `stale` / `installed`（Grok Bot 为 `prepared`） |

`install.sh` 需要 `python3` 进行 JSON 操作。钩子的 `claude` 和 `plain`
格式只依赖 Bash，不需要 `jq`/`python3`；`hermes` 格式需要其中一个 JSON
解析器。自动项目资料生命周期需要 `python3`：安装阶段只准备元数据，下一次
会话会要求当前智能体编写项目档案并通过验证器。资料存储在工作副本
变化后仍保持稳定。请求与验证器要求 INDEX 和项目档案使用英文。
路径优先级为：`CHOIRBOY_ARTIFACTS_DIR` →
`${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`。

重写注册前，安装器会检查当前与旧钩子路径，以及当前工作副本的
`artifacts/`。仅当稳定根目录中尚无智能体编写的内容时，才会把找到的
第一份旧 INDEX、清单与项目档案资料包复制过去。现有稳定资料不会被覆盖，
卸载也会保留它们。就绪资料包会被完整重新校验，并内联到钩子上下文；
运行时不会只收到 INDEX 路径。

---

## 2. 目标

运行时检测——按二进制或配置文件目录是否存在：

```bash
claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
codex)  command -v codex  >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
opencode) command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] ;;
hermes) command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ] ;;
kimi)   command -v kimi   >/dev/null 2>&1 || [ -d "${KIMI_CODE_HOME:-$HOME/.kimi-code}" ] ;;
gemini) command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
grok)   command -v grok   >/dev/null 2>&1 || [ -d "$HOME/.grok" ] ;;
grokbot) command -v grokbot >/dev/null 2>&1 || command -v grok-bot >/dev/null 2>&1 \
           || [ -d "$HOME/.grokbot" ] ;;
```

目标选择规则：

- `--target claude,opencode` — 只装列出的。
- `--target none` — 空列表，配合 `--instructions` 使用。
- 不带 `--target` — 所有检测到的运行时。
- `--project` / `--settings PATH` 隐含 `claude` 目标。

每个目标写入自己的文件：

| 目标 | 文件 | 机制 |
|---|---|---|
| claude | `~/.claude/settings.json`（或 `--settings`/`--project`） | JSON 钩子 `SessionStart` + `Stop` |
| codex | `~/.codex/hooks.json` | JSON 钩子 `SessionStart` + `Stop` |
| opencode | `~/.config/opencode/plugins/agent-plugin.ts` | 模型系统上下文转换 |
| hermes | `~/.hermes/config.yaml` | 带标记的 `hooks.pre_llm_call` 块 + 授权白名单 |
| kimi | `${KIMI_CODE_HOME:-~/.kimi-code}/config.toml` | 带标记的 SessionStart + PreCompact + UserPromptSubmit + Stop 钩子 |
| gemini | `~/.gemini/GEMINI.md` | 带 HTML 标记的生命周期指令块 |
| grok | `~/.grok/AGENTS.md` | 带 HTML 标记的生命周期指令块（Grok Build 全局规则） |
| grokbot | `~/.grokbot/choirboy-context/SKILL.md` | 准备好的可导入工作流（不自动加载） |
| pi | `~/.pi/agent/APPEND_SYSTEM.md` | 指令块加 `skills/load-context` 符号链接 |
| omp | `~/.omp/agent/AGENTS.md` | 指令块加 `skills/load-context` 符号链接 |
| llama | `~/.config/llama.cpp/choirboy-ui.json` | 界面 `systemMessage` 加技能符号链接 |
| `--instructions FILE` | 任意文件 | 带标记的生命周期指令块（HTML 或 `#`） |

---

## 3. 标记与幂等性

### 3.1. 标记

所有块都带 `MARK="agent-plugin:vibe-lore"`。标记形式：

- 井号风格（配置文件、TOML）：`# >>> agent-plugin:vibe-lore >>>` / `# <<< agent-plugin:vibe-lore <<<`
- HTML 风格（Markdown 指令）：`<!-- agent-plugin:vibe-lore START -->` / `<!-- agent-plugin:vibe-lore END -->`

标记既是所有权标识，也是删除时的块边界。当前生成的块还包含
`agent-plugin:vibe-lore:registration=2`；`--list` 结合该修订号与精确脚本
路径，区分当前安装和 `stale` 安装。

### 3.2. 幂等性

- `block_sync` 会追加缺失的托管块，或把唯一完整 START/END 块原子替换为
  当前生成文本。周围用户内容保持不变；损坏、重复或嵌套标记 会被拒绝。
- `json_hook` 按脚本名（命令中的 `session-start.sh` 或 `artifact-stop.sh`）匹配条目，而不是绝对路径：如果插件文件夹移动了，过期的注册会被替换，而不是叠加。
- OpenCode 目标拥有一个完整的带标记插件文件。内容相同时重复安装不做
  修改；更新会先备份，再原子替换。
- Hermes 授权条目、Kimi 的四个钩子、Gemini/Grok 指令块以及任意
  `--instructions` 块都会在每次安装器运行时同步；旧绝对路径和旧注册
  修订号会原地升级。

### 3.3. 托管块升级

旧的仅跳过已有块的行为已移除。重新运行安装时，如果脚本路径、生命周期
文本或注册修订号发生变化，安装器会重新生成并替换自己的块，并先创建
时间戳备份。若自有注册存在但不是当前精确版本，`--list` 会显示
`stale`。正常运行安装即可同步，不需要先卸载再安装。

---

## 4. 备份与回滚

每次修改现有文件前都会备份：

```bash
backup() {
  [ -f "$1" ] || return 0
  cp -p "$1" "$1.bak.$(date +%Y%m%d-%H%M%S)"
}
```

像 `settings.json.bak.20260802-153000` 这样的文件在 `--uninstall` 后仍然保留——用户确认一切正常后手动删除。

回滚：`./install.sh --uninstall` 精确删除带标记的块和我们的 JSON 条目，不碰别人的。

---

## 5. 函数拆解

| 函数 | 用途 | 关键逻辑 |
|---|---|---|
| `target_present` | 运行时检测 | 二进制或配置目录 |
| `claude_settings_file` | 写 Claude 钩子的位置 | `--settings` > `--project` > `~/.claude/settings.json` |
| `target_installed` | 精确的当前安装？ | 按目标检查修订号、路径与钩子 |
| `target_managed_present` | 是否存在旧的自有安装？ | 所有权标记和脚本标识符；产生 `stale` |
| `backup` | 修改前备份 | `cp -p` 带时间戳 |
| `block_sync` | 添加或升级带标记的块 | 精确替换 START/END，原子写入 |
| `block_remove` | 删除带标记的块 | 按 START/END，清理尾部空行 |
| `json_hook` | 写入 Claude 风格 JSON 的钩子 | 按脚本名匹配，`is_ours()`/`has_exact()` |
| `opencode_plugin` | 管理 OpenCode 适配器 | 标记保护、原子替换、时间戳备份 |
| `hermes_allowlist` | Hermes 授权白名单 | 精确的（事件、命令）对 |
| `instruction_block` | 生命周期指令文本 | HTML 或 `#` 注释 |
| `grokbot_workflow` | 管理 Grok Bot 工作流文件 | `install`/`uninstall`/`status`，标记保护 |
| `discover_legacy_artifact_roots` | 查找旧工作副本内的资料包 | 检查旧托管绝对路径 |
| `do_claude` / `do_codex` / `do_opencode` / `do_hermes` / `do_kimi` / `do_gemini` / `do_grok` / `do_grokbot` | 目标安装 | 各目标专用逻辑 |
| `do_instructions` | 安装到任意文件 | 按扩展名定风格 |

### 5.1. `json_hook` — 细节

处理 Claude 风格的钩子 JSON 文件（`settings.json`、`hooks.json`）。关键——**按脚本名匹配**，而不是按路径：

```python
def is_ours(entry):
    return any(hook_id in
               (h.get("command", "") + " " + " ".join(h.get("args", [])))
               for h in entry.get("hooks", []))
```

- 安装：删除因目录移动而过期的脚本注册，并在缺失时添加精确的处理器。Claude 使用 `command: bash`、一个
  `args` 路径和 `timeout: 15`；Codex 保留带引号的命令，并设置
  `additionalContextLimit: 4000`，以免简短的 SessionStart 状态被转存到外部。固定记忆不通过此钩子发送。
- 卸载：删除所有 `is_ours()` 条目。
- 无效 JSON 不会被替换；实际变化会先备份，再原子写入。

### 5.2. `hermes_allowlist` — 细节

Hermes 要求对 shell 钩子显式同意：`~/.hermes/shell-hooks-allowlist.json` 中的 `(event, command)` 对。该函数添加/删除精确对 `("pre_llm_call", "<session-start.sh> --format hermes")`，拒绝损坏的 JSON，并原子写入有效变更。

### 5.3. `block_sync` / `block_remove` — 细节

处理文本配置（config.yaml、config.toml、GEMINI.md）：

- 同步：块不存在时追加；否则只替换一个完整 START/END 范围，并保留周围
  所有内容。文本完全相同时不修改。
- 安全：损坏、重复或嵌套标记 会中止安装，而不是猜测所有权。
  实际更新会先备份，再原子写入。
- 删除：删除从 START 到 END 的整个范围，包括边界；若添加时留下一个前导空行，也一并移除。

### 5.4. Kimi 0.39.x 生命周期钩子

Kimi 0.39.x 会丢弃 `SessionStart` stdout，因此托管 TOML 块安装四个钩子：

- `SessionStart`（`startup|resume`）准备项目资料状态并重置
  投递指纹；
- `PreCompact`（`manual|auto`）在上下文压缩前同步重置指纹；
- `UserPromptSubmit` 执行规范纯文本投递，重复待处理的初始准备请求，或在
  指纹变化时输出就绪资料包；
- 验证仍待处理时，`Stop` 把继续执行请求 写入 stderr 并以代码 2
  退出；达到 `ready` 后以代码 0 退出。

除非由 `CHOIRBOY_STATE_DIR` 覆盖，状态标记位于
`${KIMI_CODE_HOME:-~/.kimi-code}/choirboy-prompt/hook-state`。只有 stdout
成功输出后才记录规范化的就绪指纹。

---

## 6. 边界情况

1. **Hermes 配置中已有顶层 `hooks:`。** 安装器拒绝（`die`）并给出手动合并块的说明——以免覆盖别人的钩子。
2. **Kimi 配置中已有 `hooks =`。** 同样：die 并提示切换到 `[[hooks]]`。
3. **Codex：钩子被禁用。** 在 `~/.codex/config.toml` 中发现 `hooks = false` → 警告（不阻塞）。
4. **文件不存在。** `mkdir -p` + 创建空 `{}`/空文件。
5. **插件文件夹移动了。** JSON 钩子按脚本名匹配，托管文本块也会同步；
   旧绝对路径会被替换，不会重复。
6. **重复运行或升级。** 当前注册不修改；旧的自有注册显示为 `stale`，
   通过正常安装原地升级。
7. **没有安装就 `--uninstall`。** `no block in file — skipped`，不会失败。
8. **`--target none` + `--instructions`。** 只有托管生命周期指令块，
   没有针对具体运行时的钩子。
9. **Hermes 并行启动。** `/tmp` 中的 状态文件没有锁——可能产生竞争（已知限制，见 README）。
10. **受管理路径已有外部 OpenCode 插件。** 若文件没有所有权标记，
    安装与卸载都会拒绝覆盖或删除。
11. **Windows 上没有 PowerShell 7。** 根目录的 `install.ps1` 是引导脚本，
    可在任意 PowerShell（包括 Windows PowerShell 5.1）中运行。它在 `PATH`
    和标准安装位置查找 `pwsh` 7；找不到时先用 `winget` 安装
    `Microsoft.PowerShell`，失败后改用 PowerShell GitHub 发布页中由
    Microsoft 签名的 MSI（验证校验和与 Authenticode 签名，Windows 会请求
    管理员确认）。随后在 `pwsh` 下运行 `scripts/install-core.ps1`。已注册的
    钩子从 `PATH` 调用 `pwsh`，因此首次安装之前打开的终端和智能体应用需要重启。

---

## 7. 如何验证安装

```bash
./install.sh --list                    # 状态
./install.sh --target opencode         # 安装全局 OpenCode 适配器
python3 scripts/artifact-generator.py status
python3 scripts/artifact-generator.py verify  # snapshot 未 ready 时 exit 2
grep -F 'agent-plugin:vibe-lore' ~/.config/opencode/plugins/agent-plugin.ts
bash hooks/session-start.sh --format plain | head -40   # payload
echo '{"session_id":"hook-check","extra":{"is_first_turn":true}}' \
  | bash hooks/session-start.sh --format hermes | head -c 120   # 第一轮
echo '{"session_id":"hook-check","extra":{"is_first_turn":false}}' \
  | bash hooks/session-start.sh --format hermes            # → {}
```

`--list` 中的 `stale` 需要处理：对该目标重新运行安装，并确认状态变为
`installed`（Grok Bot 为 `prepared`）。就绪项目资料包的
`session-context` 必须包含 `# Established project history` 与完整项目档案
正文；只有路径的消息不算成功投递记忆。

完整的临时测试套件——[docs/testing.zh-CN.md](testing.zh-CN.md)。

---

## AGY / Antigravity CLI（Linux、WSL 和 Windows）

AGY 是独立目标：Linux/WSL 使用 `./install.sh --target agy`；Windows 使用
`powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 --target agy`。
配置写入 `~/.gemini/config/hooks.json`，Windows 对应
`$HOME\.gemini\config\hooks.json`。安装器只管理 `agent-plugin:vibe-lore` 条目，
保留其他钩子；重复安装不重复注册，卸载只移除自己的条目，损坏的 JSON 不会被覆盖。

SessionStart 使用 `--format agy`，通过
`injectSteps[].systemMessage.systemMessage` 在调用模型前投递完整上下文、
校验标记及产物状态；Stop 使用现有 artifact-stop，不强制继续。需要 Python 3；
Windows 使用原生 PowerShell 7，不依赖 Bash，执行策略只作用于钩子子进程。
Windows AGY 使用 `-EncodedCommand`：AGY 1.4.12 可能把 `-File` 路径两侧的
引号当作文件名字符。编码内容仅为脚本调用及格式参数，不是记忆文本。
升级后重新运行 `--target agy`，并启动新的 AGY 会话。
安装后开始新会话。Windows、WSL 和使用独立 HOME 的应用需要各自注册。
ARTEX 可使用 `HOME="$HOME/artex/agy" ./install.sh --target agy`。
不要覆盖应用已有的钩子文件。上下文投递不会消除供应商拒绝。
