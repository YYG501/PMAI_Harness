# Stage 3 方案设计流程改进

## Context

用户在实际使用框架 stage 3（方案设计）时遇到两个问题：

1. 生成文档后没有给出文件路径，PM 无法快速定位文件确认内容
2. 写完方案后没有自动调用 skill 审阅，缺少质量把关环节

同时，为避免和 stage 4 的 `DESIGN.md` 混淆，stage 3 产出统一命名为 `solution.md`。

## 最终规则

### Stage 3 产出

PM 选择进入 stage 3 时：

1. 读取 `analysis.md`，做系统分层、模块边界设计
2. 写 `solution.md` 到 req 目录
3. 自动调用 `/plan-ceo-review` 审阅 `solution.md`，所有 req 都自动运行，不可跳过
4. 确认门只给 `solution.md` 绝对路径 + 一句话摘要；review 发现直接贴在 chat
5. PM 提修改意见时，修改 `solution.md` 后必须重新运行 `/plan-ceo-review`，再进入确认门

### 确认门格式

确认门不贴文档全文。统一格式：

```text
📝 <filename> 已写入：`<绝对路径>`

一句话摘要：<最新变更或核心内容，一行>

A) 确认，进入 stage <N+1>
B) 我要修改（请说明改哪里）
```

例外：`/plan-ceo-review`、`/plan-eng-review`、`analysis-reviewer` 等 review 结果允许直接贴在 chat，因为它们是讨论内容，不是阶段产出文档。

### 命名一致性

Stage 3 的 req 内产物只使用 `solution.md`。所有流程文档、skill、脚本、测试都应读取该文件名。

## 已覆盖文件

- `scripts/req-transition.py`
- `skills/req-stage-gate/SKILL.md`
- `skills/task-plan/SKILL.md`
- `tests/test-req-transition.sh`
- `设计.md`
- `设计-功能规格文档增强.md`
- `设计-自举使用框架.md`

## 验证方式

1. `python3 scripts/req-transition.py --help`
2. `bash tests/test-req-transition.sh`
3. `rg -n "design\\.md" . -g '!*.git/*'` 应无残留
