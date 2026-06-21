---
name: pmai-task-plan
description: |
  承接 req-plan 范围清单、拆成可验收的 task 单元：读项目底座（PRODUCT-STATE / DESIGN / 主原型）+ 本次 req-plan + 原型代码，把本次增量拆成 task。一个 task = PM 看 demo 确认方向的阶段单元（非工程 ticket、mode 中立）。按 $PMAI_HOME/skills/task-plan/templates/task-plan.md.tmpl 生成单一文件 task-plan.md（task 列表 + 执行顺序 + 验收 GAP 映射 + 末尾轻量自检与状态摘要）。覆盖审计的锚点是 req-plan 范围清单（本 skill 承接它拆 task，不另产范围清单）。不生成具体 task 文档，不生成工程合同分文件。
---

# /pmai-task-plan

## When To Use

- 范围确认阶段、req-plan 拍板后把范围拆成 task 时，由 `/pmai-next` 推进调用
- 承接 req-plan 范围清单（页面 / 字段 / 按钮 / tab / 状态 / 做不做）→ 拆成可在原型上逐个验收的 task。范围清单 + 决策页是 `req-plan.md` 的产物（new-req 产、PM 拍板）；覆盖审计对照 req-plan 范围清单，本 skill 不另产、不复制

## task 是什么（先对齐心智）

一个 task = **PM 在原型上看一段 demo、确认这块功能方向对不对**的阶段单元。

- 它不是工程 ticket，不绑某种实现 mode（原型草图 / 真系统都走同一个 task 边界）。
- 它承接「范围确认」里 PM 拍板的范围清单，把「这次要做哪些页面 / 字段 / 按钮 / tab / 状态 / 哪些明确不做」细化成一条条可在原型上验收的功能单元。
- 它承接的 req-plan 范围清单，build 完会被覆盖审计逐条对照原型代码（做没做、做全没做），所以拆 task 时要保证每条范围都落到某个 task、颗粒度到「PM 看得出有没有漏」。

## PM 视图规则（必读）

本 skill 生成的文档须遵守 `skills/_shared/PM-VIEW-RULES.md`（主索引）。具体读以下子文件：
- `_shared/pm-view/writing-rules.md`（写作规则：明确指代 / 正向描述 / 禁工程词 / 禁像素颜色 / 禁反向约束）
- `_shared/pm-view/section-order.md`（章节顺序：按 `$PMAI_HOME/skills/task-plan/templates/task-plan.md.tmpl`）
- `_shared/pm-view/input-flow.md`（输入流：项目底座 + 本次 req-plan + 原型代码；输入清单见下方 Required Inputs）

> 「工程合同」成分（反模式自检结论 / 验收 GAP 索引 / 模块规格状态）压在末尾「四、自检与状态摘要」节。详细论证 / 复审决策不长期存档，跑时输出即可。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: task-plan"
```

## Required Inputs

按 `_shared/pm-view/input-flow.md` 中 **task-plan** 段执行。核心输入三类：

1. **项目底座**（init 时建、每次必读、治失忆）：
   - `PRODUCT-STATE.md` —— 产品当前能力面，判断本次增量落在哪、哪些能力已存在
   - `DESIGN.md` —— 设计与架构约束，task 拆分边界受其约束
   - `prototype/`（主原型代码）—— 判断哪些能力原型里已有、反向校验范围清单
2. **本次 req-plan.md**（范围确认阶段 PM 拍板的范围清单 WHAT + 关键决策页 WHY）—— 拆 task 的直接依据
3. **原型代码 slice** —— 验收 GAP / 复用判断的现状锚点

特别遵守：
- `input-flow.md` 中 prototype 读取强约束（>500 行禁整文件 Read）
- `_shared/pm-view/cross-skill.md`（DESIGN 按需 grep 局部读，不强制全文）

> req-plan「关键决策页」里 PM 已拍板的范围取舍（哪些做、哪些本次不做）直接决定 task 列表与「四、自检与状态摘要」里的验收 GAP 处置 —— 凡是「本次原型不实现」的整块功能，不为它立 task。

## Workflow

### attachments AI 接管 hook（trigger 0 — 拆 task 期间生效）

PM 在 chat 描述 "我有 X 在 ~/Downloads/foo.pdf，重点 Y" → AI first-principle 识别 → 调 helper：

```python
from _lib.attachments import copy_attachment
result = copy_attachment(req_dir, Path("~/Downloads/foo.pdf"),
                        stage_prefix="task-plan", hint="Y 重点")
```

stage_prefix `"task-plan"`。chat 一行确认 `已归档（attachments/task-plan-foo.pdf），Y 重点。继续。`（禁工程黑话）。

异常 catch：`FileNotFoundError` / `SensitivePathError` / `FileSizeError` → chat 报错（fail-loud）。

**trigger 2 fallback**：写 `task-plan.md` 前扫 `attachments/`，`is_seen` 判定。

**引用 section 渲染**：写 `task-plan.md` 时 `list_attachments_seen` 按 `registered_at` 升序渲染到文档物理末尾。

**单一真相源**：`skills/_shared/pm-view/attachments-upload.md`。

### 步骤 0：读 PM 视图规则子文件（强制）

打开（一次会话只读 1 次）：
- `skills/_shared/pm-view/writing-rules.md`（写作规则）
- `skills/_shared/pm-view/section-order.md`（章节顺序）
- `skills/_shared/pm-view/input-flow.md`（输入流）

### 步骤 0.5：项目底座与范围文档强制 echo（不依赖 LLM 自觉 Read）

prose 警告「AI 不得以'觉得不必要'为由跳过」是无效防御 —— LLM 自觉 Read tool 触发不稳是反复迭代踩坑的根因。Bash `cat` 把基础必读全文 echo 进 transcript（治失忆）：

```bash
SOURCES=(
  "$REPO_ROOT/docs/PRODUCT-STATE.md"  # 项目底座：产品当前能力面，判断本次增量落在哪
  "$REPO_ROOT/docs/DESIGN.md"         # 项目底座：设计与架构约束，task 拆分边界受其约束
  "$ACTIVE_REQ_DIR/req-plan.md"       # 本次范围清单 WHAT + 关键决策页 WHY，拆 task 的直接依据
)

for f in "${SOURCES[@]}"; do
  if [ -n "$f" ] && [ -f "$f" ]; then
    echo "════════════════════════════════════════════════════════════════"
    echo "FORCE READ: $f"
    echo "════════════════════════════════════════════════════════════════"
    cat "$f"
    echo "════════════════════════════════════════════════════════════════"
    echo "END $f"
    echo "════════════════════════════════════════════════════════════════"
  else
    echo "ℹ️  $f 不存在或未解析，跳过"
  fi
done
```

**不在 echo 范围**（按 `input-flow.md` 既有强约束读，不全文 echo）：
- `prototype/`（主原型代码）—— >500 行禁整文件 Read（步骤 1 仍要看原型判断已有能力，但不能机械全文 echo）
- `DESIGN.md` 的局部章节 —— 已全文 echo；如本次只涉及某模块章节，按需 grep 复核即可

### 步骤 1：消化已 echo 输入 + 按既有强约束读 slice-read 项

步骤 0.5 已把 PRODUCT-STATE / DESIGN / req-plan 全文 echo 进 transcript。本步骤补：
- `prototype/`（主原型代码）：按 `input-flow.md` 强约束（>500 行禁整文件 Read）—— 判断哪些能力原型里已存在、反向校验范围清单
- `DESIGN.md` 涉及的模块章节：按需 grep 局部复核，确认 task 拆分边界不与既有架构约束冲突

### 步骤 2：拆分 task

> **颗粒度核心规则**：一个 task = PM 能在一次原型 demo 里完整验收的功能单元。
>
> **验收硬约束**：必须能在原型上演示一段业务流程才算端到端验收。PM 走查代码结构 / 文档可读性 / 契约合理性 **不算**端到端验收。文档型产物（功能规格文档 / functions.md / 字段口径契约 / 范围裁剪规则）天然不满足本约束 → **不立 task**，由业务 task 收尾后的沉淀流程补对应章节。跨 task 共享口径决策应在范围确认阶段（req-plan 关键决策页）定死，不为此立 task。
>
> **业务模块 task**：一个 task 对应 1-N 条紧密相关的功能清单条目；紧密相关指同一个 user story 链条，或同一个页面区域可一次性 demo。不同 user story 链条即使在同一页面，也要拆成不同 task。

每条 task 在范围清单里除「交付什么」外，还要写清以下四个字段（决定 PM 怎么看 demo 验收、build 时怎么排）：

- **执行深度**：本 task 的页面 / 字段 / 按钮 / tab / 状态做到什么程度（能跑通主流程 / 含边界态 / 含空态错误态），决定 demo 验收时 PM 看哪些。
- **PM 确认什么**：PM 在这块 demo 上要拍板的方向问题（这个流程对不对 / 这个布局取舍接不接受），一句话。
- **不做什么**：本 task 范围内明确划出去、本次不做的部分（防覆盖审计误判为「漏」，也防 build 越界）。
- **并行性**：本 task 能否与其它 task 同时在各自原型分支上跑（无 merge 冲突 + 不互相依赖产物），还是必须排在某个 task 之后。
>
> **基础设施 task**：一个 task 对应一类完整可用的基础设施能力，例如项目脚手架、共用组件库、auth context、API client、构建配置。
>
> **端到端切片原则**：task MUST 按 user story 端到端切（前端 + 后端 + 数据层捆绑）；technical layering cuts are FORBIDDEN，不允许拆成"先数据层、再 UI、再联调"。

#### 2.1 基本原则

> **DX RU1 固定提示：业务模块 / 基础设施判定硬规则**
>
> 1. 每个 task 必须显式声明 `所属模块`，只能是一个或多个业务模块，或 `基础设施`。
> 2. 产出在任何业务页面/流程上直接可见时，必须归到对应业务模块。
> 3. 只有产出不在任何业务页面/流程上直接可见，且不是文档型规格（模块规格文档 / functions.md / 字段口径契约 / 范围裁剪规则），才允许标 `基础设施`。
> 4. 基础设施 task 验收后不沉淀进 `PRODUCT-STATE.md` 的业务能力面；如需长期记录，由 PM 决定是否写入 `PRODUCT-STATE.md` / `DESIGN.md`。
>
> 基础设施识别示例：项目脚手架、共用 Button/Modal 组件库、API client、auth context、构建配置。反例：登录页的"会话管理 hook"服务于登录流程，应归登录页/账号模块。

#### 2.2 反模式（必须避免）

每次拆完先按下面 5 条反照一遍，命中任何一条就合并或重构该 task：

**反模式 A：纯前置 task（重构 / 文档 / 规格 / 契约）**

> 例 1：为了后续 task 并行改同一大文件不冲突，先加一个"纯拆文件 / 纯改结构"的 task，本身在原型上看不到任何变化。
> 例 2：为了让后续多个页面 task 共享字段口径与范围裁剪规则，先单独一个"写功能规格文档"task，文档写完后页面 task 才启动。
> 例 2 变体（同样错）：把"覆盖多平台的规格文档"塞进第一个页面 task，让该 task 同时承担"页面 + 跨平台规格"两件事。

- 问题：纯前置 task 不满足颗粒度核心规则的验收硬约束（PM 在原型上看不到一段业务流程），却要占一个完整的 demo 验收 + 收尾流程。
- 判断：
  - **重构类前置**：后续 task 串行执行时 merge 冲突不存在，前置理由不成立，合并进首个相关业务 task。仅当后续 task 必须并行且冲突无法避免，才考虑前置，并且必须带端到端行为验证点。
  - **文档 / 规格 / 契约类前置**：不立 task。由各业务 task 收尾后的沉淀流程补对应章节（颗粒度核心规则已说明）。
    - **包括 req-plan 关键决策页明文要求的"主线规范产物"** —— 即使决策页把"建立 X 规范段 / 字段字典 / 权限矩阵"列为必有产出，仍按文档类前置处理：**不合并进业务 task**、**不把 `PRODUCT-STATE.md` / `DESIGN.md` 写进业务 task 的「执行范围」allowlist**。由首个相关业务 task 收尾后沉淀进 `PRODUCT-STATE.md` / `DESIGN.md`。理由：「内容必须存在」是范围确认把关的内容硬约束，「什么时候写 / 走哪条原型分支」是流程问题（task 边界 + 沉淀）—— 两件事，不能因前者绕开后者。判定信号：产物归宿是项目底座文档（`PRODUCT-STATE.md` / `DESIGN.md`）而非 `prototype/` 里的代码 → 默认文档类。

**反模式 B：横切质量 task**

> 例：把所有 UI 改造 task 的 a11y、1280px 响应式、埋点、i18n 剥出来最后统一做一个"质量收尾 task"。

- 问题：前面 UI task 会在没有这些质量维度的状态下过 `/qa` 和 `/design-review`，等于 review 半成品。
- 判断：a11y / 响应式 / performance / 埋点 / i18n 等跨所有 UI 的质量维度必须写进每个 UI task 的验收依据，不允许独立成 task。

**反模式 C：共生对拆成两个**

> 例：task A 定义纯函数签名，task B 改 Mock 数据以匹配签名。单独跑 A 只能用 stub 验证，单独跑 B 没有函数可调。

- 判断启发式："单独跑完 A 后，能端到端验证到业务价值吗？"如果不能，合并 A 和 B。
- 典型共生对：纯函数层 + 对应 Mock/fixture；数据库 schema migration + ORM model 更新；新组件 + 首个调用方。

**反模式 D：同文件串行多 task（软约束）**

> 例：task 006/007/008 都改同一个详情页文件且串行，只为验收维度清晰就拆 3 个 task。

- 判断：同文件 + 串行的 task，必须在 `task-plan.md`「四、自检与状态摘要」的反模式 D 行里显式写出"拆多个 vs 合并"的成本权衡结论。
- 没写权衡理由而拆多个的，默认合并。

**反模式 E：业务功能 task 没有模块归属**

> 例：task "实现产品访问管理列表页" 标 `所属模块: 基础设施`。

- 问题：业务功能不沉淀进 `PRODUCT-STATE.md` 的业务能力面，产品现状档会残缺。
- 判断：见 DX RU1（业务模块 / 基础设施判定硬规则）。
- 典型错误示例：登录流程、列表筛选、批量导出、权限提示、详情页状态展示都不是基础设施。

#### 2.3 task 数量启发式

- 单 req 总 task 数 > 7 时，立即回头按 2.2 审查。不是硬上限，但经验上超过 7 往往踩中反模式 A/B/C。
- 单模块软上限 = 3 tasks。单个模块被拆成超过 3 个 task 时，必须回头审查是否把同一页面区域或同一 user story 链条拆得过细。

#### 2.4 拆分后自检清单

给每个 task 问以下 5 个问题，任何一个答"是"或"不满足"就返回 2.2 处理：

1. [ ] 这个 task 的验收依据是否只有"代码结构变好/重构完成"这种过程性描述？（反模式 A）
2. [ ] 这个 task 描述的工作是否应该是其他某个 task 的验收标准的一部分？（反模式 B）
3. [ ] 这个 task 单独跑完后，能不能由 PM 通过原型 demo 验到业务行为？（反模式 A/C）
   - PM 走查代码结构 / 文档可读性 / 契约合理性 不算独立验证
   - 必须能在原型上演示一段业务流程才算
4. [ ] 这个 task 和另一个 task 改同一文件且串行，是否在 `task-plan.md`「四、自检与状态摘要」里写了成本权衡结论？（反模式 D）
5. [ ] 所有 task 的模块归属是否满足硬规则？业务功能 task 是否真的归到了业务模块章节，而不是图省事标成 `基础设施`？（反模式 E）

### 步骤 3：写 task-plan.md

按 `$PMAI_HOME/skills/task-plan/templates/task-plan.md.tmpl` 生成 `$ACTIVE_REQ_DIR/task-plan.md`。**只生成这一份范围清单，不生成具体 task 文档**：

**章节顺序**（强制，由 `_shared/pm-view/section-order.md` 锁定）：
1. 📌 拆分摘要
2. 一、Task 列表
3. 二、执行顺序与并行性
4. 三、风险
5. 四、自检与状态摘要（反模式自检 5 条 + 验收 GAP 清单 + 模块规格状态）
6. 📁 历史档案（变更记录）

**写作约束**（违反将由 `check-doc-pm-view.py` 报错）：
- 每个名词带完整指代前缀
- 不出现像素值 / 颜色码 / 工程词（reducer / dispatch 等）
- 不出现反向约束（"禁止 X / 不允许 Y"）
- task 列表 summary 一句话讲清交付物，不写实现细节

**「四、自检与状态摘要」填写要点**：
- 4.1 反模式 5 条逐条勾选"未命中 / 命中（已处理）"，命中时一句话说明合并 / 重构结论。**5 条全 PASS 才能进入 build**。
- 4.2 验收 GAP 清单：从 `req-plan.md` 范围清单逐条审视，编号 G1, G2, ...。每条范围清单条目都要能在 build 完被覆盖审计对照原型代码验到。**三种处置之一**：
  1. **由 task-NNN 接住**（默认）—— 由该 task 在原型上做出来、demo 验收
  2. **已被 task 列表完全覆盖** —— 显式写「无 GAP」
  3. **本次原型不实现（整块功能不做）** —— PM 在 req-plan 关键决策页已拍板本期整块功能不做；
     在 GAP 行写「本次原型不实现 → req-plan 决策页 D-NN」，引用 req-plan 关键决策页对应那条决策。
     沉淀阶段（close-req）据此在 PRODUCT-STATE 标注「本功能本次不做」，供覆盖审计排除、不误报为漏。
- 4.3 模块规格状态：列出本 req 涉及的每个业务模块在 `PRODUCT-STATE.md` 里的当前状态（已存在-完整 / 已存在-待补 / 不存在-待创建），供 task 实现时判断要不要新建模块章节。

### 步骤 3.5：PM 拍板执行模式（结构决策门）

「二、执行顺序与并行性」里的执行模式（串行 / 并行 / 混合）是 task 级结构决策（AI 没把握；并行 vs 串行影响 PM 时间分配巨大）。步骤 3 写完文件后**主动问 PM** 拍板：

```
🛑 执行模式（结构决策 / 你拍板）

候选：
  A. 串行（一个 task 看完 demo 再起下一个，串起来一致性问题好抓；总时长 = 各 task 之和）
  B. 并行（多个 task 同时在各自原型分支上跑；最快；要求 task 间无冲突 + 不互相依赖产物）
  C. 混合（前面几个串行打底产规范 / 复用，后面并行铺开）

AI 倾向 <A/B/C>，理由：<本次具体情况，一行 — 例：3 个 task 改不同页面无冲突 / 但 task-001 含规范段要先定 / 故倾向混合（task-001 单跑、task-002+003 并行）>

PM 拍板：
```

PM 答完：
1. 修订 `task-plan.md`「二、执行顺序与并行性」：
   - 「执行模式（PM 拍板）」行写 PM 选定值
   - ASCII 流程图按选定模式重画
   - 各条执行线按选定模式描述（串行 = 单线 / 并行 = 多线 / 混合 = 一条单 task 线 + 一条并行线）
   - 「PM 启动建议」按选定模式重写
2. append decision 事件（记录这次 PM 拍板，沉淀进决策上下文）：
   ```bash
   python3 "$PMAI_HOME/scripts/req-events.py" append decision \
     --req "$(basename "$ACTIVE_REQ_DIR")" --source "task-plan" \
     --decided-by pm-explicit \
     --decision "执行模式：<PM 选的>" \
     --prd-anchor "task-plan 执行顺序与并行性" \
     --chosen "<串行 / 并行 / 混合>" \
     --alternatives '["串行","并行","混合"]' \
     --rationale "PM 在 task-plan 执行模式结构决策门拍板"
   ```
3. 进步骤 4 自检

> **为什么放在这里**：步骤 3 写文件时如先问 PM 会打断 Write 节奏；
> 放步骤 4 自检前是"AI 推断 + PM 拍板覆盖"的最自然时机 —— 执行模式落盘是 PM 决策结果而非 AI 自决。
>
> **续跑行为**：本步骤是范围确认阶段内部门，不影响 `/pmai-next` 的阶段推进边界
> （PM 答完执行模式后 task-plan 继续步骤 4/5）。
>
> **改拆分触发本步骤重跑**：PM 改了 task 拆分（增删 task）后，原执行模式可能不再适用 —— 重新跑步骤 3 → 重新走步骤 3.5 拍板。

### 步骤 4：自检（按 `_shared/pm-view/checklist.md` 自检清单）

写完后对 `task-plan.md` 逐条检查：
- [ ] 章节顺序符合 $PMAI_HOME/skills/task-plan/templates/task-plan.md.tmpl
- [ ] 所有名词带完整指代前缀
- [ ] 无像素值 / 颜色码 / Emoji 视觉
- [ ] 无反向约束
- [ ] 无组件实现名
- [ ] 无设计意图解释
- [ ] 抽象动词都搭配具体效果

任一项未通过 → 修复后重新自检。

### 步骤 4.5：自动跑启发式 lint

人工自检之后，调用 `check-doc-pm-view.py` 做机器校验作为兜底：

```bash
python3 "$PMAI_HOME/scripts/check-doc-pm-view.py" "$ACTIVE_REQ_DIR/task-plan.md"
```

处理输出：
- **0 errors + 0 warnings**：进入步骤 5 退出 skill
- **有 warnings**：向 PM 展示，PM 决定是否修
- **有 errors**：修复后重跑 lint；连续 3 次仍有 error 时停下询问 PM

### 步骤 5：skill 结束 → /pmai-next 接手

写完 task-plan.md → skill 退出。向 PM 展示一句话摘要 + 文件绝对路径（不贴全文）。

控制权交回 `/pmai-next`，由它：
- 输出"推荐 review 工具"区块（`/plan-eng-review` `/plan-design-review` `/autoplan` 等，PM 自选自跑）
- 走推进确认门，确认后进 build

**禁止**：skill 内部不得自动调任何 review 工具。PM 要求修改 → 改完 task-plan.md 重新走 `/pmai-next` 流程。

进 build 后，具体 task 文档由 build 阶段的 `/pmai-task-spec <task-id>` 按 task-plan.md 逐个生成（每个 task 一个单文件，机器降 AI 后台、worktree 自动托管）。

### 步骤 6（中途重新拆分）：build 期间发现拆分需要重做

build 阶段一个个把 task 做出来时，有时跑到 task-NNN 才发现 task 拆分本身有问题，需要废弃当前拆分回范围确认重拆。

`/pmai-next` 重新触发本 skill 时（PM 已完成废弃当前拆分 + 回滚），按步骤 1-3 重新写 task-plan.md，遵守两条约束：

- 新增 task 编号**往后接**，不复用已废弃 task 编号
- 在 task-plan.md 历史档案变更记录里追加一条变更说明（写明本次重拆替代了哪些已废弃 task）

废弃 / 回滚的具体操作流程见 `task-transition` 与 `/pmai-next` 推进流程，不在本 skill 复述。

## Rules

**禁止项**：

- ❌ skill 内部走推进确认门（交给 `/pmai-next`）
- ❌ skill 内部自动调任何 review 工具
- ❌ skill 内部推进阶段（交给 `/pmai-next`）
- ❌ 自动生成 tasks/task-NNN-*.md（这是 task-spec 的事，build 期间逐个生成）
- ❌ 生成 task-plan.engineering.md 之类的工程合同分文件（task-plan 单文件，自检结论压在「四、自检与状态摘要」）
- ❌ 「四、自检与状态摘要」里堆论证全文 / 拆分依据论证 / 复审决策表（这些是过程产物，跑时输出，不长期存档）
- ❌ 跳过项目底座与范围文档的"必读"（PRODUCT-STATE / DESIGN / 主原型 / req-plan）

**正向约束**：

- task 编号三位数，从 001 开始，格式 `task-001`。
- 拆完 task 必须跑步骤 2.4 自检；任何一条命中就返回 2.2 合并或重构，不能直接进入步骤 3。
- task 总数超过 7 时，必须在 task-plan.md「四、自检与状态摘要」的"结论"行里显式列出每个 task 的存在理由。
- 单模块超过 3 个 task 时，必须在 task-plan.md「四、自检与状态摘要」里写明为什么不合并。
