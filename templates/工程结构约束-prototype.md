<!-- AUTO-GENERATED FROM templates/工程结构约束.schema.json — DO NOT EDIT. -->
<!-- 改动 schema 后跑 `python3 scripts/derive-structure-templates.py` 重新派生。 -->

## 工程结构约束（原型档（prototype））

> 视觉 token / 颜色 / 间距 / 字号 → 见 DESIGN.md，本段仅管代码组织。

**原型根目录**：`{prototype-root}`

**保留**（始终允许）：
- `**/components/ui/**/*.{ts,tsx}` — shadcn primitive UI（token 来自 DESIGN.md）（signal: components_ui）
- `**/framework/layout/*.{ts,tsx}` — 壳子布局复用（真实多页共用）（signal: framework_layout）

**禁止**（本档下不允许）：
- `**/framework/context/**/*.{ts,tsx}` — Context-based 跨页面状态（signal: context_state）
- `**/modules/*/lib/store*.{ts,tsx}` — 领域 store / state container（signal: domain_store）
- `**/framework/hooks/**/*.{ts,tsx}` — 可复用 hook 抽象（业务行为脱离单页）（signal: hook_abstraction）
- `**/modules/*/pages/**/*.{ts,tsx}` — modules/<m>/pages 中间层（路由与页面解耦）（signal: pages_middle_layer）
- `**/framework/page/*Template*.{ts,tsx}` — Page Template 抽象（多页共享 props 接口）（signal: template_abstraction）

**约定**：
- 每页 self-contained，假数据写死在文件顶部
- 视觉一致性：DESIGN.md（token 源）+ components/ui（实现）
- 复用靠「复制样板文件改改」，不做抽象组件
