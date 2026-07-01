---
name: pmai-mockup
description: |
  依据讨论确定的信息设计，先打开几条真正不同的设计方向，再借 gstack /design-shotgun、HTML 草图或用户上传图片形成可比稿，归入 mockups/ 并汇总为单页对比视图；选定方向后返回 /pmai-design 定稿。轻量流程，不改动主原型。
---

# /mockup

> **这是什么**：把讨论里定下来的"这张卡/这一页放什么、谁看、信息怎么分块"先拆成**几条真正不同的设计方向**，再做成能看的设计稿，一页里并排摊给 PM 挑——挑定哪版方向，再回去把规格写定。它的定位是**发散探索 + 对比看板**，不是单方案 HTML 草图。**用看得见的设计稿代替规格里那段 ASCII 线框**，省掉"PM 看规格里的方框想象不出来→建出来才说不对→返工"。
> **三种来源**：① **gstack 设计探索**（默认优先，适合视觉气质 / 密度 / 第一眼感觉，带对比看板和反馈循环）；② **PMAI 内部发散草图**（gstack 不可用时，先出多方向 concept，再用 HTML / 静态稿形成同页对比）；③ **PM 上传图片**（PM 已经有截图 / 设计图时，直接登记进看版比选）。按要挑什么取舍，详见步骤 3。
> **和 /pmai-design 的关系**：`/pmai-design` 把信息设计讨论清楚后，到"该让 PM 看看长什么样"那一步**调本 skill**；PM 挑定方向，`/pmai-design` 接着把规格写定（规格里只留文字定义 + 指一句"长什么样见 mockup 看版第 N 版"，不再画线框）。
> **和 /pmai-build 的关系**：两码事。`/mockup` 出的是**便宜的比稿**（设计稿图 / HTML 线框，不接数据、不进主原型），只为挑方向；`/pmai-build` 才是在 `prototype/` 主原型里**真建**那一份能跑的实现。挑定方向走 `/pmai-build`（大需求）或直接在主原型里改（小改）。
> **不动主原型**：`mockups/` 是摊在桌上比来比去的设计稿集，和 `prototype/`（跑着的那一份主原型）是分开的两个家。本 skill 只写 `mockups/`，不碰 `prototype/`。

## When To Use

- 信息设计讨论已经把"这张卡/这一页放什么、谁看、信息怎么分块"理清了，**该让 PM 用眼睛挑一版方向**——视觉/布局上有岔路（左导航还是顶 tab、信息上卡面还是进抽屉、几栏排版、整体风格密度），文字描述掰不清，PM 想看着挑。
- `/pmai-design` 流程走到第 3 步（信息设计结论已出、规格还没定稿）时由它调本 skill。
- PM 手动 `/mockup "<想看哪块的设计稿>"`：随时想给某块界面出几版比一比。
- **不适用**：
  - 信息还没理清就想看图 → 先回 `/pmai-design` 把"放什么、谁看、怎么分块"讨论清楚，再来出设计稿（没想清楚出的是瞎画）。
  - 要真建那一份能跑的实现 → `/pmai-build`（大需求）或直接在 `prototype/` 改（小改）。
  - 纯文字微调、没有视觉岔路 → 不用出设计稿，直接定稿规格。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: mockup"
```

本 skill 从**主仓 main** 触发（动的是探索设计稿，不进任何 build worktree）。`mockups/` 在 main 上随时可写（属探索草稿、`check-branch.sh` 已豁免），所以**不开分支、不开 worktree、不拉 PM 进工作区**。

## 借 gstack /design-shotgun

让 PM 选一次出几版、并排比稿，是 gstack `/design-shotgun` 趟熟的做法。本 skill **PMAI 自己编排，gstack 作为优先引擎**：

- **共享合同**：本节遵守 `skills/_shared/gstack-integration.md`。这是“能力调用”：PMAI 定方向和接回路径，gstack 只产视觉探索素材。
- **PMAI 先定方向**：先读产品 / 模块 / 已有界面，列出几条要探索的产品设计方向；不是把一句需求原样丢给 gstack。
- **先探测能力再选择引擎**：生成前先跑 gstack browser / design 诊断（优先用 `$PMAI_HOME/scripts/check-gstack-browser.sh`），确认 browse/design binary、localhost 权限、headless/headed 可用性和 compare board 能力。Codex sandbox 里 localhost `EPERM` 只能说明沙箱限制，不等于 gstack 坏了。
- **gstack 做视觉探索**：gstack 装了、`/design-shotgun` 可用且这轮是在挑视觉气质 / 密度 / 第一眼感觉时，调用它生成和收反馈；接受它的对比看板、反馈循环和 taste memory。
- **PMAI 接回真相源**：gstack 产物默认在 `~/.gstack/projects/...`，不能停在那里。跑完后必须用 `scripts/import-mockup-variants.py` 把所有候选稿和挑定结果复制进本项目 `mockups/`，登记清单并刷新 PMAI 看版。
- **gstack 不可用就把 shotgun 搬进来**：不因为 gstack 不可用就退成单稿。PMAI 内部 fallback 必须先列多方向 concept，再为每个 concept 出 HTML / 静态草图，最后生成同页看版。
- **不自建图片生成**：本 skill 暂不再调用 PMAI 自带图片生成脚本；没有 gstack 时，走 PMAI 内部发散草图或接收 PM 上传图片。

## Workflow

> **PM 视图纪律**：跟 PM 说话**禁出现** `manifest` / `featured` / `variant` / `design brief` / `信息模型` / `三身份` / `派生 4 环` 等内部词。用大白话：「几版设计稿」「挑定方向」「留在看版里翻得到」。AskUserQuestion 按 `_shared/pm-view/askuser-rules.md` 走。

### 步骤 1：拿讨论结论 + 锁定要画哪块

- **/pmai-design 调进来**：讨论结论已在手（这张卡/这一页谁看、放什么、信息怎么分块、有哪些视觉岔路）——直接用，跳到步骤 2。
- **PM 手动调**：用**一句话**问要给哪块界面出设计稿、有哪些拿不准的方向；拿到回答再继续。讨论结论散在模块 `discussion.md` / `decisions.md` 里的，顺手读进来对齐。

**没想清楚就别画**：如果"放什么、谁看、怎么分块"还没定，停下来，告诉 PM 一句「这块还没想清楚，先把放什么、谁看理一下再出设计稿」，回 `/pmai-design`。瞎画比不画更费事。

### 步骤 1.5：先对齐已有界面

默认不是重新设计一套风格，而是**放回当前产品里不违和**。画之前必须先看已有界面依据：

1. 读根目录 `DESIGN.md`：视觉基线、页面模式、组件和交互约定。
2. 按这次要画的页面，读已有 `prototype/` 关键页面、组件、样式文件；只读相关 slice，别全文吞大文件。
3. 读已挑定 / 待合并的设计稿记录和看版里相关方向，避免和 PM 前面挑过的方向打架。
4. 如果这轮来自某个模块，顺手读该模块 `discussion.md` / `decisions.md` / `spec.md` 里和界面有关的约束。

然后先判这轮属于哪种：

- **贴合现有界面**（默认）：沿用已有导航、背景、卡片、表格、按钮、间距、信息密度和页面气质。没拿到 PM 明确要求前，不能跳出现有样式另起炉灶。
- **探索新风格**：只有 PM 明确说“想试新风格 / 换一套感觉 / 这块可以跳出当前样式”时才用；输出时说明这是在试新方向，不当作默认落地样式。
- **先定基调**：如果项目还没有可参考界面、`DESIGN.md` 也只是空骨架，就明说「这轮是在定基调，不是贴合已有界面」，再继续出设计稿。

生成前整理一份**现有界面约束 / 界面对齐约束**给自己用：页面框架、导航位置、背景色感、卡片 / 表格 / 抽屉 / 表单模式、按钮层级、间距密度、字体层级、常见状态。gstack 路把这些交给 `/design-shotgun`；HTML 路优先复用现有 CSS / token / class 命名，静态草图也不要凭空造另一套组件语言。

### 步骤 2：先打开设计空间 + 让 PM 选出几版

从讨论结论和已有界面对齐结论里挑出**真正的视觉 / 结构 / 工作流岔路**，先列出几条方向给 PM 看。每个方向至少写清：

```text
方案 A：<PM 能懂的名字>
试什么：<这一版探索的结构 / 路径 / 密度 / 气质>
保持什么：<必须贴合现有产品的部分>
故意改变什么：<这版和其他版真正不同的地方>
适合判断什么：<PM 看它主要判断哪件事>
风险：<如果选这版，可能牺牲什么>
```

方向可以来自：

- 信息怎么排：左导航 vs 顶 tab vs 单栏长滚动；
- 信息密度：全上卡面 vs 主信息上卡面、细节进抽屉；
- 一行是什么单元：按对象一行 vs 按动作一行；
- 工作流怎么走：先筛选再处理 vs 先任务流再看详情；
- 整体风格 / 气质（只有 PM 明确要探索新风格，或当前项目还没有界面基调时才比）。

**反同质化硬门**：方向之间必须至少在布局结构、信息密度、用户路径、视觉气质中的两项有差异；只换颜色、只改标题、只把卡片左右挪，不算一版。默认至少一版是低风险贴合现有产品，另外几版必须探索结构或工作流差异。若几版看起来像同一方案的换皮，停下来重列方向，不进入生成。

**用 AskUserQuestion 让 PM 定这轮出几版**（默认 3，重要界面到 5-8；简单界面 1-2 版意思一下就够），并确认这些方向是不是值得画。PM 可以：全画 / 改某几个方向 / 加方向 / 减方向。最多两轮方向调整，之后带着明确假设继续。

> **边界靠判断、不机械**：出几版、围绕哪些岔路，是 AI 看讨论结论 + PM 选的数量定，不是"每次必出 N 版"。

### 步骤 2.5：gstack 能力探测 + 引擎选择

生成前必须先选引擎，不能嘴上说 gstack、实际手写单稿。

1. **优先跑诊断**：
   ```bash
   bash "$PMAI_HOME/scripts/check-gstack-browser.sh"
   ```
   诊断要看：browse binary、design binary、localhost bind、是否处在 Codex sandbox `EPERM`、是否可做 smoke。**不要把 `browse status` 当无副作用检查**，它会主动启动 daemon。
2. **选择引擎并告诉 PM**：
   - `gstack-shotgun`：诊断可用，且这轮主要挑视觉气质 / 密度 / 第一眼感觉 / 多方向结构。
   - `pmai-internal-shotgun`：gstack 缺失、沙箱限制、未授权、或 PM 不想触发外部生成成本；仍然要多方向，不退成单稿。
   - `html-wireframe`：主要验证布局、字段、交互和真实文字；可作为内部 shotgun 的每版载体。
   - `image-import`：PM 已有图，登记进看版参与比选。
3. **能力不足时明确退化**：如果 gstack 因 sandbox localhost `EPERM` 不可用，要说“当前 runtime 限制 gstack browser，改走 PMAI 内部发散草图”；不要说“gstack browser 坏了”。

### 步骤 3：生成设计稿 + 落进单页看版

**先选这轮走哪条路**（可混排比，但每条路最后都要接回 PMAI 看版）：

| | gstack 设计探索 | PMAI 内部发散草图 / HTML | PM 上传图片 |
|---|---|---|
| 看什么 | 视觉风格 / 密度 / 气质 / 第一眼感觉 / 多方案探索 | 布局结构 / 交互 / 字段内容 / gstack 不可用时的多方向替代 | PM 已有截图 / 设计图 / 竞品图 |
| 文字 | 图片中文字只作参考，不能定文案 | 真的、准的 | 看图片来源；不把截图文案直接当规格 |
| 怎么来 | 调 gstack `/design-shotgun` | 先写多方向 concept，再为每版写静态 HTML / 图片稿 | PM 提供本机图片路径或附件 |
| 怎么收口 | 导入 gstack 输出目录 | 直接放 `mockups/` 并登记 | 复制进 `mockups/` |

1. **生成 / 收集 N 版**（N = 步骤 2 PM 定的数）：

   **gstack 路** —— 调 `/design-shotgun`：
   - 把步骤 1.5 的界面对齐约束、步骤 2 的方向清单、谁看 / 放什么字段 / 哪些信息一组，一次性交给 gstack。
   - 要求 gstack 生成 3-8 个真实差异方向，使用 compare board 收 PM 评分 / 评论 / remix / regenerate。
   - 让 gstack 负责生成、打开对比看板、收评分 / 评论 / remix / regenerate。
   - 等 PM 在 gstack 看板提交最终反馈后，记录本轮 gstack designs 目录（含 `variant-*.png`、`feedback.json`、`approved.json`）。
   - 不要让 gstack 目录成为产品记录；它只是临时来源。

   **PMAI 内部 shotgun / HTML 路** —— gstack 不可用或这轮需要真实文字 / 交互时使用：
   - 先把步骤 2 的每个方向写成 concept，不少于 PM 已选 N 版；每个 concept 必须说明“试什么 / 故意改变什么 / 适合判断什么 / 风险”。
   - 每个 concept 各自生成一份静态 HTML / 图片稿，不允许把一个方案换色凑多版。
   - 写 HTML 前把步骤 1.5 的界面约束给进去；项目里已有可复用的 CSS / token / class 命名时优先沿用。每版存 `mockups/<界面>-<方向>/index.html`。
   - 生成后同样登记 `mockups/manifest.json`、刷新单页看版；PM 看到的是多稿对比，不需要知道内部没有跑 gstack。

   **PM 上传图片路** —— 如果 PM 已有图片，让 PM 给本机路径或附件；复制进 `mockups/` 后登记。上传图片可以参与比选，但只作为设计素材 / 方向参照，不自动变成规格事实。

2. **接回 `mockups/`**：

   gstack 或上传图片用导入脚本：
   ```bash
   python3 "$PMAI_HOME/scripts/import-mockup-variants.py" \
     --repo "$REPO_ROOT" \
     --source-dir "<gstack 本轮 designs 目录>" \
     --requirement "<需求/模块名>" \
     --round "第一轮" \
     --concepts "<方向清单 JSON>"
   ```

   用户上传图片用：
   ```bash
   python3 "$PMAI_HOME/scripts/import-mockup-variants.py" \
     --repo "$REPO_ROOT" \
     --image "<PM 上传或本机图片路径>" \
     --requirement "<需求/模块名>" \
     --round "第一轮"
   ```

   HTML 草图直接写进 `mockups/` 后，按下一步登记。

3. **登记进清单**：往 `mockups/manifest.json` 的 `variants` 数组**每版追加一条对象**。**key 必须英文**（`gen-mock-board.py` 只认英文 key，中文 key 会被静默渲染成"—"），值可中文。导入脚本会自动登记 gstack / 上传图片；HTML 草图手动登记：

   ```json
   { "path": "<界面>-a.png", "requirement": "<需求/模块名>", "title": "方案 A：流水线看板",
     "explores": "决策流水线式布局",
     "good_parts": "阶段从左到右、信息密度高", "status": "活跃",
     "round": "第一轮", "featured": false, "retired_note": "" }
   ```

   字段含义见 `templates/mockups-manifest.json.tmpl` 的 `_fields`；`requirement` 写这版来自哪个需求 / 模块（看版按它归类），`round` 只写第几轮探索；`status` 枚举 `活跃` / `待合并` / `已退役`。gstack / 上传图片的 `path` 指图片（`.png` 等），HTML 指页面（`.html`），看版会自动按类型内联预览。

4. **刷新看版**：
   ```bash
   python3 "$PMAI_HOME/scripts/gen-mock-board.py" "$REPO_ROOT"
   ```
   读 `mockups/manifest.json`、重生成 `mockups/index.html` 和 `mockups/viewer.html`（**单页看版**：各版画面内联铺在同一页并排比，图片嵌缩略图、HTML 嵌缩放预览；点画面进入查看页，查看页带返回目录和打开页面入口；**纯生成物、别手改**）。

5. **打开给 PM 看**：把单页看版 `mockups/index.html` 打开给 PM——几版并排在一页里，点开能看每一版大图 / 原页，并能从查看页回到目录。

### 步骤 4：PM 挑定方向

PM 挑哪版/哪些块好。用 AskUserQuestion 让 PM 选（每版一个选项 + 一句话说清这版试的方向和取舍）。允许的结果：

- **挑定一版**：那版标 `featured: true`（看版里会突出）。
- **挑某几版的某几块拼**：记下"取 A 的导航 + B 的抽屉"这类结论，作为回 `/pmai-design` 拍板、再交 `/pmai-spec-writing` 成文规格的依据。
- **都不行 / 想再试**：按 PM 反馈调方向，回步骤 2 再出一轮（新一轮的 `round` 标清楚，老的留着不删）。

挑定后把 `featured` / 必要的 `status` 改进 `manifest.json`，重跑 `gen-mock-board.py` 刷新看版。

> **挑定 ≠ 定稿规格**：本 skill 只负责"PM 用眼睛挑定了方向"。规格怎么写、为什么这么定，是回 `/pmai-design` 做的事——规格里写文字定义 + 指一句"长什么样见 mockup 看版第 N 版"，不再画 ASCII 线框。

### 步骤 5：交回 /pmai-design（或给手动 PM 一个去向）

- **/pmai-design 调进来的**：把"挑定了哪版方向 / 哪几块怎么拼"作为结论交回 `/pmai-design`，它接着把规格写定。
- **PM 手动调的**：告诉 PM 设计稿都留在看版里翻得到、挑定的那版已标出，给一个 Next Up：方向定了就 `/pmai-design` 把这块写进规格（小改）或 `/pmai-build` 去真建（大需求）。

> **设计稿怎么收尾不归本 skill**："探了哪几版、为何选这版"的最终收口在沉淀那一步（build 验收后 `/pmai-build-close`，或暂不 build 时 `/pmai-record` 的探索变体归位）——挑定的标 `featured`、并进主原型的标 `已退役` 留存。本 skill 这一步只登记不删、不做最终收口。

## Rules

- **只动 `mockups/`、不碰 `prototype/`**：设计稿是静态比稿的家，主原型是另一回事。本 skill 不往主原型写任何东西。
- **不开 worktree、不开分支、不拉 PM 进工作区**：在 main 上直接出设计稿（`mockups/` 探索草稿豁免）。这是它"轻"的根本，别给它套 build 的隔离仪式。
- **设计稿是便宜的比稿**：图片 / HTML 线框即可，不接真数据、不搭真组件树、不追求能跑——只为让 PM 用眼睛挑方向。要真能跑的实现是 `/pmai-build` 的事。
- **默认贴合现有界面**：画之前必须先看 `DESIGN.md`、相关 `prototype/` 页面 / 组件 / 样式、已挑定设计稿和模块约束；没有 PM 明确要求，不得凭空换一套风格。
- **无参考时先说清楚**：如果项目还没有可参考界面，这轮就是先定基调；不要假装已经贴合现有产品。
- **gstack / HTML / 上传图片按要挑什么选**：挑**视觉风格 / 密度 / 气质** → gstack；挑**布局 / 交互 / 字段内容** → HTML 路；PM 已经有图 → 上传图片接回看版。
- **先探测 gstack，再选择引擎**：默认优先 gstack-shotgun，但必须先诊断 browse/design/localhost/compare board；Codex sandbox 的 localhost `EPERM` 是 runtime 限制，不是 gstack 损坏。不能把 `browse status` 当无副作用检查。
- **gstack 不可用也要发散**：fallback 是 PMAI 内部 shotgun（多 concept + 多 HTML / 静态稿 + 同页看版），不是退回单方案草图。
- **HTML 草图优先复用现有语言**：已有 CSS / token / class / 组件样式可参考时，静态 HTML 也要沿用它们的视觉语言；不要另造一套不相干的卡片、按钮、颜色和间距。
- **不调用 PMAI 自带图片生成脚本**：本 skill 暂时移除内置图片生成能力；不要在 mockup 流程里调用 `scripts/gen-mockup-image.sh` 或直接让 codex image_gen 出图。
- **gstack 结果必须接回 PMAI**：gstack 负责生成和收反馈，但最终所有候选稿、挑定稿和 PM 反馈必须复制进 `mockups/` 并登记清单；规格和 build 只引用 PMAI 看版路径，不引用 `~/.gstack/...`。
- **用户上传图片允许进入看版**：PM 上传或给出本机图片路径时，可以用导入脚本复制进 `mockups/`；图片只是设计素材 / 方向证据，不能绕过 `/pmai-design` 直接变成规格事实。
- **让 PM 选出几版**：像 shotgun，PM 定这轮几版（默认 3，重要界面 5-8）；多版并行 / 后台生成，别同步干等。
- **多版要真不一样**：几版之间是不同方向（导航 / 密度 / 分块 / 工作流 / 风格），不是同一版改色。同质的几版让 PM 无从取舍。
- **生成的都留下、否掉≠删掉**：所有设计稿都进版本库、进清单；没挑中的留在看版折叠区、翻得到。治"上次那版找不回"。
- **`manifest.json` 是唯一真相源，`index.html` 是纯生成物**：永远改清单、重生成看版，别手改看版页。
- **清单 key 必须英文**：`path` / `requirement` / `title` / `explores` / `good_parts` / `status` / `round` / `featured` / `retired_note`（中文 key 会被 `gen-mock-board.py` 静默丢成"—"）。
- **没想清楚不画**：信息设计（放什么、谁看、怎么分块）没定就回 `/pmai-design`，别瞎画凑数。

### PM-facing 输出禁词

跟 PM 对话 / AskUser 文案 / Next Up 块里**禁出现**：`manifest` / `featured` / `variant` / `design brief` / `信息模型` / `派生 4 环` / `三身份` / `worktree` / `brief`。用 PM 视角的话替：

| 禁词 | PM 视角替代 |
|---|---|
| `manifest` / `index.html` 看版 | 「设计稿清单」/「看版」（翻得到的那个页） |
| `featured` | 「挑定的那版」/「标出来了」 |
| `variant` / 多变体 | 「几版设计稿」/「不同方向」 |
| `design brief` / `brief` | 「交代清楚要画什么」 |
| `信息模型` / `派生 4 环` / `三身份` | 「放什么、谁看、信息怎么来」 |
| `worktree` / 开分支 | 砍掉（本 skill 本就不开） |
