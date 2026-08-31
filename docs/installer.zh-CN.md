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
- 不要同时启用 marketplace 插件和 `./install.sh --target claude`，否则会注入两次；
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
| `--list` | 只读显示：`absent` / `detected` / `installed` |

`install.sh` 需要 `python3` 进行 JSON 操作。钩子的 `claude` 和 `plain`
格式只依赖 Bash，不需要 `jq`/`python3`；`hermes` 格式需要其中一个 JSON
解析器。自动 artifact lifecycle 需要 `python3`：安装阶段只准备元数据，下一次
会话由当前智能体编写 dossiers 并通过 validator。手动安装默认使用
`artifacts/`，可由 `CHOIRBOY_ARTIFACTS_DIR` 覆盖。

---

## 2. 目标

运行时检测——按二进制或配置文件目录是否存在：

```bash
claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
codex)  command -v codex  >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
opencode) command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] ;;
hermes) command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ] ;;
kimi)   command -v kimi   >/dev/null 2>&1 || [ -d "$HOME/.kimi-code" ] ;;
gemini) command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
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
| opencode | `~/.config/opencode/plugins/agent-plugin.ts` | 全局 `chat.message` 插件 |
| hermes | `~/.hermes/config.yaml` | 带标记的 `hooks.pre_llm_call` 块 + 授权白名单 |
| kimi | `~/.kimi-code/config.toml` | 带标记的 `[[hooks]]` 块 |
| gemini | `~/.gemini/GEMINI.md` | 带标记的 HTML 指针块 |
| `--instructions FILE` | 任意文件 | 带标记的指针块（HTML 或 `#`） |

---

## 3. 标记与幂等性

### 3.1. 标记

所有块都带 `MARK="agent-plugin:vibe-lore"`。标记形式：

- hash 风格（配置文件、TOML）：`# >>> agent-plugin:vibe-lore >>>` / `# <<< agent-plugin:vibe-lore <<<`
- html 风格（markdown 指令）：`<!-- agent-plugin:vibe-lore START -->` / `<!-- agent-plugin:vibe-lore END -->`

标记既是所有权标识，也是删除时的块边界。

### 3.2. 幂等性

- `block_add` 检查 START 标记：已存在 → `already present — skipped`，不会重复。
- `json_hook` 按脚本名（命令中的 `session-start.sh` 或 `artifact-stop.sh`）匹配条目，而不是绝对路径：如果插件文件夹移动了，过期的注册会被替换，而不是叠加。
- Marketplace 钩子位于 plugin cache，不会写入 `settings.json` 的钩子数组。
  因此 marketplace 和手动 Claude 钩子是二选一的安装路径，不能同时启用。
- OpenCode 目标拥有一个完整的带标记插件文件。内容相同时重复安装不做
  修改；更新会先备份，再原子替换。

### 3.3. 标记的坑

`block_add` 按 START 标记幂等。这意味着：如果修改了 `instruction_block`（指针块的文本），已安装的块（GEMINI.md、`--instructions` 文件）**不会更新**——安装器会说 `already present — skipped`，副本保持旧版。治疗：手动修补已安装文件，或 `--uninstall` + install。

修改 `instruction_block` 后——在已安装文件中 grep 标记。

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
| `target_installed` | 已安装？ | 按标记/脚本名 grep |
| `backup` | 修改前备份 | `cp -p` 带时间戳 |
| `block_add` | 添加带标记的块 | 按 START 幂等 |
| `block_remove` | 删除带标记的块 | 按 START/END，清理尾部空行 |
| `json_hook` | 写入 Claude 风格 JSON 的钩子 | 按脚本名匹配，`is_ours()`/`has_exact()` |
| `opencode_plugin` | 管理 OpenCode 适配器 | 标记 guard、原子替换、时间戳备份 |
| `hermes_allowlist` | Hermes 授权白名单 | 精确的 (event, command) 对 |
| `instruction_block` | 指针块文本 | HTML 或 `#` 注释 |
| `do_claude` / `do_codex` / `do_opencode` / `do_hermes` / `do_kimi` / `do_gemini` | 目标安装 | 每目标逻辑 |
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
  启动 payload 设置 `additionalContextLimit: 20000`。
- uninstall：删除所有 `is_ours()` 条目。
- 无效 JSON 不会被替换；实际变化会先备份，再原子写入。

### 5.2. `hermes_allowlist` — 细节

Hermes 要求对 shell 钩子显式同意：`~/.hermes/shell-hooks-allowlist.json` 中的 `(event, command)` 对。该函数添加/删除精确对 `("pre_llm_call", "<session-start.sh> --format hermes")`，拒绝损坏的 JSON，并原子写入有效变更。

### 5.3. `block_add` / `block_remove` — 细节

处理文本配置（config.yaml、config.toml、GEMINI.md）：

- add：如果 START 不存在，在末尾追加块（前面带一个空行）。
- remove：从 START 到 END 包含地切除，如果 add 留下了一个前导空行则一并移除。

---

## 6. 边界情况

1. **Hermes 配置中已有顶层 `hooks:`。** 安装器拒绝（`die`）并给出手动合并块的说明——以免覆盖别人的钩子。
2. **Kimi 配置中已有 `hooks =`。** 同样：die 并提示切换到 `[[hooks]]`。
3. **Codex：钩子被禁用。** 在 `~/.codex/config.toml` 中没找到 `grep hooks = true` → 警告（不是阻塞）。
4. **文件不存在。** `mkdir -p` + 创建空 `{}`/空文件。
5. **插件文件夹移动了。** JSON 钩子按脚本名匹配——旧条目被替换，无重复。
6. **重复运行。** 一切幂等：`unchanged`/`skipped`。
7. **没有安装就 `--uninstall`。** `no block in file — skipped`，不会失败。
8. **`--target none` + `--instructions`。** 只有指针块，没有运行时。
9. **Hermes 并行启动。** `/tmp` 中的 state 文件没有锁——可能产生竞争（已知限制，见 README）。
10. **受管理路径已有外部 OpenCode 插件。** 若文件没有 ownership 标记，
    install 与 uninstall 都会拒绝覆盖或删除。

---

## 7. 如何验证安装

```bash
./install.sh --list                    # 状态
./install.sh --target opencode         # 安装全局 OpenCode 适配器
grep -F 'agent-plugin:vibe-lore' ~/.config/opencode/plugins/agent-plugin.ts
bash hooks/session-start.sh --format plain | head -40   # payload
echo '{"session_id":"hook-check","extra":{"is_first_turn":true}}' \
  | bash hooks/session-start.sh --format hermes | head -c 120   # 第一轮
echo '{"session_id":"hook-check","extra":{"is_first_turn":false}}' \
  | bash hooks/session-start.sh --format hermes            # → {}
```

完整的临时测试套件——[docs/testing.zh-CN.md](testing.zh-CN.md)。

---

## 8. 分发包中的兼容性 fixtures

Marketplace/custom-plugin ZIP 包含已跟踪的 `sessions/` 目录，便于安装后检查
原生格式证据。这些文件是兼容性 fixtures：`SessionStart` 与 `load-context` 都
不会把它们导入用户的原生 session store，它们也不属于自动 lore payload。
手动复现见 [`sessions/README.zh-CN.md`](../sessions/README.zh-CN.md)。
