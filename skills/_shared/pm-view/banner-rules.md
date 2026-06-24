# banner-rules：视觉锚点与 Decision gate label 规范（M2 单一真相源）

> **职责**：banner 格式 + Next Up 块格式 + Decision gate label 3 硬规则（M3 砍后整合到 M2）。
> **调用方**：init-project / design / build / close / cancel（所有用户面 skill）。
> **设计来源**：gsd `autonomous.md:62-69, 155-163` / `execute-phase.md:1725-1730` / `transition.md:494-509`（banner + Next Up）+ gsd `new-project.md:368-380` "Ready?" Decision gate。

---

## §1 阶段 banner（stage 转换处必打）

### §1.1 格式

```
━━━ PMAI ► <SKILL> ▸ <Name> ━━━
```

- `<SKILL>`：当前 skill 名，大写（如 `NEXT` / `INIT-PROJECT` / `BUILD`）
- `<Name>`：阶段显示名（如 `范围确认` / `build` / `复审`）
- **不打 stage 号**：stage 号是内部状态标记、不再 PM-facing，banner 只显阶段名

### §1.2 例子

```
━━━ PMAI ► NEXT ▸ 范围确认 ━━━
━━━ PMAI ► NEXT ▸ build ━━━
━━━ PMAI ► INIT-PROJECT ▸ 方向讨论 ━━━
```

stage 名字以 `scripts/_lib/stages.py:STAGE_NAMES` 为单一真相源（中文，跟 PM 视图一致）。

### §1.3 何时打

- skill 入口（PM 一发命令就打）
- 每个 stage 转换前后（/pmai-status 推进 stage N → N+1 时打 N+1 banner）
- skill 退出前（让 PM 知道最后停在哪）

### §1.4 渲染约束（review R6）

- **固定宽度 80 字符**（防终端宽度乱排）
- 用 `━` U+2501 Box Drawings Heavy Horizontal（纯文本兼容）
- 不用 box-drawing 重型字符（如 `┏━┓┃┗━┛`）
- 不加颜色 / emoji（review C-8）—— PM 视图保持纯文本

### §1.5 数据源

`status-view.py --banner-only <work_dir>` 输出一行 banner（实现见 `_lib/state.py:get_current_stage_banner`）。

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
## ▶ Next Up — cd <target-dir> && /pmai-design "<一句话需求>"

▶ Next Up:
  cd <target-dir>
  /pmai-design "<一句话需求>"

## ▶ Next Up — /pmai-status（范围确认拍板后，进 build）

## ▶ Next Up — /pmai-close（复审通过后收尾沉淀）
```

### §2.3 何时打

- skill 任意退出点（除被 PM `--stop` 强制中断外）
- stage 完成、续跑等待 PM 输入时（PM 答闸门后续到下一 stage 入口，**不**重发 banner，但要给 Next Up hint）

### §2.4 渲染约束

- 用 `▶` U+25B6 Black Right-Pointing Triangle 引导
- 命令用反引号 / 代码块包裹（PM 复制即用）
- 最多 2 条命令（多了换分步描述）

### §2.5 内容禁忌（PM-facing 输出禁工程黑话与内部原理）

Next Up 块 / skill 退出提示 / 状态转换后输出 / 错误退出提示 —— 任何 PM **直接看到的 chat 输出**里：

**禁内部状态词**：`Phase 1` / `Phase 2` / `finalize marker` / `auto-chain` / `bound-to-execution-event` / `dispatch` / `transition`、任何带编号的内部阶段（"步骤 7.5" "§0.4" "M2 banner" 等给 SKILL 读者看的引用号）。

**禁内部实现术语**：`task 分支` / `worktree` / `delete branch` / `commit 到 X 分支` / `git diff` 之类描述 git 内部操作的词汇。

**禁"AI 为啥这样安排"的原理解释**：PM 不需要懂内部机制 / 不需要 AI 自证流程合理。给 PM 的应该是「现在做啥 + 一句话目的」，不是「AI 为啥选这条路径」。

**允许保留**：命令名（如 `/pmai-build` / `/pmai-close`）和必要路径提示；这些是 PM 必须知道的操作信息。

**改写公式**：
- 工程版："启动复审脚本、合并分支、删除隔离环境" → PM 版："我会把这次建好的内容检查完，确认后收尾到主线。"
- 工程版："执行器写了 12 个文件，coverage diff 命中 3 项" → PM 版："我会列出已建内容和未覆盖的验收点，让你决定要不要继续改。"

**反例（C 类不适用）**：PM 决策 picker 里的「AI 倾向 A，理由：<本次工作具体情况一行>」—— 这是给 PM 决策的素材（PM 选 A/B 要看 AI 倾向理由判断），**不是**解释 AI 流程安排，本规则不约束。判定标准：理由内容是"帮 PM 做选择"还是"解释 AI 已经做了的选择"，后者禁。

---

## §3 Decision gate label 3 硬规则（M3 砍后整合 M2）

> Decision gate = AskUserQuestion 在闸门处给 PM **明确动作二选一**（gsd new-project.md:368-380 "Ready?" pattern）。
> M3 整模块砍后，**Decision gate label 规范化作为 M2 sub-feature**（不需要独立模块）。
> 注：/pmai-status 推进模式已默认往前推进 stage，**Decision gate 解决的是闸门选项语义模糊问题**，不是"每 stage 喂继续"。

### §3.0 适用范围（必读）

**§3.1-§3.4 管所有 PM 决策闸门**。判定规则：

| 形态 | 是否走 §3 | 例子 |
|---|---|---|
| **任何 PM 决策门**（阶段转换 / 选择分流 / 推进确认 / 验收 / 留守 vs 推进 / 多分支选择）| ✅ **必须用 AskUserQuestion**（runtime 不支持时按 askuser-rules.md §1.3 退化为编号列表）| `/pmai-status` 推进门；`/pmai-design` 结构决策门；`/pmai-init-project` 阶段 C；`/pmai-build` 隔离环境与执行器选择；`/pmai-close` 沉淀确认 |
| AI 主动告知 / 状态播报（不要 PM 答）| ❌ prose 输出即可 | banner / Next Up 块 / skill 启动播报 / 进展告知 |
| 反问澄清（PM 输入语义模糊，AI 需 PM 补一句话再决定走 A/B/C，不是闸门决策）| ❌ prose 反问 | "你说的'改原型'指本次范围里的改动，还是想新起一个需求？" |

**为什么这样统一**（v5 决策，推翻早期续跑模式专门豁免）：

1. **multi-分流选择门用 prose 列选项让 AI 错解 PM 自然语言** —— 实际事故：范围确认里 PM 答"差不多聊清楚了"被 AI 误判为选了某条上坡路，跳了该走的对话与闸门。picker UI 强制 PM 显式选项是防御。
2. **续跑模式实际收益是"少一次点击"** —— picker 答完即推进，体验跟 prose 续跑相同（PM 输数字 1 或点 picker 选项跟说"OK"操作量等价），但显式选项消除歧义。
3. **统一规则降低维护成本** —— 早期的"chat prose 续跑豁免"让推进闸门跟其他 skill 选项格式分裂，PM 在不同 skill 看到不同交互形态。统一后所有闸门走同一份 picker / 退化编号规则。

历史豁免（早期续跑模式专门排除推进闸门）已废止。

### §3.1 规则 1：label = 动作描述

**正确**：

| 推进选项 label | 留守选项 label |
|---|---|
| "创建 PRODUCT.md" | "继续探索" |
| "拍板范围清单，进 build" | "继续收范围" |
| "开始 build" | "继续改决策页" |
| "开始 build" | "继续改模块规格" |

**错误**（**禁用模糊词**）：

| 错误 label | 为什么错 |
|---|---|
| "OK" / "OK" | 没说推进什么 |
| "Proceed" / "继续" | 模糊（继续什么？推进还是留守？）|
| "Continue" | 同上 |
| "是" / "Yes" | 没说做什么 |
| "通过" | /pmai-status 推进模式下"通过"已是推进触发词，闸门选项不再用 |

### §3.2 规则 2：description = 一句话解释

label 是动作名（短），description 是该动作的"我会做什么"一句话解释。

**正确**：

| label | description |
|---|---|
| "创建 PRODUCT.md" | "我会开始写 docs/PRODUCT.md，进入后续配置、需求和路线图流程。" |
| "继续探索" | "你还想补充行业、客户类型、典型销售流程、Demo 形态或内部协作方式。" |
| "拍板范围清单，进 build" | "我会按确认后的范围清单和决策页，在主原型里开始动手建。" |
| "继续收范围" | "你还有范围或关键决策想再聊清楚。" |

**错误**：

- description 写 200 字长说明 → 应该是模板代码块或文档摘抄链接
- description 跟 label 完全重复（"开始 build" / "开始 build" → description 没增信息）

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
1. agent 完成当前阶段工作
2. 打下一阶段 banner（§1.2 格式；status-view.py --banner-only 提供数据）
3. 执行下一阶段第一个动作
4. 跑到 PM 输入点 → Decision gate（§3 模板）
5. PM 答推进 → 进入下一阶段入口（回 step 2）
   PM 答留守 → Loop 回当前阶段讨论态（§3.3）
6. skill 退出（stage 全完成 / PM `--stop` / 失败）→ Next Up 块（§2）
```

### §4.2 失败场景

- banner 数据源失败（status-view.py 跑挂）→ skill 继续跑，banner 留空 + 日志一行警告（不阻塞 PM 工作）
- Decision gate 选项 PM 没答 → 按 askuser-rules.md（M4）规则：STOP wait next message，不重试不默认

---

**End of banner-rules.md**（M2 + M3 整合落地； 实施）
