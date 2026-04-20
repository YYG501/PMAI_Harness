---
name: init-project
description: |
  在框架仓库中创建新业务项目，生成完整目录结构、脚本、skill 和 git 仓库。
---

# /init-project

## When To Use

- PM 在框架仓库（PM-AI-Workflow）中调用
- 需要创建一个新的业务项目时

## Workflow

### 步骤 1：收集项目信息

向 PM 询问以下信息：

1. **项目名**（英文 kebab-case，如 `my-app`）
2. **目标目录**（项目创建位置的绝对路径，如 `/Users/xxx/Projects/my-app`）
3. **项目背景**（一段话描述项目目的和上下文）

如果 PM 只给了部分信息，逐个追问缺失项。

### 步骤 2：执行创建

确认三项信息后，调用：

```bash
bash scripts/init-project.sh "<project-name>" "<target-dir>" "<background>"
```

脚本会自动完成：
- 检测 gstack 依赖
- 创建项目目录、复制模板和脚本
- 初始化 git 仓库（main 分支）
- 推导基础端口

### 步骤 3：引导 PM 进入项目

脚本成功后，提示 PM：

```
项目初始化完成。

下一步：
  cd <target-dir>
  运行 /new-req 开始第一个需求
```

## Rules

- 必须在框架仓库根目录运行（不是业务项目中）
- 目标目录不能已存在（脚本会拒绝覆盖）
- gstack 是硬依赖，未安装时脚本会报错退出
- 不要手动创建任何文件，全部由 init-project.sh 处理
