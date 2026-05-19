<!-- AUTO-GENERATED FROM templates/工程结构约束.schema.json — DO NOT EDIT. -->
<!-- 改动 schema 或 DEPTH_GUIDANCE 后跑 `python3 scripts/derive-structure-templates.py` 重新派生。 -->

## 工程结构约束（原型档（prototype））

> 视觉 token / 颜色 / 间距 / 字号 → 见 DESIGN.md，本段管代码组织 + 实现深度指引。

**原型根目录（PM 必填）**：`<改成实际路径，例：prototypes/ 或 src/ 或 apps/web/src/>`

### 代码组织

**保留**（始终允许）：
- `**/components/ui/**/*.{ts,tsx}` — shadcn primitive UI（token 来自 DESIGN.md）（signal: components_ui）
- `**/framework/layout/*.{ts,tsx}` — 壳子布局复用（真实多页共用）（signal: framework_layout）

**禁止**（本档下不允许）：
- `**/framework/context/**/*.{ts,tsx}` — Context-based 跨页面状态（signal: context_state）
- `**/modules/*/lib/store*.{ts,tsx}` — 领域 store / state container（signal: domain_store）
- `**/framework/hooks/**/*.{ts,tsx}` — 可复用 hook 抽象（业务行为脱离单页）（signal: hook_abstraction）
- `**/modules/*/pages/**/*.{ts,tsx}` — modules/<m>/pages 中间层（路由与页面解耦）（signal: pages_middle_layer）
- `**/framework/page/*Template*.{ts,tsx}` — Page Template 抽象（多页共享 props 接口）（signal: template_abstraction）

### 实现深度指引

> 以下是 task-execute 阶段 AI 写代码时的深度参考。PM 可手改任意条；
> 删除上方 auto-detected 标后视为 PM 手填，框架不再覆盖。

- **数据层**：默认 mock 静态数据（写死 JSON 在文件顶部）。不调真实接口、不写持久化层。
- **权限层**：默认不做权限校验。任何角色都能看任何页面，无登录态、无权限矩阵。
- **会话层**：默认不做 session 守护。无 session timeout、无失效跳登录、无 token 刷新、无并发登录踢出；登录页等相关页面只做静态呈现。
- **API 契约**：默认不调外部接口。前端写死假数据；如需展示 loading 用 setTimeout 模拟。
- **测试**：默认不写单测、e2e、集成测试。靠 PM 走查 + /qa 工具人肉验收。
- **边界态**：默认主路径 loading + 成功两态即可。错误态 / 空态 / 部分态等不必实现。
- **多端覆盖**：默认单端（PM 在 init 后于本段补「单端：tenant」之类的具体端名）。
- **演示路径**：默认仅主路径（happy path）。分支路径、edge case 等 PM 不在 task-plan 显式拆 task 就不实现。

### 文档输出深度指引

> 以下是 req-solution / task-spec 阶段 AI 写 `.engineering.md` 工程合同时的深度参考。
> 配合 `scripts/check-engineering-doc-size.py` 做硬行数校验。
> PM 可手改任意条；删除上方 auto-detected 标后视为 PM 手填，框架不再覆盖。

- **solution.engineering.md 目标行数**：≤300 行；由 scripts/check-engineering-doc-size.py 在 stage 闸门校验，超限报错。
- **task-NNN.engineering.md 目标行数**：≤200 行；同样 lint 校验。
- **强制引用规则**：上游已定义的类型/接口/函数签名/产品行为禁止重写——直接写「参见 solution.md §X.Y」或「参见 solution.engineering.md §X.Y」。
- **§4 功能清单工程版**：只列「差异点 / 复用点」，不再贴完整签名。
- **§7 plan-review 沉淀 / §8 autoplan / §9 a11y/视口/视觉规范**：默认 N/A 一行带过；视觉规范沿用 DESIGN.md。
- **§10 工程层验收清单**：只列主路径 happy path，不展开错误/空/部分态。

### 约定

- 每页 self-contained，假数据写死在文件顶部
- 视觉一致性：DESIGN.md（token 源）+ components/ui（实现）
- 复用靠「复制样板文件改改」，不做抽象组件
