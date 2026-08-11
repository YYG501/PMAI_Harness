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

- 读 `DESIGN.md` 的导航、页面模式、组件、层级、密度和交互约定；
- 若已声明项目级设计系统 Skill，按共享合同调用或完整读取，并把 `使用范围` 和 Skill 规则一起作为本轮约束；
- 读 `project.yml` 声明的相关实现入口（若尚未生成则只读现有产品页面），只取本轮 slice；
- 读 `mockups/manifest.json` 中已选、待合并和已退役方向；
- 读本模块 discussion / decisions / spec 的界面约束。

只有 PM 明确要求换风格时才探索新视觉；项目没有现有界面时说明“这轮在定基调”。

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

### 5. 接回 PMAI 看版

gstack 或用户图片必须通过导入脚本接回本仓；HTML 稿直接写 `mockups/<主题>-<方向>/index.html`。所有候选都登记 `mockups/manifest.json`，再刷新看版：

```bash
python3 "$PMAI_HOME/scripts/import-mockup-variants.py" \
  --repo "$REPO_ROOT" \
  --source-dir "<本轮 designs 目录>" \
  --requirement "<模块/需求>" \
  --round "<本轮>" \
  --concepts "<方向清单 JSON>"

python3 "$PMAI_HOME/scripts/gen-mock-board.py" "$REPO_ROOT"
```

清单 key 使用英文；PM-facing 标题和说明使用自然中文。gstack 临时目录、下载目录或本机绝对路径不是 PMAI 产物落点。

### 6. PM 看结果并迭代

- 单一推荐稿：PM 直接指出哪里不对，继续修改同一方向；
- 多方向：PM 选一套或组合不同方向的具体部分；
- 都不成立：根据反馈重开交互方向，不在原方向上只换皮。

每轮反馈只修改受影响候选，并保留轮次记录。选定后把对应项标为 `featured`，刷新看版；不要删除旧方向。

### 7. 返回 design

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
- 输入必须是完整任务和相关页面，不只是一张卡或当前页。
- 有真实交互岔路才多稿；无岔路只出一套推荐稿。
- 不问 PM 要画几版，不把工具选择变成 PM 菜单。
- 多稿必须在交互模型、信息层级或任务路径上真不同，不允许视觉换皮。
- 覆盖主路径、关联页面和相关边界状态；工具受限不伪装成已覆盖。
- 只写 `mockups/` 与清单，不改 build target；选定后返回 design。
- HTML、图片或静态稿只应用了设计规则时，不声称已经安装或使用真实设计系统 Core / 组件。
- PM 视图不出现 manifest、variant、worktree、context pack 等内部词。
