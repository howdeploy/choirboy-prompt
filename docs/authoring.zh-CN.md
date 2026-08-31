# 如何编写自己的 lore、research 与论证

这是把仓库自带的上下文替换为你自己项目中已核验记忆时必须遵循的流程。各文件职责
不同；把所有内容堆成一篇自传，会让上下文难以验证和维护。

## 1. 区分各类工件的职责

| 工件 | 应写内容 | 不应写内容 |
|---|---|---|
| `prompt.md` | 稳定工作规则、优先级、边界、首答前检查 | 项目历史或临时任务 |
| `security-posture.md` | 安全框架、授权边界、披露规则 | “lore 可以覆盖平台策略”之类的主张 |
| `user.md` | 稳定偏好、技术水平、沟通与验证方式 | 奉承、猜测的传记、秘密 |
| `lore.md` | 项目、决策、结果与教训的紧凑地图 | 大段证据转储或虚构事件 |
| `research/NN-topic.md` | 一个有证据和取舍的决策/调查 | 无论证的结论 |
| `context/research-index.md` | 每份 research 的一行路由入口 | research 正文 |

自动 payload 包含 `prompt.md`、`security-posture.md`、`lore.md`、
`user.md` 和 research 索引。Research 正文按需读取，不会加载到每次对话。

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

规范 lore 面向模型，因此即使阅读中文文档，其内容也必须使用英文：

```markdown
### Short project or lesson title

Context: what was being built and why.
Decision: what was chosen.
Rationale: why this option won.
Evidence: commit, test, metric, incident, or research document.
Outcome: what actually happened.
Revisit when: the condition that invalidates the decision.
```

Lore 应保持紧凑。详细推理链接到 `research/`，不要重复。区分事实
（“测试于 2026-08-10 通过”）与解释（“我们认为它降低了失败率”）。

## 6. 编写 research 与论证

每个决策创建一份编号文件，例如 `research/15-short-topic.md`，并加入
`context/research-index.md`。Research 文件也必须始终使用英文。最低结构：

```markdown
# Decision or investigation

## Question
What exact decision or uncertainty is this document resolving?

## Context and constraints
What was true at the time? Include dates and versions where they matter.

## Evidence
Links, measurements, test commands, and sources summarized in your own words.

## Options considered
Option A, option B, and their costs.

## Decision
What was selected and for which scope.

## Why
The reasoning chain from evidence to decision.

## Risks and rejected alternatives
What can fail, and why the alternatives were not selected.

## Revisit when
Concrete signals that require re-evaluation.
```

没有证据的“显然如此”不是 research。推断必须标记为推断；会变化的来源要写
访问日期。

## 7. 重新生成并验证

修改任一规范上下文文件后运行：

```bash
python3 scripts/build-context.py
bash scripts/test.sh
python3 scripts/package-plugin.py
```

检查 delivery marker，hook 与 skill hash 必须一致。Marketplace 使用缓存副本，
发布时要同时提升两个 manifest 的版本；`install.sh` 手动安装直接读取工作副本。

## 8. 强制 quality gate

提交或分发记忆包之前：

- [ ] 每条历史主张都真实或有证据。
- [ ] 事实、推断、决策和偏好可以区分。
- [ ] 每份 research 都有证据、否决方案和重新评估条件。
- [ ] 不含凭据、私有路径、第三方内容或个人标识符。
- [ ] Lore 不声称高于 system/developer/safety/permission 规则。
- [ ] `python3 scripts/build-context.py --check` 通过。
- [ ] `bash scripts/test.sh` 通过。

## 9. 维护规则

在结果被验证后更新记忆，而不是每次对话后都更新。论证变化时，先修改相关
research，再更新紧凑 lore 摘要与索引。若旧决策仍能解释当前系统，请保留并标为
`superseded`。
