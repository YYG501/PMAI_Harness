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
4. **项目意图**（工程结构约束）：
   - `prototype` — 原型档：每页 self-contained，不抽 Template / hook / context；mock 数据 / 不做权限 / 不写测试 / 仅主路径；视觉靠 DESIGN.md + components/ui
   - `system` — 系统档：抽 Template / hook / context-state / pages 中间层 / domain store；真实持久化 / 完整权限矩阵 / 完整测试 / 全路径
   - `custom` — 自定义档：PM 自由编辑，不预设深度；用 `prototype/system` 都不贴合（如混合档：真实数据 + 简化权限）时选这个
   - `unknown` — PM 暂不决定，留 placeholder 让 PM 后续跑 `python3 .claude/scripts/detect-project-structure.py` 看推荐再选

如果 PM 只给了部分信息，逐个追问缺失项。**意图字段必填**——没意图就走 unknown 兜底，不要默认猜。

### 步骤 2：执行创建

确认四项信息后，调用：

```bash
bash scripts/init-project.sh "<project-name>" "<target-dir>" "<background>" "<intent>"
```

脚本会自动完成：
- 检测 gstack 依赖
- 创建项目目录、复制模板和脚本
- 按 `<intent>` 注入「工程结构约束」段进 CLAUDE.md（带 auto-detected 标，PM 删标后视为手填，框架不再覆盖）
- 初始化 git 仓库（main 分支）
- 推导基础端口

### 步骤 3：引导 PM 进入项目

脚本成功后，提示 PM：

```
项目初始化完成。

下一步：
  cd <target-dir>
  运行 /project-solution 定项目顶层方向（产品定位 / 用户 / 路线 / 技术栈），再起第一个需求
```

> `init-project` 只建空骨架（目录 / 脚本 / git）。项目顶层方向（`docs/PROJECT.md` + `docs/roadmap.md`）由接在后面的 `/project-solution` 填——它跑完才运行 `/new-req`。

## Rules

- 必须在框架仓库根目录运行（不是业务项目中）
- 目标目录不能已存在（脚本会拒绝覆盖）
- gstack 是硬依赖，未安装时脚本会报错退出
- 不要手动创建任何文件，全部由 init-project.sh 处理
