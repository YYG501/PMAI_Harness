# 关键不变式

> 本文件只记录当前活跃架构的不变式。旧 task 状态机、`requirements/active|closed`
> 目录树、7-stage 流程已从活跃路径移除，不再作为实现或测试依据。

## 主索引

| 前缀 | 范围 | 一句话主旨 |
|---|---|---|
| **I-G** | 全局 | 多步操作 fail-loud，不吞关键错误 |
| **I-MOD** | 模块状态 | req 工作状态真相源 = `docs/modules/<模块>/.req-meta.json` |
| **I-RT** | req-transition | stage 只允许 1→2→3→4 逐级推进，stage 4 不可回退 |
| **I-CR** | close | close = 归位产物 + 清 `.req-meta.json`，不搬目录 |
| **I-CA** | cancel | cancel 不 merge，不留 active 工作状态 |
| **I-CB** | check-branch | main 写保护按新 docs 树放行，状态字段仍禁止直改 |
| **I-BA** | build 审计 | build 对模块 spec 建，三道审必须齐全且只报不改 |

---

## I-G：通用

- **I-G1**：任何多步操作要么完全成功，要么可安全重试，不能留下半完成状态。
- **I-G2**：commit、merge、状态写入、worktree 创建/清理等关键步骤不能用 `|| true` 吞错。
- **I-G3**：改变状态前必须先验证前置条件。
- **I-G4**：需要长期追溯的产物必须 git tracked；运行时临时文件不得冒充归档。
- **I-G5**：写操作必须检查返回值。

---

## I-MOD：模块工作状态真相源

- **I-MOD1**：活跃 req 只由 `docs/modules/<模块>/.req-meta.json` 表示，`status=active` 才算在做。
- **I-MOD2**：`requirements/active|closed` 不是状态真相源；迁移脚本可以读取旧目录，但活跃逻辑不得依赖旧目录。
- **I-MOD3**：模块长期知识留在 `docs/modules/<模块>/discussion.md` / `decisions.md` / `spec.md`；`.req-meta.json` 只是临时工作状态层。

---

## I-RT：req-transition

- **I-RT1**：stage 范围固定为 1-4：范围确认、build、复审、沉淀。
- **I-RT2**：forward 只能逐级推进；不能跳到不存在的 stage 5/6/7。
- **I-RT3**：rollback 只能回到较早 stage；stage 4（沉淀）不可回退。
- **I-RT4**：写 stage 必须通过 transition helper，禁止直接编辑 `.req-meta.json.stage`。
- **I-RT5**：transition 前必须保证本 req 相关文档已落盘到 git，避免下游读到旧 HEAD。

---

## I-CR：close

- **I-CR1**：close 前 req stage 必须是 4（沉淀）。
- **I-CR2**：close 不再 `git mv requirements/active → requirements/closed`。
- **I-CR3**：有 worktree/分支时，先在分支归位产物并清 `.req-meta.json`，commit 后 merge 回 main。
- **I-CR4**：无 worktree/分支时，允许直接在 main 清 `.req-meta.json` 并 commit。
- **I-CR5**：close 成功后，模块三件套留场，`.req-meta.json` 不留 `status=closed` 占位。
- **I-CR6**：merge 路径必须通过 ancestor 验证；失败不能留下半清状态。

---

## I-CA：cancel

- **I-CA1**：cancel 不 merge req 分支到 main。
- **I-CA2**：cancel = 清工作状态层 `.req-meta.json`；不创建 `status=cancelled` 占位。
- **I-CA3**：模块长期文档若已在 main 留场，不因 cancel 删除。
- **I-CA4**：cancel 清理必须幂等，重复执行不应报错或破坏长期文档。

---

## I-CB：check-branch

- **I-CB1**：路径归一化必须基于 `MAIN_REPO_ROOT`，不能被当前 cwd/worktree 误导。
- **I-CB2**：main 分支默认拒绝写入，只放行白名单路径；当前文档真相源在 `docs/**`。
- **I-CB3**：旧 `requirements/active|closed` 不在 main 写入白名单内。
- **I-CB4**：`.req-meta.json.stage` 禁止直改，必须走 transition。
- **I-CB5**：hook 失败或无法判断时 fail-closed。
- **I-CB6**：hook 自身只读，不得修改文件。

---

## I-BA：build 审计

- **I-BA1**：`/build` 的功能锚点是 `docs/modules/<模块>/spec.md`，不是 task 文件。
- **I-BA2**：build 写入边界默认是 `prototype/**`；文档归位在 `/close`。
- **I-BA3**：覆盖审计、视觉门、行为审三道结果必须齐全后才能进入 PM 验收。
- **I-BA4**：三道审只报告证据和问题，不替 PM 自动修改或拍板。
