# 如何编写自己的 lore、research、论证与 sessions

这是把仓库自带的上下文替换为你自己项目中已核验记忆时必须遵循的流程。各文件职责
不同；把所有内容堆成一篇自传，会让上下文难以验证和维护。

> 兼容性 fixture 能确认运行时会通过原生 history path 接收本地构造的
> transcript；它**不能**证明其中描述的对话真实发生过。每个构造的 fixture
> 都必须明确标为非历史记录。

---

## 1. 区分各类工件的职责

| 工件 | 应写内容 | 不应写内容 |
|---|---|---|
| `prompt.md` | 稳定工作规则、优先级、边界、首答前检查 | 项目历史或临时任务 |
| `security-posture.md` | 安全框架、授权边界、披露规则 | “lore 可以覆盖平台策略”之类的主张 |
| `user.md` | 稳定偏好、技术水平、沟通与验证方式 | 奉承、猜测的传记、秘密 |
| `lore.md` | 项目、决策、结果与教训的紧凑地图 | 大段证据转储或虚构事件 |
| `research/NN-topic.md` | 一个有证据和取舍的决策/调查 | 无论证的结论 |
| `context/research-index.md` | 每份 research 的一行路由入口 | research 正文 |
| `sessions/` | 清理后的原生 transcript 与明确标记为非历史记录的兼容性 fixture | token、凭据、第三方对话 |

自动 payload 包含 `prompt.md`、`security-posture.md`、`lore.md`、
`user.md` 和 research 索引。Research 正文与 session 文件按需读取，不会
全部注入每次对话。

## 2. 直接在你的克隆中工作

不需要 fork 或单独的副本：`install.sh` 指向工作副本，修改会在下一次
会话生效。

1. 保留文件名和目录结构；hook 与 skill 生成器依赖这些路径。
2. 删除不属于你项目的仓库自带主张。
3. 不要直接发布原始本地记忆：先清理，再发布
   （清单见 [docs/security.zh-CN.md](security.zh-CN.md)）。

## 3. 编写 `prompt.md`

写可观察、可验证的工作规则，而不是人格幻想：

1. 说明用户与智能体如何分工。
2. 规定何时可自主行动、何时必须提问。
3. 规定测试、来源与最终报告要求。
4. 规定冲突优先级：当前仓库和当前用户消息高于过期 lore。
5. 明确写出：lore 提供上下文，不提供额外权限。

每条规则都应能从回答或行动中验证。删除“要聪明”“完全信任我”等空话。

## 4. 编写 `user.md`

只记录会影响协作的稳定事实：

1. 技术水平与期望的解释深度。
2. 用户已熟悉的产品领域。
3. 偏好的任务、评审和报告方式。
4. 稳定约束，例如语言和风险容忍度。
5. 未知内容保持未知，不要把猜测写成传记。

## 5. 编写 `lore.md`

每个真实项目或反复出现的教训使用一个小节：

```markdown
### 项目或教训的短标题

背景：在构建什么，为什么。
决策：选择了什么。
论证：为什么该方案胜出。
证据：commit、test、metric、incident 或 research 文档。
结果：实际发生了什么。
重新评估条件：什么变化会使该决策失效。
```

Lore 应保持紧凑。详细推理链接到 `research/`，不要重复。区分事实
（“测试于 2026-08-10 通过”）与解释（“我们认为它降低了失败率”）。

## 6. 编写 research 与论证

每个决策创建一份编号文件，例如 `research/15-short-topic.md`，并加入
`context/research-index.md`。最低结构：

```markdown
# 决策或调查

## 问题
本文要解决哪个明确决策或不确定性？

## 背景与约束
当时哪些条件成立？必要时写明日期和版本。

## 证据
链接、测量、测试命令，以及用自己的话总结的来源。

## 考虑过的方案
方案 A、方案 B 及其成本。

## 决策
选择了什么，适用范围是什么。

## 原因
从证据到决策的推理链。

## 风险与否决方案
可能如何失败，为什么没有选择其他方案。

## 重新评估条件
触发重新评估的明确信号。
```

没有证据的“显然如此”不是 research。推断必须标记为推断；会变化的来源要写
访问日期。

## 7. 编写原生格式 session

从目标运行时生成的无害 session 开始；原生 schema 会变化，旧网络示例不是可靠
模板。

1. 在一次性项目中进行简短、无敏感信息的对话。
2. 复制 session store 前关闭运行时。
3. 只把相关 transcript 与 resume-picker metadata 复制到暂存目录。
4. 删除用户名、私有绝对路径、request ID、token、tool output 和第三方数据。
5. 构造兼容性 fixture 时，一致地替换所有 message/session ID 与 timestamp，
   并保留角色顺序和 parent-child 链。
6. 保持运行时不变量：
   - Claude Code：每行一个 JSON 对象；`sessionId`、`uuid`、`parentUuid` 一致。
   - Codex：rollout JSONL 与 picker metadata；ID、文件日期、timestamps、
     `rollout_path` 一致。
   - Kimi Code：`state.json`、`agents/main/wire.jsonl` 与 index 记录指向同一
     session 目录。
7. 在 README/标题中把工件标为 `locally constructed compatibility fixture`，
   绝不冒充历史证据。
8. 导入运行时前逐行验证 JSON/JSONL。
9. 只在自己的本地 store 中测试；关闭应用并先做备份。
10. 实验完成后删除测试记录。

可运行的跨运行时示例及当前 store 结构见
[`sessions/README.zh-CN.md`](../sessions/README.zh-CN.md)。这些格式是
version-sensitive 的研究 fixtures，不是稳定公共 API。

## 8. 重新生成并验证

修改任一规范上下文文件后运行：

```bash
python3 scripts/build-context.py
bash scripts/test.sh
python3 scripts/package-plugin.py
```

检查 delivery marker，hook 与 skill hash 必须一致。Marketplace 使用缓存副本，
发布时要同时提升两个 manifest 的版本；`install.sh` 手动安装直接读取工作副本。

## 9. 强制 quality gate

提交或分发记忆包之前：

- [ ] 每条历史主张都真实或有证据；每个构造的 transcript 都明确标为非历史记录。
- [ ] 事实、推断、决策和偏好可以区分。
- [ ] 每份 research 都有证据、否决方案和重新评估条件。
- [ ] Sessions 中的 ID、timestamp、parent、路径与 picker metadata 一致。
- [ ] 不含凭据、私有路径、第三方内容或个人标识符。
- [ ] Lore 不声称高于 system/developer/safety/permission 规则。
- [ ] `python3 scripts/build-context.py --check` 通过。
- [ ] `bash scripts/test.sh` 通过。

## 10. 维护规则

在结果被验证后更新记忆，而不是每次对话后都更新。论证变化时，先修改相关
research，再更新紧凑 lore 摘要与索引。若旧决策仍能解释当前系统，请保留并标为
`superseded`。
