---
name: codebase-audit
description: |
  Brownfield 入口：已有代码库接入框架时，扫码产出「代码现状档」
  （7 维度：技术栈 / 集成 / 架构 / 结构 / 约定 / 测试 / 隐患；带防 secret 扫描），
  然后走和新项目一样的 /project-solution 讨论（被现状档喂着）。
  与 GSD 的 map-codebase → new-project 同构。新项目（无已有代码）不用本 skill。
---

# /codebase-audit

## When To Use

- **brownfield 场景**：已有代码库要接入 PM-AI-Workflow 框架时调用，**在 `/project-solution` 之前**。
- 新项目（空仓 / 全新）**不用**本 skill —— 直接 `/init-project` → `/project-solution`。

本 skill = brownfield 入口。它产出「代码现状档」喂给 `/project-solution`，让 project-solution
被已有代码库的实况喂着讨论项目方向 —— 和新项目一样的 project-solution，只是多一份现状输入。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: codebase-audit"
```

## ⚠️ 防 secret 扫描（强约束）

扫码过程会读到代码库里的配置 / 环境文件。**禁止把任何密钥 / token / 密码 / 连接串 /
私钥写进现状档**：

- 扫到敏感值 → 一律以 `<redacted>` 占位；现状档只记「这里有一个 X 类密钥，在 Y 文件」。
- `.env` / `*.pem` / `*.key` / `credentials*` / `secrets*` 等文件：只记**存在性 + 用途**，
  不抄内容。
- 隐患段如发现疑似硬编码密钥，记「发现 N 处疑似硬编码密钥，已 redact，位置 file:line」，
  **不抄密钥本身**。

## Workflow

### 步骤 1：确认审计范围

向 PM 确认：要审计的代码库根目录（默认当前仓）；有无要排除的目录（如 `vendor/` /
`node_modules/` —— 这些本就该跳过）。

### 步骤 2：扫码 7 维度

用 read-only 工具（Glob / Grep / Read；大范围探索可派 read-only subagent fan-out）盘点
7 个维度，逐维写进 `docs/代码现状档.md`（按 `$REPO_ROOT/templates/codebase-audit.md.tmpl`）：

| # | 维度 | 扫什么 |
|---|---|---|
| 1 | 技术栈 | 语言 / 框架 / 运行时 / 包管理器 / 构建工具 + 版本（读 package.json / 锁文件 / 配置）|
| 2 | 外部集成 | 依赖的外部服务 / API / 数据库 / 第三方 SDK（连接串一律 `<redacted>`）|
| 3 | 架构 | 整体形态（单体 / 前后端分离 / 微服务）/ 分层 / 数据流向 |
| 4 | 目录结构 | 顶层目录树 + 关键目录职责 |
| 5 | 代码约定 | 命名 / 文件组织 / 状态管理 / 错误处理 / 注释风格 |
| 6 | 测试现状 | 有无测试 / 框架 / 覆盖面 / 怎么跑 |
| 7 | 隐患 | 技术债 / 风险点 / 安全隐患（含疑似硬编码密钥，已 redact）|

### 步骤 3：产出现状档 + PM 确认

写完 `docs/代码现状档.md` 后呈交 PM：

```
✅ 代码现状档：docs/代码现状档.md

📋 7 维度盘点完成：技术栈 <一句> / 集成 N 个 / 架构 <一句> / 隐患 M 项

这份现状档准吗？有补充 / 纠正直接说；确认后跑 /project-solution（它会读这份档作为
已有代码库的语境讨论项目方向）。
```

PM 提修正 → 改现状档 → 重新呈交。

### 步骤 4：交接 project-solution

PM 确认现状档后，引导 PM 跑 `/project-solution` —— project-solution 读 `docs/代码现状档.md`
作为已有代码库的语境，和新项目一样讨论项目方向、产出 `docs/PROJECT.md` + `docs/ROADMAP.md`。

## Rules

- **只读扫码**：本 skill 不改任何代码、不改任何业务文件 —— 只产出 `docs/代码现状档.md`。
- **防 secret 是硬约束**：见上方「防 secret 扫描」段，违反 = 严重错误。
- 不替代 `/project-solution` —— 本 skill 只产现状档；项目方向讨论由 project-solution 做。
- 新项目不用本 skill（无已有代码可审）。

## 边界

- **允许产出**：`docs/代码现状档.md`
- **允许动作**：read-only 扫码、7 维度盘点、防 secret redact
- **禁止**：改代码 / 改业务文档 / 替 PM 做项目方向决策
- **退出条件**：现状档经 PM 确认，引导 PM 跑 `/project-solution`
