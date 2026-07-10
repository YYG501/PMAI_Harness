# PM-AI-Workflow

## Codex 入口

本文件是 Codex / OpenAI agent 打开本生成器仓库时的项目入口。请先读本文件，再读 `CLAUDE.md`、`PRODUCT.md`、`RUNTIME.md`。

默认用中文和 PM 沟通；只有用户明确要求英文或引用原文时才切换。

## 项目定位

这是 PMAI 工作流框架的生成器仓，不是一个业务消费仓。最终产物是给 PM 单人使用的 LLM 协作工作流模板。

判断流程、边界和取舍时：

- 产品定位以 `PRODUCT.md` 为真相源。
- 当前状态、测试基线、下一步以 `RUNTIME.md` 的「当前位置」为真相源。
- Claude Code 章程、文档同步和 review 约束以 `CLAUDE.md` 为真相源。
- 本仓已有流程优先于临时发明的新流程。

## 项目原则

- **不写死机器绑定路径**：框架代码、模板、skill 文档、prompt 示例和生成到消费仓的规则里，不得写死 `/Users/<某人>/...` 这类本地路径。需要定位文件时，用运行时变量（`PMAI_HOME` / `REPO_ROOT` / `MAIN_REPO_ROOT` / `BUILD_DIR`）和仓内相对路径组合；PM 上传本机材料时可临时读取其路径，但不得沉淀进框架规则或业务代码。

## Host Mapping

- `CLAUDE.md` 里写的「Claude Code」「Claude host」「驱动 Claude」，在 Codex 会话中等价理解为当前 Codex 主控。
- `/pmai-*` 是 PMAI 的用户命令名。Codex skill 列表已暴露 `pmai-*` 时优先按该 skill 执行；Codex CLI 直输 slash 由 `~/.codex/prompts/pmai-*.md` 路由回对应 `SKILL.md`。如果当前 runtime 仍没有 slash / skill UI，再按本仓 `skills/<command-without-pmai-prefix>/SKILL.md` 的步骤执行。
- 如果 skill 目录名本身带 `pmai-` 前缀，例如 `/pmai-upgrade`，对应 `skills/pmai-upgrade/SKILL.md`。
- skill 内引用 `_shared/...` 时，从本仓 `skills/_shared/...` 读取。
- 需要调用脚本时，优先用本仓 checkout 内的 `scripts/`、`bin/`、`hooks/`，不要默认改用已安装的 `~/.pmai/`。

## 三条使用链路

### 1. 协同改造本框架仓

Codex 在本仓工作时，按普通软件项目方式协同：

1. 先确认 `git status --short --branch`，保护用户已有改动。
2. 读相关真相源：产品取舍读 `PRODUCT.md`，当前进度读 `RUNTIME.md`，框架开发规则读 `CLAUDE.md`。
3. 改 `skills/` / `scripts/` / `templates/` / `agents/` / `hooks/` 时，同步评估 `CHANGELOG.md` 未发布段。
4. 优先跑 targeted test；改测试编排、共享脚本或跨入口行为时再跑 `bash tests/run-all.sh`。

### 2. 从本 checkout 初始化消费仓

PM 在本生成器仓里让 Codex 起新业务项目时，等价执行 `/pmai-init-project`：

1. 读取 `skills/init-project/SKILL.md`。
2. 按 skill 的 A 步收集项目名、落地路径、背景和项目类型（`prototype` 或 `product`）。Codex 没有 AskUserQuestion 时，用编号问题向 PM 收集答案。
3. B 步优先调用本 checkout 的脚本搭骨架：

   ```bash
   bash scripts/init-project.sh "<project-name>" "<target-dir>" "<background>" "<project-type>"
   ```

   如果 PM 明确同意接住已有目录，再加 `--allow-existing`。

4. 脚本返回 0 只代表 B 步完成，不代表完整 `/pmai-init-project` 已完成。必须继续按 `skills/init-project/SKILL.md` 的 C/D 步执行：写 `PRODUCT.md` 一句话定位、填 `DESIGN.md`、尽量起 `prototype/` 主原型、按 skill 要求 commit，并输出 Next Up。
5. C/D 步完成后，消费仓根目录应生成 `AGENTS.md`、`CLAUDE.md` 和 `.codex/hooks.json`。后续在消费仓继续工作时，以消费仓自己的 `AGENTS.md` 为入口；Codex 首次启用项目 hooks 时可能要求信任确认。

### 3. 在消费仓中使用 PMAI

消费仓的 Codex 入口由 `templates/AGENTS.md.tmpl` 生成。进入消费仓后：

1. 先读消费仓根 `AGENTS.md`，再读 `CLAUDE.md`。
2. `/pmai-*` 命令按消费仓 `AGENTS.md` 解析到 `~/.pmai/skills/...`。
3. 需要脚本时走 `PMAI_HOME` 或 `~/.pmai`，不要把 framework 源资产复制进消费仓；`.codex/hooks.json` 只是 host 配置，hook 命令仍指向 `~/.pmai`。
4. 消费仓中不要再跑 `/pmai-init-project`；起模块工作走 `/pmai-design`，推进走 `/pmai-build` / `/pmai-build-close` / `/pmai-status`。

## 工作方式

1. 开始改动前先确认 `git status --short --branch`，不要覆盖用户未提交改动。
2. 需要了解框架现状时，先读 `CLAUDE.md`、`RUNTIME.md` 和相关 `skills/*/SKILL.md`，再改代码。
3. 改 `scripts/` / `skills/` / `templates/` / `agents/` / `hooks/` 这类会影响消费仓的资产时，同步评估是否需要更新 `CHANGELOG.md` 未发布段。
4. 手工编辑用 `apply_patch`，保持改动聚焦，不做无关重构。
5. 优先运行 targeted test，再按风险运行 `bash tests/run-all.sh`。

## Codex Runtime Fallback

- AskUserQuestion 不可用时，用简短编号问题向 PM 收集答案；没拿到明确答案前不要代替 PM 拍板。
- Claude Code subagent 不可用时，不要假装已经完整跑过 subagent review；应说明 runtime 限制，并用可验证的本地检查补位。
- review / qa / design-review 类外部工具仍由 PM 主动触发；Codex 可以列出建议和记录 PM 明确给出的结果。
- 需要网络、安装、推送、远端查询或写出工作区外文件时，先按当前 sandbox 规则申请权限。

## 护栏

- 不要把消费仓规则误套到本生成器仓：本仓可以改 `skills/`、`scripts/`、`templates/` 等框架源文件。
- 不要把 `~/.pmai/skills` 或 `~/.pmai/scripts` 复制回本仓。
- 不要把 repo-local `bash bin/pmai ...` 的结果误判为 installed user-facing CLI；涉及 install / doctor / status 时同时说明 CLI source 和 audit/status target。
- 不要恢复已移除的 `--local` 项目级安装模式；遗留项目副本只通过 `pmai uninstall --local <dir>` 清理。
