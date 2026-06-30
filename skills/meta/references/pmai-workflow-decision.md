# PMAI Workflow 决策（/pmai-meta）

本文件用于 `/pmai-meta` 的 PMAI workflow / skill 决策路径。它处理“该调用现有能力、升级现有 skill、新建入口，还是先不做”。它不是产品想法会诊，也不是模块设计。

---

## 先读现状

没有读相关现状，不准给结论。

必须按问题读取：

- 涉及某个 skill：读 `skills/<skill>/SKILL.md` 和该 skill 的 `references/`。
- 涉及多个 skill：读每个候选 skill 的主文件和关键 reference，确认边界。
- 涉及文档同步 / 飞书 / 发布：读相关 lark / publish / sync skill 和测试。
- 涉及框架公开入口：读 README、CHANGELOG 未发布段、doctor / install / upgrade 暴露逻辑和相关测试。

读完后先写“现有边界”：

```text
我先看到现有边界是：
- <skill A> 负责 <职责>
- <skill B> 负责 <职责>
- 缺口在 <一句话>
```

如果缺口只是现有 skill 的门禁或文案，不要默认新建入口。

---

## 真问题

PMAI workflow 决策问的不是“要不要加一个 skill”，而是：

- 这次谁是最终真相源？
- 这次缺的是决策入口、执行能力、文档成文、测试门禁，还是 PM 视图表达？
- 现有 skill 的边界是不是已经对，只是执行不稳？
- 新入口会不会让公开菜单更乱？
- 下游应该交给哪个 skill，还是停住？

---

## 四类 Alternatives

任何 workflow 结论前，必须比较至少两个真实方向：

| 方向 | 何时成立 | 常见落点 |
|---|---|---|
| 调用现有 | 现有 skill 已覆盖，只是本轮没按它走 | 更新调用说明或当前任务改走现有 skill |
| 改现有 | 边界正确，但门禁、测试、问法或 PM 视图不稳 | `/pmai-skill-improve <skill>` |
| 新建入口 | 现有 skill 都太底层，确实缺上层决策入口 | 新 skill + doctor / README / tests |
| 先不做 | 价值不稳、会污染菜单、或只是一次性任务 | 记录触发条件，停住 |

“新建入口”不是默认答案。只有同时满足以下条件才推荐：

- 现有 skill 都不能自然承接这类判断。
- 这类问题会重复出现，不是一次性工作。
- 新入口能减少 PM 决策负担，而不是多一个要记的命令。
- 有明确下游工具或执行路径，不会变成空泛咨询。
- 能写出回归测试防止同类失败。

---

## Dangerous Premise

workflow 决策常见危险前提：

- 以为缺新 skill，其实缺的是现有 skill 的执行门禁。
- 以为缺执行工具，其实缺的是“这次谁是真相源”的同步方向判断。
- 以为应该回 `/pmai-design`，其实问题是 framework skill 边界。
- 以为 PM 想要直接落盘，其实 PM 还没拍 alternatives。
- 以为一次成功案例能上升为公开入口，其实只是临时 playbook。

必须说清什么证据会推翻当前方向。

---

## Handoff 规则

- skill / workflow 反馈消化 → `/pmai-skill-improve`。
- 模块结构、信息模型、状态、动作 → `/pmai-design`。
- 文档成文 → `/pmai-doc-writing` 或 `/pmai-spec-writing`。
- 构建实现 → `/pmai-build`。
- 飞书同步执行 → `/pmai-lark-sync` 或对应底层 lark skill。
- PM 未拍方向 → 停住，不写最终方案。

禁止把 skill / workflow 改造问题交给 `/pmai-design`。design 只负责产品模块结构，不负责 PMAI 框架入口决策。
