---
name: pmai-init-project
description: |
  PM 主动入口 —— 起一个新业务项目时一气呵成 4 阶段：参数收集（含已有内容判断）→ 骨架建设
  → 方向讨论（PROJECT.md + ROADMAP.md）→ Next Up。在生成器仓里跑。
---

# /pmai-init-project（一气呵成入口）

> PM 起一个新业务项目时**只跑这一个命令**，agent 内部串起 4 阶段全流程；不切窗口、不跑第二个命令、不需要记中间步骤。
>
> **PM 视图（M2 banner + Decision gate label）**：4 阶段每阶段入口出 banner（`status-view.py --banner-only --skill INIT-PROJECT`）；阶段 C Decision gate「创建 PROJECT.md / 继续探索」按 `_shared/pm-view/banner-rules.md` §3 3 硬规则；阶段 D Next Up 块按 §2 格式。
>
> **PM 答题规则（M4）**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 3 硬规则走（空答 STOP / 没拿到答案禁止落盘 PROJECT.md / runtime 退化保留 wait）。

```
┌─────────────────────────────────────────────────────────┐
│              PMAI ► /pmai-init-project (M1)                  │
├─────────────────────────────────────────────────────────┤
│  阶段 A · 参数收集（含已有内容判断）                        │
│    项目名 → 落地路径 → 已有内容判断 → 一句话背景 → 项目类型 │
│                          ↓                              │
│  阶段 B · 骨架建设 (Bash → init-project.sh)               │
│    业务仓 + git init + 首 commit "init: <name>"          │
│                          ↓                              │
│  阶段 C · QUESTIONING (@读 _shared/project-questioning.md)│
│    讨论 → Decision gate "创建 PROJECT.md/继续探索" + Loop│
│    写 PROJECT.md + ROADMAP.md + atomic commit           │
│                          ↓                              │
│  阶段 C.5 · 视觉基线（调 gstack /design-consultation）     │
│    gstack 跑 → DESIGN.md 视觉基线 8 段 + 我们追加 inventory│
│    + PM 定稿确认 + commit                                 │
│                          ↓                              │
│  阶段 D · 终态汇总 + Next Up（只汇总不 commit）            │
│    ✅ <name> 已就绪 / cd <target> && /pmai-new-req "..."     │
└─────────────────────────────────────────────────────────┘
```

---

## When To Use

- PM 在**生成器仓（PM-AI-Workflow）**里调用（业务仓里不能跑；init-project.sh 拷贝时已排除本 skill）
- PM 想起一个新业务项目（greenfield）—— 含项目方向讨论（PROJECT.md + ROADMAP.md），不只是空骨架

**不在 scope**：
- 接入已有 codebase → 走 `/pmai-codebase-audit`（阶段 A step 3a 检测到代码标志后会拒绝并提示）
- 已有项目重新规划方向 → 走 `/pmai-project-solution`（4 场景之一）
- 业务仓里起新需求 → 走 `/pmai-new-req`

---

## Workflow

> 5 阶段顺序执行（A / B / C / C.5 / D）；每阶段失败有显式兜底（见 §Rules / 失败兜底段）。
>
> **M2 banner**（见 `_shared/pm-view/banner-rules.md` §1）：agent 进入每个阶段时**先 Bash echo 一行 banner**。init-project 是项目级 skill（生成器仓内跑、无 active req），不调 `status-view.py`，直接 echo 字面值：
> - 阶段 A：`echo "━━━ PMAI ► INIT-PROJECT ▸ Stage A/5: 参数收集 ━━━"`
> - 阶段 B：`echo "━━━ PMAI ► INIT-PROJECT ▸ Stage B/5: 骨架建设 ━━━"`
> - 阶段 C：`echo "━━━ PMAI ► INIT-PROJECT ▸ Stage C/5: QUESTIONING ━━━"`
> - 阶段 C.5：`echo "━━━ PMAI ► INIT-PROJECT ▸ Stage C.5/5: 视觉基线 ━━━"`
> - 阶段 D：`echo "━━━ PMAI ► INIT-PROJECT ▸ Stage D/5: 终态汇总 ━━━"`

### 阶段 A · 参数收集（含已有内容判断）

**AskUserQuestion 分批问参数**，**5 步顺序**（拿到关键值就立刻判断，避免 PM 答完一堆才发现路径不行）：

1. **项目名**（英文 kebab-case，如 `my-app`）—— AskUser

2. **落地路径**（**禁让 PM 从空白手敲绝对路径**；自适应推默认）：

   - **先用 Bash 自适应推默认值**：
     ```bash
     PWD_DIR="$(pwd)"
     # 判断 PM 是否在生成器仓 / 全局副本里跑（含 skills/init-project/SKILL.md 即是）
     if [ -f "$PWD_DIR/skills/init-project/SKILL.md" ]; then
       # 在生成器仓跑（老模式：cd 进 PM-AI-Workflow 再跑）→ 推兄弟目录
       DEFAULT_PATH="$(dirname "$PWD_DIR")/<project-name>"
       DEFAULT_NOTE="（你在生成器仓里跑，推断兄弟目录）"
     else
       # 在任意 cwd 跑（v1.1 后 pmai install + 全局 symlink 支持）→ 推 cwd 本身
       DEFAULT_PATH="$PWD_DIR"
       DEFAULT_NOTE="（你在这个目录启 claude → 直接在当前位置 init）"
     fi
     ```
   - AskUser 二选 1：
     - 选项 ① "用 `<DEFAULT_PATH>`<DEFAULT_NOTE>"（推荐）
     - 选项 ② "换别的路径"（PM 选 ② 再补一道 AskUser 让 PM 给绝对路径）

   **PM 在 cwd 直接 init 的常见场景**：PM `cd /Users/x/Projects/my-app && claude` → cwd = `/Users/x/Projects/my-app` → 走 else 分支 default = cwd → step 3 检查 cwd 内容（如果有资料 → step 3b 三选接住；如果是 codebase → step 3a 拒）→ 阶段 B 加 `--allow-existing` 落地。

3. **AI 主动诊断 + 出方案**（PM 既然在 cwd 启 claude → AI 直接看 + 直接拍，**PM 只一拍即可**；不要给三选菜单装懂事）：

   **3.1 列 cwd 内容**：
   ```bash
   # 含 . 开头条目；标 dir/file + 大小；超过 50 条只列前 50
   ls -lAh "$TARGET_DIR" | head -50
   # 同时 git 状态（如果是 git repo）
   [ -d "$TARGET_DIR/.git" ] && git -C "$TARGET_DIR" log --oneline -5 2>/dev/null
   ```

   **3.2 AI 逐条标注**（推测用途 / 类型；不写清单不能装懂事）—— 维度：

   | 类型 | 判断 | 默认处置 |
   |---|---|---|
   | 系统噪音 | `.DS_Store` / `Thumbs.db` / `*.log` | `.gitignore` 处理；不动文件 |
   | 已有 git | `.git/` + 有/无 commit history | reinit 兼容（git init 是 noop）；有 commit → 提示 PM 确认是否在已 history 上叠 PMAI |
   | 工具配置 | `.gitignore` / `.editorconfig` / `.nvmrc` | 跟 PMAI 模板**合并**（去重并集），不覆盖 |
   | 文档 | `README.md` / `LICENSE` / `*.md` 笔记 | 保留原位；若 PMAI 模板有同名 → 合并或加 `.pmai` 后缀 |
   | 资料/导出 | `*.json` ChatGPT 导出 / `*.pdf` 资料 / `*.csv` / `*.xlsx` | 归档到 `docs/inputs/<语义子目录>/`（子目录名 AI 看文件名+内容推） |
   | 源码 | `*.py` / `*.js` / `*.ts` / 任何 manifest（`package.json`/`pyproject.toml`/...）| **提示 PM 优先跑 `/pmai-codebase-audit`** 产出现状档；PM 坚持 init 也允许（init 不删代码 + 可逆） |
   | 已有 framework | 含 `docs/PROJECT.md` / `.pm-workflow/` / 其他 PMAI 元数据 | 提示 PM 这里曾经 init 过 → 是否走 `/pmai-project-solution` 重做方向更合适 |

   **3.3 AI 给完整方案**（结构化展示，每条一行说清「源 → 目标」）：

   ```
   📍 当前位置: <target-dir>

   📂 内容（ls -A）:
     <逐条 + 大小 + AI 推测用途>

   💡 判断:
     - <一条关键判断>
     - <... 视情况>

   🎯 方案:
     1. 项目根 = <target-dir>（你已经在这里）
     2. <现有文件 1> → <处置；如归档目标路径或保留>
     3. <... 逐条>
     N. git: reinit / 首次 init（视 .git/ 状态）+ 首 commit 含 PMAI 元数据 + 归档资料
   ```

   **3.4 PM 一拍即可**（AskUser 二选，**默认走方案**）：
   - 选项 ① "按这个方案走"（推荐）
   - 选项 ② "我要改"（PM 自由 chat 反馈具体哪条要调；AI 改完回 3.3 再确认；可循环）

   **3.5 PM 选 ① → AI 执行**：
   ```bash
   # 1. 归档动作（仅 3.3 方案标了归档的文件）
   mkdir -p "$TARGET_DIR/<归档目标路径>"
   mv "$TARGET_DIR/<source-file>" "$TARGET_DIR/<归档目标路径>/"
   # 2. 配置合并（如 .gitignore 跟 PMAI 模板并集去重）
   # 3. 调 init-project.sh --allow-existing 接住非空目录
   bash "$SCRIPT" "<project-name>" "<target-dir>" "<background>" "<intent>" --allow-existing
   ```

   **退化捷径**：
   - cwd 完全空（`ls -A` 空）+ 无 `.git/` → 跳过 3.3/3.4，直接调 init-project.sh（不带 `--allow-existing`，走老 mkdir 路径）
   - cwd 只有 `.DS_Store` → 跳过 3.3/3.4，直接 init + `--allow-existing`（无需 PM 拍方案）

   **edge case 提示**：
   - **已有 codebase**（源码 / manifest）：AI 在 3.3 方案里**优先推荐** `/pmai-codebase-audit`，但**不硬 gate**（[[feedback_pm_decision_is_binding_contract]]：PM 拍 init 即接住，init 不破坏代码 + 可逆）
   - **已有 PMAI 元数据**：AI 在 3.3 方案里**优先推荐** `/pmai-project-solution` 重做方向，同样不硬 gate

4. **一句话项目背景**（写进生成的 CLAUDE.md）—— AskUser

5. **项目类型**（决定生成的工程结构约束段；AskUser 三选 / 四选）：
   - `prototype` — Next.js 单页原型 / Demo 仓（每页 self-contained，不抽 Template / hook / context）
   - `system` — 完整业务系统（多模块 + 后端契约 / 真实持久化 / 完整权限 / 完整测试）
   - `custom` — PM 自由编辑（不预设深度）
   - `unknown` — 先 init 跑通后再分类（探测兜底档）

**已有内容接口约定**（review C-7 + 2026-05-27 PM 反馈两轮细化）：
- **AI 主动诊断不硬 gate**：本 skill step 3 由 AI `ls -A` + 逐条标注 + 给完整方案 + PM 一拍即可走（不再写死代码标志清单、不再给三选菜单装懂事）
- **codebase / 已 init 项目优先推荐 audit / project-solution**：3.3 方案里 AI 优先建议跑 `/pmai-codebase-audit`（已有源码）或 `/pmai-project-solution`（已有 PMAI 元数据），但**不硬 gate**（[[feedback_pm_decision_is_binding_contract]]：PM 坚持 init 也接住 —— init 不删代码 + 可逆）
- **脚本层默认仍拒**：`init-project.sh` 段 c（line 118+）默认拒已存在目录；本 skill 通过 `--allow-existing` flag 接住 PM 拍后的方案。脚本本身不判断内容是否真是 codebase（那是 skill 层 AI 诊断的责任）

### 阶段 B · 骨架建设（agent Bash 调 init-project.sh）

agent 用 Bash 工具调（**绝对路径**走 `$PMAI_HOME` —— v1.1 后 PM 在任意 cwd 跑都行；按阶段 A step 3.5 的 PM 拍板决定是否加 `--allow-existing`）：

```bash
SCRIPT="${PMAI_HOME:-$HOME/.pmai}/scripts/init-project.sh"
# fallback: 如果 PM 在生成器仓里直接跑（无 pmai install），用本仓 scripts/
[ ! -f "$SCRIPT" ] && [ -f "$(pwd)/scripts/init-project.sh" ] && SCRIPT="$(pwd)/scripts/init-project.sh"

# 默认（目标目录不存在 / 阶段 A step 3 完全空 / 只有 .DS_Store 的退化捷径）
bash "$SCRIPT" "<project-name>" "<target-dir>" "<background>" "<intent>"

# 阶段 A step 3.5 PM 拍方案后（cwd 非空 / 含资料 / 含已有内容）
bash "$SCRIPT" "<project-name>" "<target-dir>" "<background>" "<intent>" --allow-existing
```

脚本会：
- 检测 gstack 依赖（gstack 未装 → 报错退出）
- 默认：拒已存在目录（line 119+）；命中 `--allow-existing` → 跳过该检查，目录可非空
- 创建目标目录（已存在则用现有）+ 复制模板 / 脚本 / skills / agents / hooks
- 按 `<intent>` 注入「工程结构约束」段进 CLAUDE.md
- 初始化 git（main 分支）+ 首 commit `init: <project-name>`（命中 `--allow-existing` 时首 commit 也包含 PM 原本就放在目录里的资料文件）
- 推导基础端口

agent 收到脚本退出码 0 后**汇报**：「✅ 骨架已就绪 / 目录 / 模板 / scripts / skills / agents / hooks 全部到位」→ 进阶段 C。

**失败兜底（R10）**：脚本退出码非 0 → agent 不进阶段 C，向 PM 报错（贴脚本 stderr）+ 提示 PM 检查（常见原因：chmod 权限 / git init 失败 / 模板 source 缺失）。

### 阶段 C · QUESTIONING（@读 `_shared/project-questioning.md`）

agent **@读 `skills/_shared/project-questioning.md`**（**单一真相源** —— 提问法 / 问题库 / 写作规则 / 闸门 / Decision gate / 检查清单），按文件内 §10.1 greenfield 调用方实现指南跑：

1. **§2 提问纪律 + §3 问题库**：按 greenfield 6 节顺序问 PM
2. **§4 未决问题闸门**：暂存文件 `docs/.project-solution-open-questions.md`（路径用 `<target-dir>/docs/...`）
3. **§6 Decision gate 模板**：跑「创建 PROJECT.md / 继续探索」二选一 + Loop 回路（**选项内容 / label / description 全按 `_shared` §6.2，本 SKILL 不内嵌副本**）
4. **§5 写作规则**：PM 选「创建 PROJECT.md」后写 `<target-dir>/docs/PROJECT.md` + `<target-dir>/docs/ROADMAP.md`
5. **§7 6 节齐不齐检查**：跑 `check-project-sections.py` 验证
6. **§8 PM 定稿**：展示路径 + 摘要，PM 答「OK / 定了」推进
7. **§9 atomic commit**（review A5）：`git commit -m "docs: project direction settled"`
8. 进阶段 D。

**失败兜底（R10）**：`_shared/project-questioning.md` 路径检测前置 → 缺失 → 报错 "框架未完整安装；请 git status 检查 skills/_shared/project-questioning.md"，不进讨论。

**失败兜底（R11）**：PM 阶段 C 中途答"停 / 等下 / 我先想想" → agent 检测 git 状态：
- 已 commit 阶段 B 骨架（首 commit `init: <name>` 已落）+ PROJECT.md 未 commit → **留 unstaged**，提示 PM "下次直接发 `/pmai-project-solution` 续上 PROJECT.md / ROADMAP.md 写作即可"
- 阶段 B 未完成 → 提示 PM 手动 `rm -rf <target-dir>` 重来

### 阶段 C.5 · 视觉基线（调 gstack `/design-consultation` + 追加 inventory）

> **为什么有这步**：DESIGN.md 是 task executor 写代码时的硬约束（`task-execute` 步骤 2.0 强制 echo 全文）。如果视觉基线没在 task 启动前定好，executor 在"颜色 / 字体 / 间距 / 动效"这些维度上没规范可遵守 → 乱搞。本阶段把项目级视觉基线一次性建好。
>
> **职责分工**：gstack `/design-consultation` 包揽视觉基线（颜色 / 字体 / 间距 / 布局 / 动效 / 美学方向 / 竞品研究 / 视觉预览板）写 DESIGN.md 头 8 段；我们追加「共享组件 inventory」段（req 级累积用，gstack 不管）。
>
> **不抄 gstack** —— 直接调它的 skill，跟随它的升级。下游 SKILL 不解析 gstack 写的字段，只读 inventory 段，gstack 自由演化我们自动兼容。

**步骤**：

1. **跟 PM 说一句开场**：
   ```
   接下来跑 gstack /design-consultation 给项目定视觉基线（颜色 / 字体 / 布局 / 动效）。
   它会问产品调性、是否要竞品研究、生成视觉预览板等。跟着它的对话走。
   gstack 跑完后我再补一段空的「共享组件 inventory」表，stage 4 累积用。
   ```

2. **调 `/design-consultation`**（用 Skill 工具）—— gstack 接管对话流，PM 跟 gstack 互动定视觉方向。gstack Phase 6 把 DESIGN.md 写到 `<target-dir>/docs/DESIGN.md`（gstack 的 8 段 + Decisions Log）。

3. **gstack 跑完后回到本 SKILL**，AI 用 Edit 工具在 DESIGN.md **末尾追加**「共享组件 inventory」空段：
   ```markdown

   ## 共享组件 inventory

   > **这是什么**：stage 4 gap-check 的查询底座。每个 req 动手前逐组件查这里：
   > **有 → 复用**；**没有 → 新建并加进本表**。req 间累积，越来越全，reuse 率随之上升。
   > **gstack `/design-consultation` 不管这段**，由本框架的 `/pmai-req-stage-gate` Stage 4 4A 累积。

   | 组件名 | 用途 | 视觉 | 状态 | 交互 | 出处 req |
   |---|---|---|---|---|---|
   | <!-- stage 4 4A 累积，目前为空 --> | | | | | |
   ```

4. **PM 定稿确认门**：

   ```bash
   # 自检：占位 __ 应该已被 gstack 全部替换为具体值
   PLACEHOLDERS=$(grep -c "__\|#______" "$TARGET_DIR/docs/DESIGN.md" 2>/dev/null || echo 0)
   # 自检：inventory 段是否已追加
   HAS_INVENTORY=$(grep -c "^## 共享组件 inventory" "$TARGET_DIR/docs/DESIGN.md" 2>/dev/null || echo 0)
   ```

   - `PLACEHOLDERS > 0` → 警告 PM「gstack 写的视觉基线还有占位没填，建议回去补 gstack 流程」（不硬卡，PM 可以选择推进 + 后续手补）
   - `HAS_INVENTORY = 0` → 步骤 3 追加失败，必须修复

   定稿确认（AskUserQuestion，按 `_shared/pm-view/askuser-rules.md` §1 走）：
   ```
   📋 视觉基线定稿确认：
    - 颜色 / 字体 / 间距 / 布局 / 动效 都已具体化（占位检查：{PLACEHOLDERS} 个未填）
    - 共享组件 inventory 段已建（stage 4 累积用）
   PM 确认推进？
   ```

5. **atomic commit**：
   ```bash
   cd "$TARGET_DIR"
   git add docs/DESIGN.md
   git commit -m "docs(DESIGN): 视觉基线定稿（gstack /design-consultation + inventory 段）"
   ```

6. 进阶段 D。

**失败兜底（R12）**：gstack 未安装 / `/design-consultation` 调用失败 → 跟 PM 说「gstack 不可用，跳过 C.5。DESIGN.md 留空，第一个 req 进 stage 4 时再起视觉基线。」直接进阶段 D（DESIGN.md 不存在也不阻塞下游 —— stage 4 4A 会兜底）。

**失败兜底（R13）**：PM 在 C.5 答"停 / 等下" → DESIGN.md 留 gstack 写到一半的状态（unstaged），提示 PM "下次想续可以直接调 `/design-consultation`，inventory 段需要手动追加 / 跑 `/pmai-req-stage-gate` 时自动兜底。"

### 阶段 D · 终态汇总 + Next Up（只汇总不 commit）

> PROJECT.md / ROADMAP.md + DESIGN.md commit 已分别在阶段 C / C.5 完成。阶段 D **只做终态输出**。

agent 输出 Next Up 块（对齐 M2 banner 规范）：

```
═══════════════════════════════════════
✅ <project-name> 已就绪
📁 位置: <target-dir>
📄 已创建: CLAUDE.md / docs/PROJECT.md / docs/ROADMAP.md / docs/DESIGN.md / .claude/skills/ / .claude/scripts/ ...
═══════════════════════════════════════

▶ Next Up:
  cd <target-dir>
  /pmai-new-req "<一句话需求>"
```

---

## Rules

- v1.1 后 PM 在**任意 cwd** 都能调（`pmai install` 后 `~/.claude/skills/pmai-init-project` 全局可用）；阶段 B 脚本路径走 `$PMAI_HOME` 绝对路径
- 老模式兼容：PM 在生成器仓根目录跑也行（脚本 `$PMAI_HOME` fallback 到 `$(pwd)/scripts/init-project.sh`）
- 目标目录默认不能已存在；step 3a 命中代码标志硬拒；step 3b 资料档分流由 PM 三选决定（AI 加 `--allow-existing` 接住）
- gstack 是硬依赖，未安装时阶段 B 脚本会报错退出
- 不要手动跳过阶段 C —— PROJECT.md / ROADMAP.md 是项目方向真相源，不能空骨架交付
- 阶段 C.5 调 gstack `/design-consultation` 的输出（DESIGN.md 头 8 段 + Decisions Log）**不抄、不映射、不重写** —— 直接接受 gstack 写的内容；我们只在末尾追加「共享组件 inventory」段。gstack 升级时自动跟上。
- 提问法 / 5 组话术 / 写作规则**真相源只在 `skills/_shared/project-questioning.md`**；本 skill 阶段 C 不内嵌副本（避免双份维护漂移）

### PM-facing 输出禁词（[[feedback_pm_chat_no_engineering_jargon]] 词典 A）

AI 跟 PM 对话时**禁出现**下列工程黑话：`brownfield` / `greenfield` / `intent` / `project-intent` / `gate` / `闸门` / `brownfield 检测` / `brownfield 接口`。

这些是 AI 内部状态词 / 模型术语，PM 视角无对应心智。PM 视图用：

| 禁词 | PM 视角替代 |
|---|---|
| `brownfield` / `brownfield 检测` | 「已有 codebase」/「已有内容判断」 |
| `greenfield` | 「全新项目」 |
| `intent` / `project-intent` | 「项目类型」 |
| `gate` / `闸门` | 「判断」/ 直接砍 |
| `name → path → ... → intent` | 「项目名 → 落地路径 → 已有内容判断 → 一句话背景 → 项目类型」 |

SKILL.md 内部段落（"为什么这步" / "review C-7 落实"）保留 `brownfield` 概念词用于设计文档准确性；AI 跟 PM 对话 / banner / AskUser 文案 / Next Up 块时必须翻译。

---

## 失败兜底速查

| 场景 | 兜底 |
|---|---|
| 阶段 A step 3 cwd 完全空 / 只 `.DS_Store` | 跳过 3.3/3.4 退化捷径；直接调脚本 |
| 阶段 A step 3 AI 出方案 + PM 选 ①（走方案）| AI 执行归档 mv + 调脚本加 `--allow-existing` |
| 阶段 A step 3 PM 选 ②（要改）| 等 PM 文本反馈具体哪条改；AI 调整方案后回 3.3/3.4 再确认（可循环）|
| 阶段 A step 3 AI 诊断到已有 codebase / PMAI 元数据 | 3.3 方案里**优先推荐** `/pmai-codebase-audit` 或 `/pmai-project-solution`；PM 坚持 init 也接住（不硬 gate）|
| 阶段 B `init-project.sh` 失败（chmod / git init / 模板缺失）| 报错贴 stderr + PM 检查；不进阶段 C |
| 阶段 B 跑成功但 `_shared/project-questioning.md` 缺失 | 阶段 C 入口前置检测 + 报错 "框架未完整安装" |
| 阶段 C PM 答"停" + 骨架已 commit | PROJECT.md / ROADMAP.md 留 unstaged + 提示下次 `/pmai-project-solution` 续 |
| 阶段 C PM 答"停" + 骨架未 commit | 提示手动 `rm -rf <target-dir>` 重来 |
| 阶段 C.5 gstack 未安装 / `/design-consultation` 调用失败 | 跳过 C.5，DESIGN.md 留空；第一个 req 进 stage 4 4A 时兜底 |
| 阶段 C.5 PM 答"停" | DESIGN.md 留 gstack 写到一半的 unstaged 状态；下次手调 `/design-consultation` 续 |
