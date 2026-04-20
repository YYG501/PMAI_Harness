---
name: task-execute
description: |
  在 task worktree 中实现代码、启动 dev server、写执行日志、填文档偏差、自审并记录。
---

# /task-execute

## When To Use

- Suborchestrator 在 task worktree 中读取此 skill 并执行

## Workflow

### 步骤 1：读取 task 文件

读取 task 文件（使用绝对路径到主仓的 req 目录）。提取：
- 任务描述
- 执行范围
- 验收标准
- 审查工具列表
- 启动前必读文档

### 步骤 2：读取必读文档

按「启动前必读」列表，逐个读取文档内容。理解：
- 模块规格和接口约定
- 设计系统规范（DESIGN.md）
- 项目背景（CONTEXT.md）

### 步骤 3：实现代码

根据任务描述和执行范围实现代码：
- 新建文件按执行范围创建
- 修改文件按执行范围修改
- 不动的文件不要碰

### 步骤 4：启动 dev server（UI 类 task）

如果是 UI 类 task：
1. 启动 dev server，绑定到 task 文件中指定的端口
2. 确保 server 在后台运行，不阻塞后续步骤
3. 验证 server 可访问

非 UI 类 task 跳过此步骤。

### 步骤 5：写执行日志

在 task 文件的「执行日志」section 填写：

```markdown
### 执行报告 - [YYYY-MM-DD HH:MM]
**改动摘要：** [简述做了什么]
**新建文件：** [文件列表]
**修改文件：** [文件列表]
**验收标准完成情况：**
- [x] 条件 1 — 已实现
- [x] 条件 2 — 已实现
```

### 步骤 6：写文档偏差

在 task 文件的「文档偏差」section：
- 如果实现与文档描述一致：写「无偏差」
- 如果有偏差：填写偏差表格

```markdown
| 文档位置 | 文档原文 | 实际实现 |
|----------|----------|----------|
| docs/modules/auth.md 第 15 行 | 使用 JWT 认证 | 改用 Session 认证（因 XX 原因） |
```

### 步骤 7：自审（gstack 质量 gate）

自审链路按以下顺序运行 gstack skill：

**7a. /review（代码审查，所有 task）**
- 运行 `/review`，审查 task 分支 vs req 分支的 diff
- **suborchestrator 自行处理所有发现，不 Ask PM**
- mechanical issues 自动修，critical issues 自行修复并记录到自审记录
- 追加事件：
  ```bash
  python3 .claude/scripts/task-events.py append "<task-file>" --type review_completed --tool "/review" --result "<pass|fail>"
  ```

**7b. /qa（功能测试，仅 UI task）**
- 如果审查工具字段包含 `/qa`：
  - 运行 `/qa`，测试 dev server URL
  - 发现 bug 自行修复（atomic commit）
  - 追加事件

**7c. /design-review（视觉审查，仅 UI task）**
- 如果审查工具字段包含 `/design-review`：
  - 运行 `/design-review`，对照 DESIGN.md 检查视觉一致性
  - 发现问题自行修复
  - 追加事件

### 步骤 8：写自审记录

在 task 文件的「自审记录」section 填写每个工具的审查结果，包括发现的问题和处理方式：

```markdown
### 自审 1 - [YYYY-MM-DD HH:MM]
**工具：** /review
**结果：** pass（2 个 mechanical issue 已自动修复）
**详细发现：** 
- F-001: 变量命名不一致 → 已修复
- F-002: 缺少 null check → 已修复
**遗留问题：** 无
```

### 步骤 9：修复自审发现的问题

如果自审发现了无法自动修复的问题：
1. 手动修复代码
2. 重新跑对应的审查工具
3. 更新自审记录
4. 追加新的 review_completed 事件

### 步骤 10：提交待验收

所有审查工具通过后，调用：

```bash
python3 .claude/scripts/task-transition.py "<task-file>" --to 待验收
```

脚本会自动校验：
- 文档偏差 section 已填
- 自审记录 section 有内容
- 所有审查工具都有 review_completed 事件

Dev server 保持运行（PM 验收时需要访问）。

## Rules

- task 文件用绝对路径读写（task worktree 中的路径和主仓路径不同）
- 代码改动在 task worktree 中进行
- 文档（docs/）不在 task worktree 中修改（hook 会拦截）
- 文档偏差记录到 task 文件，由 `/doc-update` 在 close-task 前处理
- 每个审查工具必须有对应的 review_completed 事件，否则无法转为待验收
- dev server 在 task-execute 结束后保持运行，直到 close-task 时杀掉
