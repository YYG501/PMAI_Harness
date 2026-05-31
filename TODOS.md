# TODOS

> 只放**开放项**：待决策 / 已 defer 待触发 / 阻塞中。
> 条目一旦实施完成或被废弃，**从本文件移除** —— 溯源由 git history + `CHANGELOG.md` + `docs/归档/` 设计文档承担，不在 TODO 清单里留「已完成存根」。
>
> **2026-05-30 stale-sweep**：清掉 office-hours 六步重构作废的 pre-reshape 存根（旧 7-stage / `solution.md` / `doc-update` 沉淀 / task-spec PM 视图 revise / office-hours 六问 / TTHW stage 5-6 / v2 状态物化-已落地 等）。git history（本次 commit 前）有完整旧清单。

---

## 六步重构后续（2026-05-30 survey）

### 真 req build spike 端到端验证（六步落地唯一余下项）

- **What**：build 三道审的**脚本编排已固化**（`scripts/build-audits.py` resolve + synthesize；覆盖审计 agent / 视觉门 gstack skill 仍 LLM 调起）。差的是在**一个真实 req** 上跑一遍：三道审产 conformant 结果 json、dev server 复用 timing、三审合成 + 自动托管 worktree 闭环。脚本回归齐（`test-build-audits.sh` 7 例），但 LLM 调起那两道 + 整 loop 没在真需求上验过。
- **触发**：下一个真实 req 用新 build 路径跑，当 **build spike**。
- **Context**：`docs/设计/PMAI重构-实施清单.md` §6 阶段 2 + §2 gstack 接入表；编排 `scripts/build-audits.py`。

### 消费仓 sync（合 main 前确认）

- **在飞旧 req 状态值越界**：旧 7-stage req（停在 stage 5-7）在新机器（`MAX_STAGE=4`）下越界。**迁移脚本 `migrate-reqs-to-6step.py` 已落地**（含 active stage∈{3,4} 歧义警告）—— 消费仓同步前跑一次解越界、按歧义警告手工确认。CLAUDE.md.tmpl 六步重写 + attachments rewire 均已做（见 `CHANGELOG.md`）。

> **注**：§7.A 站点爬（`scrape-prototype`）/ §7.B 对齐线上（`align-to-live`）/ §7.C checks 引擎（`checks-diff.py`）**已于 `reshape-office-hours` 分支落地**（见 `CHANGELOG.md`），从本清单移除；设计真相源仍在 `docs/设计/PMAI重构-实施清单.md` §7。

---

## 框架分发 / 升级

### pmai sync 自动化（旧 UP）

- **What**: 框架资产进已装消费仓的**增量同步**当前靠 `框架同步-SOP.md`（手动、已标 DEPRECATED）。`pmai install` / `pmai upgrade` 已落地（2026-05-26 v1.1）；剩 `pmai sync`（已装消费仓拉框架增量）自动化。
- **触发**: 结构稳定后 / 下游有第二人用框架时。
- **Context**: `docs/设计/框架分发与全局安装.md`。

---

## 探测档 / 结构（YAGNI，待触发）

- **TD-1 探测档 → 完整档（restructure-suggest）**：detect 自动写 CLAUDE.md「工程结构约束」段但不主动给改造建议；已有项目结构 vs PM 意图错配时（如 ExampleConsumerApp system 风格 + 想做原型）靠 PM 自读判断。加 `compare-structure-to-intent.py` + `restructure-suggest` skill。**触发**：PM 实际撞到「想知道现状 vs 意图差距」≥ 2 次。
- **TD-3 多 prototype-root（monorepo）**：detect 仅识别第一个 prototype-root；monorepo / 多产品仓未来按 `apps/<app>/src/` 分别管理。**触发**：实际服务过 monorepo。
- **TD-4 detect schema 版本号 + migration**：schema 标 `schema_version: 1` 但无 migration 脚本，演进时旧 CLAUDE.md auto-detected 段不自动升级。**触发**：真出 `schema_version: 2`。

---

## DX / onboarding（低优先）

- **gstack 硬依赖 README 未提**（旧 I1）：PM 第一次跑 init 才知道要装 gstack。
- **错误信息用 INVARIANTS 编号**（旧 DB1）：失败时 `I-CT7` / `I-AD5` 等编号对 PM 不友好 —— PM 视图 banner / 禁工程黑话已部分覆盖，残留在脚本 stderr。

---

**注**：TD-5（DESIGN.md vs CLAUDE.md「工程结构约束」边界）已落到 CLAUDE.md.tmpl 段顶注释，不进 TODOS。
