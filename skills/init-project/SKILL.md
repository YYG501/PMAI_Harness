---
name: init-project
description: |
  PM 主动入口 —— 起一个新业务项目时一气呵成 4 阶段：参数收集 + brownfield 检测 → 骨架建设
  → 方向讨论（PROJECT.md + roadmap.md）→ Next Up。在生成器仓里跑。
---

# /init-project（一气呵成入口）

> PM 起一个新业务项目时**只跑这一个命令**，agent 内部串起 4 阶段全流程；不切窗口、不跑第二个命令、不需要记中间步骤。

```
┌─────────────────────────────────────────────────────────┐
│              PMAI ► /init-project (M1)                  │
├─────────────────────────────────────────────────────────┤
│  阶段 A · 参数收集 + brownfield 检测                       │
│    name → path → [brownfield gate] → background → intent│
│                          ↓                              │
│  阶段 B · 骨架建设 (Bash → init-project.sh)               │
│    业务仓 + git init + 首 commit "init: <name>"          │
│                          ↓                              │
│  阶段 C · QUESTIONING (@读 _shared/project-questioning.md)│
│    讨论 → Decision gate "创建 PROJECT.md/继续探索" + Loop│
│    写 PROJECT.md + roadmap.md + atomic commit           │
│                          ↓                              │
│  阶段 D · 终态汇总 + Next Up（只汇总不 commit）            │
│    ✅ <name> 已就绪 / cd <target> && /new-req "..."     │
└─────────────────────────────────────────────────────────┘
```

---

## When To Use

- PM 在**生成器仓（PM-AI-Workflow）**里调用（业务仓里不能跑；init-project.sh 拷贝时已排除本 skill）
- PM 想起一个新业务项目（greenfield）—— 含项目方向讨论（PROJECT.md + roadmap.md），不只是空骨架

**不在 scope**：
- brownfield 项目接入 → 走 `/codebase-audit`（阶段 A 检测到目标目录已含 `.git/` 或代码会拒绝并提示）
- 已有项目重新规划方向 → 走 `/project-solution`（4 场景之一）
- 业务仓里起新需求 → 走 `/new-req`

---

## Workflow

> 4 阶段顺序执行；每阶段失败有显式兜底（见 §Rules / 失败兜底段）。

### 阶段 A · 参数收集 + brownfield 检测

**用 AskUserQuestion 分批问参数**，**5 步顺序**（不要一气呵成问完 4 个再 brownfield 检测，避免 PM 答完才发现路径无效）：

1. **项目名**（英文 kebab-case，如 `my-app`）—— AskUser
2. **落地路径**（绝对路径，如 `/Users/xxx/Projects/my-app`）—— AskUser
3. **brownfield 检测闸门**（在拿到路径后**立刻**做）：
   - `test -e <target-dir>` 已存在 → **拒绝 + 提示走 `/codebase-audit`**（"目标目录已存在；本 skill 只接 greenfield。如果要接入已有 codebase，请发 `/codebase-audit`"）
   - `test -d <target-dir>/.git` 或目录非空 → 同上拒绝
   - 通过 → 进 step 4
4. **一句话项目背景**（写进生成的 CLAUDE.md）—— AskUser
5. **项目意图**（`project-intent`，工程结构意图；AskUser 二选 / 三选）：
   - `prototype` — Next.js 单页原型 / Demo 仓（每页 self-contained，不抽 Template / hook / context）
   - `system` — 完整业务系统（多模块 + 后端契约 / 真实持久化 / 完整权限 / 完整测试）
   - `custom` — PM 自由编辑（不预设深度）
   - `unknown` — 探测兜底档（先 init 跑通后再分类）

**brownfield 接口约定**（review C-7 落实）：本 skill 阶段 A 拒已存在目录 + 提示 `/codebase-audit`；`scripts/init-project.sh` 也拒已存在目录（脚本不放宽，line 109-113）—— **两层都拦**，PM 任意一层拒都不会创建项目。

### 阶段 B · 骨架建设（agent Bash 调 init-project.sh）

agent 用 Bash 工具调：

```bash
bash scripts/init-project.sh "<project-name>" "<target-dir>" "<background>" "<intent>"
```

脚本会：
- 检测 gstack 依赖（gstack 未装 → 报错退出）
- 创建目标目录 + 复制模板 / 脚本 / skills / agents / hooks
- 按 `<intent>` 注入「工程结构约束」段进 CLAUDE.md
- 初始化 git（main 分支）+ 首 commit `init: <project-name>`
- 推导基础端口

agent 收到脚本退出码 0 后**汇报**：「✅ 骨架已就绪 / 目录 / 模板 / scripts / skills / agents / hooks 全部到位」→ 进阶段 C。

**失败兜底（R10）**：脚本退出码非 0 → agent 不进阶段 C，向 PM 报错（贴脚本 stderr）+ 提示 PM 检查（常见原因：chmod 权限 / git init 失败 / 模板 source 缺失）。

### 阶段 C · QUESTIONING（@读 `_shared/project-questioning.md`）

agent **@读 `skills/_shared/project-questioning.md`**（提问法 / 写作规则 / 收敛条件 / Decision gate 模板的单一真相源），按文件内 greenfield 顺序跑讨论：

1. agent 按 `_shared/project-questioning.md` 的提问法（greenfield 顺序）逐组问 PM
2. 讨论收敛时跑 **Decision gate**（gsd Decision gate pattern，3 条硬规则）：
   - 选项 1（推进）：「**创建 PROJECT.md**」—— "我会开始写 PROJECT.md + roadmap.md，进阶段 D"
   - 选项 2（留守）：「**继续探索**」—— "你还想补充行业 / 用户 / 流程 / 路线 ..."（选了 → Loop 回讨论态，不退出）
3. PM 选 "创建 PROJECT.md" → agent 按写作规则写 `<target-dir>/docs/PROJECT.md` + `<target-dir>/docs/roadmap.md`
4. **atomic commit**（review A5 落实）：

```bash
cd <target-dir>
git add docs/PROJECT.md docs/roadmap.md
git commit -m "docs: project direction settled"
```

5. 进阶段 D。

**失败兜底（R10）**：`_shared/project-questioning.md` 路径检测前置 → 缺失 → 报错 "框架未完整安装；请 git status 检查 skills/_shared/project-questioning.md"，不进讨论。

**失败兜底（R11）**：PM 阶段 C 中途答"停 / 等下 / 我先想想" → agent 检测 git 状态：
- 已 commit 阶段 B 骨架（首 commit `init: <name>` 已落）+ PROJECT.md 未 commit → **留 unstaged**，提示 PM "下次直接发 `/project-solution` 续上 PROJECT.md / roadmap.md 写作即可"
- 阶段 B 未完成 → 提示 PM 手动 `rm -rf <target-dir>` 重来

### 阶段 D · 终态汇总 + Next Up（只汇总不 commit）

> PROJECT.md / roadmap.md + commit 已在阶段 C 完成。阶段 D **只做终态输出**。

agent 输出 Next Up 块（对齐 M2 banner 规范）：

```
═══════════════════════════════════════
✅ <project-name> 已就绪
📁 位置: <target-dir>
📄 已创建: CLAUDE.md / docs/PROJECT.md / docs/roadmap.md / .claude/skills/ / .claude/scripts/ ...
═══════════════════════════════════════

▶ Next Up:
  cd <target-dir>
  /new-req "<一句话需求>"
```

---

## Rules

- 必须在框架仓库（PM-AI-Workflow）根目录运行（业务仓里跑不到本 skill）
- 目标目录不能已存在 + 不能含 `.git/` 或代码文件（两层拦：阶段 A skill 拒 + init-project.sh 拒）
- gstack 是硬依赖，未安装时阶段 B 脚本会报错退出
- 不要手动跳过阶段 C —— PROJECT.md / roadmap.md 是项目方向真相源，不能空骨架交付
- 提问法 / 5 组话术 / 写作规则**真相源只在 `skills/_shared/project-questioning.md`**；本 skill 阶段 C 不内嵌副本（避免双份维护漂移）

---

## 失败兜底速查

| 场景 | 兜底 |
|---|---|
| 阶段 A brownfield 检测命中（目标目录已存在 / 含 git / 含代码）| 拒绝 + 提示走 `/codebase-audit` |
| 阶段 B `init-project.sh` 失败（chmod / git init / 模板缺失）| 报错贴 stderr + PM 检查；不进阶段 C |
| 阶段 B 跑成功但 `_shared/project-questioning.md` 缺失 | 阶段 C 入口前置检测 + 报错 "框架未完整安装" |
| 阶段 C PM 答"停" + 骨架已 commit | PROJECT.md / roadmap.md 留 unstaged + 提示下次 `/project-solution` 续 |
| 阶段 C PM 答"停" + 骨架未 commit | 提示手动 `rm -rf <target-dir>` 重来 |
