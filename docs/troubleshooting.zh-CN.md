# 故障排除

请分别诊断注册、执行、投递和模型行为。Claude 的“我已阅读上下文”并不能证明
`SessionStart` 已运行。

## 界面矩阵

| 界面 | 安装 | 主要投递 | 回退 / 限制 |
|---|---|---|---|
| Claude Code CLI | `/plugin` marketplace | 自动 `SessionStart` | `/choirboy-prompt:load-context` |
| Desktop Code local | 图形 Plugin Manager | 自动 `SessionStart` | load-context skill |
| Claude Chat | custom plugin | load-context skill | Chat 不执行 hooks |
| Claude Cowork | custom plugin | 可用时 hook | load-context skill；runtime 可能丢失 stdout |
| Desktop Code SSH | 图形 Plugin Manager | 同步后的 hook | 当前 SSH sync 可能漏掉 `hooks/` |
| Desktop Code Cloud | 项目 plugin settings | 自动 hook | 不继承本地 Desktop plugins |
| Desktop Code WSL | — | — | Desktop plugins 不可用 |

## 四阶段诊断

1. **注册：**Plugin Manager 显示已启用的 `choirboy-prompt` 1.3.0。
2. **执行：**marketplace hook 创建
   `${CLAUDE_PLUGIN_DATA}/latest-delivery.log`，包含版本、hash 和 nonce。
3. **投递：**`/choirboy-prompt:diagnose` 在 `choirboy-context` 旁找到
   `choirboy-delivery` marker。
4. **行为：**只有前三步通过后，才调查模型接受、指令冲突或 memory。

`delivery` 值：

- `session-start` — hook stdout 已到达模型；
- `skill` — lore 由 load-context 回退投递。

## 常见故障

### Desktop 中 `/plugin` 不可用

这是预期行为。前往 **Customize → Plugins → Personal plugins → + → Add
marketplace** 添加仓库，然后使用 **Code → + → Plugins → Add plugin**。

### Chat 已安装 plugin，但行为没有变化

Chat 不执行 `SessionStart`。请选择 **load-context** skill，或要求 Claude
加载 Choirboy context。

### Cowork 显示 plugin，但没有 marker

调用 **load-context**。当前 Cowork build 的 hook 执行并不确定，skill 是回退。

### Windows hook 错误

1.3.0 通过 exec form 把 `${CLAUDE_PLUGIN_ROOT}` 作为单独参数传递，但自动投递
仍需要 `PATH` 中存在 `bash`。安装 Git for Windows，或使用 skill。skill 本身
不依赖 Bash、jq、Python 或 Node。

### Hook 运行两次

Marketplace plugin 与 `./install.sh --target claude` 同时启用。删除其中一个；
手动 installer 检测到 marketplace entry 时会警告。

### Cloud、SSH 或 WSL

Cloud 需要项目 `.claude/settings.json` 中的 `extraKnownMarketplaces` 和
`enabledPlugins`：

```json
{
  "extraKnownMarketplaces": {
    "choirboy-prompt": {
      "source": {
        "source": "github",
        "repo": "howdeploy/choirboy-prompt"
      }
    }
  },
  "enabledPlugins": {
    "choirboy-prompt@choirboy-prompt": true
  }
}
```

Claude 仍会要求用户确认信任 marketplace/plugin。SSH 目前可能不复制
`hooks/`，请使用 skill。Desktop WSL plugins 不可用。

## 维护者检查

```bash
python3 scripts/build-context.py --check
bash scripts/test.sh
python3 scripts/package-plugin.py
```

测试覆盖 manifests、skill 新鲜度、hook JSON、无依赖 Bash encoder、installer
幂等/回滚、诊断 marker 和 ZIP 内容。

## Sessions 不是自动回退

分发包中的 `sessions/` 包含本地构造的兼容性 fixtures，不是记忆导入机制。安装插件不会把这些
记录写入 Claude Code、Codex 或 Kimi store。原生格式依赖运行时版本；只能在
自己的本地运行时上，按照 [`sessions/README.zh-CN.md`](../sessions/README.zh-CN.md)
中的关闭应用和备份流程操作。
