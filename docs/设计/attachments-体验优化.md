# D-iii：attachments AI 接管（Model 2）(v1)

> **状态**：草稿 v1（§0 已锁，方案主体待 plan-eng-review）
> **日期**：2026-05-25
> **作者**：PM + AI
> **历史文件名**：`attachments-体验优化.md` → 落地后改名为 `attachments-AI-接管.md`
> **版本史**：v0 stub（§0 待共写）→ **v1**（PM 拍 Model 2：AI 接管、PM 不感知 attachments/ 目录；E3/E4/E5 三个 edge case 决议齐 + §0 锁定）

---

## §0 原始痛点（v1 锁定，**不可反向修改**）

### §0.1 痛点（1-3 句）

PM 完全不知道现仓 attachments 机制存在 + 不知道路径 + 不知道如何上传。两个现 trigger（PM 主动提 / AI 写产出前扫）都是 **reactive**，永远 silent 直到 PM "知道该说"，但 PM 没在任何 chat 里看到过提示就永远学不到机制存在。

根本性：现状机制选 "PM 管 `attachments/` 目录"（工程视角，要求 PM 学路径约定 + 文件名前缀），但 PM 视角应是 "我跟你说我有什么材料"，AI 后台搞定 cp + 命名 + 引用。**PM 视角 vs 工程视角错配**（与 D-i v4 "office-hours snapshot" 同结构决策）。

### §0.2 触发场景

| # | 场景描述 | 实证证据 |
|---|---|---|
| 1 | PM 起 req → 走 worktree → 跑 stage-gate → 全程没看到任何 chat 提到 attachments，永远不知道这个机制存在 | **EVIDENCE**：PM 表述（本会话）"目前就是不知道如何把附件上传，上传到什么位置，以及是否后续的阶段，能够读取到这些附件" |
| 2 | 现 trigger 1 要 PM 主动说 "我有附件" 才告诉路径 → PM 不知道该说就永远不知道路径 | **EVIDENCE**：`docs/归档/完成/attachments-机制.md` §三：trigger 1 = "PM 主动提"，AI 仅在 PM 提了之后才告诉路径 |
| 3 | 现 trigger 2 silent 扫描，空目录永远不输出 → PM 没体感任何反馈 | **EVIDENCE**：同上 §三 trigger 2 = "AI 写产出时主动扫"，空目录跳过、不打扰 PM |
| 4 | PM 视角应是"跟 AI 描述材料"（同 D-i v4 office-hours 是 "PM 跟 AI 讨论需求"），不该是"管理 worktree 子目录的文件 system 操作" | **EVIDENCE**：PM 拍方向 A = mental model 切 Model 2（AI 接管，PM 不感知 attachments/ 目录） |

### §0.3 根因

**两层根因**：

1. **机制层根因**：attachments 机制选 PM 自管目录（工程视角），要求 PM 学 `requirements/active/req-NNN-<slug>/attachments/` 路径约定 + `brief-` / `analysis-` / `task-NNN-` 文件名前缀。**PM 单人生产力工具不该让用户学 filesystem 约定**（与项目章程 "PM single-user 工作流" 冲突）。
2. **discoverability 根因**：两个 trigger 都 reactive，**没有 proactive announcement**。PM 自始至终在任何 chat 里看不到 attachments 路径，就永远学不到机制存在。

### §0.4 不解决什么

| # | 衍生 / 假设场景 | 为什么不解决 |
|---|---|---|
| 1 | attachments 内文件版本管理 | git 自然 diff 即可（沿用 `attachments-机制.md` §九） |
| 2 | attachments 大小限制 / git LFS 接入 | 小项目暂不需要；超大文件 PM 自外部引用（同 §九） |
| 3 | 跨 req 共享材料（多 req 用一份）| PM 自己复制到各 req 的 attachments/（同 §九 接受重复） |
| 4 | AI 跨 req 检索历史 attachments | 用 `grep -r` 即可，不进框架（同 §九） |
| 5 | 自动 OCR / binary 解析（视频 / 音频 / 二进制）| gstack 工具栈 / Read 工具原生不在范围（同 §九，需先转写） |
| 6 | attachments 子目录结构（per-stage subfolder） | 文件名前缀 + 引用 section 足够定位（同 §九） |
| 7 | 砍掉现 trigger 2（AI 扫 attachments/ 静默发现新文件）| **保留作 fallback**（E5 决议）—— PM 真自己 cp 进去（绕过 chat）仍能识别，0 信息损失，几行 SKILL prose 成本 |
| 8 | hardcode 触发词（"上传" / "@" 等关键字）| **PM 拍**：AI 自己 first-principle 识别（chat 含 "绝对路径 + 描述材料" 即触发） |
| 9 | "问 PM 是否覆盖" 在每次命名冲突 | E4 决议：自动追加 `-2` / `-3` 后缀更顺，每次都问烦 |
| 10 | "PM 提交意图后 AI 反问是否上传"（避免误识别）| trade：破"一次回话搞定"体感；误识别时 PM 立即说"不是"，AI rm 成本极低，不值得每次都问 |

---

## §1 方案概述（v1 Model 2 + LLM 接管）

### §1.1 一句话

PM 在 chat 自然描述 "我有 X 在路径 Y" → AI Bash cp 到 `$ACTIVE_REQ_DIR/attachments/<stage 前缀>-<源 basename>` + 在当前 stage 产出 `## 📎 参考材料` 引用 + chat 一行确认。**PM 完全不感知 `attachments/` 目录**（IDE 里仍能看到，但心智操作里不去碰）。

### §1.2 PM 体感 walkthrough

```
[Stage 2 req-stage-gate 跑到一半，AI 在需求讨论]

PM: 我有份用户访谈，在 ~/Downloads/interview-2026-05.pdf，重点是第 3 页痛点列表。

AI: 已归档（attachments/analysis-interview-2026-05.pdf），重点已记。继续。
```

后台 PM 不感知：
- AI 校验 `~/Downloads/interview-2026-05.pdf` 可读
- AI Bash `cp` 到 `$ACTIVE_REQ_DIR/attachments/analysis-interview-2026-05.pdf`
- AI 写 analysis.md 时引用 + 末尾 `## 📎 参考材料` section 追加一行

后续 stage 自动继承（input-flow.md 各 stage "按需读 attachments/" 规则保持不变）。

### §1.3 AI 触发识别（first-principle，无 hardcode）

PM 在 chat 同时含以下两个元素 → AI 自动识别为 "上传附件" 意图：

1. **一个或多个绝对路径**：macOS `/Users/...` 或 `~/...`（AI 用 Read tool 自带 `~` 展开校验）
2. **关联描述**：可识别 PM 在描述这是个材料 / 给 AI 看的（典型句式："我有份 X" / "看这个 [路径]" / "重点是" / "材料在 [路径]"）

判断由 LLM prose 做（不用关键词列表）。AI 不确信时（如 PM 给路径但不像在上传）→ chat 反问一句 "是否要把 [path] 归档进本 req 的参考材料？"。

> **诚实命名**：本设计称这套为 "trigger 0 LLM 接管识别"，与现仓 trigger 1（PM 主动提 reactive）/ trigger 2（AI 扫目录 silent）并列。三者共存（trigger 0 优先，1/2 保留作 fallback）。

### §1.4 AI 后台动作序列（按顺序）

PM 触发后 AI **一次性**完成下列动作，chat 只输出最终 1 行确认（不输出 cp 命令 / 绝对路径全文 / 工程内部状态）：

1. **校验源路径可读**：失败 → chat 报错 "路径不可读：`<path>`，重提？"（不静默吞）
2. **生成新文件名**：`<stage 前缀>-<源 basename>`（机械命名；PM 拍候选 a）
3. **冲突检测**：目标 `$ACTIVE_REQ_DIR/attachments/<新名>` 已存在 → 自动追加 `-2` / `-3` / ... 后缀（E4 决议）
4. **Bash cp**：`cp <src> $ACTIVE_REQ_DIR/attachments/<新名>`
5. **引用追加**：当前 stage 产出文档（brief.md / analysis.md / prd.md / task-NNN.md 等）末尾 `## 📎 参考材料` section 追加一行（section 不存在 → 创建）
6. **chat 一行确认**：`已归档（attachments/<新名>），<PM 给的重点>。继续。`

#### §1.4.1 stage 前缀映射

| stage | 当前 stage 产出 | attachments 命名前缀 |
|---|---|---|
| 1 | brief.md | `brief-` |
| 2（A 分支）| analysis.md | `analysis-` |
| 2（B 分支 office-hours，D-i v4）| stage2-office-hours.md | `analysis-`（与 A 分支统一，B 分支同款 `analysis-` 前缀） |
| 3 | prd.md | `prd-` |
| 4 | docs/DESIGN.md（项目级，不在 req attachments）| —— stage 4 通常不附 req 附件；如有则 `design-` |
| 5 | task-plan.md / implementation-design.md | `task-plan-` / `impl-` |
| 6 | task-NNN-<slug>.md | `task-NNN-`（按当前 task short_id） |
| 7 | close-report.md | `close-` |

stage 推断由 caller 在 SKILL prose 内取 `$ACTIVE_REQ_STAGE` + 当前 task short_id（如在 task-spec / task-execute 阶段）。

### §1.5 多附件 batch（E3 决议）

```
PM: 我有 3 份附件，~/Downloads/a.pdf b.png c.md，重点分别是 X / Y / Z。
AI: 已归档：
    - attachments/analysis-a.pdf — X
    - attachments/analysis-b.png — Y
    - attachments/analysis-c.md — Z
    继续。
```

AI 顺序 cp 多份，每份独立命名 / 引用 section 追加 3 行 / chat 一次确认（bullet 列表）。

### §1.6 替换 / 删除（E4 决议）

| 场景 | PM 句式 | AI 行为 |
|---|---|---|
| **替换同语义** | "把 X 换成 Y"（X 已归档过）| Bash `rm $ACTIVE_REQ_DIR/attachments/<X 新名>` → `cp <Y src> 同名` → 引用 section 行不动 |
| **删除** | "删 X" | Bash `rm` + 从 `## 📎 参考材料` section 删该行 |
| **同名冲突** | PM 上传同名文件 | 自动追加 `-2` / `-3` 后缀（不问 PM，chat 显示完整新名） |

### §1.7 trigger 2 静默扫描保留（E5 决议）

现 trigger 2（AI 写产出前扫 `attachments/` 发现新文件主动问 PM "要不要纳入本 stage"）**保留**作 fallback。Model 2 切换后预期 trigger 2 永远 silent（PM 不再手动 cp），但留着兜底零成本 —— PM 万一真自己拖文件进 IDE 的 attachments/ 目录，AI 扫到仍能识别。

### §1.8 后续 stage 继承（不变）

`_shared/pm-view/input-flow.md` 各 stage "按需读 attachments/" 规则**完全不变**。AI 在 stage N 写产出前扫本 req `attachments/`，引用过的按需 Read 即可。

### §1.9 PM 视角 vs IDE 可见性

attachments/ 目录在 git tracked → PM IDE 里**仍能看到**。本设计的目标不是 "藏起来"，是 "PM 心智操作里不去碰" —— PM 看到目录里有文件，但所有上传 / 改名 / 删除都通过 chat 让 AI 做。这跟"office-hours snapshot 进 req"（D-i v4）同款 mental model：物理上可见，操作上 AI 全管。

---

## §2 与现役机制的关系

| 现役 mechanism | v1 关系 | 改动 |
|---|---|---|
| `docs/归档/完成/attachments-机制.md`（v0 落地）| **加 trigger 0 LLM 接管识别**，trigger 1/2 保留作 fallback | 既有目录结构 / 命名约定 / 后续 stage 继承不变 |
| `_shared/pm-view/attachments-upload.md`（**新文件**）| 加 trigger 0 prose + 命名规则 + 多附件 / 替换 / 删除 / 冲突 / 失败兜底 / stage 前缀映射 | 0 → 新建一份单一真相源 |
| `skills/new-req/SKILL.md` | 步骤 4.4 attachments hook 升级：trigger 0 优先 + trigger 1/2 fallback | 段加 trigger 0 引用 + chat 文案 |
| `skills/req-analysis/SKILL.md` | 同上 | 同上 |
| `skills/prd-writing/SKILL.md` | 同上 | 同上 |
| `skills/task-spec/SKILL.md` | 同上 | 同上 |
| `skills/req-stage-gate/SKILL.md` | D-i v4 已在 Stage 1→2 Stage 2→3 等节点提到 attachments hook → v1 同款升级 | 段加 trigger 0 引用 |
| `_shared/pm-view/input-flow.md` | **不变**（后续 stage 继承规则保留）| 0 改动 |
| `templates/*.tmpl`（brief / analysis / prd / task）末尾 `## 📎 参考材料` 注释 | **不变** | 0 改动 |

---

## §3 实施清单

| vp | 任务 | 估时 |
|---|---|---|
| vp-1 | `skills/_shared/pm-view/attachments-upload.md` 新增 — trigger 0 LLM 识别 prose + 命名规则 + 多附件 batch / 替换 / 删除 / 冲突 / 失败兜底 / stage 前缀映射表 + PM 视图禁工程黑话清单 | 30 min |
| vp-2 | 各 stage SKILL 加 trigger 0 引用：`skills/{new-req, req-analysis, prd-writing, task-spec, req-stage-gate}/SKILL.md` 段升级（trigger 0 优先 + trigger 1/2 fallback prose） | 30 min |
| vp-3 | chat 文案模板（PM 视图）：上传成功 1 行 + 多附件 batch + 失败 / 路径不可读 + 替换 / 删除 + 冲突追加后缀。PM 视图禁工程黑话约束（不输出 cp 命令 / 绝对路径全文 / 内部状态机词） | 15 min |
| vp-4 | 测试：`tests/test-attachments-llm-upload.sh` 新增 — 手动 walkthrough fixture（mock PM 给路径 → AI 模拟 cp → 验证 `attachments/` 落盘 + 引用 section 追加 + 后续 stage 读到）。基线 412/0 → 预期 ≥ 416/0 | 30 min |
| vp-5 | 文档同步：`CHANGELOG.md` 未发布段 + `docs/INDEX.md` 加 v1 落地条目 + 设计文档归档 `git mv docs/设计/attachments-体验优化.md docs/归档/完成/attachments-AI-接管.md` + `docs/归档/完成/attachments-机制.md` 加一段 "v1 升级：trigger 0 LLM 接管已加" 指针 | 10 min |

**总估时**：~1.75h（vp-1 / vp-2 / vp-3 可并行）

**测试基线**：当前 412 / 0；落地后预期 ≥ 416 / 0（vp-4 加 ~4 个 case）

---

## §4 砍掉的机制清单（防 review 加回来）

| 机制 | 为什么砍 |
|---|---|
| PM 手动管 `attachments/` 目录 / 学路径约定 | §0.3 根因层；Model 1 → Model 2 切换核心 |
| PM 手动加 stage 文件名前缀 | AI 接管命名（§1.4.1） |
| Chat 上传 hardcode 触发词（"上传" / "@" / 类似）| PM 拍：AI first-principle 识别（§1.3） |
| 每次冲突都问 PM "是否覆盖" | E4 决议：自动 `-2` 后缀更顺 |
| 砍 trigger 2 旧扫描（彻底单路径走 chat）| E5 决议：保留作 fallback（PM mental model 切换是渐进的） |
| AI 反问 "是否上传" 在每次识别后 | trade：破 "一次回话搞定" 体感；不确信时再反问就够（§1.3） |
| `attachments/` 子目录结构（per-stage subfolder）| `attachments-机制.md` §九已砍；本设计不重新引入 |
| 跨 req attachments 共享 / OCR / git LFS | 同上 §九（attachments-机制.md v0 已显式不解决） |

---

## §5 风险与待验

### §5.1 待验项

1. **AI first-principle 识别准确性**：误识别（PM 不是想上传但路径出现）/ 漏识别（PM 暗示但路径没出现）的实际频率。消费仓真实 req 跑过后看（与 D-i v4 R3-H2 同款 "相信 LLM 全文喂消化" 决策模式）。
2. **multi-platform 路径**：Windows path `C:\...` 是否走通（fixture 仅测过 macOS POSIX）。低优先 — PM 是 macOS 用户。
3. **命名冲突 `-2` `-3` `-N` 上限**：长 req 多次上传同名 → 是否累积污染目录。无上限设；PM 自己看 `## 📎 参考材料` section 删多余引用即可。

### §5.2 风险

| R# | 风险 | 缓解 |
|---|---|---|
| R1 | AI 误识别 PM 意图（PM 说 "我之前在 ~/foo.pdf 上看到过类似设计" → AI 误 cp） | §1.3：AI 不确信时反问 "是否归档"，PM 答 OK 才 cp；PM 立即说 "不是" AI 即 rm（成本极低） |
| R2 | 源路径不可读（PM 已移走 / rename） | §1.4 步骤 1 校验失败 → chat 报错让 PM 重提，不静默吞 |
| R3 | 文件 >10MB | pre-commit hook 已 warn；AI chat 一句提示 "可能超大，是否仍纳入？"，PM 拍 |
| R4 | trigger 0 + trigger 2 同时触发（PM 同 stage 既 chat 上传又 IDE 拖文件）| trigger 0 优先；trigger 2 扫到 trigger 0 已处理过的文件 → 跳过（按 `## 📎 参考材料` 引用 section 判 "已引用"） |
| R5 | stage 前缀映射在 stage 4 模糊 | §1.4.1 已标 "stage 4 通常不附 req 附件；如有则 `design-`"，PM / AI 拍 |
| R6 | PM chat 一句话给多个绝对路径但混了不相关的（"我看过 ~/a.pdf 和 ~/b.pdf 但只想上传 a"）| §1.3 LLM 识别：AI prose 判断有歧义时反问 |
| R7 | 替换语义识别错（PM 说 "把 X 换成 Y"，AI 不知该 rm 哪个）| §1.6：靠 `## 📎 参考材料` section 已引用文件做 anchor，AI 反问 PM 确认 |

---

## §6 实证支撑

PM 表述（本会话 2026-05-25）：

> "目前就是不知道如何把附件上传，上传到什么位置，以及是否后续的阶段，能够读取到这些附件"

诊断推导：

- 现仓 attachments 机制（`docs/归档/完成/attachments-机制.md` commit 65329d0）完整 → mechanism 不是问题，**discoverability + PM 视角错配** 是
- PM 拍 mental model A（"AI 接管，PM 不感知 attachments/ 目录"），与 D-i v4 office-hours snapshot 同款决策（工程视角 vs PM 视角）
- E3 / E4 / E5 三个 edge case 全拍定（multi-附件 batch / 替换删除冲突 / trigger 2 保留作 fallback）

**Fact-check（现仓约束验证，避免 D-i v0→v4 错决 5 次的 pattern 重演）**：

- `docs/归档/完成/attachments-机制.md:36-44` §一目录结构 + 命名约定（`brief-` / `analysis-` / `solution-` / `task-NNN-`）
- 同上 §三 现 trigger 1/2 行为
- 同上 §九 8 条"不解决"清单（本 v1 全部沿用，不重新引入）
- `_shared/pm-view/input-flow.md` 各 stage "按需读 attachments/" 规则 → 后续 stage 继承不动

---

## §7 决策路径（v0 → v1）

### v0 — stub（§0 待 PM 共写）

PM 表述 "我会有很多附件" 太宽泛，§0 痛点未锁、方案主体未展开。

### v1 — Model 2 AI 接管（**当前**）

**触发**：
1. PM 拍方向 A（Model 2，AI 接管 PM 不感知目录）
2. E3 / E4 / E5 三个 edge case 全拍定（PM 决策记录在本会话）
3. fact-check 现仓 attachments 机制（`docs/归档/完成/attachments-机制.md` 158 行），确认机制完整、根因是 discoverability + PM 视角错配

**v1 核心**：
- 加 trigger 0 LLM 接管识别（PM chat "绝对路径 + 描述材料" → AI cp + 命名 + 引用）
- 命名候选 a 机械 `<stage 前缀>-<源 basename>`
- 替换 / 删除 / 冲突 / 多附件 batch / 失败兜底全 prose 化（不开机器约束）
- trigger 1/2 保留作 fallback
- 后续 stage 继承 / close-req / cancel-req 行为完全不变

**v1 估时**：~1.75h（vp-1 ~ vp-5）

---

## §X Review Findings

（待 plan-eng-review 跑 D-iii v1 时填）

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-24 | v0 stub 创建（D4 Round 2 B 分组）| 等 §0 共写 |
| 2026-05-25 | PM 拍 mental model A（Model 2 AI 接管，不感知 `attachments/` 目录）| 切方向，否决 Model 1 教学补丁 |
| 2026-05-25 | E3 / E4 / E5 三个 edge case 全拍定（多附件 batch 顺序 cp / 自动 `-2` 后缀 / trigger 2 保留作 fallback）| v1 设计完整 |
| 2026-05-25 | 命名机制 = 候选 a 机械 `<stage 前缀>-<源 basename>`（vs 候选 b 语义 slug / 候选 c PM 拍每次）| 减交互回合 |
| 2026-05-25 | §0 锁定 + v1 方案主体展开 | 待 plan-eng-review |

---

**End of D-iii：attachments AI 接管 v1**
