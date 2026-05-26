# banner-rules：视觉锚点与 Decision gate label 规范（M2 单一真相源）

> **职责**：banner 格式 + Next Up 块格式 + Decision gate label 3 硬规则（M3 砍后整合到 M2，2026-05-25 codex C-1）。
> **调用方**：req-stage-gate / init-project / new-req / task-confirm / task-execute / close-task / close-req（所有用户面 skill）。
> **设计来源**：gsd `autonomous.md:62-69, 155-163` / `execute-phase.md:1725-1730` / `transition.md:494-509`（banner + Next Up）+ gsd `new-project.md:368-380` "Ready?" Decision gate。

---

## §1 阶段 banner（stage 转换处必打）

### §1.1 格式

```
━━━ PMAI ► <SKILL> ▸ Stage <N>/<T>: <Name> ━━━
```

- `<SKILL>`：当前 skill 名，大写（如 `REQ-STAGE-GATE` / `INIT-PROJECT` / `TASK-EXECUTE`）
- `<N>/<T>`：当前 stage / 总 stage 数（如 `3/7` for req stage 3 of 7）
- `<Name>`：stage 显示名（如 `PRD-Writing` / `Implementation-Design` / `QUESTIONING`）

### §1.2 例子

```
━━━ PMAI ► REQ-STAGE-GATE ▸ Stage 3/7: PRD-Writing ━━━
━━━ PMAI ► INIT-PROJECT ▸ Stage C/4: QUESTIONING ━━━
━━━ PMAI ► TASK-EXECUTE ▸ Stage 5/7: Task-Spec → Execute ━━━
```

### §1.3 何时打

- skill 入口（PM 一发命令就打）
- 每个 stage 转换前后（req-stage-gate stage N → N+1 时打 N+1 banner）
- skill 退出前（让 PM 知道最后停在哪）

### §1.4 渲染约束（review R6）

- **固定宽度 80 字符**（防终端宽度乱排）
- 用 `━` U+2501 Box Drawings Heavy Horizontal（纯文本兼容）
- 不用 box-drawing 重型字符（如 `┏━┓┃┗━┛`）
- 不加颜色 / emoji（review C-8）—— PM 视图保持纯文本

### §1.5 数据源

`status-view.py --banner-only <req_dir>` 输出一行 banner（实现见 `_lib/state.py:get_current_stage_banner()`）。

---

## §2 Next Up 块（skill 退出 + stage 完成时必出）

### §2.1 格式

```
## ▶ Next Up — <command> <hint>
```

或多步骤形态：

```
▶ Next Up:
  <command-1>
  <command-2>
```

### §2.2 例子

```
## ▶ Next Up — cd <target-dir> && /new-req "<一句话需求>"

▶ Next Up:
  cd <target-dir>
  /new-req "<一句话需求>"

## ▶ Next Up — /req-stage-gate（推进 stage 3 → 4 gap-check）

## ▶ Next Up — /close-req（req 全 task 完成，merge 进 main）
```

### §2.3 何时打

- skill 任意退出点（除被 PM `--stop` 强制中断外）
- stage 完成、续跑等待 PM 输入时（PM 答闸门后续到下一 stage 入口，**不**重发 banner，但要给 Next Up hint）

### §2.4 渲染约束

- 用 `▶` U+25B6 Black Right-Pointing Triangle 引导
- 命令用反引号 / 代码块包裹（PM 复制即用）
- 最多 2 条命令（多了换分步描述）

---

## §3 Decision gate label 3 硬规则（M3 砍后整合 M2）

> Decision gate = AskUserQuestion 在闸门处给 PM **明确动作二选一**（gsd new-project.md:368-380 "Ready?" pattern）。
> M3 整模块砍后，**Decision gate label 规范化作为 M2 sub-feature**（不需要独立模块）。
> 注：gsd 续跑模式（`req-stage-gate/SKILL.md:27-49, 625` 现役机制）已默认推进 stage，**Decision gate 解决的是闸门选项语义模糊问题**，不是"每 stage 喂继续"。

### §3.0 适用范围（必读 — D-iv v0.3 patch 加）

**§3.1-§3.4 只管 AskUserQuestion picker 闸门**（GUI 选项卡片形式）。判定规则：

| 形态 | 是否走 §3 | 例子 |
|---|---|---|
| SKILL.md 代码里显式调 `AskUserQuestion(...)` 或写 yaml `header / question / options` 模板 | ✅ 走 §3.1-§3.4 | `/init-project` 阶段 C「创建 PROJECT.md / 继续探索」；`/new-req` 步骤 4 缺口补问 |
| chat 自由对话续跑（PM 答自然语言「OK / 通过 / 没问题 / 定了」触发推进）| ❌ 走常规形态，**不受 §3 约束** | `/req-stage-gate` Stage N→N+1 确认门；`/task-execute` 步骤 12 PM 验收「通过 / 打回」|
| chat prose 列选项让 PM 自然语言回答（如「- 选项 A - 选项 B」让 PM 选）| ❌ 走常规 | `/req-stage-gate` Stage 1→2 选择门（"结构化批判 / office-hours / 改 brief"）|
| close-task / close-req B 类逐条对齐（SKILL 显式写「AskUserQuestion 或 prose」二选一）| 用 AskUserQuestion 走 §3，用 prose 走常规 | close-task §1.5 B 类对齐 |

**为什么这样分**：续跑模式 + chat 自由对话是 v3/v4 设计核心，PM 习惯了一句"OK"推进；强行套 §3 的 AskUserQuestion picker 会破坏续跑体验。§3 只针对真正用 GUI 选项卡片的场景（PM 看到的是「按钮二选一」而不是「自由聊天框」）。

### §3.1 规则 1：label = 动作描述

**正确**：

| 推进选项 label | 留守选项 label |
|---|---|
| "创建 PROJECT.md" | "继续探索" |
| "写 PRD" | "继续完善 analysis" |
| "推进 stage 4 gap-check" | "继续修订 PRD" |
| "启动 task-001" | "改 task scope" |

**错误**（**禁用模糊词**）：

| 错误 label | 为什么错 |
|---|---|
| "OK" / "OK" | 没说推进什么 |
| "Proceed" / "继续" | 模糊（继续什么？推进还是留守？）|
| "Continue" | 同上 |
| "是" / "Yes" | 没说做什么 |
| "通过" | gsd 续跑模式下"通过"已是续跑触发词，闸门选项不再用 |

### §3.2 规则 2：description = 一句话解释

label 是动作名（短），description 是该动作的"我会做什么"一句话解释。

**正确**：

| label | description |
|---|---|
| "创建 PROJECT.md" | "我会开始写 .planning/PROJECT.md，进入后续配置、需求和路线图流程。" |
| "继续探索" | "你还想补充行业、客户类型、典型销售流程、Demo 形态或内部协作方式。" |
| "写 PRD" | "我会开始写 prd.md（按 stage 2 analysis），进入 stage 3。" |
| "继续完善 analysis" | "你还有问题想补 analysis 里。" |

**错误**：

- description 写 200 字长说明 → 应该是模板代码块或文档摘抄链接
- description 跟 label 完全重复（"创建 PROJECT.md" / "创建 PROJECT.md" → description 没增信息）

### §3.3 规则 3：留守选项有 Loop 回路

留守选项（"继续探索" / "继续完善 X"）选了之后：

- ✅ **自动回到当前 stage 的讨论态**（不退出 skill）
- ✅ Loop 直到 PM 选推进选项才退出闸门
- ❌ **不退出 skill** —— PM 没拍板下一步，skill 不能假定推进
- ❌ **不给"暂跳过 / 以后再说"逃生舱** —— 必须二选一拍板（往前推或留下来继续讨论）

### §3.4 AskUserQuestion 模板（照搬 gsd）

```yaml
header: "Ready?"  # 或 "推进?" / "下一步?"
question: "<一句话总结到目前为止的讨论，问 PM 是否准备好推进>"
options:
  - label: "<动作描述>"  # 规则 1
    description: "<一句话解释>"  # 规则 2
  - label: "继续 X"  # 留守，描述具体留守做什么
    description: "<一句话解释 PM 留守后做什么>"
    # 选了 → Loop 回讨论态（规则 3）
```

---

## §4 实施指南

### §4.1 stage 转换流程

```
1. agent 完成 stage N 工作
2. 打 stage N+1 banner（§1.2 格式；status-view.py --banner-only 提供数据）
3. 执行 stage N+1 第一个动作
4. 跑到 PM 输入点 → Decision gate（§3 模板）
5. PM 答推进 → 进 stage N+2 入口（回 step 2）
   PM 答留守 → Loop 回 stage N 讨论态（§3.3）
6. skill 退出（stage 全完成 / PM `--stop` / 失败）→ Next Up 块（§2）
```

### §4.2 失败场景

- banner 数据源失败（status-view.py 跑挂）→ skill 继续跑，banner 留空 + 日志一行警告（不阻塞 PM 工作）
- Decision gate 选项 PM 没答 → 按 askuser-rules.md（M4）规则：STOP wait next message，不重试不默认

---

**End of banner-rules.md**（M2 + M3 整合落地；vp-7 实施）
