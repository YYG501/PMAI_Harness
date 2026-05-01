<!-- AUTO-GENERATED FROM templates/工程结构约束.schema.json — DO NOT EDIT. -->
<!-- 改动 schema 后跑 `python3 scripts/derive-structure-templates.py` 重新派生。 -->

## 工程结构约束（系统档（system））

> 视觉 token / 颜色 / 间距 / 字号 → 见 DESIGN.md，本段仅管代码组织。

**原型根目录**：`{prototype-root}`

**保留**（始终允许）：
- `**/components/ui/**/*.{ts,tsx}` — shadcn primitive UI（token 来自 DESIGN.md）（signal: components_ui）
- `**/framework/layout/*.{ts,tsx}` — 壳子布局复用（真实多页共用）（signal: framework_layout）

**应有**（本档下应当出现）：
- `**/framework/context/**/*.{ts,tsx}` — Context-based 跨页面状态（signal: context_state）
- `**/modules/*/lib/store*.{ts,tsx}` — 领域 store / state container（signal: domain_store）
- `**/framework/hooks/**/*.{ts,tsx}` — 可复用 hook 抽象（业务行为脱离单页）（signal: hook_abstraction）
- `**/modules/*/pages/**/*.{ts,tsx}` — modules/<m>/pages 中间层（路由与页面解耦）（signal: pages_middle_layer）
- `**/framework/page/*Template*.{ts,tsx}` — Page Template 抽象（多页共享 props 接口）（signal: template_abstraction）

**约定**：
- 共享数据流由 store / context 承载，禁止页面内重复 fetch / dedupe
- 同一交互模式必须抽 hook / Template，避免长尾分叉
- modules/<m>/pages 中间层由路由按业务域聚合
