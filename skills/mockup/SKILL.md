---
name: pmai-mockup
description: |
  design 的按需交互探索能力：读取现有产品、完整任务、上下游页面和边界状态；有真实交互岔路时生成 2–3 个真正不同的方向，没有岔路时只生成一套推荐稿。只写 mockups/ 与清单，选定后返回 design。
---

# /pmai-mockup · 交互方向探索

## 入口护栏

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止并引导 PM 先发 `/pmai-init-project`。

执行前读取：

- `skills/_shared/context-reconstruction.md`
- `skills/_shared/decision-policy.md`
- `skills/_shared/gstack-integration.md`
- `skills/_shared/project-design-system.md`
- `skills/_shared/PM-VIEW-RULES.md` 及其引用的 PM 视图规则

## 定位与边界

mockup 负责把已经讲清的产品问题变成可看的交互方向，帮助 PM 判断信息层级、任务路径和交互模型。它通常由 design 自动调用，也保留手动入口。

- 只写 `mockups/`、`mockups/manifest.json` 和生成的看版；
- 不修改 `project.yml` 声明的实现入口或模块 `spec.md`；
- 不创建 worktree，不成为第二条 build 链路；
- PM 选定方向后立即返回 design，由 design 把选择变成决定和规格。

## 输入合同

生成前必须拿齐下面的最小上下文；缺的是产品模型时返回 design，不靠画图猜：

1. 根目录 `DESIGN.md`；
2. 按 `skills/_shared/project-design-system.md` 解析并执行的项目设计系统声明（已接入时）；
3. 与本轮相关的现有产品页面、组件和样式；
4. 本次**完整任务**：触发、入口、主路径、完成结果；
5. 上游入口页和下游详情/关联页；
6. context pack 中的 active 决定、已选方向和被否方向；
7. 角色、权限、数据范围；
8. 相关边界状态：空态、加载、错误、长内容、权限不足、无数据、冲突、移动/窄屏（适用时）；
9. 本轮不做什么，以及哪些内容只是 mock。

“只画当前卡片”不算完整输入。若这张卡的动作会进入用户详情、部门详情、抽屉、弹窗或其它页面，候选稿必须把这段任务走完。

## 主流程

### 1. 先对齐现有产品

默认贴合当前产品，不重新发明一套视觉语言：

- 读 `DESIGN.md` 的体验目标、导航、页面模式、组件、层级、密度和交互约定，不只摘颜色、字体、圆角；
- 若已声明项目级设计系统 Skill，按共享合同调用或完整读取，并把 `使用范围` 和 Skill 规则一起作为本轮约束；
- 读 `project.yml` 声明的相关实现入口（若尚未生成则只读现有产品页面），只取本轮 slice；
- 读 `mockups/manifest.json` 中已选、待合并和已退役方向；
- 读本模块 discussion / decisions / spec 的界面约束。

生成前必须把读取结果编译为本轮设计依据，明确四类约束：

- `必须继承`：`DESIGN.md` 中与本轮任务直接相关的体验原则、视觉基调、密度和交互习惯；
- `必须复用`：实际参考的应用外壳、导航、页面标题、布局、组件和状态模式，并绑定真实仓内路径；
- `允许改变`：本轮为了验证交互方向可以调整的区域；
- `设计护栏`：根据产品定位写出本轮不能出现的体验退化，例如反表单产品不能堆成字段面板、任务型页面不能让同级区块争抢首屏。

```bash
python3 "$PMAI_HOME/scripts/mockup-quality.py" compile \
  --repo "$REPO_ROOT" \
  --requirement "<模块/需求>" \
  --round "<本轮>" \
  --round-goal "<本轮要判断的产品问题>" \
  --reference "<现有页面 / 组件 / 样式的仓内路径，可重复>" \
  --must-inherit "<必须继承，可重复>" \
  --reuse "<必须复用，可重复>" \
  --may-change "<允许改变，可重复>" \
  --guardrail "<设计护栏，可重复>" \
  --out "mockups/audits/<需求>/<轮次>/design-basis.json"
```

已有产品至少绑定一个真实实现参考；不能只写“参考了现有产品”。没有现有界面的全新产品才使用 `--new-visual-baseline`，并说明“这轮在定基调”。只有 PM 明确要求换风格时才探索新视觉。生成期间 `DESIGN.md`、已声明设计系统 Skill 或绑定参考发生变化时，旧依据立即失效，重新编译后再继续。

### 2. 判断是否存在真实交互岔路

真实岔路至少改变下面一项，而且会影响用户完成任务：

- 交互模型；
- 信息层级；
- 主任务路径；
- 一行/一卡代表的业务对象；
- 页面之间如何衔接；
- 权限或状态下的行为。

处理规则：

- **无真实岔路**：只生成一套推荐稿，不凑第二、第三套；
- **有真实岔路**：直接生成 2–3 个方向，不再先列方向、再问 PM“画几版”；
- **只是颜色、字体、圆角或左右换位**：不算不同方向；
- **产品模型岔路**：返回 design/meta 让 PM 先拍，不用视觉稿代替产品决定。

每个真实方向必须说明：试什么、保持什么、故意改变什么、适合验证什么、牺牲什么。方向之间至少在交互模型、信息层级、任务路径三项中的一项有本质差异。

接入看版时，把上面的比较信息收成 PM 可直接阅读的三项：

- `核心做法`：这一版如何组织信息和任务路径；
- `适合`：它最适合哪类判断或使用情境；
- `主要取舍`：为了得到这个效果牺牲什么，不能只记优点。

### 3. 选择生成能力

框架自动选择工具，不让 PM 选引擎：

1. 先运行 `check-gstack-browser.sh` 探测当前 runtime；不要把 `browse status` 当无副作用检查；
2. 主要验证视觉气质、密度或多结构方向且 gstack 可用：用 gstack `/design-shotgun`；
3. 主要验证真实文字、字段和交互：用 HTML 草图；
4. gstack 受限：走 PMAI 内部 HTML / 静态稿，不把 runtime 限制说成 gstack 损坏；
5. PM 已给截图/设计图：导入看版，只当方向证据，不自动成为规格事实。

禁止因 gstack 不可用就把有真实岔路的任务退成一套稿；也禁止在无岔路时为了 shotgun 强行多稿。

### 4. 生成完整任务覆盖

每个候选方向按适用范围覆盖：

- 主入口与主路径；
- 关联的入口页、列表/卡片、详情页、弹窗/抽屉；
- 上游选择如何带入下游；
- 空态、错误态、长内容、无权限、无数据和关键边界状态；
- 各角色/权限下不同的可见和可操作范围；
- 完成、取消、失败、返回和重新进入后的状态。

不适用的状态可省，但要在该方向说明为什么不适用。不能只把正常态当前卡片画漂亮，就声称完成任务探索。

### 5. 视觉验收后才进入看版

每个方向生成后，必须用可操作真实页面的浏览器或 Playwright 打开结果，自行完成一轮“截图 → 检查 → 修改 → 重截”。至少检查：

- `design-principles`：逐条对照本轮 `必须继承` 与 `设计护栏`，不能只证明颜色和组件像；
- `existing-shell-and-components`：已有产品实际复用了绑定的应用外壳与组件模式；若另画相似外壳，视为失败；
- `information-hierarchy`：主任务、Agent 判断 / 引导 / 结果（适用时）先于过程、证据和辅助信息，同级区块没有争抢首屏；
- `task-path-and-states`：主路径、关联页与适用边界状态可走通，按钮不是摆设；
- `responsive-layout`：桌面和 320–480 宽窄屏没有遮挡、截断、不可控横滚或信息顺序错乱；
- `text-and-controls`：文字可读、按钮和控件含义明确，信息密度符合 `DESIGN.md`。

先按候选路径生成报告骨架：

```bash
python3 "$PMAI_HOME/scripts/mockup-quality.py" init-audit \
  --repo "$REPO_ROOT" \
  --contract "mockups/audits/<需求>/<轮次>/design-basis.json" \
  --variant "mockups/<候选方向>/index.html" \
  --out "mockups/audits/<需求>/<轮次>/visual-audit.json"
```

多方向时重复 `--variant`。把实际使用的浏览器适配器、桌面与窄屏 PNG 截图、截图时间与摘要、逐项证据、每条编译约束的 pass 结果和视觉走查观察补进报告；gstack 图片可先按导入后的确定路径生成骨架，再导入图片。不通过就先修改方向；不能把 finding 留给 PM，再把稿子当完成结果呈交。生成 / 导入候选资产后运行：

```bash
python3 "$PMAI_HOME/scripts/mockup-quality.py" verify \
  --repo "$REPO_ROOT" \
  --contract "mockups/audits/<需求>/<轮次>/design-basis.json" \
  --report "mockups/audits/<需求>/<轮次>/visual-audit.json"
```

命令返回 `MOCKUP_QUALITY: PASS` 后，才刷新看版呈交。工具受限、没有真实浏览器截图或质量检查未通过时，明确说明尚未完成，不生成伪造的 pass 报告。

mockup 是 design 内部能力，不单独制造生命周期阶段。无浏览器时回执必须同时写明桌面与窄屏验收均为 blocked、阻塞原因和后续补验条件；`designing` 保持不变，不能把 blocked 写成视觉通过。

### 6. 接回 PMAI 看版

gstack 或用户图片必须通过导入脚本接回本仓；HTML 稿直接写 `mockups/<主题>-<方向>/index.html`。所有候选都登记 `mockups/manifest.json`，再刷新看版：

```bash
python3 "$PMAI_HOME/scripts/import-mockup-variants.py" \
  --repo "$REPO_ROOT" \
  --source-dir "<本轮 designs 目录>" \
  --requirement "<模块/需求>" \
  --round "<本轮>" \
  --round-goal "<本轮要判断的产品问题>" \
  --concepts "<方向清单 JSON>" \
  --design-basis "audits/<需求>/<轮次>/design-basis.json" \
  --visual-audit "audits/<需求>/<轮次>/visual-audit.json"

python3 "$PMAI_HOME/scripts/mockup-quality.py" verify \
  --repo "$REPO_ROOT" \
  --contract "mockups/audits/<需求>/<轮次>/design-basis.json" \
  --report "mockups/audits/<需求>/<轮次>/visual-audit.json"

python3 "$PMAI_HOME/scripts/gen-mock-board.py" "$REPO_ROOT"
```

清单 key 使用英文；PM-facing 标题和说明使用自然中文。每条新生成稿固定使用 `schema_version: 2`，记录本轮目标、创建与更新时间、设计依据和视觉验收报告；同轮多方向共享轮次、本轮目标和两份质量证据。HTML 稿直接登记时也遵守同一字段，不得绕过质量门。PM 上传的截图 / 设计图只作为外部方向证据，可保留历史兼容格式，不声称已通过 PMAI 视觉验收。看版按需求、轮次、方向三层展示，需求和轮次都按最近更新时间倒序，轮内已选方向优先。gstack 临时目录、下载目录或本机绝对路径不是 PMAI 产物落点。

### 7. PM 看结果并迭代

- 单一推荐稿：PM 直接指出哪里不对，继续修改同一方向；
- 多方向：PM 选一套或组合不同方向的具体部分；
- 都不成立：根据反馈重开交互方向，不在原方向上只换皮。

每轮反馈前重新读取 `DESIGN.md`、项目设计系统声明和本轮设计依据；只修改受影响候选，修改后重做双 viewport 视觉验收并刷新该候选的更新时间，保留轮次记录。选定后把对应项标为 `featured`，刷新看版；不要删除旧方向。

### 8. 返回 design

返回内容只包括：

- 选定的是哪套交互模型；
- 合并了哪些方向的哪些部分；
- 这次选择解决了什么任务问题；
- 放弃方向及代价；
- 仍需 design 拍板的产品问题（如有）。

挑定不等于规格定稿，也不直接进入 build。由 design 把结论写进 decisions，并自动调用 spec-writing。

## 给 PM 的回执

```text
设计稿已经放进看版：<路径>。

这轮重点验证了：<交互模型 / 信息层级 / 任务路径>。
覆盖了：<主路径 + 关联页面 + 边界状态>。
你选定的是：<方向 / 组合>。

▶ Next Up：我会回到 design，把这个方向写成当前规格；不需要你再调用内部 Skill。
```

## Rules

- 默认先读现有产品和 `DESIGN.md`，不凭空换风格。
- 生成前编译设计依据，绑定 `DESIGN.md`、项目设计系统与实际参考路径；不允许只口头声称读过。
- 已有产品复用真实应用外壳与组件模式，不重新画一套相似外壳。
- 输入必须是完整任务和相关页面，不只是一张卡或当前页。
- 有真实交互岔路才多稿；无岔路只出一套推荐稿。
- 不问 PM 要画几版，不把工具选择变成 PM 菜单。
- 多稿必须在交互模型、信息层级或任务路径上真不同，不允许视觉换皮。
- 覆盖主路径、关联页面和相关边界状态；工具受限不伪装成已覆盖。
- 每个生成方向必须通过桌面与窄屏视觉验收；未通过不进入看版。
- 只写 `mockups/` 与清单，不改 build target；选定后返回 design。
- HTML、图片或静态稿只应用了设计规则时，不声称已经安装或使用真实设计系统 Core / 组件。
- PM 视图不出现 manifest、variant、worktree、context pack 等内部词。
