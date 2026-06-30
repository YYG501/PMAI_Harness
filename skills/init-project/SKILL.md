---
name: pmai-init-project
description: |
  项目初始化统一入口：自动判断全新项目、已有资料目录、已有代码库或已接入过 PMAI；全新项目搭起上下文底座，已有代码库自动进入代码现状盘点和接入流程。PM 不需要在“初始化”和“代码盘点”之间手动选命令。
---

# /pmai-init-project（项目初始化统一入口）

> PM 起一个项目或把已有项目接入 PMAI 时**只跑这一个命令**，agent 内部判断项目情况并分流；不切窗口、不跑第二个命令、不需要记中间步骤。
>
> **全新项目**：只建"上下文脊柱"——项目级的几份文件 + 一份能跑的主原型，AI 以后每次进项目先读它们，治失忆。**不锁流程、不强逼你先答一堆方向问卷**——脊柱搭好就可以自由探索、试方向，AI 放开手陪你试。等方向清晰、你准备好了，再用 `/pmai-design` 立第一个模块、把成果"纳入结构"。
>
> **已有代码库**：不补空骨架、不起主原型、不要求 gstack，直接进入已有项目接入：先盘点真实代码现状，产出代码现状档，再基于现状和 PM 确认沉淀产品方向。
>
> **PM 视图**：每一步入口先 echo 一行进度条（banner 规范见 `_shared/pm-view/banner-rules.md`）；最后一步给 ▶ Next Up 块。

```
┌─────────────────────────────────────────────────────────┐
│              PMAI ► /pmai-init-project                      │
├─────────────────────────────────────────────────────────┤
│  A · 参数收集 + 项目情况判断                              │
│    项目名 → 落地路径 → 自动判断空目录 / 资料 / 代码 / 已接入 │
│                 ↓                         ↓             │
│          全新/资料目录                 已有代码库          │
│                 ↓                         ↓             │
│  B · 建骨架 (init-project.sh)       E · 代码现状盘点       │
│  C · 一句话方向 + 视觉基线            按代码现状盘点流程      │
│  D · 终态汇总 + Next Up              产 CODEBASE-AUDIT 等 │
└─────────────────────────────────────────────────────────┘
```

---

## 起项目 = 只建骨架、不锁流程（核心理念）

起项目这一步的职责被**收窄到只搭脊柱**，刻意不在这里逼 PM 走完整方向讨论：

- **早期最值钱的是自由探索**。方向往往是边试边清晰的，不是开局答问卷答出来的。开局就强制一道重门方向讨论，会把还没想清楚的方向过早定死，锁住创造力。
- **脊柱搭好 = AI 就能放开手陪你试**。PRODUCT.md 里有一句话定位、DESIGN.md 有视觉基线、prototype/ 能跑——AI 进项目读得到上下文，就能直接陪 PM 在主原型上随便改、试几个方向、推翻重来，全程在 main 上动、不开 worktree、不走流程。
- **方向清晰后再"纳入结构"**。当某个方向试明白了、PM 准备好了，用 `/pmai-design` 立第一个功能模块（模块三件套），把探索成果沉淀成结构化的规格。结构是**长出来的**，不是开局强加的。

> 想要在项目跑起来后系统校准方向（定位 / 用户 / 边界 / 待办池），那是 `/pmai-direction` 的活，PM 任何时候可主动调；本 skill 不替它做那道重门。

---

## When To Use

- PM 在**生成器仓（PM-AI-Workflow）**里调用（业务仓里不能跑；init-project.sh 拷贝时已排除本 skill）
- PM 想起一个新业务项目 —— 含一句话定位（PRODUCT.md）+ 视觉基线（DESIGN.md）+ 一版能跑的主原型；脊柱搭好即交付，**不在这里做完整方向讨论**
- PM 位于一个已有代码库，想让 PMAI 接住这个项目 —— 本入口自动进入已有项目接入，先整理真实现状，不让 PM 手动切到另一个 skill

**不在 scope**：

- 已接入项目的方向重定 / 路线规划 → 走 `/pmai-direction`（PM 准备好了主动调）
- 手动选择“初始化还是代码盘点” → 不让 PM 选；A 步自动判断并分流。代码盘点只作为本入口的内部子流程，不作为公开同级 skill
- 立第一个功能模块、写规格 → 方向清晰后走 `/pmai-design`
- 业务仓里起新需求 → 走 `/pmai-design`

---

## 这一步建出什么（上下文脊柱）

全新项目 / 资料目录分支跑完后，项目里有这几样，构成 AI 以后每次进项目的"必读上下文"：

| 文件 / 目录 | 装什么 | 谁写 / 谁读 |
|---|---|---|
| `PRODUCT.md` | 一句话定位 + 业务术语表（项目方向真相源；起步只留一句话，方向清晰后随 `/pmai-design` / `/pmai-direction` 长厚） | C 步写一句话；每次进项目读 |
| `TODO.md` | PM 待办池（无序，不排序） | C 步写 |
| `PRODUCT-STATE.md` | 产品**现状层**（现在长什么样、做到哪、哪些真哪些 mock）；模板已就位，内容随每次沉淀累积 | 只在 `/pmai-build-close` 沉淀那刻更新；开 `/pmai-design` 时先读 |
| `DESIGN.md` | 视觉与交互约定（**正向约束**：该怎么做，不是禁止清单） | C 步起草；build 前 AI 必读再动手 |
| `PRODUCT-RULES.md` | 跨模块的规则 + 关键决策 + 奠基理路（项目级基线） | 随产品演进 PM 调；`/pmai-build-close` 沉淀时回写跨模块决策 |
| `prototype/` | **单一主原型**（默认 Next.js + TS + Tailwind + shadcn，init 时可改栈）；所有探索 / 需求的原型都在这一条线上演进 | C 步起一版能跑的；早期自由探索直接在 main 上改它，大需求才在 worktree 改、确认后并回 main |

> 模板源：`templates/PRODUCT-STATE.md.tmpl` / `templates/DESIGN.md.tmpl` / `templates/PRODUCT-RULES.md.tmpl` / `templates/prototype-README.md.tmpl`。建骨架（B 步）由 `init-project.sh` 把这些铺到位，本 skill 负责把一句话定位 / 视觉基线填进去。

已有代码库分支不强铺 `prototype/` 或空骨架；它的交付物以 `docs/CODEBASE-AUDIT.md`、`PRODUCT.md`、`TODO.md`、`PRODUCT-STATE.md`、`DESIGN.md` 兜底段和可选模块规格骨架为主，具体按 E 步的 codebase-audit 子流程执行。

---

## Workflow

> 先执行 A。A 步判断后：
>
> - 全新项目 / 只有资料目录 → 继续 B / C / D。
> - 已有代码库 → 直接进入 E（已有项目接入子流程），不走 B / C / D，不调用 `init-project.sh`，不要求 gstack。
> - 已接入过 PMAI → 不重跑 init，引导 `/pmai-status` 或 `/pmai-direction`。
>
> 每步失败有显式兜底（见 §失败兜底速查）。
>
> **进度条**：agent 进入每一步**先 Bash echo 一行**。init-project 是项目级 skill（生成器仓内跑、无 active work），直接 echo 字面值：
> - A：`echo "━━━ PMAI ► INIT-PROJECT ▸ 参数收集 ━━━"`
> - B：`echo "━━━ PMAI ► INIT-PROJECT ▸ 建骨架 ━━━"`
> - C：`echo "━━━ PMAI ► INIT-PROJECT ▸ 一句话方向 + 视觉基线 + 主原型 ━━━"`
> - D：`echo "━━━ PMAI ► INIT-PROJECT ▸ 终态汇总 ━━━"`
> - E：`echo "━━━ PMAI ► INIT-PROJECT ▸ 已有项目接入 ━━━"`

### A · 参数收集 + 项目情况判断

**AskUserQuestion 分批问参数**，拿到路径后立刻判断项目情况，避免 PM 答完一堆才发现路径不该走全新骨架。

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

   **PM 在 cwd 直接 init 的常见场景**：PM 先 `cd <target-project-dir>` 再启动 Claude / Codex → cwd = `<target-project-dir>` → 走 else 分支 default = cwd → step 3 检查 cwd 内容。空目录走全新项目；资料目录用 `--allow-existing` 接住；已有源码自动进入已有项目接入。

3. **AI 主动诊断 + 自动分流**（PM 既然在 cwd 启 claude → AI 直接看；不要给“init / audit / 改方案”三选菜单）：

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
   | 源码 | `*.py` / `*.js` / `*.ts` / `Package.swift` / `Cargo.toml` / `go.mod` / `pom.xml` / `build.gradle` / 任何 manifest（`package.json` / `pyproject.toml` / ...）| **自动进入已有项目接入**：按 `skills/_internal/codebase-audit/SKILL.md` 扫码产出现状档；不调用 `init-project.sh`，不要求 gstack，不改业务代码 |
   | 已有 framework | 含 `PRODUCT.md` / `PRODUCT-STATE.md` / `AGENTS.md` + PMAI 规则 / 其他 PMAI 元数据 | 不重跑 init；先走 `/pmai-status` 看现状，PM 明确要重做方向再走 `/pmai-direction` |

   **3.3 AI 给判断结果**（结构化展示，每条一行说清「看到什么 → 判断 → 下一步」）：

   ```
   📍 当前位置: <target-dir>

   📂 内容（ls -A）:
     <逐条 + 大小 + AI 推测用途>

   💡 判断:
     - <一条关键判断>
     - <... 视情况>

   🎯 下一步:
     - 如果是空目录 / 资料目录：按全新项目骨架继续，列出源 → 目标的处置方案
     - 如果是已有代码库：直接进入已有项目接入，先产 docs/CODEBASE-AUDIT.md；不改业务代码
     - 如果已接入过 PMAI：不重跑初始化，先看当前状态或重做方向
   ```

   **3.4 全新项目 / 资料目录：PM 一拍即可**（AskUser 二选，**默认走方案**）：
   - 选项 ① "按这个方案走"（推荐）
   - 选项 ② "我要改"（PM 自由 chat 反馈具体哪条要调；AI 改完回 3.3 再确认；可循环）

   **3.5 全新项目 / 资料目录：PM 选 ① → AI 执行**：
   ```bash
   # 1. 归档动作（仅 3.3 方案标了归档的文件）
   mkdir -p "$TARGET_DIR/<归档目标路径>"
   mv "$TARGET_DIR/<source-file>" "$TARGET_DIR/<归档目标路径>/"
   # 2. 配置合并（如 .gitignore 跟 PMAI 模板并集去重）
   # 3. 调 init-project.sh --allow-existing 接住非空目录
   bash "$SCRIPT" "<project-name>" "<target-dir>" "<background>" "<mode>" --allow-existing
   ```

   **3.6 已有代码库：自动进入 E 步**：
   - 不再问 PM“要不要跑代码盘点”。
   - 读取 `skills/_internal/codebase-audit/SKILL.md` 全文，按其流程继续；目标根目录就是本 A 步的 `<target-dir>`。
   - 只做必要的审计范围确认，例如是否排除 `vendor/`、`node_modules/`、`.build/`、`DerivedData/`；没有明确排除就用默认跳过规则。
   - 不调用 `init-project.sh`，因此不会被 gstack 缺失卡住。
   - 不改业务代码；写 PMAI 接入文档前按 codebase-audit 的确认要求执行。
   - 如果 PM 明确说“我不是要接已有代码，就是要在这个目录叠全新 PMAI 骨架”，才按 PM 决定回到 3.4/3.5，用 `--allow-existing` 接住。这个 override 需要 PM 明确说出，不作为默认选项展示。

   **退化捷径**：
   - cwd 完全空（`ls -A` 空）+ 无 `.git/` → 跳过 3.3/3.4，直接调 init-project.sh（不带 `--allow-existing`，走老 mkdir 路径）
   - cwd 只有 `.DS_Store` → 跳过 3.3/3.4，直接 init + `--allow-existing`（无需 PM 拍方案）

   **edge case 提示**：
   - **已有代码库**（源码 / manifest）：默认自动进入 E 步；PM 明确坚持补全新骨架时才 override。
   - **已有 PMAI 脚手架**：默认不重跑 init；先看状态或重做方向。

4. **一句话项目背景**（仅全新项目 / 资料目录分支需要，写进生成的 CLAUDE.md）—— AskUser

5. **项目类型 / mode 基线**（仅全新项目 / 资料目录分支需要，决定主原型按哪一档实现深度走 + 注入哪份「工程结构约束」段；AskUser 四选）：
   - `prototype` — Next.js 单页原型 / Demo 仓（每页 self-contained，全 mock，不抽 Template / hook / context）—— 起步默认
   - `system` — 完整业务系统（多模块 + 后端契约 / 真实持久化 / 完整权限 / 完整测试）
   - `custom` — PM 自由编辑（按层混搭，不预设深度）
   - `unknown` — 先 init 跑通后再分类（探测兜底档）

   > 这个选项决定主原型 `prototype/` 默认按哪一档建（mode 中立：原型档全 mock / 真系统档真后端），以及 `工程结构约束-{档}.md` 注入哪份。某层以后从 mock 转真，是一次显式拍板的需求，在主原型里原地重写那层，不另开分叉。

**已有内容接口约定**：
- **AI 主动诊断并分流**：本 skill step 3 由 AI `ls -A` + 逐条标注 + 判断项目类型；不给 PM 三选菜单装懂事。
- **已有代码库自动进入代码现状盘点子流程**：代码盘点是本入口的内部子流程，不是 PM 初始化时要主动选择的第二个公开入口。
- **PM 决定仍优先**：PM 明确坚持在已有代码库叠全新骨架时可以接住；AI 不能把这个 override 当默认选项展示。
- **脚本层默认仍拒**：`init-project.sh` 默认拒已存在目录；本 skill 只在全新项目 / 资料目录分支经 PM 拍板后加 `--allow-existing`。脚本本身不判断内容是否真是 codebase（那是 skill 层 AI 诊断的责任）。

### B · 建骨架（仅全新项目 / 资料目录分支；agent Bash 调 init-project.sh）

agent 用 Bash 工具调（**绝对路径**走 `$PMAI_HOME` —— PM 在任意 cwd 跑都行；按 A 步 step 3.5 的 PM 拍板决定是否加 `--allow-existing`）。已有代码库分支禁止调用本脚本：

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
- 检测 gstack 能力（`gstack` CLI 或 `~/.claude/skills/gstack` 任一可用即可；两者都缺 → 报错退出）
- 默认：拒已存在目录；命中 `--allow-existing` → 跳过该检查，目录可非空
- 创建目标目录（已存在则用现有）+ 铺上下文脊柱模板（PRODUCT-STATE / DESIGN / PRODUCT-RULES / TODO + prototype/ README 等）
- 按 `<mode>`（项目类型）注入对应的「工程结构约束」段进 CLAUDE.md
- 初始化 git（main 分支）+ 首 commit `init: <project-name>`（命中 `--allow-existing` 时首 commit 也包含 PM 原本就放在目录里的资料文件）

agent 收到脚本退出码 0 后**汇报**：「✅ 骨架已就绪 / 上下文脊柱模板 + scripts + 工程结构约束段全部到位」→ 进 C 步。

**失败兜底**：脚本退出码非 0 → agent 不进 C 步，向 PM 报错（贴脚本 stderr）+ 提示 PM 检查（常见原因：chmod 权限 / git init 失败 / 模板 source 缺失）。

### E · 已有项目接入（自动分流到代码现状盘点）

> 进入条件：A 步判断目标目录是已有代码库。
>
> 本步直接执行 `skills/_internal/codebase-audit/SKILL.md` 的 workflow；不要让 PM 再手动选择代码盘点入口，也不要把“继续初始化骨架”列成默认同级选项。

执行规则：

1. 读取 `skills/_internal/codebase-audit/SKILL.md` 全文。
2. 审计根目录 = A 步确认的 `<target-dir>`。
3. 只问必要的排除目录；默认跳过依赖缓存、构建产物和系统目录。
4. 先产代码现状档，再让 PM 过目，之后在同一流程内定项目方向。
5. 全程不调用 `init-project.sh`；gstack 不可用不阻塞本步。
6. 退出时按 codebase-audit 的 Next Up 引导 `/pmai-design`。

---

### C · 一句话方向 + 视觉基线 + 主原型脚手架（轻）

> **这一步刻意是轻的**。起项目不在这里逼 PM 答完整方向问卷——那会过早锁死还没想清楚的方向。本步只把"AI 能放开手陪你试"的三样脊柱填到位：**PRODUCT.md 留一句话定位 + DESIGN.md 视觉基线 + prototype/ 起一版能跑**。项目跑起来后想系统校准方向（方向重定 / 路线规划）再走 `/pmai-direction`。
>
> **DESIGN.md 是 build 硬约束**：原型 build 时 AI 动手前必读再写代码。视觉基线没定好 → 在"颜色 / 字体 / 间距 / 动效"上没规范可遵守 → 乱搞。`templates/DESIGN.md.tmpl` 是正向约束版起草模板（告诉 AI"该怎么做"比列一堆"别做什么"更能逼出好视觉；四节：视觉基调 / 产品化 demo 目标 / UI 习惯 / 组件来源）。

**步骤**：

1. **跟 PM 说一句开场**：
   ```
   骨架搭好了。接下来只做三件轻的，让 AI 能放开手陪你试方向：
     1. PRODUCT.md 写一句话定位（这产品给谁、解决什么——一句话即可，项目跑起来后再用 /pmai-direction 校准）
     2. DESIGN.md 视觉基线（颜色 / 字体 / 布局 / 动效 / UI 习惯，build 时的硬约束）
     3. prototype/ 起一版能跑的主原型（默认 Next.js + TS + Tailwind + shadcn，想换栈现在说）
   视觉基线可以我陪你过一遍模板填，也可以借 gstack /design-consultation 出初稿。
   ```

2. **PRODUCT.md 写一句话定位**：AskUser 问 PM 一句话（这产品给谁、解决什么），写进 `<target-dir>/PRODUCT.md` 的定位节 + 业务术语表起一个空架（方向清晰后随 `/pmai-design` / `/pmai-direction` 长厚）。**不在这里跑 5 节方向问卷**——一句话定位够 AI 进项目读上下文、陪 PM 探索即可。同时写 `<target-dir>/TODO.md`（PM 把脑子里的待办先记下，无序）。

3. **填 DESIGN.md（正向视觉约束）**：基于 `DESIGN.md`（B 步已铺的 `DESIGN.md.tmpl` 起草版），AI 陪 PM 把四节填具体——
   - 视觉基调（主色 / 强调色 / 中性灰阶 / 圆角 / 阴影 / 字号阶梯 / 间距倍数）
   - 产品化 demo 目标（首屏见价值 / 主按钮最低可用闭环）
   - UI 习惯（不用浏览器原生弹框 / 宽表横向滚动 / 状态要全）
   - 组件 / token 来源（指向 prototype/ 的 `components/ui` shadcn + 本文件 token）

   > **想借 gstack 出初稿**：调 gstack `/design-consultation`（用 Skill 工具），让它接管对话定视觉方向并写 `DESIGN.md`。**不抄 gstack** —— 直接调它的 skill、接受它写的内容、跟随它升级；不解析、不映射、不重写。gstack 不可用就回到本步用模板手填（见失败兜底）。

4. **起主原型 `prototype/`**：在 `<target-dir>/prototype/` 用脚手架起一版能跑的（默认 Next.js + TS + Tailwind + shadcn；PM 在 step 1 说要换栈就按 PM 的）。约定（来自 `prototype-README.md.tmpl`）：每页 self-contained、视觉照 DESIGN.md、按 step A5 选的项目类型档走实现深度（prototype 档全 mock / system 档真后端 / custom 档按层混搭）。
   **prototype/README.md 在脚手架之后写**：`create-next-app` 会生成自己的默认 README，脚手架跑完后 AI 用 `$PMAI_HOME/templates/prototype-README.md.tmpl` 覆盖 `prototype/README.md`（占位符按项目替换）—— 不在 B 步铺，避免与 `create-next-app` 的非空目录冲突。

5. **PM 定稿确认门**（AskUserQuestion，按 `_shared/pm-view/askuser-rules.md` 走）：
   ```bash
   # 自检：DESIGN.md 模板占位是否还残留（理想为 0）
   PLACEHOLDERS=$(grep -c "{{.*}}\|<#色值>\|<N px>" "$TARGET_DIR/DESIGN.md" 2>/dev/null || echo 0)
   # 自检：prototype/ 是否起来了（有 package.json 即可跑）
   HAS_PROTO=$([ -f "$TARGET_DIR/prototype/package.json" ] && echo 1 || echo 0)
   ```
   ```
   📋 脊柱定稿确认：
    - PRODUCT.md 一句话定位已写（这产品给谁 / 解决什么）
    - DESIGN.md 四节（视觉基调 / demo 目标 / UI 习惯 / 组件来源）都已具体化（占位检查：{PLACEHOLDERS} 个未填）
    - prototype/ 主原型已起一版能跑（{HAS_PROTO}）
   PM 确认推进？
   ```
   - `PLACEHOLDERS > 0` → 提示 PM「DESIGN.md 还有占位没填」（不硬卡，PM 可推进后续手补）
   - `HAS_PROTO = 0` → 主原型没起来，提示 PM 是否跳过（gstack / 脚手架不可用时也允许空 prototype/，第一个 `/pmai-design` build 时再起）

6. **atomic commit**：
   ```bash
   cd "$TARGET_DIR"
   git add PRODUCT.md TODO.md DESIGN.md prototype/
   git commit -m "docs: 一句话定位 + 视觉基线 + prototype/ 主原型脚手架"
   ```

7. 进 D 步。

**失败兜底（gstack / 脚手架不可用）**：gstack 未装或 `/design-consultation` 调用失败 → 回到 step 3 用 `DESIGN.md.tmpl` 模板手填；脚手架起不来 → 跟 PM 说「主原型先留空，第一个 `/pmai-design` build 时再起」，DESIGN.md 仍要填（它是 build 硬约束，不能空）。直接进 D 步。

**失败兜底（PM 中途停）**：PM 在 C 步答"停 / 等下" → 已写的 PRODUCT.md 一句话 / DESIGN.md / prototype/ 留写到一半的 unstaged 状态，提示 PM "下次想续可以直接陪你过 DESIGN.md，或第一个 `/pmai-design` 时补主原型。"

### D · 终态汇总 + Next Up（只汇总不 commit）

> PRODUCT.md / TODO.md / DESIGN.md / prototype/ 的 commit 已在 C 步完成。D 步**只做终态输出**。

agent 输出 Next Up 块：

```
═══════════════════════════════════════
✅ <project-name> 已就绪
📁 位置: <target-dir>
📄 已建上下文脊柱: PRODUCT.md（一句话定位）/ TODO.md / PRODUCT-STATE.md / DESIGN.md / PRODUCT-RULES.md
🧩 主原型: prototype/（<所选技术栈>）
═══════════════════════════════════════

▶ Next Up（不锁流程，两条路随你）:
  cd <target-dir>
  · 先随便试方向 —— 直接在 prototype/ 上改，AI 陪你试（在 main 上动、不开 worktree）
  · 想清楚某个方向了 —— /pmai-design "<一句话>" 立第一个模块、纳入结构
  · 想把项目方向系统过透 —— /pmai-direction
```

---

## Rules

- PM 在**任意 cwd** 都能调（`pmai install` 后 `~/.claude/skills/pmai-init-project` 全局可用）；B 步脚本路径走 `$PMAI_HOME` 绝对路径
- 老模式兼容：PM 在生成器仓根目录跑也行（脚本 `$PMAI_HOME` fallback 到 `$(pwd)/scripts/init-project.sh`）
- 目标目录默认不能已存在；A 步 AI 诊断到资料目录时，PM 拍方案后用 `--allow-existing` 接住
- 已有代码库自动进入 E 步，不调用 `init-project.sh`
- gstack 只对全新项目 / 资料目录的 B/C 分支是依赖；检测口径是 `gstack` CLI 或 `~/.claude/skills/gstack` 任一可用即可。已有代码库接入不应被 gstack 缺失阻塞
- **起项目 = 只建骨架、不锁流程**：C 步只填一句话定位，**不在这里跑完整方向问卷**（项目跑起来后的方向重定 / 路线规划是 `/pmai-direction` 的活，PM 准备好了主动调）。早期靠自由探索想清楚方向，比开局答问卷更有效
- PRODUCT.md 不能完全空交付，但**只要一句话定位即可**（够 AI 进项目读上下文、陪 PM 探索）；术语表起空架，方向清晰后随 `/pmai-design` / `/pmai-direction` 长厚
- **DESIGN.md 是 build 硬约束，不能空交付** —— C 步即使主原型起不来，视觉基线也要填好（第一个 `/pmai-design` build 就靠它）
- 借 gstack `/design-consultation` 出 DESIGN.md 初稿时**不抄、不映射、不重写** —— 直接接受它写的内容，跟随它升级

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
| A 步 step 3 AI 诊断到已有代码库 | 自动进入 E 步（代码现状盘点子流程）；PM 明确坚持补全新骨架时才 override |
| A 步 step 3 AI 诊断到已有 PMAI 脚手架 | 不重跑 init；先看 `/pmai-status`，PM 明确要重做方向时走 `/pmai-direction` |
| B 步 `init-project.sh` 失败（chmod / git init / 模板缺失）| 报错贴 stderr + PM 检查；不进 C 步 |
| C 步 gstack / 脚手架不可用 | 用 `DESIGN.md.tmpl` 模板手填视觉基线；主原型起不来则留空，第一个 `/pmai-design` build 时补（DESIGN.md 不能空）|
| C 步 PM 答"停" + 骨架已 commit | PRODUCT.md 一句话 / TODO.md / DESIGN.md / prototype/ 留 unstaged + 提示下次直接续填或 `/pmai-direction` 过透方向 |
| C 步 PM 答"停" + 骨架未 commit | 提示手动 `rm -rf <target-dir>` 重来 |
