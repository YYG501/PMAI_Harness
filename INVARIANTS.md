# 关键不变式

> 本文件只记录当前活跃架构的不变式。旧 task 状态机、`requirements/active|closed`
> 目录树、`req-*` 分支、`work-*` 泛化分支、`/pmai-next` 和阶段推进脚本都已从活跃路径移除。

## 主索引

| 前缀 | 范围 | 一句话主旨 |
|---|---|---|
| **I-G** | 全局 | 多步操作 fail-loud，不吞关键错误 |
| **I-MOD** | 模块状态 | 工作状态真相源 = `docs/modules/<模块>/.work-meta.json` |
| **I-BR** | 分支 | 隔离实现只认 `build-*` 分支 |
| **I-CR** | close | close = 归位产物 + 清 `.work-meta.json`，不搬目录 |
| **I-CA** | cancel | cancel 不 merge，不留 active 工作状态 |
| **I-CB** | check-branch | main 拦业务代码，docs 树作为文档真相源放行 |
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

- **I-MOD1**：活跃工作只由 `docs/modules/<模块>/.work-meta.json` 表示，`status=active` 才算在做。
- **I-MOD2**：`requirements/active|closed` 不是状态真相源；活跃逻辑不得依赖旧目录。
- **I-MOD3**：模块长期知识留在 `docs/modules/<模块>/discussion.md` / `decisions.md` / `spec.md`；`.work-meta.json` 只是临时工作状态层。
- **I-MOD4**：stage 字段只作展示和提示，不再作为机器推进门或 close 硬门。

---

## I-BR：分支

- **I-BR1**：运行态只认 `build-*` 作为工作隔离分支前缀。
- **I-BR2**：不得再创建 `req-*` 分支；不得保留通用 `work-*` 兼容分支。
- **I-BR3**：`/pmai-status` 只扫描 `build-*` worktree 和模块 `.work-meta.json`。

---

## I-CR：close

- **I-CR1**：close 的前提是 PM 明确确认当前模块可以收尾，不依赖 stage 数字硬门。
- **I-CR2**：close 不再 `git mv requirements/active → requirements/pmai-closed`。
- **I-CR3**：有 worktree/分支时，先在 build 分支归位产物并清 `.work-meta.json`，commit 后 merge 回 main。
- **I-CR4**：无 worktree/分支时，允许直接在 main 清 `.work-meta.json` 并 commit。
- **I-CR5**：close 成功后，模块三件套留场，`.work-meta.json` 不留 `status=closed` 占位。
- **I-CR6**：merge 路径必须通过 ancestor 验证；失败不能留下半清状态。

---

## I-CA：cancel

- **I-CA1**：cancel 不 merge build 分支到 main。
- **I-CA2**：cancel = 清工作状态层 `.work-meta.json`；不创建 `status=cancelled` 占位。
- **I-CA3**：模块长期文档若已在 main 留场，不因 cancel 删除。
- **I-CA4**：cancel 清理必须幂等，重复执行不应报错或破坏长期文档。

---

## I-CB：check-branch

- **I-CB1**：路径归一化必须基于 `MAIN_REPO_ROOT`，不能被当前 cwd/worktree 误导。
- **I-CB2**：main 分支默认拒绝业务代码写入；当前文档真相源在 `docs/**`，允许直接写。
- **I-CB3**：旧 `requirements/active|closed` 不在 main 写入白名单内。
- **I-CB4**：hook 失败或无法判断时 fail-closed。
- **I-CB5**：hook 自身只读，不得修改文件。

---

## I-BA：build 审计

- **I-BA1**：`/pmai-build` 的功能锚点是 `docs/modules/<模块>/spec.md`，不是 task 文件。
- **I-BA2**：build 写入边界默认是 `prototype/**`；文档归位在 `/pmai-build-close`。
- **I-BA3**：覆盖审计、视觉门、行为审三道结果必须齐全后才能进入 PM 验收。
- **I-BA4**：三道审只报告证据和问题，不替 PM 自动修改或拍板。
