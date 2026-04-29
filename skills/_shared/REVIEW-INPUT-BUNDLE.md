# Review Input Bundle（review 喂给谁的统一约定）

> 适用范围：所有 PM 在主窗口跑的 plan-time review skill —
> `/plan-design-review`、`/plan-eng-review`、`/plan-devex-review` 等 gstack 评审。

---

## 一、为什么有这套东西

PM 视图 / 工程视图拆两文件后（PM-VIEW-RULES §二），
`/plan-design-review` 这类 gstack skill 天然只读 PM 指过去的那一个文件。
而**视觉 token / 像素值 / 动效曲线全在 `.engineering.md`**——
review 落到 PM 视图主文件，只能评 IA / 交互 / 文案，碰不到视觉层。

实测：example-consumer-app task-003 跑了 3 轮 `/plan-design-review`，16 decisions
全部停留在 IA / 交互 / 文案级；颜色对比、字重节奏、留白、动效曲线一条都没触达。

---

## 二、解决方案：派生 review bundle

不动 PM/工程双文件结构，**落档时按 review 类型派生一份 bundle**，
PM 把 bundle 路径喂给 review skill。

```
PM 视图主文件（不变）
        +
工程合同 §相关章节（不变）
        +
项目级文档（DESIGN.md / docs/modules/*）
        ↓
scripts/build-review-input.py  ← 按约定拼装
        ↓
.runs/review-input-<task>-<review>.md  ← 派生 artifact，给 review skill 吃
```

源文件不暴露给 review；review 评的是 bundle，但 bundle 是源文件的派生，
所以 review 结论沉淀回源文件时仍然有效。

---

## 三、约定（review 类型 → 喂哪些章节）

| Review 类型 | PM 视图 | 工程视图章节 | 项目级文档 |
|---|---|---|---|
| `design`（`/plan-design-review`） | 全文 | §7（plan-review 沉淀）/ §8（视口 / 视觉规范细则） | `docs/DESIGN.md` |
| `eng`（`/plan-eng-review`） | §功能清单 / §跨功能产品规则 / §验收清单 | §3（启动前必读）/ §4（功能清单工程版）/ §5（实现指引）/ §6（易错点 / 禁止项） | `docs/modules/*.md` |
| `dx`（`/plan-devex-review`） | 全文 | §5（实现指引） | — |

约定固化在 `scripts/build-review-input.py` 的 `REVIEW_CONVENTIONS`。
新增 review 类型只改这一处。

匹配方式：substring 命中 `## ` 标题行。脚本对找不到的章节会留 ⚠️ 警告占位，
不静默跳过——便于发现"task spec 章节命名漂了"。

---

## 四、PM 怎么用

### 4.1 跑命令拿 bundle 路径

在主仓根（或 req worktree）跑：

```bash
python3 .claude/scripts/build-review-input.py \
    requirements/active/<req>/tasks/<task-NNN>-<slug>.md \
    --review design
```

输出 bundle 绝对路径到 stdout，类似：

```
/Users/.../ExampleConsumerApp/.runs/review-input-task-003-detail-allocation-view-cascade-design.md
```

### 4.2 把 bundle 路径喂给 review skill

在主窗口（gstack skill 所在窗口）开新对话或继续对话，告诉 Claude：

```
请对以下文件跑 /plan-design-review：

<bundle 绝对路径>
```

或者直接在 chat 里拖文件 / 用 `@<path>` 引用。

### 4.3 review 跑完后（按 source anchor 沉淀回源文件）

bundle 每个章节前面都有一行 source anchor：

```html
<!-- review-source: pm-view, file=task-NNN.md, section=📋 功能清单 -->
<!-- review-source: engineering, file=task-NNN.engineering.md, section=8. 视口 / 视觉规范细则 -->
<!-- review-source: project-doc, file=docs/DESIGN.md -->
```

review skill 输出 decision / finding 时**必须引用对应 anchor**（kind + file +
section）。下游沉淀（PM 手动 / AI 协助）按 anchor 机械路由：

| anchor kind | 落点 | 典型内容 |
|---|---|---|
| `pm-view` | PM 视图主文件相关章节 | IA / 交互 / 文案修订 |
| `engineering` | 工程合同 `.engineering.md` 对应 §章节 | 视觉 token / 颜色 / 动效 / 易错点 / plan-review 沉淀（V1-V35 这一类）|
| `project-doc` | `docs/DESIGN.md` / `docs/modules/*.md` | 项目级共享合同变更 |

补充约定：

- **GSTACK REVIEW REPORT 状态记录**（review 跑了几次 / verdict / unresolved 数）→ PM 视图末「📁 历史档案 / GSTACK REVIEW REPORT」节，固定写在 PM 视图，无需 anchor
- **review 给出"该把 X 决策提到 DESIGN.md 层"建议** → kind 改为 `project-doc` 写回 DESIGN.md，原 `engineering` anchor 处替换为引用（避免双写）

bundle 是派生 artifact，**不**保留 review 结果；下一轮重跑脚本自动重生。

---

## 五、AI 操作约束

- **生成或修改 bundle 文件本身**（写入 `.runs/review-input-*.md`）只允许通过
  `scripts/build-review-input.py` 调用；不允许 AI 手动 Edit / Write 派生文件。
- **review 结论回写**走源文件（PM 视图 + `.engineering.md`），不写 bundle。
- 如果发现脚本约定的章节命名和当前模板不一致（脚本输出 ⚠️），先回头修
  `templates/task.md.tmpl` / `task.engineering.md.tmpl` 的章节命名 / 修
  `REVIEW_CONVENTIONS` 关键词，不要绕路。

---

## 六、当前未挂入的 skill 流程

本工具目前**只是命令行工具**，没有挂入 task-confirm / task-spec 等 skill 自动调用：

- task-confirm 摘要里**没有**自动提示 PM 跑 bundle
- task-spec 落档时**不**自动生成 bundle

这是有意保守的范围：先验证 bundle 本身有效，再决定要不要写进 skill。
PM 或 AI 现阶段需手动调用脚本。

下一步候选（视使用感受决定）：

1. 在 `task-confirm` 步骤 1.5 摘要里附「review 命令清单」段落，输出三条
   `python3 .claude/scripts/build-review-input.py ... --review {design,eng,dx}`
2. 在 `task-spec` 落档完成后自动跑一次 design / eng bundle 生成，bundle
   路径写进 task PM 视图末尾 GSTACK REVIEW REPORT 节
3. 把 `REVIEW_CONVENTIONS` 从脚本内 dict 提到独立 yaml/json 配置，让
   PM 能 per-project override
4. 加 `scripts/sediment-review.py`：吃 review 输出文本 + bundle 路径，按
   source anchor 自动追加 decision 到对应源文件（当前靠 PM / AI 手工分流）
