---
name: implementation-design
description: |
  Stage 5（拆 task 前）：读 brief / analysis / prd.md / docs/PROJECT.md / docs/DESIGN.md，
  按 $REPO_ROOT/templates/implementation-design.md.tmpl 产出 req 级实现设计文档
  implementation-design.md（HOW：这个 req 用什么架构、照哪些现有代码写、为什么这么选）。
  由 /req-stage-gate 在 Stage 4→5 编排调用，task-plan 之前。
  产出经 PM 确认门审定架构决策表后放行。do NOT use to write PRD (WHAT) or task spec.
---

# /implementation-design

## When To Use

- Orchestrator 在 Stage 4→5 调用（由 `/req-stage-gate` 触发），**在 `/task-plan` 之前**。
- 每个 req 都跑 —— 它产出的 `implementation-design.md` 是 `task-spec` 的上游 HOW 源。

本 skill 承接原 `solution.engineering.md` 的 req 级 HOW 内容 —— `req-solution`
退场后 req 级「这个 req 用什么架构、照哪些代码写」无家可归，本 skill 是它的新家。

## 性质：工程合同格式 + PM 经门审定

`implementation-design.md` 是**工程合同格式**的 artifact：

- 允许所有工程内容（TS 类型 / 字段名 / 像素 / 颜色 / 反向约束）。
- **不跑 PM-view lint** —— `check-doc-pm-view.py` 跳过本文件（同它已跳过 `.engineering.md`）。
- **有 PM 确认门** —— 产出后由 `/req-stage-gate` 走确认门，PM 审定**架构决策表 + 原型简化项段**
  （选择 / 备选 / 理由 + 简化项 SIMP-ID / PRD 锚点 / 计划简化为），两块同门一次性放行。
  架构决策表含「这个 req 用什么架构、为什么这么选」、原型简化项段含「原型故意做得比 PRD 少的
  scope 削减」—— 两者都是 scope 决策，AI 单方面定再注入 task 与框架内核「PM 在环里」冲突。
  确认门展示 ① 架构决策表「选择」列摘要 ② 简化项段「SIMP-ID + 计划简化为」摘要 + 文件路径，
  PM 可下钻全文，不必逐字背工程细节。

- **简化项段 scoped PM-view lint**（源头约束）—— 段 1.5「原型简化项」内容会被 close-req §2a
  写回 PRD（PRD 是 PM 视图），所以本段产出后跑一次 scoped PM-view lint，只校验段 1.5 内的
  「真实需求」「原型本次计划简化为」「为什么简化」三个 PM 视图字段（其余段保持工程豁免）。
  scoped 模式入口见步骤 3 自检 + 步骤 3.5 lint 调用。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: implementation-design"
```

## 接口契约（与 req-stage-gate 的边界）

| 维度 | 本 skill 负责 | orchestrator (req-stage-gate) 负责 |
|---|---|---|
| 写 `implementation-design.md` | ✅ | ❌ |
| 产出失败 / 重跑 | ✅（报告失败原因） | ❌ |
| 走 PM 确认门（审架构决策表） | ❌ | ✅ |
| 输出推荐 review 区块 | ❌ | ✅ |
| 调 req-transition.py | ❌ | ✅ |

**退出契约**：本 skill 返回时，`implementation-design.md` 已写完。orchestrator 接手走
PM 确认门（审架构决策表），通过后再调 `/task-plan`。

## Required Inputs

逐一读取：

| 输入 | 用途 |
|---|---|
| `$ACTIVE_REQ_DIR/prd.md` | req 级功能规格（WHAT）—— HOW 据此设计，不重抄 WHAT |
| `$ACTIVE_REQ_DIR/prd.md §三` | **本 req 临时词典**（名词解释）—— 写 HOW 时按本 req 引入的新业务实体 / 角色精确指代，禁同义词漂移 |
| `get_stage_source($ACTIVE_REQ_DIR, 2)` | **stage 2 真相源** —— 需求分析 / 讨论产物：A 分支 `analysis.md`（结构化），B 分支 `stage2-office-hours.md`（YC office-hours snapshot）。技术依赖 / 约束据此读。helper：`python3 -m _lib.state read_req_meta $ACTIVE_REQ_DIR` 取 `stage2_source`，或调 `_lib.state.get_stage_source` |
| `$ACTIVE_REQ_DIR/brief.md` | 原始诉求（轻量背景）|
| `$REPO_ROOT/docs/PROJECT.md` | 项目级背景（技术栈 / 产品定位）|
| `$REPO_ROOT/docs/PROJECT.md ## 业务术语表` | **长期词典**（跨 req 已沉淀的稳定业务术语）—— 跟 PRD §三 同时读：PROJECT 是沉淀基线，PRD §三 是本 req 新引入的临时词；两者并集 = 写 implementation-design 时的术语词典 |
| `$REPO_ROOT/docs/DESIGN.md` | **组件 inventory** —— §2 文件·模式索引据此写「复用现有组件 X」，与 stage 4 gap-check 读同一份 |
| `$REPO_ROOT/docs/modules/`（如存在）| 现有模块规格 —— 照哪些现有代码写 |

## Workflow

### attachments AI 接管 hook（trigger 0 — Stage 5a 期间生效）

PM 在 chat 描述 "我有 X 在 ~/Downloads/foo.pdf，重点 Y" → AI first-principle 识别 → 调 helper：

```python
from _lib.attachments import copy_attachment
result = copy_attachment(req_dir, Path("~/Downloads/foo.pdf"),
                        stage_prefix="impl", hint="Y 重点")
```

stage_prefix `"impl"`（Stage 5a `implementation-design`）。chat 一行确认 `已归档（attachments/impl-foo.pdf），Y 重点。继续。`（禁工程黑话）。

异常 catch：`FileNotFoundError` / `SensitivePathError` / `FileSizeError` → chat 报错（fail-loud）。

**trigger 2 fallback**：写 `implementation-design.md` 前扫 `attachments/`，`is_seen` 判定。

**引用 section 渲染**：写 `implementation-design.md` 时 `list_attachments_seen` 按 `registered_at` 升序渲染到文档物理末尾。

**单一真相源**：`skills/_shared/pm-view/attachments-upload.md`。

### 步骤 0.5：项目级文档强制 echo（不依赖 LLM 自觉 Read）

implementation-design 必读输入是所有 orchestrated skill 里最多的（8 项），LLM 自觉 Read 漏读 / 浅读概率最高。**与 task-execute 步骤 2.0 / prd-writing 步骤 0.5 同款失效模式同款修法** —— Bash `cat` 把基础必读全文 echo 进 transcript，保证进入 working context。

```bash
# stage 2 真相源路径解析
STAGE2_SRC=$(cd "$REPO_ROOT" && python3 -c "
import sys; sys.path.insert(0, 'scripts')
from pathlib import Path
from _lib.state import get_stage_source
print(get_stage_source(Path('$ACTIVE_REQ_DIR'), 2))
" 2>/dev/null)

SOURCES=(
  "$ACTIVE_REQ_DIR/prd.md"           # WHAT 主源
  "$STAGE2_SRC"                       # 技术依赖 / 约束
  "$ACTIVE_REQ_DIR/brief.md"         # 原始诉求
  "$REPO_ROOT/docs/PROJECT.md"       # 技术栈 / 业务术语表（长期词典）
  "$REPO_ROOT/docs/DESIGN.md"        # 组件 inventory（正向源：照哪些组件写）
)

for f in "${SOURCES[@]}"; do
  if [ -n "$f" ] && [ -f "$f" ]; then
    echo "════════════════════════════════════════════════════════════════"
    echo "FORCE READ: $f"
    echo "════════════════════════════════════════════════════════════════"
    cat "$f"
    echo "════════════════════════════════════════════════════════════════"
    echo "END $f"
    echo "════════════════════════════════════════════════════════════════"
  else
    echo "ℹ️  $f 不存在或未解析，跳过"
  fi
done
```

涉及模块的 `docs/modules/<m>.md` 在**步骤 1.5** echo（要等步骤 1 基于 prd 识别完本 req 涉及哪些模块；不能在 0.5 机械列出 —— 会污染 context）。

### 步骤 1：消化已 echo 输入 + 识别涉及模块

步骤 0.5 已把 prd / stage2源 / brief / PROJECT / DESIGN 全文 echo 进 transcript。本步骤基于内容：
- `docs/DESIGN.md` 的组件 inventory 是「照哪些现有组件写」的权威来源 —— stage 4 gap-check 已先更新过 inventory（每 req 必跑组件复用关口），本 skill 读到的是更新后的。§2 文件·模式索引据 inventory 写「复用现有组件 X」；inventory 没有的才标新建。
- `prd.md` 是 WHAT —— 本文件只补 HOW，不重复 PRD 的功能行为描述（引用，不重抄）。
- 同时识别本 req 涉及的模块清单（参考 `docs/modules/INDEX.md`，若 INDEX 未在步骤 0.5 echo 则补 `cat` 一次），落到 `MODULE_SPECS` 数组供步骤 1.5 使用。

### 步骤 1.5：涉及模块 spec 强制 echo（同 0.5 同源）

```bash
MODULE_SPECS=(
  # 步骤 1 识别填入，例：
  # "$REPO_ROOT/docs/modules/部门+用户+角色设计/department-group-role-design-v4.1.md"
)

for f in "${MODULE_SPECS[@]}"; do
  if [ -f "$f" ]; then
    echo "════════════════════════════════════════════════════════════════"
    echo "FORCE READ: $f"
    echo "════════════════════════════════════════════════════════════════"
    cat "$f"
    echo "════════════════════════════════════════════════════════════════"
    echo "END $f"
    echo "════════════════════════════════════════════════════════════════"
  fi
done
```

涉及模块为空（如纯基础设施 req）→ 跳过本步骤。

### 步骤 2：按归宿表产出 implementation-design.md

按 `$REPO_ROOT/templates/implementation-design.md.tmpl` 生成
`$ACTIVE_REQ_DIR/implementation-design.md`，5 段结构：

| 段 | 内容 | 承接来源 |
|---|---|---|
| 段 1 · 架构决策表 | 这个 req 用什么架构 / 数据结构 / 派生状态规则 | 原 solution.engineering ch1 + ch2 |
| **段 1.5 · 原型简化项**（v2 新增）| 本 req 原型故意做得比 PRD 少的 scope 削减（kind 1 直接登记 / kind 2 由 task-plan §4.2 反向写回）| §0 痛点决议 + plan-eng-review Round 1 |
| 段 2 · 文件·模式索引 | 照哪些现有代码 / 组件 / 模式写；mock 改造；关键算法消费规则 | 原 ch3 + ch4 + ch5 |
| 段 3 · 约束与验收 | 易错点 / 反向约束 + 工程层验收清单 + **段 3.3 自由度声明**（新增）| 原 ch6 + ch10 + 自由度声明 |
| 段 4 · 审计与修订记录 | plan-review 沉淀 + 修订留痕 | 原 ch7（ch8 autoplan 噪音不留；视觉规范细则 → DESIGN.md）|

#### 2.1 段 1.5 · 原型简化项登记引导（kind 1）

**触发问句**：写完段 1 架构决策后，对 PRD §六 功能需求逐条问自己：「原型本期是否原样实现这条？」。
若 PM 在 stage 2-4 已决策本期某功能行为简化（不全做 PRD 写的范围），登记一行：

- **PRD 锚点**：写「§六 6.X <功能名>」或「Story N」。close-req §2a 按章节号 + 功能名解析回 PRD，
  必须能在 PRD 找到对应行。
- **真实需求**：写「见 PRD §六 6.X」一句引用，不重抄 PRD 原文（避免 §5.4 closed PRD 双源）。
- **原型本次计划简化为**：诚实写「计划」—— stage 5 还没执行，写时是计划描述，不是 as-built。
  若执行期偏离计划，走 close-task adjustment 路径。
- **为什么简化**：一句话理由（如「本期主流程已覆盖 80% 用例，分支路径下个 req」）。
- **来源**：本段直接登记的写 `kind 1`；`kind 2` 是 task-plan §4.2 反向写回的（本 skill 不主动写）。

**范围阈值**（C8）：只登 PM 主动决策的**决策级简化**。路线默认（如原型档「默认仅主路径」）由
`docs/工程结构约束-prototype.md` 总体说明覆盖，不为每个略过的 edge case 立 SIMP 行。判断标准：
**「PM 是否会因此条简化在评审时被问『为什么这块没做』」** —— 会 → 登；不会 → 走总体说明。

**无简化项的情况**：原型本期 1:1 实现 PRD 全部范围 → 表格保留表头 + 单独一行写「无」。
不要省段头（close-req §2a 读不到段会报错）。

**kind 2 不在此处登记**：整块功能原型不做的（如「PRD 有 SSO 但原型本期完全不接 SSO」）由
task-plan §4.2 验收 GAP 清单原地登记（编排顺序：implementation-design 在 task-plan 之前，
拿不到 task-plan 决策），task-plan 决议后反向写回本段一行（来源列标 kind 2）。

**可消费 schema（强制）** —— 段 1 / 段 2 每条 HOW 是一行，带稳定字段：

- **`HOW-ID`**：稳定行级锚（段 1 用 `HOW-01..`，段 2 用 `HOW-10..`）。一旦分配**不复用、不重排**——
  `task-spec` 按 ID 引用，不靠章节标题 grep。
- **适用模块 / 适用 task 关键词**：`task-spec` 据此（按 `input-flow.md §9.1.1` 章节-grep）挑出
  当前 task 相关的 HOW 行。
- **决策内容**：
  - 段 1 每行**必带**「选择 / 备选 / 理由 / 约束失效条件」—— 允许写「无非平凡备选」，**不留空**
    （§0「为什么这么选」就是 HOW 缺口，默认空大段 = 没满足 §0）。
  - 段 2 每行写文件路径 / 模式 + 复用 / 新建标注。
- **来源**：承接自 `solution.engineering` 哪章，或「新增」。

### 步骤 3：自检

- [ ] 5 段齐全（段 1 / 段 1.5 / 段 2 / 段 3 含 3.1/3.2/3.3 / 段 4）；段 1 / 段 2 每条 HOW 行带 `HOW-ID` + 适用关键词
- [ ] 段 3.3 自由度声明：无偏离则整表写"无"（不允许省段头）；有偏离时每条带「适用范围 / 档位 / 理由」三列填全
- [ ] 段 1 每行「选择 / 备选 / 理由 / 约束失效条件」都填了（备选可写「无非平凡备选」，但不空）
- [ ] 段 1.5 每条 SIMP 行带稳定 `SIMP-ID`，「PRD 锚点」能在当前 PRD 找到对应章节；
      「原型本次计划简化为」字段名诚实命名（不写「原型本次实现」—— stage 5 是计划非事实）；
      「来源」列标 `kind 1`（本段直接登记，`kind 2` 由 task-plan §4.2 反向写回）
- [ ] 段 2 的「复用现有组件」与 `docs/DESIGN.md` 组件 inventory 对得上
- [ ] 不重复 PRD 的 WHAT（功能行为描述用引用，不重抄）
- [ ] 像素 / 视觉规范细则没塞进来（那归 `docs/DESIGN.md`）

### 步骤 3.5：段 1.5 scoped PM-view lint（源头约束）

段 1.5 内容会被 close-req §2a 写回 PRD（PRD 是 PM 视图），所以本段在源头先跑一次 scoped
PM-view lint，避免把工程词带进 PRD 标注：

```bash
python3 "$REPO_ROOT/.claude/scripts/check-doc-pm-view.py" \
  "$ACTIVE_REQ_DIR/implementation-design.md" --simp-scope
```

`--simp-scope` 模式只校验「## 段 1.5 · 原型简化项」表格的「真实需求」「原型本次计划简化为」
「为什么简化」三列；其余段保持工程豁免（不变）。

处理输出：
- **0 errors + 0 warnings** → 进步骤 4
- **有 errors** → 回步骤 2.1 改段 1.5 措辞（用 PM 视图语言重写涉事字段），再重跑；
  连续 3 次仍有 error → 停下询问 PM
- **有 warnings** → 每条显式判定（要么修，要么给 PM 一句话理由）

无段 1.5（整段不存在）→ 退步骤 2.1 补段头 + 写「无」。lint 跳过空段（段头存在 + 单行「无」时
0 校验）。

### 步骤 4：skill 结束

写完 `implementation-design.md` → skill 退出。控制权交回 `/req-stage-gate`，由它走 PM
确认门（审架构决策表 + 段 1.5 原型简化项摘要，两块同门），通过后调 `/task-plan`。

产出失败（输入缺失 / PRD 未定稿等）→ 报告失败原因，不硬写。

## Rules

**禁止项**：
- ❌ 写 WHAT（功能行为 / 用户场景 / 验收标准）—— 那是 PRD，本文件引用不重抄
- ❌ 拆 task —— 那是 `/task-plan`
- ❌ 把视觉规范细则（像素 / 颜色 / 字号 / 视口断点）写进本文件 —— 归 `docs/DESIGN.md`（视觉基线段由 gstack 写 / 共享组件 inventory 段由 stage 4 4A 累积）
- ❌ 段 1 架构决策行留空「备选 / 理由」
- ❌ skill 内部走 PM 确认门 / 调 req-transition.py（归 orchestrator）
- ❌ 把本文件拆成 GSD 式多文件 —— 单文件 5 段（主 AI 一气写完，无 agent 边界）
- ❌ 段 1.5 字段叫「原型本次实现」—— 必须叫「原型本次计划简化为」（C6：stage 5 是计划非事实）
- ❌ 段 1.5 PRD 锚点写自由文本（如「登录功能」）—— 必须含 §章节号 + 功能名，否则 close-req 锚点解析失败 stop
- ❌ 段 1.5 登路线默认范围（如「edge case 不实现」）—— 那由 `docs/工程结构约束-prototype.md` 总体说明覆盖（C8 阈值=决策级简化）
- ❌ 段 1.5 直接登 kind 2（整块功能不做）—— kind 2 由 task-plan §4.2 原地登记后反向写回（C1 编排顺序）

**定向豁免（§5.3）**：

段 1.5「原型简化项」字段允许写原型行为细节（如「列表只展示 5 条无分页」「按钮无 loading 态」），
这是 **scope delta** —— PRD 里根本没有的「少做」信息，按定义不在 PRD 重抄范围。
段 1 / 段 2 / 段 3 / 段 4 仍守「❌ 写 WHAT（功能行为）」规则，只段 1.5 豁免。

## 阶段 5 边界（拆 task 前）

- **允许产出**：`$ACTIVE_REQ_DIR/implementation-design.md`（5 段，含 段 1.5 原型简化项）
- **允许动作**：读上游 + 项目级文档、设计 req 级架构 / 文件·模式索引 / 约束 / 段 1.5 原型简化项 kind 1 登记
- **禁止顺手推进**：不拆 task、不走确认门、不调 review、不直接登 kind 2（task-plan 之后才决议）
- **退出条件**：`implementation-design.md` 已写完 + 段 1.5 通过 scoped lint，控制权交回 `/req-stage-gate`

## 文档结构

段结构 + 可消费 schema 的单一真相源 = `$REPO_ROOT/templates/implementation-design.md.tmpl`。
本 skill 不在内部复制章节定义。
