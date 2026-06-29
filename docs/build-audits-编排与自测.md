# build 三道审编排（`scripts/build-audits.py`）参考 + 自测留档

> **性质**：`/pmai-build` 三道审的脚本级编排参考 + 2026-05-31 自测记录。
> **落地状态**：脚本 + 回归（`tests/test-build-audits.sh`）已落地；真实业务模块端到端验证见 `TODOS.md`。

---

## 1. 它管什么 / 不管什么（LLM vs 脚本边界）

build 完三道机器审，各查一种病、对照不同参照物，合成一份给 PM；PM 拍板是唯一决策点。

| 道 | 查 | 工具 | 参照 |
|---|---|---|---|
| ① 覆盖审计 | 建全没 | `coverage-reviewer` agent（白纸视角、非自审） | 模块 `spec.md` |
| ② 视觉门 | 长得对不对 | gstack `/design-review`（只截图不改） | `DESIGN.md` |
| ③ 行为审 | 跑得通不通 | 浏览器 / 脚本化验收 | 模块 `spec.md` 派生的验收流程 |

**覆盖审计是 agent、视觉门是 gstack skill —— 都是 LLM 驱动，脚本没法当子进程调起。** 所以 `build-audits.py`
**不"跑"三道审**，只固化能确定性固化的部分（这几块原本靠 AI 自觉、易漏跑/各起 dev server/不合成）：

- `resolve <task>`：校验输入（范围清单 / `prototype/` / dev 端口）→ 缺则 **fail-loud**；建 `.pm-workflow/audits/<模块>/` 内部审计目录；打印三道 manifest（每道读什么、把规范化结果写哪、dev server 复用约定）。
- `synthesize <task>`：读三道规范化结果 → **校验三道齐全**（漏跑 fail-loud 点名）→ 合成 `synthesis.md` + 机器 summary（计数 + `gate=clean|needs-review`，门禁仅作给 PM 的**建议**、不替 PM 拍板）。

接线：`skills/build/SKILL.md` 在三道审前跑 `resolve`，每道审各写规范化 json，最后调 `synthesize`。

## 2. 输入契约（三道规范化结果，build 跑完每道写一份）

| 文件（`<worktree>/.pm-workflow/audits/<模块>/`）| schema |
|---|---|
| `coverage.json` | `{"items":[{"name","status":"built\|missing\|degraded","note"}]}` |
| `visual.json` | `{"findings":[{"severity":"P0\|P1\|P2","desc"}]}`（空 findings = 视觉通过）|
| `behavior.json` | `{"status":"pass\|fail\|skipped","passed":int,"total":int,"note"}` |

`gate = needs-review` 当：有 missing/degraded、或有视觉 finding、或行为 fail；否则 `clean`。

## 3. 自测留档（2026-05-31，仿真数据跑通）

### resolve 输出（manifest 摘录）

```
[build-audits] 输入已校验，内部审计目录已就绪：.../.pm-workflow/audits/<模块>
按下面 manifest 跑三道审，各写规范化结果：
  ① 覆盖审计（coverage-reviewer agent，静态读码、不需 dev server）→ 写 .../.pm-workflow/audits/<模块>/coverage.json
  ② 视觉门（gstack /design-review，只截图不改；复用同一次 dev server）→ 写 .../.pm-workflow/audits/<模块>/visual.json
  ③ 行为审（浏览器 / 脚本化验收；复用同一次 dev server）→ 写 .../.pm-workflow/audits/<模块>/behavior.json
  dev server：覆盖审计不需要；视觉门 + 行为审复用 build 阶段启动的同一个（端口候选 3000, 5173），别各起各的。
```

### synthesize 机器 summary（needs-review 场景：漏建 1 + 降级 1 + 视觉 2 + 行为 fail）

```json
{"coverage":{"built":2,"missing":1,"degraded":1},"visual":{"P0":0,"P1":1,"P2":1,"total":2},
 "behavior":{"status":"fail","passed":2,"total":3},"gate":"needs-review"}
```

### 合成的 `synthesis.md`（PM 看的那一页，摘录）

```
## 一句话
有待办：漏建 1 项、降级占位 1 项、视觉待办 2 条、行为审有流程没跑通。…

## ① 覆盖审计（建全没）
- 建了：2 项 / 丢了：1 项 / 降级占位：1 项
  - 丢了：历史导出 CSV（范围清单要求但代码里没有导出入口）
  - 降级占位：空态（无历史）（建了空态文案但没接真实判空，恒显示列表）
## ② 视觉门（长得对不对）
  - [P1] 历史卡片间距 12px，DESIGN 规定 16px
## ③ 行为审（跑得通不通）
- ❌ 有流程没跑通（2/3）：「点导出→下载 CSV」流程：导出按钮不存在，流程走不到
## 建议改的项（PM 勾哪些改）
- [ ] 补建：历史导出 CSV
- [ ] 补实：空态（无历史）（现是占位）
- [ ] 视觉：历史卡片间距 12px，DESIGN 规定 16px
- [ ] 修行为审没跑通的流程（详见 verify/report.md）
```

### 守卫验证

- **漏跑一道** → `synthesize` fail-loud（exit 2）：`三道审不完整：行为审未跑（缺 .../.pm-workflow/audits/<模块>/behavior.json）`。
- **三道全过** → `gate=clean`、synthesis 一句话「三道审均无待办……可看 demo 拍板」。
- **缺输入**（范围清单 / 端口）→ `resolve` fail-loud。
- **`--fail-on-gate`** + needs-review → 非零退出码。

## 4. 余下（build spike 才能验）

脚本编排确定、测过；但 LLM 调起的覆盖审计 agent / 视觉门 skill 在**真页面**上产出 conformant json、
dev server 三道复用 timing、整 loop —— 须下一个真实模块工作当 build spike 跑一遍才算闭环。
