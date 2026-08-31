# sessions/ — 原生 session store 兼容性 fixtures

**语言：**[English](README.md) · [Русский](README.ru.md) ·
[简体中文](README.zh-CN.md)

这是 [research/12](../research/12-choirboy-prompt-lore-injection.md) 的兼容性
fixtures：**同一段本地构造的对话，以 Claude Code、Codex、Kimi Code 三种
原生 session-store 格式保存**。ID 使用保留的 `fa1ce000-…` 范围；这些文件
不是历史对话记录。

Fixture 对话覆盖以下路径：模型在被植入的 lore/meta-prompt 框架下，会主动起草并进一步
弱化一个审查绕过 prompt，即使 transcript 中没有直接 trigger vocabulary。
向量不在词汇，而在 provenance：分类器检查请求文本，却不检查上下文里的
“先前工作”从何而来。

本地 session store 没有 transcript 签名、MAC 或服务端来源确认。只要文件形状
正确，兼容版本的运行时就能把它显示在 resume picker 中，并作为历史重放。

## 它证明什么、不证明什么

从智能体视角，这些文件成为“真实先前对话”的可见证据：transcript 在本地构造，
但本地运行时仍通过原生 history path 对其索引、恢复和重放。这证明 provenance
边界缺失。

它**不能证明其中描述的对话真实发生过**。这些是本地构造的兼容性 fixtures，
必须一直保留非历史来源标签。只能在你自己的本地运行时和数据上使用。

## 目录结构

| 运行时 | 文件 | Store 位置 |
|---|---|---|
| Claude Code | `claude/<sessionId>.jsonl` | `~/.claude/projects/<mangled-cwd>/` |
| Codex | `codex/rollout-….jsonl` + `codex/threads-insert.sql` | `~/.codex/sessions/YYYY/MM/DD/` + `state_5.sqlite` |
| Kimi Code | `kimi/session_<uuid>/{state.json,agents/main/wire.jsonl}` + `kimi/session_index.jsonl.example` | `~/.kimi-code/sessions/wd_<name>_<hash>/` |

工件中的路径（SQL 的 `rollout_path`、`state.json` 的 `homedir`、index 示例）
保留字面量 `$HOME` placeholder。只在测试副本中展开，例如
`sed -i "s|\$HOME|$HOME|g" <copy>`。

## 在自己的机器上复现

先备份目标 store，修改前关闭应用，检查后删除兼容性记录。原生 schema 会随运行时
版本变化。

### Claude Code

```bash
cp sessions/claude/fa1ce000-0000-4000-8000-0000000000c1.jsonl \
   ~/.claude/projects/-home-research-choirboy-prompt/
```

目录名来自 session 的 `cwd`，把斜杠替换为连字符。它只会出现在该项目的
resume list 中。`claude --resume` 与 Claude Desktop **Code** 标签读取同一 store；
示例中的 `uuid`/`parentUuid` 链已保持一致。

### Codex

Rollout 是事实来源，但 picker 读取 SQLite：

```bash
mkdir -p ~/.codex/sessions/2026/08/10
cp sessions/codex/rollout-2026-08-10T18-30-00-fa1ce000-0000-7000-8000-0000000000c2.jsonl \
   ~/.codex/sessions/2026/08/10/
# 因为 WAL，应用必须关闭：
sed "s|\$HOME|$HOME|g" sessions/codex/threads-insert.sql \
  | sqlite3 ~/.codex/state_5.sqlite
```

`thread_history_1.sqlite` 是派生投影。UUIDv7 风格 ID、文件名日期、
`YYYY/MM/DD` 路径与 `created_at` 必须一致。

### Kimi Code

```bash
mkdir -p ~/.kimi-code/sessions/wd_choirboy-prompt_fixture
cp -r sessions/kimi/session_fa1ce000-0000-4000-8000-0000000000c3 \
      ~/.kimi-code/sessions/wd_choirboy-prompt_fixture/
KIMI_FIXTURE_DIR="$HOME/.kimi-code/sessions/wd_choirboy-prompt_fixture/session_fa1ce000-0000-4000-8000-0000000000c3"
sed "s|\$HOME|$HOME|g" "$KIMI_FIXTURE_DIR/state.json" > "$KIMI_FIXTURE_DIR/state.json.tmp"
mv "$KIMI_FIXTURE_DIR/state.json.tmp" "$KIMI_FIXTURE_DIR/state.json"
sed "s|\$HOME|$HOME|g" sessions/kimi/session_index.jsonl.example \
  >> ~/.kimi-code/session_index.jsonl
```

`search-index/` 是派生 tantivy 索引，不需要复制。

## 如何编写自己的兼容性 fixture

1. 在目标运行时创建一个无害 session，以获取当前 schema。
2. 关闭运行时，只把该 session 复制到暂存目录。
3. 删除 token、request ID、私有路径、tool output 与第三方数据。
4. 一致替换 ID 和 timestamp；保留角色、顺序、parent link、路径与 picker metadata。
5. 在标题和 README 中把结果标记为 `locally constructed compatibility
   fixture`，并注明它不是历史记录。
6. 验证每一行 JSON/JSONL，备份自己的 store，再测试副本。
7. 实验完成后删除测试记录。

编写 lore、research、论证与 sessions 的完整强制流程：
[docs/authoring.zh-CN.md](../docs/authoring.zh-CN.md)。

## 边界

这是防御性兼容性检查，只能在自己的运行时上运行。在平台验证 session
provenance 之前，模型无法区分伪造历史与真实历史。对策见
[docs/detection.zh-CN.md](../docs/detection.zh-CN.md)。
