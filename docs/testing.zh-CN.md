# 测试

Hook、skills、installer、诊断与包检查。规范 runner 是
`bash scripts/test.sh`；以下各节解释其中的 assertions。

---

## 1. 原则

- 每个检查都是独立的 bash 命令，带显式 PASS/FAIL。
- 套件可从任意目录运行；临时文件放在 `/tmp` 下，带 `choirboy-test.` 前缀。
- 运行后删除临时文件。设置 `CHOIRBOY_TEST_KEEP_TMP=1` 可保留这些文件并打印
  用于检查的精确目录。
- payload **按运行时收到的确切形式**检查，而不是「凭感觉」。
- 规范 context、research、INDEX 与 dossiers 必须使用英文；suite 会拒绝任何
  model-facing Markdown 中的 Cyrillic/CJK，artifact validator 在运行时执行
  同一规则。

---

## 2. 钩子检查

### 2.1. 清单与版本

```bash
python3 -c 'import json; d=json.load(open(".claude-plugin/plugin.json")); print(d["name"], d["version"])'
claude plugin validate .
```

预期：两个清单均有效，打印名称和版本，Claude validator 报告
`Validation passed`。`plugin.json` 是插件版本来源；同一值写入 marketplace
并打印在 payload 中。

### 2.2. Claude 格式——带上下文的有效 JSON

```bash
bash hooks/session-start.sh --format claude \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "additionalContext" in d["hookSpecificOutput"]; print("OK")'
```

预期：`OK`。另外检查 `prompt.md` 的第一个标题，以及包含版本、投递方式、
SHA-256 和 nonce 的 `choirboy-delivery` marker。

### 2.3. 没有 jq 和 python3 时的 Claude 格式

```bash
PYTHON_BIN="$(command -v python3)"
TMP_BIN="$(mktemp -d)"
for cmd in cat date dirname head mkdir mv sed; do
  src="$(command -v "$cmd")"
  printf '#!/bin/bash\nexec "%s" "$@"\n' "$src" > "$TMP_BIN/$cmd"
  chmod +x "$TMP_BIN/$cmd"
done
PATH="$TMP_BIN" /bin/bash hooks/session-start.sh --format claude \
  | "$PYTHON_BIN" -c 'import json,sys; json.load(sys.stdin); print("OK")'
rm -rf "$TMP_BIN"
```

预期：`OK`。该测试故意从 `PATH` 中移除 `jq` 和 `python3`，验证干净的
Claude Desktop 安装所使用的内置 Bash 编码器。

### 2.4. Plain 格式——人类可读的 payload

```bash
bash hooks/session-start.sh --format plain | head -40
```

预期：prompt → posture → lore → user → research 索引标题顺序正确，带 `---` 分隔符。

### 2.5. Hermes：第一轮投递

```bash
SID="hook-check-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":true}}' "$SID" \
  | bash hooks/session-start.sh --format hermes | head -c 120
```

预期：`{"context": "..."`——payload 到达。

### 2.6. Hermes：第二轮沉默

```bash
SID="hook-check-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":false}}' "$SID" \
  | bash hooks/session-start.sh --format hermes
```

预期：`{}`。

### 2.7. Hermes：无标记时的回退——每个 session_id 一次

```bash
SID="hook-check-fb-$(date +%s)"
printf '{"session_id":"%s"}' "$SID" \
  | bash hooks/session-start.sh --format hermes | head -c 120   # → context
printf '{"session_id":"%s"}' "$SID" \
  | bash hooks/session-start.sh --format hermes                 # → {}
```

预期：第一次调用——`{"context": ...`，第二次——`{}`。

> 坑：测试后从 state 文件 `${TMPDIR:-/tmp}/agent-plugin-hermes-${USER}.state` 中清理 sid，否则回退会「记住」sid，下次用相同 sid 运行会返回 `{}`。

### 2.8. Hermes：空 stdin 不会弄崩钩子

```bash
printf '' | bash hooks/session-start.sh --format hermes
```

预期：`{}`（不是错误）。原因：`input="$(cat 2>/dev/null || true)"`。

---

## 3. 安装器检查

### 3.0. 在隔离的 Claude 配置中测试 marketplace 安装

```bash
VERIFY_CFG="$(mktemp -d)"
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin marketplace add "$PWD"
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin install choirboy-prompt@choirboy-prompt
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin list | grep 'Status: ✔ enabled'
find "$VERIFY_CFG" -depth -delete
```

预期：marketplace 添加成功，插件版本复制到临时 cache，状态为 `enabled`，
没有钩子加载错误。本地 `$PWD` 只用于测试尚未发布的工作副本；README 中的
用户路径会从 GitHub 添加同一个 marketplace。

### 3.1. --list

```bash
./install.sh --list
```

预期：TARGET/STATUS/LOCATION 列；状态 `absent`/`detected`/`installed`。

### 3.2. 幂等性

```bash
./install.sh --target hermes ; ./install.sh --target hermes
```

预期：第二次运行打印 `already present — skipped` / `unchanged`；文件不重复。

### 3.3. 备份

安装到现有文件后检查：

```bash
ls -la ~/.hermes/config.yaml.bak.*
```

预期：存在带时间戳的备份。

### 3.4. 回滚

```bash
./install.sh --uninstall --target hermes
./install.sh --list | grep hermes   # → detected（不是 installed）
```

预期：块被删除，`agent-plugin:vibe-lore` 标记在配置中不存在。

### 3.5. 没有内容文件时钩子不失败

模拟全新克隆（没有 `prompt.md`/`lore.md`/`user.md`）：

```bash
TMP=$(mktemp -d)
cp -r hooks .claude-plugin "$TMP/"
# TMP 中没有内容文件
bash "$TMP/hooks/session-start.sh" --format plain >/dev/null 2>&1
echo "exit=$?"   # 预期：0（graceful 模式：文件被跳过，stderr 中给出警告）
rm -rf "$TMP"
```

Graceful 模式已在 `hooks/session-start.sh` 中实现：缺失的内容文件被跳过，stderr 中给出警告，钩子不会因 `set -euo pipefail` 失败（见 [docs/security.zh-CN.md](security.zh-CN.md) §3.3）。

### 3.6. 插件文件夹移动

安装、移动文件夹、再次安装：

```bash
./install.sh --target claude
mv /path/to/plugin /path/to/plugin-moved
/path/to/plugin-moved/install.sh --target claude
```

预期：`~/.claude/settings.json` 中恰好一条我们的钩子记录（不是两条）；旧的被新的替换——`json_hook` 按脚本名匹配。

### 3.7. OpenCode 适配器生命周期

规范测试套件会在隔离的 `HOME` 中安装适配器，重复安装，检查 `--list`，
对故意漂移的带标记插件进行带备份刷新，再进行带备份卸载。它还会验证
`~/.config/opencode/plugins/agent-plugin.ts` 上没有 ownership 标记的外部文件
绝不会被覆盖。

预期：`OpenCode install, list, idempotent refresh, backup, and rollback` 与
`OpenCode foreign-plugin guard` 都打印 `PASS`。生成的适配器必须使用
模型侧 system-context transform，在 compaction 后重建规范 plain payload，
暴露 pending→ready 与 freshness 变化，并保留 fail-open 错误处理。运行时过渡
assertions 位于 `scripts/test-opencode-transition.ts`，由 `bun` 运行；当
`bun` 不可用时，套件会在 stderr 打印 `SKIP OpenCode pending-to-ready runtime
test (bun unavailable)` 而不是失败。

---

## 4. 内容检查（清理）

任何发布之前：

```bash
# 禁用标识符（NSFW/refusal 模型名称、通往私有项目的路径）。
# 具体名称清单是仓库之外的私有清单；这里是通用模式：
grep -rniE "(nsfw-(checkpoint|lora)|refusal-reduction|private-research)" --include="*.md" --include="*.sh" .
# 完整地址
grep -rnoE "bc1[a-zA-Z0-9]{20,}|0x[a-fA-F0-9]{40}" .
# 闭合：每个文件引用都能解析
for f in $(grep -rhoE "(research/[0-9]+-[a-z-]+\.md|research/coldcard/[a-z_.]+\.(md|py))" --include="*.md" . | sort -u); do
  [ -f "$f" ] || echo "BROKEN: $f"
done
```

预期：grep 为空；闭合无 BROKEN。

---

## 5. 一条命令的快速套件

```bash
bash scripts/test.sh
python3 scripts/package-plugin.py
```

---

## 6. 何时运行

- 修改 `hooks/session-start.sh` 后——§2.2–2.8。
- 修改 `.claude-plugin/plugin.json` 或 `marketplace.json` 后——§2.1 和 §3.0。
- 修改 `install.sh` 后——§3.1–3.7。
- 修改内容文件后——先运行 `python3 scripts/build-context.py`，再运行规范测试和
  §4（闭合、清理）。
- 修改 `instruction_block` 后——在已安装文件中按标记 grep（见 [docs/installer.zh-CN.md](installer.zh-CN.md) §3.3）。
