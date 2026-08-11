# banner-rules：视觉锚点与 Decision gate label 规范

> **职责**：banner 格式 + Next Up 块格式 + Decision gate label 3 硬规则。
> **调用方**：proposal / init-project / design / build / build-close / build-cancel 等所有用户面 skill。
> **设计来源**：gstack / gsd 的 banner + Next Up + "Ready?" Decision gate pattern。

---

## §1 skill banner（入口和关键切换处必打）

### §1.1 格式

```
━━━ PMAI ► <SKILL> ▸ <Name> ━━━
```

- `<SKILL>`：当前 skill 名，大写，如 `PROPOSAL` / `INIT-PROJECT` / `DESIGN` / `BUILD`
- `<Name>`：给 PM 看的当前动作名，如 `产品方向澄清` / `项目初始化` / `需求探索` / `开始 build`
- **不展示内部阶段号**：PM 只需要知道现在在做什么，不需要知道内部状态字段

### §1.2 例子

```
━━━ PMAI ► PROPOSAL ▸ 产品方向澄清 ━━━
━━━ PMAI ► INIT-PROJECT ▸ 项目初始化 ━━━
━━━ PMAI ► DESIGN ▸ 需求探索 ━━━
━━━ PMAI ► BUILD ▸ 开始 build ━━━
━━━ PMAI ► BUILD-CLOSE ▸ 收尾沉淀 ━━━
```

### §1.3 何时打

- skill 入口：PM 一发命令就打，让 PM 知道当前命令已接住
- skill 内出现明确模式切换时：例如 design 从探索进入方案收敛，build 从准备进入执行，build-close 从验收进入沉淀
- skill 退出前通常不再重复 banner，退出点给 `▶ Next Up`

### §1.4 渲染约束

- 固定一行，尽量控制在 80 字符内
- 用 `━` U+2501 Box Drawings Heavy Horizontal（纯文本兼容）
- 不用复杂 box-drawing 字符（如 `┏━┓┃┗━┛`）
- 不加颜色 / emoji，PM 视图保持纯文本

### §1.5 数据源

优先由当前 skill 明确传入 `--skill <name>` 后调用 `status-view.py --banner-only` 渲染。渲染失败不阻塞主流程：skill 继续跑，最多给一行普通进展说明。

---

## §2 Next Up 块（skill 退出时必出）

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

## ▶ Next Up — /pmai-build "<模块名>"

## ▶ Next Up — 构建结果定稿后自动最终检查并收尾
```

### §2.3 何时打

- skill 正常退出时
- skill 需要 PM 后续手动继续时
- skill 因可恢复问题停住时，给出下一条最直接命令或一句明确处理动作

被 PM 明确要求停止时，只说明已停在哪里；不要伪造下一步。

### §2.4 渲染约束

- 用 `▶` U+25B6 Black Right-Pointing Triangle 引导
- 命令用反引号 / 代码块包裹，PM 可复制即用
- 最多 2 条命令；超过 2 条时改成一句任务说明 + 第一条命令

### §2.5 内容禁忌（PM-facing 输出禁工程黑话与内部原理）

Next Up 块 / skill 退出提示 / 错误退出提示 —— 任何 PM **直接看到的 chat 输出**里：

**禁内部状态词**：`Phase 1` / `Phase 2` / `finalize marker` / `auto-chain` / `bound-to-execution-event` / `dispatch` / `transition`、任何带编号的内部阶段（"步骤 7.5" "§0.4" "M2 banner" 等给 SKILL 读者看的引用号）。

**禁内部实现术语**：`task 分支` / `worktree` / `delete branch` / `commit 到 X 分支` / `git diff` 之类描述 git 内部操作的词汇。

**禁"AI 为啥这样安排"的原理解释**：PM 不需要懂内部机制 / 不需要 AI 自证流程合理。给 PM 的应该是「现在做啥 + 一句话目的」，不是「AI 为啥选这条路径」。

**允许保留**：前台命令名（如 `/pmai-design` / `/pmai-build`）和必要路径提示。`/pmai-build-close` 只在兼容或恢复场景提示，正常链路不要求 PM 手动运行。

**改写公式**：
- 工程版："启动复审脚本、合并分支、删除隔离环境" → PM 版："我会把这次建好的内容检查完，确认后收尾到主线。"
- 工程版："执行器写了 12 个文件，coverage diff 命中 3 项" → PM 版："我会列出已建内容和未覆盖的验收点，让你决定要不要继续改。"

**反例（C 类不适用）**：PM 决策 picker 里的「AI 倾向 A，理由：<本次工作具体情况一行>」——这是给 PM 决策的素材（PM 选 A/B 要看 AI 倾向理由判断），**不是**解释 AI 流程安排，本规则不约束。判定标准：理由内容是"帮 PM 做选择"还是"解释 AI 已经做了的选择"，后者禁。

---

## §3 Decision gate label 3 硬规则

> Decision gate = AskUserQuestion / picker 在闸门处给 PM **明确动作选择**。runtime 不支持 picker 时，按 `askuser-rules.md` 退化成编号选项。

### §3.0 适用范围（必读）

**§3.1-§3.4 管所有 PM 决策闸门**。判定规则：

| 形态 | 是否走 §3 | 例子 |
|---|---|---|
| **真实 PM 决策门**（产品模型岔路 / one-way door / AI 改变 PM 已明确方向 / build 开工确认）| 必须用 AskUserQuestion / picker（runtime 不支持时按 askuser-rules.md §1.3 退化为编号列表）| `/pmai-design` 的对象或权限模型岔路；发布 / 删除 / 安全例外授权；build 只确认工作环境和构建工具 |
| **框架内部编排**（meta / mockup / spec-writing / 默认验收 / 保存依据 / close）| 不问 PM，按共用 decision policy 自动处理 | 首个 design 只在项目建造定义处确认一次；`/pmai-build` 读取定义并生成验收方案，定稿后自动 finalize |
| AI 主动告知 / 状态播报（不要 PM 答）| prose 输出即可 | banner / Next Up 块 / skill 启动播报 / 进展告知 |
| 反问澄清（PM 输入语义模糊，AI 需 PM 补一句话再决定走 A/B/C，不是闸门决策）| prose 反问即可 | "你说的'改原型'指本次范围里的改动，还是想新起一个需求？" |

**为什么统一**：

1. 多分流选择门如果只用 prose 列选项，AI 容易错解 PM 自然语言。
2. picker / 编号选项让 PM 显式选择，降低歧义。
3. 统一规则让不同 skill 的决策门长得一致。

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
| "通过" | 没说通过后要发生什么 |

### §3.2 规则 2：description = 一句话解释

label 是动作名（短），description 是该动作的"我会做什么"一句话解释。

**正确**：

| label | description |
|---|---|
| "创建 PRODUCT.md" | "我会开始写 PRODUCT.md，进入后续配置、需求和路线图流程。" |
| "继续探索" | "你还想补充行业、客户类型、典型流程、Demo 形态或内部协作方式。" |
| "拍板范围清单，进 build" | "我会按确认后的范围清单和决策页，在主原型里开始动手建。" |
| "继续收范围" | "你还有范围或关键决策想再聊清楚。" |

**错误**：

- description 写 200 字长说明 → 应该是模板代码块或文档摘抄链接
- description 跟 label 完全重复（"开始 build" / "开始 build" → description 没增信息）

### §3.3 规则 3：留守选项有 Loop 回路

留守选项（"继续探索" / "继续完善 X"）选了之后：

- 自动回到当前讨论态，不退出 skill
- Loop 直到 PM 选推进选项才退出闸门
- 不给"暂跳过 / 以后再说"逃生舱：必须二选一拍板（往前推或留下来继续讨论）

### §3.4 AskUserQuestion 模板

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

## §4 失败场景

- banner 数据源失败（status-view.py 跑挂）→ skill 继续跑，banner 留空 + 一行普通进展说明（不阻塞 PM 工作）
- Decision gate 选项 PM 没答 → 按 askuser-rules.md 规则：STOP wait next message，不重试不默认

---

**End of banner-rules.md**
