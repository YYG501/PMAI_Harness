# D-i：office-hours 跨 Stage 1+2 集成 — 用户视角「需求讨论」单次交互 (v4)

> **状态**：草稿 v4（Codex Round 3 outside voice + fact-check 反转 v0→v1 错误前提）
> **日期**：2026-05-24
> **作者**：PM + AI + Codex (outside voice)
> **历史文件名**：`Stage2-分析方式选择-office-hours.md` → 落地后改名为 `office-hours-跨stage1-2集成.md`
> **版本史**：v0 复制 → v1 引用 follow → v2 路径契约 → v3 路径契约+体验包装 → **v4 snapshot 复制 + 体验包装 + Codex outside voice 8 finding 修复**（见 §7 决策路径）

---

## §0 原始痛点（v3 锁定不变；§0.2 加 fact-check EVIDENCE）

### §0.1 痛点（1-3 句）

office-hours 在 Stage 1（`/new-req` 选项 1）和 Stage 2（v3 stage-gate 选择门）都"被调用一次"看起来不合理 —— 根因不是"集成 2 处"，而是**框架把"用户视角的一次讨论"硬拆成 Stage 1（感受）+ Stage 2（分析）两阶段**。用户视角只是"提需求 → 跟 AI 讨论 → 进 PRD"，讨论工具 2 选 1（office-hours 六问 / req-analysis 第一性原理 + reviewer）。

### §0.2 触发场景

| # | 场景描述 | 实证证据 |
|---|---|---|
| 1 | PM 在 `/new-req` 被问"选项 1 自跑 office-hours / 选项 2 AI 引导" → 选 1 → 进 worktree 跑 stage-gate → 又被问 Stage 2 分析 → 重复 | **EVIDENCE**：PM 表述（本会话）"officehour 可能会在两个阶段被调用，感觉不太合理" |
| 2 | PM 觉得用户视角是"一次讨论"不是 brief+analysis 两阶段 | **EVIDENCE**：PM 表述"从用户视角来看，就是用户提需求，然后讨论，讨论工具 2 选 1" |
| 3 | TTHW 拖时间 | **EVIDENCE**：`TODOS.md:62` HW1 office-hours 六问拖时间 |
| 4 | PM 原意是"用户一开始就调用 office-hours" | **EVIDENCE**：PM 表述"原来的设计是用户一开始就会调用 officehours" |
| 5 | **fact-check：office-hours 设计稿生成后不变** | **EVIDENCE**：`~/.claude/skills/gstack-office-hours/SKILL.md:1575` 文件名 `{user}-{branch}-design-{datetime}.md` 带 datetime 戳；`:1581-1583` Supersedes 是新文件链式记录、老文件不动；`:1708-1749` Spec Review Loop 只在 Write 后 PM approval 前 max 3 次 Edit、approval 后不再 touch；上游升级只改 template、不改已生成的老文件。**v1 "office-hours 上游会变所以引用"论据基于错误前提；v2/v3 路径契约是绕弯设计** |

### §0.3 根因

**两层根因**：

1. **直接根因（v2 已识别）**：Stage 2 下游契约 = "读 `$ACTIVE_REQ_DIR/analysis.md` 这个特定文件"，文件 + 结构双约束让下游死耦合到 `/req-analysis` 输出形态。
2. **体验根因（v3 新识别）**：Stage 1+2 在框架里是两个独立阶段，每个阶段都有自己的 office-hours hook，用户体验跟"一次讨论" mental model 不一致。
3. **架构根因（v4 新识别）**：v1 → v2 → v3 路径契约方向基于"office-hours 上游会变"错误前提（fact-check 推翻）；req 自包含原则要求 stage 2 真相源在 req 内（git / CI / 跨机器 / 归档 / consumer 仓全维度），不能引用仓外 `~/.gstack/` 路径（Codex Round 3 T1 R3-C2 命中）。

### §0.4 不解决什么

| # | 衍生 / 假设场景 | 为什么不在 §0 范围 |
|---|---|---|
| 1 | 让 office-hours 内嵌 4 层 / 跑 reviewer | gstack 上游 skill 本仓不改 |
| 2 | 把 Stage 1+2 真合并（彻底删 brief/analysis 二选一）| D5 review 否决路径 X，~1-2 周；本设计选 Z 路径"体验包装、架构不重构" |
| 3 | 多 req 共享同一份 office-hours 设计稿 | v4 snapshot 后每 req 各自有独立 stage2-office-hours.md，天然独立 |
| 4 | office-hours `Open Questions` 在 B 分支强制 PM 答题 | office-hours prose 不带占位答题；未决问题闸门是 `/req-analysis` 输出契约 |
| 5 | `/req-analysis` 内部分流（子分支）| 不清晰；本设计 stage-gate 入口分流 |
| 6 | office-hours Supersedes 链自动跟进 | v4 snapshot 时刻冻结；PM 想换版本 → 回 Stage 2 重做 |
| 7 | term-detector 扫 `docs/modules/INDEX.md` 比对已有模块冲突 | trade；stage 4 gap-check 兜底 |
| 8 | attachments hook 在 B 分支补 attachments | **D-iii 独立设计**解决 |
| 9 | office-hours 与 req-analysis 输出"等价质量评估" | 两工具各自承担质量 |
| 10 | AI 替 PM 调起 `/office-hours` | new-req 边界一致（AI 不替 PM 调） |
| 11 | Stage 3 用 `/plan-ceo-review` 反向对齐 PRD | **D-ii 独立设计**解决 |
| 12 | 引入 Stage 2 规范化 schema contract（office-hours prose → schema 字段化）| **v4 §5 待验**：相信 LLM 全文喂消化能力（v0 时 PM 已 ACCEPT prd-writing LLM-based fact）；消费仓真实 req 验证后再决定是否需要 |
| 13 | `/new-req` 主对话里也提供 office-hours 选择门 | Z 路径选择 stage-gate 处理体验包装；如未来 new-req 需要选择门 → 独立 D-* |
| 14 | 升级 `STAGE_OUTPUT_FILES` schema 为 `dict[int, list[str]]` 支持多产物 | **Codex R3-H1 命中**：会破 req-transition.py:247 类型；v4 不升级 schema，新建独立 helper 不动现有字典 |

---

## §1 方案概述（v4 snapshot 复制 + 体验包装）

### §1.1 一句话

**保留 stage 1+2 工程拆分**（不重构 brief/analysis 双产物），PM 视角呈现为**"一次需求讨论"单次交互**。底层 B 分支跑 office-hours 后 **AI snapshot 复制原文** 到 `$ACTIVE_REQ_DIR/stage2-office-hours.md`（req 自包含、可进 git / CI / 跨机器 / 归档 / consumer 仓）。`.req-meta.json` 记 `stage2_source` 指 **req 内相对路径** + `stage2_source_origin` 原 `~/.gstack/` 路径（追溯用）。下游 8 个 SKILL/template 改 helper 调用读 `stage2_source`，`req-transition.py:247` 同改 helper 避免 B 分支推不进 stage 3。

### §1.2 流程示意

```
Stage 1（new-req 主对话）：PM 写初步 brief.md → handoff → 进 worktree
  ↓
PM 在 worktree 跑 /req-stage-gate
  ↓
[v3 体验包装层] AI 一开口：brief 二次确认 + 需求讨论入口（合二为一 chat）

  ✅ brief.md
     <$ACTIVE_REQ_DIR/brief.md 绝对路径>

  📋 一句话摘要
     <AI 重新读 brief.md 的核心内容>

  💬 这版 brief 是否可定稿？然后我们用哪种方式跟这个需求讨论？
   - 结构化批判（默认）：第一性原理 4 层 + reviewer + 未决问题答题
   - YC office-hours 式：六问 / 设计思考；产物作 Stage 2 真相源、跳 reviewer
   - 改 brief（请说哪里）

  ↓
[分流 A 结构化]
  ↓
  /req-analysis（现状不动）
  ↓
  未决问题闸门 → 推进确认门
  ↓
  set_stage_source(req_dir, 2, "analysis.md", tool="req-analysis")
    → .req-meta.json: stage2_source = "analysis.md", stage2_tool = "req-analysis"

[分流 B office-hours]
  ↓
  探测 ~/.gstack/projects/$SLUG/*-design-*.md (按 mtime)
  ├── 找到 → 列文件名 + mtime → 问 PM「用这份 / 跑新 / 手动指定」
  │   ├── 用这份 → 进 [snapshot] 步骤
  │   ├── 跑新 → 提示 PM「在本 chat 跑 /office-hours，跑完告诉我新文件名」
  │   │         (PM 中断 stage-gate 去跑 office-hours，跑完通知 AI → resume)
  │   └── 手动指定 → PM 贴路径 → 进 [snapshot]
  └── 没找到 → 提示 PM「在本 chat 跑 /office-hours / 自行指定路径 / 切回 A」
              (resume 协议同上)

  [snapshot] 步骤（v4 新增）：
    1. 校验源路径可读
    2. AI 用 Read 工具读 office-hours 设计稿全文
    3. AI 用 Write 工具复制到 $ACTIVE_REQ_DIR/stage2-office-hours.md
       (顶部加注释：<!-- snapshot from ~/.gstack/projects/$SLUG/<filename> at <timestamp> -->)
    4. set_stage_source(req_dir, 2, "stage2-office-hours.md",
                        tool="office-hours",
                        origin="<原 ~/.gstack/ 绝对路径>")
       → .req-meta.json:
           stage2_source = "stage2-office-hours.md"  (req 内相对)
           stage2_source_origin = "<原绝对路径>"     (追溯)
           stage2_tool = "office-hours"
  ↓
  term-detector hook 扫 $ACTIVE_REQ_DIR/stage2-office-hours.md (req 内)
  ↓
  (stage-gate 不调 reviewer / 不调 check-open-questions.py)
  ↓
  推进确认门：「Stage 2 真相源已写入（office-hours 工具）。推进 Stage 3？」

下游 SKILL 读 stage 2 真相源：
  source = get_stage_source(req_dir, 2)  # 返回 req 内绝对路径
  content = source.read_text()           # A 分支 analysis.md / B 分支 stage2-office-hours.md
  → 喂 LLM
```

### §1.3 下游统一改造（Codex R3-M1 扩 grep）

**8 处下游硬编码** 全改 helper 调用：

| 调用点 | 当前 | v4 改后 |
|---|---|---|
| `prd-writing/SKILL.md` Required Inputs | 读 `$ACTIVE_REQ_DIR/analysis.md` | 读 `get_stage_source(req_dir, 2)` |
| `task-plan/SKILL.md` | 间接读 analysis.md | 同上 |
| `implementation-design/SKILL.md:66` | 读 analysis.md | 同上 |
| `close-task/SKILL.md` 偏差对账文案 | 提 analysis.md | 改"Stage 2 真相源" |
| `req-analysis/SKILL.md` 步骤 3.5 term-detector hook | 扫 analysis.md | 调 helper（A 分支扫 analysis.md / B 分支由 stage-gate 接管扫 stage2-office-hours.md）|
| **`task-spec/SKILL.md:54, :81`** lazy fallback | 提 analysis.md | 调 helper（Codex R3-M1 新发现）|
| **`doc-update/SKILL.md:41`** req 级原文定位 | 提 analysis.md | 调 helper（Codex R3-M1）|
| **`templates/task-plan.md.tmpl:7`** 依赖声明 | analysis.md | 通用术语"Stage 2 真相源"（Codex R3-M1）|
| **`templates/CLAUDE.md.tmpl:124`** stage 推断 | analysis.md | 通用化（Codex R3-M1）|
| **`req-transition.py:247`** transition 校验 | `req_dir / STAGE_OUTPUT_FILES[current]` | `get_stage_source(req_dir, current)` 调 helper（Codex T2 R3-C1 必修，否则 B 分支推不进 Stage 3）|
| `_shared/pm-view/input-flow.md` Stage 5/6 文案 | analysis.md | 改"Stage 2 真相源"通用术语 |

`scripts/_lib/stages.py STAGE_OUTPUT_FILES` 字典 schema **不动**（保留 `dict[int, str]` —— Codex T2 / R3-H1 命中：升级 list 会破现有 transition），v4 helper 用现有字典做 fallback。

### §1.4 helper 设计（v4 简化）

```python
# scripts/_lib/state.py 扩展（不新建 req_meta.py）
from .stages import STAGE_OUTPUT_FILES  # 不动 schema

def get_stage_source(req_dir: Path, stage_num: int) -> Path:
    """返回 stage N 真相源绝对路径。
    
    优先读 .req-meta.json 的 stage{N}_source 字段（req 内相对路径），
    缺失时降级 STAGE_OUTPUT_FILES[stage_num]（默认产物文件名）。
    """
    meta = read_req_meta(req_dir, strict=False)
    field = f"stage{stage_num}_source"
    if meta and field in meta:
        return req_dir / meta[field]   # req 内相对 → 绝对
    return req_dir / STAGE_OUTPUT_FILES[stage_num]   # fallback

def set_stage_source(req_dir: Path, stage_num: int, filename: str,
                     tool: str, origin: Optional[str] = None) -> None:
    """写 stage N 真相源到 .req-meta.json。
    
    Args:
        filename: req 内相对路径 (e.g. "analysis.md" / "stage2-office-hours.md")
        tool: 产生它的工具名 (e.g. "req-analysis" / "office-hours")
        origin: 可选 — 外部源原始绝对路径（追溯用，office-hours 场景下记 ~/.gstack/ 原始 path）
    """
    ...
```

Helper 通用 stage_num 参数：future-proof，未来 stage 3/5 加路径契约 0 helper 改动。

### §1.5 PM 视角（Z 路径体验包装）

PM 进 worktree 跑 `/req-stage-gate` 看到的就是**一次对话** —— brief 二次确认 + 工具选择 + 改 brief 退路。选完 AI 后台跑完 stage 1→2 推进。

stage 1/2 拆分被 hide 进 AI 内部，PM 不感知"stage 推进 N→N+1" 仪式。

---

## §2 与现役机制的关系（v4）

| 现役 mechanism | v4 关系 | 改动 |
|---|---|---|
| `req-stage-gate/SKILL.md` Stage 1→2 步骤 | **改** | brief 二次确认 + 分析方式选择门合二为一；A 走 /req-analysis + helper 写元数据；B 走 office-hours bridge + **AI 复制 snapshot** + helper 写元数据 |
| `req-analysis/SKILL.md` | **不动** | A 分支照常 |
| `new-req/SKILL.md` | **改**（§1.4 PM 拍定）| 砍选项 1，简化为单一"AI 引导写 brief"路径 |
| `gstack-office-hours/SKILL.md` | **不动** | gstack 上游 |
| `check-open-questions.py` | **不动**（Codex R3-M2 命中）| 不污染 req-aware；skip 由 stage-gate caller 控制（B 分支不调 lint）|
| `prd-writing` / `task-plan` / `implementation-design` | **改** | 读 helper |
| `close-task/SKILL.md` 偏差对账区文案 | **改文案** | "analysis.md" → "Stage 2 真相源" |
| `close-req/SKILL.md` 反向对齐 | **不动**（Round 1 已验不读 analysis.md）|
| **`task-spec/SKILL.md`** | **改**（Codex R3-M1 新发现）| line 54, 81 读 helper |
| **`doc-update/SKILL.md`** | **改**（Codex R3-M1 新发现）| line 41 读 helper |
| **`templates/task-plan.md.tmpl`** | **改文案**（Codex R3-M1）| line 7 改通用术语 |
| **`templates/CLAUDE.md.tmpl`** | **改文案**（Codex R3-M1）| line 124 改通用 |
| `scripts/_lib/term-detector.py` | **不动** | 接路径参数 |
| `scripts/_lib/state.py` | **加** | `get_stage_source(req_dir, n)` + `set_stage_source(req_dir, n, filename, tool, origin)` |
| `scripts/_lib/stages.py STAGE_OUTPUT_FILES` | **不动 schema**（Codex T2 R3-H1）| 字典保留 dict[int, str]；不升级 list；改注释扩双用途说明（transition 校验 + helper fallback）|
| **`scripts/req-transition.py:247`** | **改**（Codex T2 R3-C1 必修）| `req_dir / STAGE_OUTPUT_FILES[current]` → `get_stage_source(req_dir, current)`，确保 B 分支能推进 Stage 3 |
| `_shared/pm-view/input-flow.md` Stage 5/6 | **改文案** | analysis.md → Stage 2 真相源 |
| `.req-meta.json` schema | **加 3 字段** | `stage{N}_source`（req 内相对路径）+ `stage{N}_tool` + `stage{N}_source_origin`（追溯，B 分支限定）|
| `agents/analysis-reviewer.md` | **不动** | A 分支调；B 分支不调 |

---

## §3 实施清单

| vp | 任务 | 估时 |
|---|---|---|
| vp-1 | `scripts/_lib/state.py` 加 `get_stage_source(req_dir, n)` + `set_stage_source(req_dir, n, filename, tool, origin=None)` helper；复用 `stages.py STAGE_OUTPUT_FILES` 作 fallback（不升级 schema）；`stages.py` 改注释扩双用途说明 | 25 min |
| vp-2 | `req-stage-gate/SKILL.md` Stage 1→2：brief 二次确认 + 分析方式选择门合二为一；A 跑 /req-analysis + helper 写元数据；B 走 office-hours bridge | 50 min |
| vp-2b | `new-req/SKILL.md` 砍选项 1（§1.4 PM 拍定）| 20 min |
| vp-3 | office-hours bridge：探测 `~/.gstack/` → PM 选/跑新/手动指定 → **AI Read 源文件 + Write 复制到 `$ACTIVE_REQ_DIR/stage2-office-hours.md`** → helper 写 `.req-meta.json` (stage2_source / stage2_tool / stage2_source_origin) | 45 min |
| vp-4 | 下游 9 处改 helper 调用（Codex R3-M1 扩 grep）：prd-writing / task-plan / implementation-design / close-task 文案 / req-analysis 步骤 3.5 term-detector hook / **task-spec / doc-update / templates/task-plan.md.tmpl / templates/CLAUDE.md.tmpl** | 50 min |
| **vp-4b** | **`req-transition.py:247` 改 helper 调用**（Codex T2 R3-C1 必修）；确保 B 分支无 analysis.md 但有 stage2-office-hours.md 能推进 Stage 3 | 15 min |
| vp-5 | `.req-meta.json` schema 文档同步 + `INVARIANTS.md` 加 stage{N}_source / stage{N}_tool / stage{N}_source_origin 字段定义 | 15 min |
| vp-6 | 测试拆可执行回归项（Codex R3-M3）：<br>① `state.py` unit：`get_stage_source` 4 case（meta 有/缺/旧 req fallback/stage_num KeyError 防御）<br>② `state.py` unit：`set_stage_source` 3 case（新建 .req-meta.json / append / 写入失败）<br>③ `req-transition.py` 集成：A 分支 analysis.md 存在能推进 / **B 分支 stage2-office-hours.md 存在 + analysis.md 缺也能推进**（CRITICAL REGRESSION）/ 旧 req 兼容<br>④ snapshot 集成：B 分支复制后 `$ACTIVE_REQ_DIR/stage2-office-hours.md` 存在 + 内容与源相同<br>⑤ stage-gate chat 合并：A 分支 / B 分支用这份 / B 分支跑新 / B 分支手动指定 / B 分支切回 A<br>⑥ 下游 9 处读 helper：用 stage2_source=analysis.md / stage2_source=stage2-office-hours.md 各跑一遍验证<br>⑦ new-req 砍选项 1 回归：现有 new-req 测试不破 | 65 min |
| vp-7 | 文档同步：`CHANGELOG.md` 未发布段 + `RUNTIME.md`「当前位置」+ `docs/INDEX.md` + 落地后 `git mv` 设计文档归档为 `office-hours-跨stage1-2集成.md` | 15 min |

**总估时**：~5h（vp-1 / vp-3 / vp-6 部分可并发：vp-1 完后 vp-3 / vp-4 / vp-4b 可并行）

**测试基线**：当前 398 / 0；落地后预期 ≥ 405 / 0（vp-6 加 ~7 个 case）

---

## §4 砍掉的机制清单（防 review 加回来）

| 机制 | 为什么砍 |
|---|---|
| B 分支跑 analysis-reviewer | office-hours 含 Cross-Model Perspective + Spec Review Loop；PM 显式 trade |
| B 分支跑第一性原理 4 层 | office-hours 等价覆盖；强补违反 §0.1 |
| B 分支跑 attachments hook | §0.4.8 D-iii 独立 |
| B 分支跑增量分析基线读取 | §0.4.7 trade |
| B 分支跑未决问题闸门 | 闸门是 /req-analysis 输出契约；office-hours `Open Questions` prose 不带占位（§0.4.4）|
| **v0 复制方案中 v1 反转的"office-hours 会变"论据** | **v4 fact-check 推翻**（§0.2.5）：office-hours 文件名带 datetime 戳、Supersedes 是新文件链、review loop 只在 approval 前 — 文件生成后冻结；v1 论据基于错误前提，反转 v1 决策回到复制 |
| **v1 引用 + metadata + follow 方案** | v2 review 否决（"架构不灵活" + ~6-8h 改 N SKILL follow） |
| **v3 引用 `~/.gstack/` 外部路径** | **Codex T1 R3-C2 命中**（v4 反转）：req 自包含原则（git / CI / 跨机器 / 归档 / consumer 仓全维度），不能引用仓外；改 snapshot 进 req |
| **D2 Round 2 复用 STAGE_OUTPUT_FILES 字典** | **Codex T2 R3-H1 命中**（v4 反转）：升级 dict→list 破 req-transition.py:247 类型；改新建独立 helper 不动现有字典（保 transition 校验 + helper fallback 双用途，但 schema 不动）|
| **D1 Round 3 schema 升级 dict[int, str] → dict[int, list[str]]** | 同上（v4 反转）|
| **D2 Round 3 check-open-questions.py 加 stage2_tool 读取** | **Codex R3-M2 命中**（v4 反转）：doc lint 是通用 utility（被 project-solution 用 --require-section 调），不该 req-aware；skip 由 stage-gate caller 控制（B 分支不调 lint）|
| Supersedes 链自动跟进 | §0.4.6 trade；PM 想换版本 → 回 Stage 2 重做 |
| AI 主动调起 `/office-hours` | new-req 边界（§0.4.10）|
| 保留 `/new-req` 选项 1 | §1.4 PM 拍定砍 |
| Stage 2 规范化 schema contract（office-hours prose → 字段化）| **Codex R3-H2** → §0.4.12 DEFER；v4 §5 待验项，相信 LLM 全文喂消化能力 |

---

## §5 风险与待验

### §5.1 待验项

1. **office-hours 章节结构 LLM 派生 §六 实际效果**（**Codex R3-H2 DEFER**）—— v0 时已 verify prd-writing 是 LLM-based 全文喂、章节结构 LLM 能消化；但 office-hours prose 不保证有 In Scope / 功能分解结构。**消费仓真实 req 验证一次** — 用 office-hours 风格 stage2-office-hours.md 跑 prd-writing 产 PRD §六，看派生质量。如不行，再引入规范化 schema contract。
2. **`resume 协议`实施细节**（**Codex R3-H3 PARTIALLY ACCEPT**）—— v4 §1.2 流程图含 resume 路径（B 分支没找到 → 提示 PM 跑 → 等通知 → snapshot），vp-2 实施时 stage-gate **状态机** 要明确：PM 中断 stage-gate 去跑 office-hours 后，AI 怎么"等"（在 chat 里等下一句通知）+ PM 跑完通知 AI 用什么句式（"跑完了" / 给路径 / 等）。可能需要约定 chat 提示词。
3. **新增 `.req-meta.json` 字段对旧 req 兼容**：helper 降级 fallback 已含；vp-6 ③ 覆盖。
4. **snapshot 复制磁盘 / 权限失败的 fallback**：bridge 步骤 1 校验源可读 + Write 失败时 helper 抛错 + stage-gate 提示 PM；不静默吞。

### §5.2 风险

| R# | 风险 | 缓解 |
|---|---|---|
| R1 | snapshot 后原 `~/.gstack/` 文件被 PM 删 | snapshot 已在 req 内，下游不受影响；`stage2_source_origin` 字段失效但仅追溯用，无副作用 |
| R2 | `.req-meta.json` 写入失败 | helper `set_stage_source` 抛错 + stage-gate 显式提示 |
| R3 | PM 手动指定的源路径不存在 / 不是 markdown | bridge 步骤 1 校验可读 |
| R4 | snapshot 文件名冲突（PM 多次跑 B 分支同 req）| snapshot 总写 `$ACTIVE_REQ_DIR/stage2-office-hours.md` 固定文件名；多次跑覆盖（PM 主动选 = 主动覆盖）|
| R5 | 下游 helper 调用不一致 / 9 处 grep 漏改 | vp-6 端到端覆盖 |
| R6 | `req-transition.py:247` 改 helper 后旧 req 兼容性 | vp-6 ③ 旧 req 兼容测试覆盖 |
| R7 | v3 体验包装 chat 合并输出过长 | vp-2 控制；摘要 ≤ 3 行；选项段独立 |
| R8 | resume 协议 PM 中断后 chat 长时间断（PM 关 chat 几天）| PM 重开 chat 跑 `/req-stage-gate` 续走 stage-gate 续跑模式（现仓已有机制）|

---

## §6 实证支撑

PM 表述（本会话 2026-05-24）：

> "officehour 可能会在两个阶段被调用，感觉不太合理"
> "从用户视角来看，就是用户提需求，然后讨论，讨论工具 2 选 1"
> "原来的设计是用户一开始就会调用 officehours"
> "我觉得总体搞复杂了 …… 架构不灵活"
> "你先帮我看看 office hours 的产出，到底会不会变" → 触发 v4 fact-check 反转

**Fact-check 证据**：
- `~/.claude/skills/gstack-office-hours/SKILL.md:1575` `DATETIME=$(date +%Y%m%d-%H%M%S)`：文件名带时间戳
- `:1581-1583` Supersedes 是新文件 frontmatter 字段，老文件原封不动
- `:1708-1749` Spec Review Loop 只在 Write 后 PM approval 前跑 max 3 次 Edit，approval 后 office-hours skill 不再 touch 该文件
- 上游 gstack 升级 (preamble 显示 UPGRADE_AVAILABLE 1.42.2.0 → 1.44.0.0) 影响 template，不改已生成的老文件

**Codex outside voice 证据**（Round 3）：
- `req-transition.py:247` 硬要求 STAGE_OUTPUT_FILES[2] = "analysis.md" → B 分支推不进 stage 3（R3-C1）
- ~/.gstack/ 路径不进 git / CI / 跨机器 / 归档 → req 不自包含（R3-C2）
- STAGE_OUTPUT_FILES 双语义复用 + schema 升级 = `req-transition.py:247` 类型错（R3-H1）
- 下游硬编码 analysis.md 还在 task-spec / doc-update / templates 多处（R3-M1）

其他 EVIDENCE：
- `TODOS.md:62` HW1（TTHW office-hours 拖时间）
- `skills/new-req/SKILL.md` 明示边界（AI 不替 PM 调）

---

## §7 决策路径（v0 → v1 → v2 → v3 → v4）

### v0 — 复制方案（被 v1 错杀）
office-hours 原文复制到 analysis.md。预估 ~3h。**v1 否决理由"office-hours 上游会变" → v4 fact-check 推翻该理由**。

### v1 — 引用 + follow 方案
analysis.md 写指针 + 下游 N SKILL 加 follow。预估 ~6-8h。v2 否决（"架构不灵活"）。

### v2 — 路径契约（Stage 2 单一）
`.req-meta.json` 加 stage2_source 字段 + helper + 5 SKILL 改路径读取。预估 ~3h。

### v3 — 路径契约 + 体验包装（Stage 1+2）
v2 基础上加 PM 视角"一次需求讨论" 体验包装；B 分支引用 ~/.gstack/ 路径。预估 ~4h 5min。Round 2 ACCEPT D1 (helper 通用) + D2 (复用 STAGE_OUTPUT_FILES) + Round 3 ACCEPT D1 (schema dict→list) + D2 (check-open-questions.py req-aware)。

### v4 — snapshot 复制 + 体验包装 + Codex outside voice 修复（**当前**）

**触发**：
1. Round 3 D3 cross-model tension T1：Codex 推 snapshot 复制 vs v3 引用
2. PM 提问 "office-hours 产出到底会不会变"
3. AI fact-check 现仓 office-hours SKILL.md → 推翻 v1 "office-hours 上游会变" 错误前提
4. **v1 决策基于错误前提，整个 v0→v1→v2→v3 路径是绕弯设计；v0 复制方向才是合理的，被 v1 错杀**

**AI 反思**：之前 5 轮 review (Round 1 D1/D2 + Round 2 D1/D2/D4/D5 + Round 3 D1/D2) 都没识破 v1 fact 错误。Codex outside voice + PM 提问触发 fact-check 才推翻。**Round 3 价值 = 命中前 5 轮 blind spot**。

**v4 改动 vs v3**：
1. B 分支 **snapshot 复制** office-hours 设计稿到 `$ACTIVE_REQ_DIR/stage2-office-hours.md`（req 自包含）
2. `stage2_source` 改 req 内相对路径；新加 `stage2_source_origin` 字段（追溯）
3. 砍 D2 Round 2 复用 STAGE_OUTPUT_FILES（Codex R3-H1：升级 list 破 transition）
4. 砍 D1 Round 3 schema 升级 dict→list
5. 砍 D2 Round 3 check-open-questions.py req-aware（Codex R3-M2：doc lint 不污染）
6. 下游 grep 扩到 9 处（Codex R3-M1 + req-transition.py）
7. 新增 vp-4b 修 `req-transition.py:247`（Codex T2 R3-C1）
8. vp-6 拆可执行回归项（Codex R3-M3）

**v4 估时**：~4h 5min（v3）→ ~5h（v4 加 vp-4b + grep 扩 + 测试加强）

**v4 架构红利**（v0/v1/v2/v3 都没有的）：
- req 自包含：git / CI / 跨机器 / 归档 / consumer 仓全维度 都行
- 未来 Stage 3/5 加路径契约：helper 通用 stage_num 参数 + STAGE_OUTPUT_FILES 不动 schema，零冲突
- office-hours 上游演化：snapshot 在 req 内不受影响（req = 那时决定的快照）

---

## §X Review Findings

> Round 1 + Round 2 + Round 3 全集；**SUPERSEDED / 反转表示在更新版本里 finding 自然消失或方向反转**。

### Round 1 — 2026-05-24 — plan-eng-review

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| F1 | Critical | stage-gate 调起 /office-hours 与 new-req 边界冲突 | §0.3 | new-req | **ACCEPT A** — v3 §1.2 统一"提示 PM 自跑" |
| F2 | Low | close-req 是否读 analysis.md | NONE | grep | **CLOSE** |
| F3 | Low | task-plan 不直接 grep analysis.md | NONE | grep | **CLOSE** |
| F4 | Medium | analysis.md 双 Open Questions section 冲突 | §0.3 | regex | **SUPERSEDED**（v2+ 路径契约下 B 分支根本不写 analysis.md → v4 改为 stage2-office-hours.md，仍无 Open Questions 转换问题）|
| F5 | Medium | bridge 转换题号 / regex 严格匹配 | §0.3 | check-open-questions.py | **SUPERSEDED** — v2+ 不写 analysis.md / 不跑闸门 |
| F6 | Low | TODOS.md HW1 加固 §0.1 | §0.1 | TODOS.md:62 | **CLOSE** |
| F7 | Low | new-req 选项 1 时机区分 | §0.2 | new-req | **SUPERSEDED** — v3 §1.4 PM 拍定砍选项 1 |
| F8 | Critical | "架构不灵活" | §0.3 | PM | **ACCEPT** — v2 路径契约 |
| F9 | Medium | v1 引用 → office-hours 删 dangling | NONE | v1 | **SUPERSEDED** — v4 snapshot 进 req 解决 |
| F10 | Medium | v2 测试端到端 | NONE | test review | **ACCEPT** — vp-6 |

### Round 2 — 2026-05-24 — plan-eng-review

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| R2-F1 | Medium | v2 helper 硬绑 stage 2 | §0.3 | grep | **ACCEPT A** (D1 R2) — v4 helper 通用 `get_stage_source(req_dir, n)` |
| R2-F2 | Medium | v2 STAGE_DEFAULT_OUTPUTS vs stages.py STAGE_OUTPUT_FILES 重复 | DRY | stages.py:24 | **ACCEPT A** (D2 R2) → **v4 REVERSED**（Codex R3-H1 命中升级 list 破 transition；改不复用、helper 用现有字典做 fallback 但不升级 schema）|
| R2-F3 | Critical | "office-hours 调两次不合理" | §0.3 体验根因 | PM | **ACCEPT B + Z** (D4/D5 R2) — D-i 升 v3 体验包装；D-ii / D-iii 独立 |

### Round 3 — 2026-05-24 — plan-eng-review (Claude + Codex outside voice)

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| R3-F1 | Medium | stages.py STAGE_OUTPUT_FILES 字典只含 stage 1/2/3/5；stage 4/6/7 forward-compat | NONE | prior learning align-same-dir | **ACCEPT B + multi-path** (D1 R3) → **v4 REVERSED**（Codex R3-H1 命中：升级 list 破 req-transition.py:247 类型）；改不动 schema，helper 通用 stage_num 参数 + future-proof 在 helper 层 |
| R3-F2 | Medium | "B 分支不跑闸门" prose → script lint | prior learning prose-vs-script | check-open-questions.py | **ACCEPT A** (D2 R3) → **v4 REVERSED**（Codex R3-M2 命中：doc lint 不该 req-aware）；改由 stage-gate caller 控制 skip（B 分支不调 lint），prose 仍标"B 分支由 caller 跳过"但 prose 写在 stage-gate SKILL.md 而非 doc lint 内 |
| **R3-C1** | **Critical** | **B 分支推不进 Stage 3：req-transition.py:247 硬要求 analysis.md** | §0.3 + Codex T2 | `req-transition.py:247` + `stages.py:24` grep | **ACCEPT**（v4 vp-4b 必修）— `req-transition.py:247` 改 `get_stage_source(req_dir, current)` 调 helper；B 分支只产 stage2-office-hours.md 也能推进 |
| **R3-C2** | **Critical** | **"路径契约"指向仓外文件，不进 git/CI/跨机器/归档** | §0.3 架构根因 (v4 新) | git/CI 架构常识 + fact-check office-hours mutability | **ACCEPT** — v4 整体反转 v3 → v4 snapshot 复制到 `$ACTIVE_REQ_DIR/stage2-office-hours.md`，req 自包含 |
| **R3-H1** | **High** | **STAGE_OUTPUT_FILES 复用 + schema 升级 dict→list 冲突 req-transition.py:247** | DRY 表面 + 双语义实际冲突 | `req-transition.py:247` grep | **ACCEPT** — v4 不复用字典作 schema 升级；helper 用现有 dict[int, str] 字典做 fallback，不升级 |
| R3-H2 | High | office-hours prose 不保证有功能分解 / In Scope 结构 prd-writing 派生 | §0.3 | prd-writing:104/125/127/530 | **DEFER** — v4 §5 待验项；相信 LLM 全文喂消化（v0 已 ACCEPT），消费仓真实 req 验证；如不行再引入规范化 schema contract |
| R3-H3 | High | "PM 视角单次交互 / AI 后台自动跑"过度宣称（B 分支没文件时 PM 实际中断去跑 office-hours）| §0.3 | plan:59 vs plan:95 矛盾 | **PARTIALLY ACCEPT** — v4 §1.2 流程图含 resume 路径；vp-2 实施时明确 stage-gate 状态机 + PM 通知句式约定（§5.1.2 待验）|
| R3-M1 | Medium | 下游硬编码 analysis.md 漏 task-spec / doc-update / templates 多处 | NONE | grep task-spec:54/81, doc-update:41, templates/task-plan.md.tmpl:7, templates/CLAUDE.md.tmpl:124 | **ACCEPT** — v4 vp-4 扩 grep 到 9 处 |
| R3-M2 | Medium | check-open-questions.py 不该 req-aware | NONE | project-solution --require-section | **ACCEPT** — v4 反转 D2 Round 3；skip 由 stage-gate caller 控制 |
| R3-M3 | Medium | 测试计划像愿望不像可执行回归 | NONE | tests/run-all.sh shell suite | **ACCEPT** — v4 vp-6 拆 7 个具体回归项 |

**汇总**：
- ACCEPT 12 条（Round 1 F1/F8/F10、Round 2 R2-F1/F2/F3、Round 3 R3-C1/C2/H1/M1/M2/M3）
- CLOSE 3 条（F2 / F3 / F6）
- SUPERSEDED 6 条（F4 / F5 / F7 / F9、v4 REVERSED of R2-F2/R3-F1/R3-F2）
- DEFER 1 条（R3-H2）
- PARTIALLY ACCEPT 1 条（R3-H3）

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-24 | v0 草稿 + §0 共写锁定 | 等 review |
| 2026-05-24 | review D1 → v0 → v1（复制 → 引用 follow）| 3h → 6-8h |
| 2026-05-24 | review D2-v2 → v1 → v2（架构不灵活 → 路径契约）| 6-8h → 3h |
| 2026-05-24 | Round 2 D1 / D2：helper 通用 + 复用字典 | forward-compatible 升级（部分被 v4 反转）|
| 2026-05-24 | Round 2 D4 (B) / D5 (Z) → v2 → v3：scope 扩 stage 1+2 + 体验包装 | 3h → 4h 5min |
| 2026-05-24 | §1.4 PM 拍定：砍 /new-req 选项 1 | +20 min vp-2b |
| 2026-05-24 | Round 3 D1 / D2：multi-path schema + script lint（v3 → v3.5 微调）| 暂存（被 v4 反转）|
| 2026-05-24 | **Round 3 D3 Codex outside voice T1 + PM "office-hours 产出会不会变" 提问 → AI fact-check** | **v3 → v4 整体反转**：snapshot 复制方案 + 反转 Round 2 D2 / Round 3 D1 / Round 3 D2 |
| 2026-05-24 | **v4 锁定**：snapshot 复制 + Codex 8 finding 修复（ACCEPT 12 / DEFER 1 / PARTIALLY ACCEPT 1）| 估时 ~5h；测试 ≥ 405/0 |

---

**End of D-i：office-hours 跨 Stage 1+2 集成 v4**

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 1 | issues_found | 8 findings (2 Critical / 3 High / 3 Medium) → 反转 v3 → v4 snapshot 复制方案；ACCEPT 6 / DEFER 1 / PARTIAL 1 |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 3 | CLEAR (PLAN) | 21 issues / 0 critical_gaps；ACCEPT 12 / CLOSE 3 / SUPERSEDED 6 / DEFER 1 / PARTIAL 1 |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **CODEX**: 8 findings (T1 复制 vs 引用 / T2 STAGE_OUTPUT_FILES 复用 / T3 下游漏 grep / R3-H2 语义契约 DEFER / R3-H3 resume 协议 PARTIAL / R3-M1 下游扩 grep / R3-M2 doc lint 不污染 / R3-M3 测试拆回归项)；T1 触发 v3 → v4 整体反转
- **CROSS-MODEL**: Codex + Claude (本 review) 一致命中"v3 引用 ~/.gstack/ 不进 git/CI/跨机器" → ACCEPT v4 snapshot；fact-check 反转 PM v1 "office-hours 上游会变"错误前提（office-hours 文件名带 datetime 戳生成后冻结）
- **UNRESOLVED**: 1（R3-H3 resume 协议状态机细节 vp-2 实施时明确）
- **VERDICT**: ENG CLEARED — v4 锁定 / 可进实施。下一步 vp-1 → vp-7（~5h 估时）+ vp-6 测试拆 7 个可执行回归项（基线 398/0 → 预期 ≥ 405/0）
- **REVIEW COMPLETE: 11/11 sections**（CLAUDE.md 项目级强制约束完整跑：Preamble / Design Doc Check / Step 0 Scope Challenge / Section 1 Architecture / Section 2 Code Quality / Section 3 Tests (coverage diagram + 9 GAP) / Section 4 Performance / Outside Voice (Codex) / Required outputs / Implementation Tasks JSONL / Completion + Review Log + Dashboard + Plan File Review Report。**0 跳过项 / 0 BLOCKER 降级**）

