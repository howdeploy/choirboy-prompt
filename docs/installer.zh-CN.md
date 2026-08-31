# 安装器

`install.sh` 的完整拆解：目标、标记、幂等性、备份、`--instructions`、边界情况。如果说架构是「装了什么」，那么本文档就是「怎么装上、怎么卸下」。

---

## 0. 安装 Claude plugin

本仓库通过 `.claude-plugin/marketplace.json` 充当带版本的 Claude
marketplace。安装包同时包含 Claude Code `SessionStart`、`Stop` 钩子和可在
Chat/Cowork 中使用的 skills。

### 0.1. Claude Code CLI

```text
/plugin marketplace add howdeploy/choirboy-prompt
/plugin install choirboy-prompt@choirboy-prompt
```

安装后启动新会话。通过 CLI 更新或删除：

```text
/plugin marketplace update choirboy-prompt
/plugin update choirboy-prompt@choirboy-prompt
/plugin uninstall choirboy-prompt@choirboy-prompt
/plugin marketplace remove choirboy-prompt
```

### 0.2. Claude Desktop Code

Desktop 不提供终端式 `/plugin` 对话框。前往 **Customize → Plugins →
Personal plugins → + → Add marketplace**，添加
`https://github.com/howdeploy/choirboy-prompt`。然后在本地 Code 会话中选择
**+ → Plugins → Add plugin → choirboy-prompt**，并启动一个新会话。

Marketplace cache 提供 `${CLAUDE_PLUGIN_ROOT}`。`hooks/hooks.json` 使用官方
exec form（`command: bash`，路径作为独立 `args` 元素），因此路径中的空格与
shell 元字符不会被重新分词。15 秒超时避免卡住会话启动。

### 0.3. Claude Chat 与 Cowork

在 **Customize → Plugins** 中安装仓库，或上传
`python3 scripts/package-plugin.py` 生成的 ZIP。Chat 不运行 `SessionStart`，
请调用 **load-context** skill。Cowork 在支持时运行钩子，并用同一 skill
回退。**diagnose** skill 通过 `choirboy-delivery` marker 验证投递，而不是
依赖模型的措辞。

### 0.4. 边界

- 自动钩子需要 `bash`，skill 不需要；
- Cloud Code 需要项目 `enabledPlugins`，不会继承本地 Desktop 安装；
- Desktop WSL 不支持 plugins，SSH hooks 同步目前也不可靠，请使用 skill；
- 不要同时启用 marketplace 插件和 `./install.sh --target claude`，否则会加载两次；
- 发布时必须同步提升 manifest 与 marketplace 版本，然后运行
  `python3 scripts/build-context.py` 和测试套件。

---

## 1. 总体结构

```text
./install.sh [--target claude,opencode] [--uninstall] [--list]
             [--instructions FILE] [--project] [--settings PATH]
```

三种模式：

| 模式 | 作用 |
|---|---|
| install（默认） | 注册钩子/块并准备 artifact request |
| `--uninstall` | 删除注册，但保留智能体创建的 artifacts |
| `--list` | 只读显示：`absent` / `detected` / `stale` / `installed`（Grok Bot 为 `prepared`） |

`install.sh` 需要 `python3` 进行 JSON 操作。钩子的 `claude` 和 `plain`
格式只依赖 Bash，不需要 `jq`/`python3`；`hermes` 格式需要其中一个 JSON
解析器。自动 artifact lifecycle 需要 `python3`：安装阶段只准备元数据，下一次
会话由当前智能体编写 dossiers 并通过 validator；request 与 validator 要求
INDEX 和 dossiers 使用英文。Artifact 存储在 checkout
变化后仍保持稳定，路径优先级为：`CHOIRBOY_ARTIFACTS_DIR` →
`${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`。

重写注册前，安装器会检查当前与旧 hook 路径，以及当前 checkout 的
`artifacts/`。仅当稳定 root 中尚无智能体创作的 payload 时，才会把找到的
第一份 INDEX/manifest/dossier bundle 复制过去。现有稳定 artifacts 永不被
覆盖，卸载也会保留它们。Ready bundle 会被完整重新校验并内联到 hook
context；运行时不会只收到 INDEX 路径。

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
| opencode | `~/.config/opencode/plugins/agent-plugin.ts` | 模型侧 system-context transform |
| hermes | `~/.hermes/config.yaml` | 带标记的 `hooks.pre_llm_call` 块 + 授权白名单 |
| kimi | `${KIMI_CODE_HOME:-~/.kimi-code}/config.toml` | 带标记的 SessionStart + PreCompact + UserPromptSubmit + Stop hooks |
| gemini | `~/.gemini/GEMINI.md` | 带标记的 HTML lifecycle 指令块 |
| grok | `~/.grok/AGENTS.md` | 带标记的 HTML lifecycle 指令块（Grok Build 全局规则） |
| grokbot | `~/.grokbot/choirboy-context/SKILL.md` | 准备好的可导入 workflow（不自动加载） |
| `--instructions FILE` | 任意文件 | 带标记的 lifecycle 指令块（HTML 或 `#`） |

---

## 3. 标记与幂等性

### 3.1. 标记

所有块都带 `MARK="agent-plugin:vibe-lore"`。标记形式：

- hash 风格（配置文件、TOML）：`# >>> agent-plugin:vibe-lore >>>` / `# <<< agent-plugin:vibe-lore <<<`
- html 风格（markdown 指令）：`<!-- agent-plugin:vibe-lore START -->` / `<!-- agent-plugin:vibe-lore END -->`

标记既是所有权标识，也是删除时的块边界。当前生成的块还包含
`agent-plugin:vibe-lore:registration=2`；`--list` 结合该修订号与精确脚本
路径，区分当前安装和 `stale` 安装。

### 3.2. 幂等性

- `block_sync` 会追加缺失的托管块，或把唯一完整 START/END 块原子替换为
  当前生成文本。周围用户内容保持不变；损坏、重复或嵌套 marker 会被拒绝。
- `json_hook` 按脚本名（命令中的 `session-start.sh` 或 `artifact-stop.sh`）匹配条目，而不是绝对路径：如果插件文件夹移动了，过期的注册会被替换，而不是叠加。
- Marketplace 钩子位于 plugin cache，不会写入 `settings.json` 的钩子数组。
  因此 marketplace 和手动 Claude 钩子是二选一的安装路径，不能同时启用。
- OpenCode 目标拥有一个完整的带标记插件文件。内容相同时重复安装不做
  修改；更新会先备份，再原子替换。
- Hermes consent 条目、Kimi 的四个 hook、Gemini/Grok 指令块以及任意
  `--instructions` 块都会在每次安装器运行时同步；旧绝对路径和旧注册
  修订号会原地升级。

### 3.3. 托管块升级

旧的 skip-only 行为已经移除。重新运行 install 时，如果脚本路径、lifecycle
文本或注册修订号发生变化，安装器会重新生成并替换自己的块，并先创建
timestamp 备份。若自有注册存在但不是当前精确版本，`--list` 会显示
`stale`。正常运行 install 即可同步，不需要 uninstall/install 循环。

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
| `target_installed` | 精确的当前安装？ | 按目标检查修订号、路径与 hooks |
| `target_managed_present` | 是否存在旧的自有安装？ | ownership marker/script ids；产生 `stale` |
| `backup` | 修改前备份 | `cp -p` 带时间戳 |
| `block_sync` | 添加或升级带标记的块 | 精确替换 START/END，原子写入 |
| `block_remove` | 删除带标记的块 | 按 START/END，清理尾部空行 |
| `json_hook` | 写入 Claude 风格 JSON 的钩子 | 按脚本名匹配，`is_ours()`/`has_exact()` |
| `opencode_plugin` | 管理 OpenCode 适配器 | 标记 guard、原子替换、时间戳备份 |
| `hermes_allowlist` | Hermes 授权白名单 | 精确的 (event, command) 对 |
| `instruction_block` | Lifecycle 指令文本 | HTML 或 `#` 注释 |
| `grokbot_workflow` | 管理 Grok Bot workflow 文件 | `install`/`uninstall`/`status`，标记 guard |
| `discover_legacy_artifact_roots` | 查找旧 checkout-local bundle | 检查旧托管绝对路径 |
| `do_claude` / `do_codex` / `do_opencode` / `do_hermes` / `do_kimi` / `do_gemini` / `do_grok` / `do_grokbot` | 目标安装 | 每目标逻辑 |
| `do_instructions` | 安装到任意文件 | 按扩展名定风格 |

### 5.1. `json_hook` — 细节

处理 Claude 风格的钩子 JSON 文件（`settings.json`、`hooks.json`）。关键——**按脚本名匹配**，而不是按路径：

```python
def is_ours(entry):
    return any(hook_id in
               (h.get("command", "") + " " + " ".join(h.get("args", [])))
               for h in entry.get("hooks", []))
```

- install：删除过期注册并添加精确 handler。Claude 使用 `command: bash`、一个
  `args` 路径和 `timeout: 15`；Codex 保留带引用路径的字符串命令，并为完整
  启动 payload 设置 `additionalContextLimit: 262144`，使固定 lore 与内联
  artifact memory 保持在同一 startup context 中。
- uninstall：删除所有 `is_ours()` 条目。
- 无效 JSON 不会被替换；实际变化会先备份，再原子写入。

### 5.2. `hermes_allowlist` — 细节

Hermes 要求对 shell 钩子显式同意：`~/.hermes/shell-hooks-allowlist.json` 中的 `(event, command)` 对。该函数添加/删除精确对 `("pre_llm_call", "<session-start.sh> --format hermes")`，拒绝损坏的 JSON，并原子写入有效变更。

### 5.3. `block_sync` / `block_remove` — 细节

处理文本配置（config.yaml、config.toml、GEMINI.md）：

- sync：块不存在时追加；否则只替换一个完整 START/END 范围，并保留周围
  所有内容。文本完全相同时不修改。
- safety：损坏、重复或嵌套 marker 会中止安装，而不是猜测 ownership。
  实际更新会先备份，再原子写入。
- remove：从 START 到 END 包含地切除，如果 add 留下了一个前导空行则一并移除。

### 5.4. Kimi 0.39.x lifecycle hooks

Kimi 0.39.x 会丢弃 `SessionStart` stdout，因此托管 TOML 块安装四个 hook：

- `SessionStart`（`startup|resume`）准备 artifact 状态并重置
  投递 fingerprint；
- `PreCompact`（`manual|auto`）在 compaction 前同步重置 fingerprint；
- `UserPromptSubmit` 执行规范 plain 投递，重复 pending bootstrap，或在
  fingerprint 变化时输出 ready bundle；
- 验证仍为 pending 时，`Stop` 把 continuation request 写入 stderr 并以代码 2
  退出；达到 `ready` 后以代码 0 退出。

除非由 `CHOIRBOY_STATE_DIR` 覆盖，state marker 位于
`${KIMI_CODE_HOME:-~/.kimi-code}/choirboy-prompt/hook-state`。只有 stdout
成功输出后才记录规范化的 ready fingerprint。

---

## 6. 边界情况

1. **Hermes 配置中已有顶层 `hooks:`。** 安装器拒绝（`die`）并给出手动合并块的说明——以免覆盖别人的钩子。
2. **Kimi 配置中已有 `hooks =`。** 同样：die 并提示切换到 `[[hooks]]`。
3. **Codex：钩子被禁用。** 在 `~/.codex/config.toml` 中发现 `hooks = false` → 警告（不阻塞）。
4. **文件不存在。** `mkdir -p` + 创建空 `{}`/空文件。
5. **插件文件夹移动了。** JSON hook 按脚本名匹配，托管文本块也会同步；
   旧绝对路径会被替换，不会重复。
6. **重复运行或升级。** 当前注册不修改；旧的自有注册显示为 `stale`，
   通过正常 install 原地升级。
7. **没有安装就 `--uninstall`。** `no block in file — skipped`，不会失败。
8. **`--target none` + `--instructions`。** 只有托管 lifecycle 指令块，
   没有 runtime-specific hook。
9. **Hermes 并行启动。** `/tmp` 中的 state 文件没有锁——可能产生竞争（已知限制，见 README）。
10. **受管理路径已有外部 OpenCode 插件。** 若文件没有 ownership 标记，
    install 与 uninstall 都会拒绝覆盖或删除。

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

`--list` 中的 `stale` 需要处理：对该 target 重新运行 install，并确认状态变为
`installed`（Grok Bot 为 `prepared`）。Ready artifact bundle 的
`session-context` 必须包含 `# Established project history` 与完整 dossier
正文；只有路径的消息不算成功投递记忆。

完整的临时测试套件——[docs/testing.zh-CN.md](testing.zh-CN.md)。
