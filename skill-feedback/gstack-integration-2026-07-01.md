<!-- 状态：已消化（2026-07-01；见提交记录）；保留作历史档案 -->

# gstack integration 反馈消化

## 消化结果对账表

| # | 反馈类目 | 落地状态 | 现状位置 | 剩余 gap |
|---|---|---|---|---|
| 1 | PMAI 与 gstack 关系要统一 | 已落地 | `skills/_shared/gstack-integration.md` | 无 |
| 2 | PDF 出口应明确是 `/make-pdf` | 已落地 | `skills/doc-writing/SKILL.md`、`templates/deliverables-INDEX.md.tmpl` | 无 |
| 3 | `/document-generate` 要看清作用 | 已落地 | `skills/_shared/gstack-integration.md` | 无 |
| 4 | gstack skill 可在消费仓直接调用，但要接回 PMAI 真相源 | 二次补齐 | `skills/_shared/gstack-integration.md`、`templates/CLAUDE.md.tmpl`、`templates/AGENTS.md.tmpl`、`scripts/check-engineering-docs-index.py` | 第一版只有规则合同，本轮补工程文档接回目录和索引门禁 |
| 5 | 不新增 `/pmai-gstack` / 不 vendoring gstack | 已落地 | `skills/_shared/gstack-integration.md` | 无 |

## PM 反馈摘要

- PMAI 消费仓未来可以直接调用 gstack skill，但 PMAI 要规定调用点和接回规则。
- `/make-pdf` 是 Markdown 转 PDF 的明确能力，不应泛称“Markdown 转 PDF skill”。
- `/document-generate` 是工程文档生成能力，不应混入产品介绍、PRD、模块规格、PM 汇报材料主链路。
- gstack 是专项能力层；PMAI 仍负责产品上下文、真相源、接回路径和收口门禁。

## 二次反馈（2026-07-01）

PM 追问：“但调用结果必须回到 PMAI 的文档地图这一块实现了吗”。复核后确认第一版只是规范性实现，旁路文档没有执行性接回门禁。

本轮采纳：

- 新增 `docs/engineering/` + `docs/engineering/INDEX.md` 作为 gstack 工程文档旁路采用后的接收点。
- 消费仓入口和文档地图明确：工程文档接回 engineering，产品材料走 doc-writing，功能规格走 spec-writing / design。
- 新增 pre-commit checker，阻止已接回的工程文档未登记索引。
