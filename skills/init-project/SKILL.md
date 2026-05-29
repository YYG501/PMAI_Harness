---
name: pmai-init-project
description: |
  PM 主动入口 —— 起一个新业务项目时一气呵成 4 步：参数收集（含已有内容判断）→ 骨架建设
  → 上下文脊柱（PRODUCT-STATE + PROJECT + DESIGN + prototype/ 主原型）→ Next Up。在生成器仓里跑。
---

# /pmai-init-project（一气呵成入口）

> PM 起一个新业务项目时**只跑这一个命令**，agent 内部串起全流程；不切窗口、不跑第二个命令、不需要记中间步骤。
>
> **它建的是"上下文脊柱"**：项目级的几份文件 + 一份能跑的主原型，AI 以后每次进项目先读它们，治失忆。不是一堆走流程的中间稿。
>
> **PM 视图**：每一步入口先 echo 一行进度条（banner 规范见 `_shared/pm-view/banner-rules.md`）；最后一步给 ▶ Next Up 块。

```
┌─────────────────────────────────────────────────────────┐
│              PMAI ► /pmai-init-project                      │
├─────────────────────────────────────────────────────────┤
│  A · 参数收集（含已有内容判断）                            │
│    项目名 → 落地路径 → 已有内容判断 → 一句话背景 → 项目类型 │
│                          ↓                              │
│  B · 骨架建设 (Bash → init-project.sh)                   │
│    业务仓 + git init + 首 commit "init: <name>"          │
│                          ↓                              │
│  C · 项目方向（@读 _shared/project-questioning.md）        │
│    讨论 → 确认门 → 写 PROJECT.md + ROADMAP.md + commit   │
│                          ↓                              │
│  C.5 · 视觉基线 + 主原型脚手架                             │
│    DESIGN.md（正向视觉约束）+ prototype/ 起一版能跑 + commit│
│                          ↓                              │
│  D · 终态汇总 + Next Up（只汇总不 commit）                │
│    ✅ <name> 已就绪 / cd <target> && /pmai-new-req "..."    │
└─────────────────────────────────────────────────────────┘
```

---

## When To Use

- PM 在**生成器仓（PM-AI-Workflow）**里调用（业务仓里不能跑；init-project.sh 拷贝时已排除本 skill）
- PM 想起一个新业务项目 —— 含项目方向讨论（PROJECT.md + ROADMAP.md）+ 视觉基线（DESIGN.md）+ 一版能跑的主原型，不只是空骨架

**不在 scope**：

- 接入已有 codebase → 走 `/pmai-codebase-audit`（A 步 AI 诊断到源码时会优先推荐）
- 已有项目重新规划方向 → 走 `/pmai-project-solution`
- 业务仓里起新需求 → 走 `/pmai-new-req`

---

## 这一步建出什么（上下文脊柱）

init 跑完后，项目里有这几样，构成 AI 以后每次进项目的"必读上下文"：

| 文件 / 目录 | 装什么 | 谁写 / 谁读 |
|---|---|---|
| `docs/PROJECT.md` | 定位 / 用户 / 角色 / 术语 / 路线（项目方向真相源） | C 步讨论后写；每次进项目读 |
| `docs/ROADMAP.md` | 路线节奏 | C 步写 |
| `docs/PRODUCT-STATE.md` | 产品**现状层**（现在长什么样、做到哪、哪些真哪些 mock）；模板已就位，内容随每次沉淀累积 | 只在 close-req 沉淀那刻更新；每个新需求开头先读 |
| `docs/DESIGN.md` | 视觉与交互约定（**正向约束**：该怎么做，不是禁止清单） | C.5 起草；build 前 AI 必读再动手 |
| `docs/PRODUCT-RULES.md` | 跨功能产品规则 | 随产品演进 PM 调 |
| `prototype/` | **单一主原型**（默认 Next.js + TS + Tailwind + shadcn，init 时可改栈）；所有需求的原型都在这一条线上演进 | C.5 起一版能跑的；每个需求在自己后台暂存区改它，确认后并回 main |

> 模板源：`templates/PRODUCT-STATE.md.tmpl` / `templates/DESIGN.md.tmpl` / `templates/PRODUCT-RULES.md.tmpl` / `templates/prototype-README.md.tmpl`。骨架建设（B 步）由 `init-project.sh` 把这些铺到位，本 skill 负责把内容讨论 / 填进去。

---

## Workflow

> 顺序执行 A / B / C / C.5 / D；每步失败有显式兜底（见 §失败兜底速查）。
>
> **进度条**：agent 进入每一步**先 Bash echo 一行**。init-project 是项目级 skill（生成器仓内跑、无 active req），直接 echo 字面值：
> - A：`echo "━━━ PMAI ► INIT-PROJECT ▸ A/5: 参数收集 ━━━"`
> - B：`echo "━━━ PMAI ► INIT-PROJECT ▸ B/5: 骨架建设 ━━━"`
> - C：`echo "━━━ PMAI ► INIT-PROJECT ▸ C/5: 项目方向 ━━━"`
> - C.5：`echo "━━━ PMAI ► INIT-PROJECT ▸ C.5/5: 视觉基线 + 主原型 ━━━"`
> - D：`echo "━━━ PMAI ► INIT-PROJECT ▸ D/5: 终态汇总 ━━━"`

### A · 参数收集（含已有内容判断）

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
       # 在任意 cwd 跑（pmai install + 全局 symlink 支持）→ 推 cwd 本身
       DEFAULT_PATH="$PWD_DIR"
       DEFAULT_NOTE="（你在这个目录启 claude → 直接在当前位置 init）"
     fi
     ```
   - AskUser 二选 1：
     - 选项 ① "用 `<DEFAULT_PATH>`<DEFAULT_NOTE>"（推荐）
     - 选项 ② "换别的路径"（PM 选 ② 再补一道 AskUser 让 PM 给绝对路径）

   **PM 在 cwd 直接 init 的常见场景**：PM `cd /Users/x/Projects/my-app && claude` → cwd = `/Users/x/Projects/my-app` → 走 else 分支 default = cwd → step 3 检查 cwd 内容（如果有资料 → step 3b 三选接住；如果是 codebase → 优先推荐 audit）→ B 步加 `--allow-existing` 落地。

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
   | 已有 framework | 含 `docs/PROJECT.md` / 其他 PMAI 元数据 | 提示 PM 这里曾经 init 过 → 是否走 `/pmai-project-solution` 重做方向更合适 |

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
     N. git: reinit / 首次 init（视 .git/ 状态）+ 首 commit 含 PMAI 脚手架 + 归档资料
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
   bash "$SCRIPT" "<project-name>" "<target-dir>" "<background>" "<mode>" --allow-existing
   ```

   **退化捷径**：
   - cwd 完全空（`ls -A` 空）+ 无 `.git/` → 跳过 3.3/3.4，直接调 init-project.sh（不带 `--allow-existing`，走老 mkdir 路径）
   - cwd 只有 `.DS_Store` → 跳过 3.3/3.4，直接 init + `--allow-existing`（无需 PM 拍方案）

   **edge case 提示**：
   - **已有 codebase**（源码 / manifest）：AI 在 3.3 方案里**优先推荐** `/pmai-codebase-audit`，但**不硬 gate**（[[feedback_pm_decision_is_binding_contract]]：PM 拍 init 即接住，init 不破坏代码 + 可逆）
   - **已有 PMAI 脚手架**：AI 在 3.3 方案里**优先推荐** `/pmai-project-solution` 重做方向，同样不硬 gate

4. **一句话项目背景**（写进生成的 CLAUDE.md）—— AskUser

5. **项目类型 / mode 基线**（决定主原型按哪一档实现深度走 + 注入哪份「工程结构约束」段；AskUser 四选）：
   - `prototype` — Next.js 单页原型 / Demo 仓（每页 self-contained，全 mock，不抽 Template / hook / context）—— 起步默认
   - `system` — 完整业务系统（多模块 + 后端契约 / 真实持久化 / 完整权限 / 完整测试）
   - `custom` — PM 自由编辑（按层混搭，不预设深度）
   - `unknown` — 先 init 跑通后再分类（探测兜底档）

   > 这个选项决定主原型 `prototype/` 默认按哪一档建（mode 中立：原型档全 mock / 真系统档真后端），以及 `工程结构约束-{档}.md` 注入哪份。某层以后从 mock 转真，是一次显式拍板的需求，在主原型里原地重写那层，不另开分叉。

**已有内容接口约定**：
- **AI 主动诊断不硬 gate**：本 skill step 3 由 AI `ls -A` + 逐条标注 + 给完整方案 + PM 一拍即可走（不写死代码标志清单、不给三选菜单装懂事）
- **codebase / 已 init 项目优先推荐 audit / project-solution**：3.3 方案里 AI 优先建议跑 `/pmai-codebase-audit`（已有源码）或 `/pmai-project-solution`（已有 PMAI 脚手架），但**不硬 gate**（[[feedback_pm_decision_is_binding_contract]]：PM 坚持 init 也接住 —— init 不删代码 + 可逆）
- **脚本层默认仍拒**：`init-project.sh` 默认拒已存在目录；本 skill 通过 `--allow-existing` flag 接住 PM 拍后的方案。脚本本身不判断内容是否真是 codebase（那是 skill 层 AI 诊断的责任）

### B · 骨架建设（agent Bash 调 init-project.sh）

agent 用 Bash 工具调（**绝对路径**走 `$PMAI_HOME` —— PM 在任意 cwd 跑都行；按 A 步 step 3.5 的 PM 拍板决定是否加 `--allow-existing`）：

```bash
SCRIPT="${PMAI_HOME:-$HOME/.pmai}/scripts/init-project.sh"
# fallback: 如果 PM 在生成器仓里直接跑（无 pmai install），用本仓 scripts/
[ ! -f "$SCRIPT" ] && [ -f "$(pwd)/scripts/init-project.sh" ] && SCRIPT="$(pwd)/scripts/init-project.sh"

# 默认（目标目录不存在 / A 步 step 3 完全空 / 只有 .DS_Store 的退化捷径）
bash "$SCRIPT" "<project-name>" "<target-dir>" "<background>" "<mode>"

# A 步 step 3.5 PM 拍方案后（cwd 非空 / 含资料 / 含已有内容）
bash "$SCRIPT" "<project-name>" "<target-dir>" "<background>" "<mode>" --allow-existing
```

脚本会：
- 检测 gstack 依赖（gstack 未装 → 报错退出）
- 默认：拒已存在目录；命中 `--allow-existing` → 跳过该检查，目录可非空
- 创建目标目录（已存在则用现有）+ 铺脊柱模板（PRODUCT-STATE / DESIGN / PRODUCT-RULES / ROADMAP + prototype/ README 等）
- 按 `<mode>`（项目类型）注入对应的「工程结构约束」段进 CLAUDE.md
- 初始化 git（main 分支）+ 首 commit `init: <project-name>`（命中 `--allow-existing` 时首 commit 也包含 PM 原本就放在目录里的资料文件）

agent 收到脚本退出码 0 后**汇报**：「✅ 骨架已就绪 / 脊柱模板 + scripts + 工程结构约束段全部到位」→ 进 C 步。

**失败兜底**：脚本退出码非 0 → agent 不进 C 步，向 PM 报错（贴脚本 stderr）+ 提示 PM 检查（常见原因：chmod 权限 / git init 失败 / 模板 source 缺失）。

### C · 项目方向（@读 `_shared/project-questioning.md`）

agent **@读 `skills/_shared/project-questioning.md`**（**单一真相源** —— 提问法 / 问题库 / 写作规则 / 确认门 / 检查清单），按文件内 greenfield 调用方实现指南跑：

1. **提问纪律 + 问题库**：按 6 节顺序问 PM（定位 / 用户 / 角色 / 术语 / 路线 等）
2. **未决问题确认门**：暂存文件 `docs/.project-solution-open-questions.md`（路径用 `<target-dir>/docs/...`）
3. **确认门模板**：跑「创建 PROJECT.md / 继续探索」二选一 + Loop 回路（**选项内容 / label / description 全按 `_shared` 文件，本 SKILL 不内嵌副本**）
4. **写作规则**：PM 选「创建 PROJECT.md」后写 `<target-dir>/docs/PROJECT.md` + `<target-dir>/docs/ROADMAP.md`
5. **6 节齐不齐检查**：跑 `check-project-sections.py` 验证
6. **PM 定稿**：展示路径 + 摘要，PM 答「OK / 定了」推进
7. **atomic commit**：`git commit -m "docs: project direction settled"`
8. 进 C.5 步。

**失败兜底**：`_shared/project-questioning.md` 路径检测前置 → 缺失 → 报错 "框架未完整安装；请 git status 检查 skills/_shared/project-questioning.md"，不进讨论。

**失败兜底（PM 中途停）**：PM C 步中途答"停 / 等下 / 我先想想" → agent 检测 git 状态：
- 已 commit B 步骨架（首 commit `init: <name>` 已落）+ PROJECT.md 未 commit → **留 unstaged**，提示 PM "下次直接发 `/pmai-project-solution` 续上 PROJECT.md / ROADMAP.md 写作即可"
- B 步未完成 → 提示 PM 手动 `rm -rf <target-dir>` 重来

### C.5 · 视觉基线 + 主原型脚手架

> **为什么有这步**：`docs/DESIGN.md` 是原型 build 时的硬约束（AI 动手前必读再写代码）。视觉基线没定好 → build 在"颜色 / 字体 / 间距 / 动效"上没规范可遵守 → 乱搞。`prototype/` 是单一主原型，所有需求都在这一条线上演进，起步先有一版能跑的。本步把这两样一次建好。
>
> **DESIGN.md 写成正向约束**：告诉 AI"该怎么做"（用什么组件、什么节奏、什么密度）比列一堆"别做什么"更能逼出好视觉。`templates/DESIGN.md.tmpl` 已是正向约束版起草模板（视觉基调 / 产品化 demo 目标 / UI 习惯 / 组件来源四节）。

**步骤**：

1. **跟 PM 说一句开场**：
   ```
   接下来定项目视觉基线（写进 docs/DESIGN.md：颜色 / 字体 / 布局 / 动效 / UI 习惯），
   再用脚手架起一版能跑的主原型（prototype/，默认 Next.js + TS + Tailwind + shadcn，想换栈现在说）。
   视觉基线可以我陪你过一遍模板填，也可以借 gstack /design-consultation 出初稿。
   ```

2. **填 DESIGN.md（正向视觉约束）**：基于 `docs/DESIGN.md`（B 步已铺的 `DESIGN.md.tmpl` 起草版），AI 陪 PM 把四节填具体——
   - 视觉基调（主色 / 强调色 / 中性灰阶 / 圆角 / 阴影 / 字号阶梯 / 间距倍数）
   - 产品化 demo 目标（首屏见价值 / 主按钮最低可用闭环）
   - UI 习惯（不用浏览器原生弹框 / 宽表横向滚动 / 状态要全）
   - 组件 / token 来源（指向 prototype/ 的 `components/ui` shadcn + 本文件 token）

   > **想借 gstack 出初稿**：调 gstack `/design-consultation`（用 Skill 工具），让它接管对话定视觉方向并写 `docs/DESIGN.md`。**不抄 gstack** —— 直接调它的 skill、接受它写的内容、跟随它升级；不解析、不映射、不重写。gstack 不可用就回到本步用模板手填（见失败兜底）。

3. **起主原型 `prototype/`**：在 `<target-dir>/prototype/` 用脚手架起一版能跑的（默认 Next.js + TS + Tailwind + shadcn；PM 在 step 1 说要换栈就按 PM 的）。约定（来自 `prototype-README.md.tmpl`）：每页 self-contained、视觉照 DESIGN.md、按 step A5 选的项目类型档走实现深度（prototype 档全 mock / system 档真后端 / custom 档按层混搭）。`prototype/README.md` 模板 B 步已铺，照它的约定建。

4. **PM 定稿确认门**（AskUserQuestion，按 `_shared/pm-view/askuser-rules.md` 走）：
   ```bash
   # 自检：DESIGN.md 模板占位是否还残留（理想为 0）
   PLACEHOLDERS=$(grep -c "{{.*}}\|<#色值>\|<N px>" "$TARGET_DIR/docs/DESIGN.md" 2>/dev/null || echo 0)
   # 自检：prototype/ 是否起来了（有 package.json 即可跑）
   HAS_PROTO=$([ -f "$TARGET_DIR/prototype/package.json" ] && echo 1 || echo 0)
   ```
   ```
   📋 视觉基线 + 主原型定稿确认：
    - DESIGN.md 四节（视觉基调 / demo 目标 / UI 习惯 / 组件来源）都已具体化（占位检查：{PLACEHOLDERS} 个未填）
    - prototype/ 主原型已起一版能跑（{HAS_PROTO}）
   PM 确认推进？
   ```
   - `PLACEHOLDERS > 0` → 提示 PM「DESIGN.md 还有占位没填」（不硬卡，PM 可推进后续手补）
   - `HAS_PROTO = 0` → 主原型没起来，提示 PM 是否跳过（gstack / 脚手架不可用时也允许空 prototype/，第一个 req build 时再起）

5. **atomic commit**：
   ```bash
   cd "$TARGET_DIR"
   git add docs/DESIGN.md prototype/
   git commit -m "docs(DESIGN): 视觉基线定稿 + prototype/ 主原型脚手架"
   ```

6. 进 D 步。

**失败兜底（gstack / 脚手架不可用）**：gstack 未装或 `/design-consultation` 调用失败 → 回到 step 2 用 `DESIGN.md.tmpl` 模板手填；脚手架起不来 → 跟 PM 说「主原型先留空，第一个 req build 时再起」，DESIGN.md 仍要填（它是 build 硬约束，不能空）。直接进 D 步。

**失败兜底（PM 中途停）**：PM 在 C.5 答"停 / 等下" → DESIGN.md / prototype/ 留写到一半的 unstaged 状态，提示 PM "下次想续可以直接陪你过 DESIGN.md，或第一个 req build 时补主原型。"

### D · 终态汇总 + Next Up（只汇总不 commit）

> PROJECT.md / ROADMAP.md + DESIGN.md / prototype/ 的 commit 已分别在 C / C.5 完成。D 步**只做终态输出**。

agent 输出 Next Up 块：

```
═══════════════════════════════════════
✅ <project-name> 已就绪
📁 位置: <target-dir>
📄 已建脊柱: docs/PROJECT.md / ROADMAP.md / PRODUCT-STATE.md / DESIGN.md / PRODUCT-RULES.md
🧩 主原型: prototype/（<所选技术栈>）
═══════════════════════════════════════

▶ Next Up:
  cd <target-dir>
  /pmai-new-req "<一句话需求>"
```

---

## Rules

- PM 在**任意 cwd** 都能调（`pmai install` 后 `~/.claude/skills/pmai-init-project` 全局可用）；B 步脚本路径走 `$PMAI_HOME` 绝对路径
- 老模式兼容：PM 在生成器仓根目录跑也行（脚本 `$PMAI_HOME` fallback 到 `$(pwd)/scripts/init-project.sh`）
- 目标目录默认不能已存在；A 步 AI 诊断到已有内容时优先推荐 audit / project-solution，PM 拍 init 也接住（AI 加 `--allow-existing`，**不硬 gate**）
- gstack 是硬依赖，未安装时 B 步脚本会报错退出
- 不要手动跳过 C 步 —— PROJECT.md / ROADMAP.md 是项目方向真相源，不能空骨架交付
- **DESIGN.md 是 build 硬约束，不能空交付** —— C.5 即使主原型起不来，视觉基线也要填好（第一个 req build 就靠它）
- 借 gstack `/design-consultation` 出 DESIGN.md 初稿时**不抄、不映射、不重写** —— 直接接受它写的内容，跟随它升级
- 提问法 / 话术 / 写作规则**真相源只在 `skills/_shared/project-questioning.md`**；本 skill C 步不内嵌副本（避免双份维护漂移）

### PM-facing 输出禁词（[[feedback_pm_chat_no_engineering_jargon]]）

AI 跟 PM 对话时**禁出现**下列工程黑话：`brownfield` / `greenfield` / `intent` / `project-intent` / `gate` / `闸门` / `brownfield 检测`。

这些是 AI 内部状态词 / 模型术语，PM 视角无对应心智。PM 视图用：

| 禁词 | PM 视角替代 |
|---|---|
| `brownfield` / `brownfield 检测` | 「已有 codebase」/「已有内容判断」 |
| `greenfield` | 「全新项目」 |
| `intent` / `project-intent` | 「项目类型」/「mode 基线」 |
| `gate` / `闸门` | 「确认」/「判断」/ 直接砍 |
| `name → path → ... → intent` | 「项目名 → 落地路径 → 已有内容判断 → 一句话背景 → 项目类型」 |

SKILL.md 内部段落保留 `brownfield` 概念词用于设计准确性；AI 跟 PM 对话 / 进度条 / AskUser 文案 / Next Up 块时必须翻译。

---

## 失败兜底速查

| 场景 | 兜底 |
|---|---|
| A 步 step 3 cwd 完全空 / 只 `.DS_Store` | 跳过 3.3/3.4 退化捷径；直接调脚本 |
| A 步 step 3 AI 出方案 + PM 选 ①（走方案）| AI 执行归档 mv + 调脚本加 `--allow-existing` |
| A 步 step 3 PM 选 ②（要改）| 等 PM 文本反馈具体哪条改；AI 调整方案后回 3.3/3.4 再确认（可循环）|
| A 步 step 3 AI 诊断到已有 codebase / PMAI 脚手架 | 3.3 方案里**优先推荐** `/pmai-codebase-audit` 或 `/pmai-project-solution`；PM 坚持 init 也接住（**不硬 gate**）|
| B 步 `init-project.sh` 失败（chmod / git init / 模板缺失）| 报错贴 stderr + PM 检查；不进 C 步 |
| B 步跑成功但 `_shared/project-questioning.md` 缺失 | C 步入口前置检测 + 报错 "框架未完整安装" |
| C 步 PM 答"停" + 骨架已 commit | PROJECT.md / ROADMAP.md 留 unstaged + 提示下次 `/pmai-project-solution` 续 |
| C 步 PM 答"停" + 骨架未 commit | 提示手动 `rm -rf <target-dir>` 重来 |
| C.5 步 gstack / 脚手架不可用 | 用 `DESIGN.md.tmpl` 模板手填视觉基线；主原型起不来则留空，第一个 req build 时补（DESIGN.md 不能空）|
| C.5 步 PM 答"停" | DESIGN.md / prototype/ 留 unstaged 状态；下次续填 / 第一个 req 补主原型 |
