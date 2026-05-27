<!--
本文件由 docs/设计/_模板-方案.md 起手。
§0 v0 于 2026-05-21 PM+AI 共写锁定（曾含 reopen）；v1（2026-05-21，plan-eng-review D5 决策）把
reopen 拆出为独立 D-task docs/设计/reopen通道.md，本文档收敛为 accept 闸门单 vp。
触发来源：req-006 task-001-ops-log-pages 的 close-task 被 I-CT7 挡下（2026-05-21 调查）。
-->

# accept 闸门：执行事件校验前移 (v1)

> **状态**：§0 锁定 v1 / §1+ §X review 落定 / **已实施并验证（test-task-transition 32/0、全量 389/0）**
> **日期**：2026-05-21
> **作者**：PM + AI

---

## §0 原始痛点（PM + AI 共写，已锁定，后续 review **不可反向修改**）

> ⚠️ 任何后续 review / autoplan / dual voice 都**不能**给本节加东西、不能重新定义痛点。
> 如需更新 §0 → PM 主动决策并重置版本号。

### §0.1 痛点（1-3 句）

I-CT7（事件流审计）能抓"task 没走执行通道"，但在 close-task —— 整条流程最后一步 —— 才收网。task 的执行阶段没有任何前置机制强制它真走过 `/pmai-task-execute`；唯一兜底来得太晚 —— task-001 的 work 全做完、PM 已验收，却卡在 merge 前一刻才被发现执行阶段从未 instrument。

### §0.2 触发场景

| # | 场景 | 实证证据 |
|---|---|---|
| 1 | task 执行期完全未走 `/pmai-task-execute`，事件流缺 execution 事件，直到 close-task I-CT7 才发现 | ExampleConsumerApp req-006 `task-001-ops-log-pages`：事件流仅 2 条 `status_changed`，3.5h 执行期零事件；close-task I-CT7 BLOCK；代码与产物均真实齐全 |

### §0.3 根因

`task-transition.py` 处理「执行中→已完成」（PM 验收）时，不校验事件流是否有 execution 事件。`/pmai-task-execute` 因此非强制、可被整段跳过；唯一兜底是 close-task 末尾的 I-CT7 —— 检查点离故障点（执行期）太远，发现时 task 已终态。

### §0.4 不解决什么

| # | 衍生场景 | 为什么不在范围 |
|---|---|---|
| 1 |「已完成」终态相关的回退 / 证据修复（原 v0 根因 B）| **D5 拆出**为独立 D-task `docs/设计/证据修复命令.md`；2026-05-21 PM 拍板选乙（evidence-repair 命令，非 reopen 状态机回退）|
| 2 | v2 状态物化重做 | TODOS.md 独立条目 |
| 3 | 改 I-CT7 / I-CT8 判定逻辑 | I-CT7 是对的；本方案只前移其核心校验、让 I-CT7 退化为兜底 |

---

## §1 方案主体

### §1.1 方案（一句话）

在 `task-transition.py` 的 `check_preconditions()`「执行中→已完成」分支（现 L206-247，已有"文档偏差"/"自审记录"两项校验）追加第三项：事件流须有至少一条 execution 事件（`execution_started` / `execution_manual_completed`），否则拒绝转移、提示先走 `/pmai-task-execute`。I-CT7 在 close-task 保留为兜底。

### §1.2 review 决策（D1 / D2 / C8 — 已落定）

- **D1**：事件流文件缺失 / 不可读 → **fail-closed**（拦），与 I-CT7（`audit-task-events.py` 对"文件不存在"一律视为违规）同口径。
- **C8**（codex finding 8 补强）：malformed JSON 行同样按 fail-closed —— 若事件流有坏行**且**未在好行中找到 execution 事件，拦下（无法确定坏行是否就是 execution 事件）。
- **D2**：`EXEC_EVENT_TYPES` 常量 + `has_execution_event()` 谓词抽到 `scripts/_lib/`，accept 闸门与 I-CT7（audit-task-events.py）共用同一定义，杜绝两道闸门口径漂移。

### §2 与现有机制的关系

- **改**：`task-transition.py` `check_preconditions()`「执行中→已完成」分支
- **加**：`scripts/_lib/events.py`（共享 exec-event 谓词）；`audit-task-events.py` 改用之
- **保留**：I-CT7 / I-CT8（close-task 兜底不变）；pre-commit hook `check-status-direct-edit.py`（正交）
- **砍**：无

### §3 实施清单

- **vp-1a**：抽 `scripts/_lib/events.py`（`EXEC_EVENT_TYPES` + `has_execution_event(events)`）；`audit-task-events.py` 改 import。~15 行。
- **vp-1b**：`check_preconditions` 加 accept 闸门（按 task stem 定位 `.runs/events/<stem>.jsonl`、load、调 `has_execution_event`、fail-closed 含 malformed）。~10-15 行。
- **测试**（4 新 + 1 组 regression 修复）：
  1. 事件流有 `execution_started` → 放行
  2. 事件流有 `execution_manual_completed` → 放行
  3. 事件流无 execution 事件 → 拦
  4. 事件流文件缺失 / 含 malformed 行且无 execution 事件 → 拦（fail-closed）
  5. **REGRESSION（CRITICAL，随 vp-1 同 PR）**：vp-1 改了「执行中→已完成」的既有行为，`tests/test-task-transition.sh` 里"执行中→已完成 成功"用例（`test_allow_missing_review_event` :182 及同类）的 fixture 没 seed execution 事件，会全 FAIL。修复：加 `fixture_seed_execution_started` helper（仿 `fixture_seed_full_event_stream` fixture.sh:411，只 seed 到 execution_started），逐个 audit 受影响用例改用之。

### §4 砍掉的机制清单

无。

### §5 实证支撑

`ExampleConsumerApp/.runs/events/task-001-ops-log-pages.jsonl`（补记前 2 行）+ close-task I-CT7 BLOCK 实况。生产唯一 accept 路径已查证：`task-submit/SKILL.md:191` → `task-transition.py --to 已完成`；`task-transition.py` 是状态字段与 `status_changed` 事件唯一合法写入者；闸门加进 `check_preconditions` 无合法路径绕过。

---

## §X Review Findings — /plan-eng-review 2026-05-21

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| D1 | High | accept 闸门读事件流，缺失/不可读行为未定义 | §0.3 | task-transition.py 无读事件流逻辑 | **ACCEPT** — fail-closed |
| D2 | Medium | exec-event 判定与 I-CT7 重复 → 口径漂移 | §0.3 | audit-task-events.py:112-113 已有同逻辑 | **ACCEPT** — 抽 `_lib` 共享 |
| C8 | Medium | malformed JSON 行行为未定义（codex finding 8）| §0.3 | audit `load_events` 静默跳坏行 | **ACCEPT** — 并入 fail-closed |
| T1 | High (regression) | vp-1 打破现有"执行中→已完成 成功"测试 | §0.3 | test-task-transition.sh fixture 未 seed execution 事件 | **ACCEPT** — fixture helper + 改用，CRITICAL |
| T2 | Medium | §3 原测试数严重低估（1 → 4 + regression）| §0.3 | Section 3 覆盖率诊断图 | **ACCEPT** — 4 新测写入 §3 |

**汇总**：ACCEPT 5 / DEFER 0。Outside voice（codex）9 finding：1/2/3/4/5/6/7 针对 reopen → **D5 决策拆出**（见 `reopen通道.md` §5 预载）；finding 8 → C8 已并入；finding 9 → T2 印证。

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-21 | §0 v0 共写锁定（含 reopen vp-2）| — |
| 2026-05-21 | plan-eng-review D5：reopen 拆出独立 D-task；§0 → v1，本文档收敛为 accept 闸门单 vp | scope −1 vp |
| 2026-05-21 | plan-eng-review 完成（D1/D2/C8/T1/T2 落定）| §1+/§3/§X 定稿，待实施 |
| 2026-05-21 | T1-T4 实施完成：`_lib/events.py` + `check_preconditions` accept 闸门 + `audit-task-events.py` 共用 + regression fixture + 4 新测 | accept 闸门上线，全量 389/0 |

---

**End of accept 闸门：执行事件校验前移 v1**
