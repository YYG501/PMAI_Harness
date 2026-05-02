<!-- AUTO-GENERATED FROM templates/工程结构约束.schema.json — DO NOT EDIT. -->
<!-- 改动 schema 或 DEPTH_GUIDANCE 后跑 `python3 scripts/derive-structure-templates.py` 重新派生。 -->

## 工程结构约束（系统档（system））

> 视觉 token / 颜色 / 间距 / 字号 → 见 DESIGN.md，本段管代码组织 + 实现深度指引。

**原型根目录（PM 必填）**：`<改成实际路径，例：prototypes/ 或 src/ 或 apps/web/src/>`

### 代码组织

**保留**（始终允许）：
- `**/components/ui/**/*.{ts,tsx}` — shadcn primitive UI（token 来自 DESIGN.md）（signal: components_ui）
- `**/framework/layout/*.{ts,tsx}` — 壳子布局复用（真实多页共用）（signal: framework_layout）

**应有**（本档下应当出现）：
- `**/framework/context/**/*.{ts,tsx}` — Context-based 跨页面状态（signal: context_state）
- `**/modules/*/lib/store*.{ts,tsx}` — 领域 store / state container（signal: domain_store）
- `**/framework/hooks/**/*.{ts,tsx}` — 可复用 hook 抽象（业务行为脱离单页）（signal: hook_abstraction）
- `**/modules/*/pages/**/*.{ts,tsx}` — modules/<m>/pages 中间层（路由与页面解耦）（signal: pages_middle_layer）
- `**/framework/page/*Template*.{ts,tsx}` — Page Template 抽象（多页共享 props 接口）（signal: template_abstraction）

### 实现深度指引

> 以下是 task-execute 阶段 AI 写代码时的深度参考。PM 可手改任意条；
> 删除上方 auto-detected 标后视为 PM 手填，框架不再覆盖。

- **数据层**：真实持久化（IndexedDB / 后端 API / 数据库），跨页状态由 store / context 承载。
- **权限层**：完整权限矩阵：登录态 + 角色 + 资源访问控制。每个页面 / 操作有显式权限校验。
- **API 契约**：完整 API 定义（OpenAPI / GraphQL schema）+ 真实后端联调。前端不写假数据。
- **测试**：完整测试覆盖：纯函数 ≥ 80% 单测；关键交互 e2e；引用稳定性测试覆盖核心 reducer / store。
- **边界态**：全部边界态（loading / empty / error / partial / success / retry / timeout）。
- **多端覆盖**：按 PM 在 init 时定的端数实现（单端 / 双端 / 三端齐全）。三端时复用同 store / hook 但 UI 各端独立。
- **演示路径**：全路径（含分支 + edge case）。每个用户决策点都有对应实现。

### 约定

- 共享数据流由 store / context 承载，禁止页面内重复 fetch / dedupe
- 同一交互模式必须抽 hook / Template，避免长尾分叉
- modules/<m>/pages 中间层由路由按业务域聚合
