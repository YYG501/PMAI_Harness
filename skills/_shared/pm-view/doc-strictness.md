# §四 文档级严格度对照表

> 本文件是 [`PM-VIEW-RULES.md`](../PM-VIEW-RULES.md) §四 的物理拆分。配套阅读：[`writing-rules.md`](./writing-rules.md)（§三 写作规则细则）。

所有 PM 视图文档共享同一套严格度（UI 行业词允许、其它工程化内容禁用）；工程合同层全部允许：

| 文档类型 | UI 行业词（Badge/Drawer 等） | 像素 / 颜色 | 反向约束 | 工程词（reducer/dispatch）|
|---|---|---|---|---|
| `docs/modules/<模块>/discussion.md` | ✅ 允许 + 指代前缀 | ❌ 禁用 | ❌ 禁用 | ❌ 禁用 |
| `docs/modules/<模块>/decisions.md` | ✅ 允许 + 指代前缀 | ❌ 禁用 | ❌ 禁用 | ❌ 禁用 |
| `docs/modules/<模块>/spec.md` | ✅ 允许 + 指代前缀 | ❌ 禁用 | ❌ 禁用 | ❌ 禁用 |
| `prd.md` | ✅ 允许 + 指代前缀 | ❌ 禁用 | ❌ 禁用 | ❌ 禁用 |
| `*.engineering.md` | ✅ 全部允许 | ✅ 全部允许 | ✅ 全部允许 | ✅ 全部允许 |
