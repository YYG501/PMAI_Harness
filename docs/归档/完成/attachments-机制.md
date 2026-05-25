# req attachments 机制 v0（已被 D-iii v2 helper 化升级承接）

> **状态**：v0 已落地（commit `65329d0` 2026-05-18 归档）→ **2026-05-25 D-iii v2 helper-based 升级**
> **现役**：`docs/归档/完成/attachments-AI-接管.md`（D-iii v2，2026-05-25 落地，测试基线 425/0）
> **v2 改动**：trigger 0 LLM 接管识别 + `_lib/attachments.py` helper（denylist + hard cap + Python `shutil.copy2`）+ `.req-meta.json:attachments_seen` 字段（真相源）+ `## 📎 参考材料` 仅作 PM 可见展示
> **v0 内容保留作历史基线**：目录结构 / 命名约定 / trigger 1/2 / 后续 stage 继承 / 多格式支持 / close-req 处理 / cancel-req 处理 / §九 不解决清单 全部沿用 v2
> **日期**：2026-05-18（v0）/ 2026-05-25 加升级指针
> **作者**：PM + AI

---

## 目的

支持 PM 在 req 任意 stage（brief / analysis / solution / task spec）上传额外材料（PDF / 截图 / 旧 PRD / SDK 文档等），让 AI 在写产出时主动读 + 在产出里明文引用。

---

## 一、目录结构

每个 req 自己的 `attachments/` 子目录，所有 stage 共用：

```
requirements/active/req-NNN-<slug>/
  brief.md
  analysis.md
  solution.md
  attachments/                      ← 本 req 专属
    brief-user-interview.pdf
    brief-competitor-screenshot.png
    solution-architecture.png
    solution-sdk-doc.pdf
    task-003-payment-api-spec.pdf
```

**约定**：
- 文件名加 **stage 前缀**（`brief-` / `analysis-` / `solution-` / `task-NNN-`）便于区分来源
- 不强制子目录结构（PM 自由组织）
- 超大文件（视频 / >50MB PDF）可**外部引用**，PM 自负失联风险

**归档**：req close 时随分支 merge 进 main → `requirements/closed/req-NNN-<slug>/attachments/`

**req 隔离**：req 之间天然隔离（各 worktree + 各分支），attachments/ 不跨 req 共享

---

## 二、各 stage 文档引用规范

每个 stage 产出文档（brief / analysis / solution / task spec）末尾加 `## 📎 参考材料` section（可选）：

```markdown
## 📎 参考材料

- `attachments/brief-user-interview.pdf` — 用户访谈记录（30 页，重点 §3 痛点列表）
- `attachments/brief-competitor-screenshot.png` — 竞品当前登录流程
```

**填法**：
- 只列**本 stage 引用过的**材料；上游 stage 已引用的**不重复列**
- 每条写：相对路径 — 简短说明（关键章节 / 重点）
- 无引用 → 整个 section 删掉，不留空

---

## 三、AI 触发逻辑（被动，不烦扰）

**不在每个 skill 入口都问 "有材料吗"**——避免烦扰。两个被动触发点：

### 触发 1：PM 主动提
PM 在对话中说"我有份材料" / "我上传了 XX" → AI 回：

> "放 `requirements/active/req-NNN-<slug>/attachments/`（文件名建议加 stage 前缀），告诉我文件名 + 重点是啥，我读完继续。"

### 触发 2：AI 写产出时主动扫
AI 在写 brief / analysis / solution / task spec 草稿前，扫一遍本 req 的 `attachments/`：
- 发现**本 stage 还没引用过的新文件** → 问 PM："发现 `attachments/<file>`，要不要纳入本 stage 参考？说明它的重点。"
- 已被本 stage 或上游 stage 引用过 → 跳过

---

## 四、多格式读取支持

| 格式 | 支持 |
|---|---|
| PDF / 图片（PNG/JPG 等）/ Markdown / 文本 | ✅ Read 工具直接读 |
| 大 PDF（>10 页）| ✅ Read 工具 `pages` 参数分页读 |
| 音频 / 视频 | ❌ 无原生支持 → PM 需先转写成文本贴进 attachments/（如 `solution-meeting-transcript.md`）|
| 外部链接（URL）| WebFetch 工具读 |

---

## 五、后续 stage 继承

`_shared/pm-view/input-flow.md` 各 stage 加一条规则：

> **如本 req `attachments/` 目录有上游 stage 引用过的材料，按需 Read**

适用 stage：analysis / solution / task spec / prd-writing。

---

## 六、close-req 处理

attachments/ 是 worktree 内文件 → 随 req 分支自然 merge 进 main → 归档到 `requirements/closed/`。**无需特殊处理**。

**额外动作**：close-req §1.5 rewrite mode 处理 modulespec / DESIGN / CONTEXT 时，可参考 attachments/ 里的视觉 / 业务材料（已在 input-flow 各 stage 必读列表里覆盖）。

---

## 七、cancel-req 处理

attachments/ 随分支不 merge → 自然丢弃（同 v4 设计 §2.2.1 边界处理一致：cancel 时 worktree 内改动 = 丢弃）。

如果 PM 想保留某材料给下一 req：
- 重启的新 req 时手动复制
- 或外部引用

不在 cancel-req 流程里特意挽救（避免增加 cancel 流程复杂度）。

---

## 八、实施清单

| # | 触及 | 估时 |
|---|---|---|
| 1 | `skills/new-req/SKILL.md` 步骤 4 加 attachments 提示话术（触发 1）+ AI 扫 attachments/ 钩子（触发 2）| 0.5h |
| 2 | `skills/req-analysis/SKILL.md` / `skills/req-solution/SKILL.md` / `skills/task-spec/SKILL.md` 各加 attachments 引用规范 + AI 扫钩子 | 1h |
| 3 | `skills/_shared/pm-view/input-flow.md` 各 stage 加 "按需读 attachments/" 规则 | 0.5h |
| 4 | `templates/` brief / solution / task 模板末尾示范 `## 📎 参考材料` section（可选注释）| 0.5h |
| 5 | 测试（手动跑一遍：放材料 → 触发提示 → 引用写入 → 后续 stage 继承读）| 0.5h |

**总估时**：2.5-3h

---

## 九、不解决的（防 review 回写）

| # | 衍生 / 假设场景 | 为什么不解决 |
|---|---|---|
| 1 | attachments 内文件版本管理 | PM 替换文件 → git 自然 diff 即可 |
| 2 | attachments 大小限制 / git LFS 接入 | 小项目暂不需要；超大文件 PM 自外部引用 |
| 3 | 跨 req 共享材料（如某份访谈给多 req 用）| PM 自己复制到各 req 的 attachments/（接受重复），或外部引用 |
| 4 | AI 跨 req 主动检索历史 attachments | 用 `grep -r` 即可，不进框架 |
| 5 | attachments 内文件的语义索引 / 自动摘要 | PM 在引用 section 里写"重点是啥"已足够 AI 定位 |
| 6 | attachments 子目录结构规范 | PM 自由组织；文件名前缀 + 引用 section 足够定位 |
| 7 | cancel-req 时挽救 attachments | 同 v4 §2.2.1 边界处理：worktree 改动自然丢弃 |

---

## 十、和 v4 PRD 体系收敛设计的关系

本机制**独立于** PRD 体系收敛 v4，但有几处交叉：

- `attachments/` 作为 v4 各 stage input-flow 必读补充（"按需读"规则）—— 第五节
- close-req §1.5 rewrite 时 attachments 作为参考输入（v4 §2.3 INDEX / §2.6 引导话术）—— 第六节
- worktree 边界处理逻辑共享（v4 §2.2.1 的 worktree commit / merge / cancel 逻辑直接复用）—— 第七节

不进 v4 设计文档；本机制单独实施单独测试。

---

**End of req attachments 机制 v0**
