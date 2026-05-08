# 工程合同 §5 实现指引：项目级 + req 级 prose 合并（4.5d.4 修订）

> 本文件是 `skills/task-spec/SKILL.md` 步骤 9 的子节「§5 实现指引：项目级 + req 级 prose 合并」的物理拆分。主 SKILL 步骤 9 仅留指针，本文件是完整规则。

§5 实现指引由两层 prose 段落合并而成（**不是 enum 字段，不机械冲突阻断**）：

**A 层 项目级（CLAUDE.md「## 工程结构约束」段）**

读 `$REPO_ROOT/CLAUDE.md` 的 `## 工程结构约束` section（含 auto-detected 标的内容 = init-project 注入；删 auto-detected 标后视为 PM 手填，框架不再覆盖）。

四档行为：

| 段内容 | A 层取值 |
|---|---|
| `prototype` 档（auto-detected: prototype 标）| prototype 派生模板：代码组织约束 + 实现深度 prose 指引（数据层 / 权限 / API / 测试 / 边界态 / 多端 / 演示路径）|
| `system` 档（auto-detected: system 标）| 同上 system 档 |
| `custom` 档（auto-detected: custom 标 / PM 手填骨架）| PM 自由编辑的 prose 段落（按当前内容采用） |
| `unknown` 档 / 段不存在 / placeholder 未替换 | **fallback**：警告 PM「项目级约束缺失或未定，建议跑 init-project 或 detect-project-structure 先补」，但不阻断；A 层取空，按 B 层单源生成 |

**B 层 req 级覆盖（solution.md「## 🔧 本轮实现深度变更」段）**

读 `$ACTIVE_REQ_DIR/solution.md` 的 `## 🔧 本轮实现深度变更` section：

- 内容是「无变更」/ 留空 / section 不存在 → B 层取空，§5 按 A 层单源生成
- 内容含变更描述（自由文本）→ B 层取该 prose 段，作为对 A 层的覆盖项

**合并语义（无机械冲突阻断）**

task-spec **不再做项目级 vs req 级的冲突检测**——任何组合都按 prose 合并直接拼到工程合同 §5。冲突场景（如项目级 prototype + req 级要做完整系统）由 PM 在多个时机自决：
- task-execute 看代码 / 看原型时：发现实际实现需要调整时，按业务层偏差路径走（task PM 视图「📁 历史档案 → 业务层偏差」 + close-task → /doc-update）
- close-req 步骤 2c：决定 req 级深度变更**是否同步到项目级 CLAUDE.md**（影响后续 req）

task-spec 只如实合并不阻断；冲突的处理在 task-execute / close-req / close-task 等下游环节，不在 task-spec。

**拼接结果写入工程合同 §5**：

```markdown
## 5. 实现指引

### 工程结构约束（项目级，A 层）

[CLAUDE.md「## 工程结构约束」段全文；{prototype-root} 已替换为实际值。
A 层缺失时本节写「项目级未定 — A 层缺失，按 req 级单源生成」]

### 本轮实现深度变更（req 级，B 层）

[solution.md「## 🔧 本轮实现深度变更」section 原文。
B 层为「无变更」时本节写「无变更（沿用 A 层）」]

### 具体实现要求

[基于 A + B 合并的有效深度生成 task 级 actionable 指引：
 - A 层是项目默认风格（prose 段落）
 - B 层 prose 描述本 req 的覆盖项（如有）
 - AI 在 task-execute 写代码时按 B 层覆盖 + A 层兜底执行]
```

如步骤 12 PM 选 B（修订 PM 视图）：本步骤跳过；步骤 12.5 reconcile 时按当前 A + B 重新拼接。
