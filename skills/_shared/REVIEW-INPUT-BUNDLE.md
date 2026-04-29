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

### 4.3 review 跑完后（默认流程：U-list → PM 一次确认 → AI 按 anchor 自动写回）

**这是 default 行为，AI 不再每条问"要不要落"**：

1. **AI 整理 U-list**：把 review 输出里**需要 PM 决定**的项目（taste call / 二选一 / 视觉权重判断）提取成「U1-Un」列表，**每项必带推荐 + 理由**；机械修订项（明确推论 / token 算术 / 显然错误）AI 不问，直接归入"自动写回"清单
2. **AI 一次性向 PM 出 U-list**：表格形式，每项 ≤ 1 行；PM 回「默认全选」或者点出要改的项即可
3. **PM 确认后 AI 直接写回**，不再问任何后续：
   - U-list 项 → 按 anchor 路由（kind = pm-view / engineering / project-doc）到对应源文件章节
   - 自动写回项（机械修订 + 状态 / 文案 / token 漂移修复）→ 同样按 anchor 路由
   - reconcile hash → 用最新 PM 视图 `shasum -a 256 | cut -c1-12` 重算并写回工程合同顶部 `<!-- synced_pm_view_hash: ... -->`
   - GSTACK REVIEW REPORT 节 → 追加本轮 runs / status / decisions / unresolved（PM 视图末）
4. **AI 写完一次性汇报**：列改动 stat、anchor 落点、未触达的项；不要分多轮追问

#### Anchor 路由参考

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

## 六、Skill 流程挂入与配套脚本

### 已挂入

- **`task-confirm`** 步骤 2 默认态摘要附「推荐 review-input bundle 命令」三条（design / eng / dx），PM 复制即跑
- **`task-spec`** 步骤 11.0 落档完成时机械跑一次 build-review-input.py 派生 bundle（业务模块 task：eng + design / 基础设施 task：仅 eng）；步骤 11.1 / 11.2 推荐区块附 bundle 路径
- **`task-spec`** 步骤 12.5 reconcile 流程末尾追加重新派生 bundle（避免 PM 改完后 bundle stale）
- **`scripts/finalize-review.py`** review 跑完后 AI 调用收尾：increment runs cell + replace status / findings / UNRESOLVED / VERDICT + recompute synced_pm_view_hash
- **`<repo>/.claude/review-conventions.json`**（可选）per-project override REVIEW_CONVENTIONS：替换 design / eng / dx 任一类型的章节关键词 / 项目级文档清单，或加新 review 类型

### 仍未做

- `scripts/sediment-review.py` —— 吃 review 自然语言输出 + bundle 路径，按 source anchor 自动追加 decision 到源文件。当前靠 AI 在 chat 协助分流（U-list → PM 一次确认 → AI Edit），实测 2 个样本（example-consumer-app task-003 design / eng）都 work；脚本化 ROI 待 2-3 个新样本观察后决定。**风险**：review 输出格式不稳定，机械解析需 LLM 二次结构化（额外 token + 不稳定）。

### 配套脚本一览

| 脚本 | 时机 | 作用 |
|---|---|---|
| `build-review-input.py <task-file> --review {design,eng,dx}` | task-spec 落档时 + reconcile 后 + PM 改完源文件后 | 派生 bundle 到 `.runs/review-input-<task>-<review>.md` |
| `finalize-review.py <pm-view> --review ... --status ... --findings ... [--unresolved N --verdict TEXT]` | review 跑完 / decision 全部分流写回后 | 更新 GSTACK REVIEW REPORT 表 + 重算 synced_pm_view_hash |
