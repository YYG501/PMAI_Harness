---
skills:
  - build
  - init-project
  - _internal/codebase-audit
date: 2026-07-10
source: 会话内 PM 直接反馈（模式 B）
---

<!-- 状态：已消化（2026-07-10 ea49139）；保留作历史档案 -->

# Build 开工确认与项目级类型反馈

## 原始反馈

PM 对统一构建链路的开工方式连续做了以下纠正：

1. “AI 自动选择隔离环境、工具和验收方式”不对，工作环境和构建工具仍应由用户确认。
2. 构建对象不是每轮 build 再选择；项目一开始就应定义这是原型项目还是真实产品项目。
3. 如果用户以后要改变项目类型，应修改项目定义文件，而不是在某轮对话里临时切换。
4. 验收方案不需要用户确认，按项目类型和风险走默认方案。
5. build 开工卡不显示项目类型，也不显示验收方案；只显示工作环境和构建工具。

核心判断：

> 不让 PM 选择项目类型和验收，不等于 AI 每轮自由推断。项目类型由项目定义决定，验收由框架默认规则决定；只有工作环境和构建工具在新 build 开工前确认一次。

## 消化结果对账表

| # | 反馈类目 | 落地状态 | 落地位置 | 实际结果 |
|---|---|---|---|---|
| 1 | 工作环境由 PM 确认 | ✅ 已落地 | `skills/build/SKILL.md` §3；`skills/_shared/decision-policy.md`；`scripts/check-branch.sh` | AI 默认推荐独立环境；PM 可调整为当前环境。当前环境只放行 v2 合同声明的目标路径 |
| 2 | 构建工具由 PM 确认 | ✅ 已落地 | `scripts/builder-profile.py`；`skills/build/SKILL.md` §3；消费仓 AGENTS / CLAUDE 模板 | profile 只产推荐；PM 确认或调整后才开工。工具失败换工具必须重新确认 |
| 3 | 项目类型在项目开始时定义 | ✅ 已落地 | `.pm-workflow/config.yml:project.type` 模板；`scripts/project-type.py`；`scripts/init-project.sh`；`skills/init-project/SKILL.md` | 新项目只接受 `prototype / product`；build 静默读取，不按本轮需求猜 |
| 4 | 已有代码接入也必须定义类型 | ✅ 已落地 | `skills/_internal/codebase-audit/SKILL.md` §4 | 首次接入时 PM 二选确认并写入同一配置文件，不留下无定义项目 |
| 5 | 验收按默认方案，不让 PM 选 | ✅ 已落地 | `skills/build/SKILL.md` §2、§7；`scripts/acceptance-profile.py` | 验收 profile 继续按项目类型和风险后台生成；受限或失败仍如实记录，不能因隐藏而跳过 |
| 6 | 开工卡不显示项目类型和验收 | ✅ 已落地 | `skills/build/SKILL.md` 开工卡；`templates/AGENTS.md.tmpl`；`templates/CLAUDE.md.tmpl`；`evals/cases/no-internal-menus.json` | 卡片固定只显示“工作环境、构建工具”；禁止显示类型、验收清单、worktree、合同、hash 和证据 JSON |
| 7 | 旧消费仓渐进兼容 | ✅ 已落地 | `scripts/project-type.py`；`tests/test-project-type.sh` | 旧 `prototype` marker 映射 prototype，旧 `system` marker 映射 product；`custom / unknown` 停止并要求补定义文件 |

未采纳项：无。以上均为 PM 明确拍板后的流程定义。

## 用户侧最终流程

```text
项目初始化 / 首次接入时定义 prototype 或 product
→ design 讨论并形成建造依据
→ build 后台读取项目类型并生成默认验收
→ AI 推荐工作环境和构建工具
→ PM 一次确认或调整这两项
→ 构建并看结果、多轮修改
→ PM 定稿
→ 完整验收、进入 main、更新正式文档
```

开工卡目标形态：

```text
准备构建：用户权限管理

工作环境：独立环境
构建工具：Codex（gpt-5.4, high）

[按这个方案构建]
[调整工作环境]
[调整构建工具]
```

## 验证

- 实现提交：`ea49139 fix(build): 项目类型与验收退出开工卡`
- 完整回归：`465 passed / 0 failed`
- 静态评测：5 个 static cases 全部通过；schema 共 14 cases 校验通过
- Python 编译、Bash 语法、JSON 解析和 `git diff --check` 均通过
- 未 push、未合入 main、未升级用户目录中的 `~/.pmai`
