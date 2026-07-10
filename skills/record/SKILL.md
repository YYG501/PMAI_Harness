---
name: pmai-record
description: |
  轻量记录：将 PM 在主线上完成、或设计讨论后暂不进入 build 的稳定结论，按四类归位至项目底座（现状、决策记录、待办、设计草图），单独提交。支持 PM 主动触发，亦承接 AI 在工作收敛时的记录提议。
---

# /pmai-record

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要沉淀记录或更新项目文档。

> **这是什么**：分档运行里**最轻那一档**（main 直接改 / 聊定直落、设计讨论后暂不 build）的记录入口。让轻档产出也有一个地方归位，不再"飘着没进库 / 真相源乱 / 决策不进库 / mock 找不回"。
> **和自动 finalize 的关系**：同一套四类分流（@读 `_shared/record-routing.md`），但完整 build 在落地主线后自动编译文档，本 skill 是 main 上或 design 后暂不 build 时的轻量同构（重量随产出缩放）。
> **和 quick-fix 的关系**：quick-fix 管"在 main 上改一处"，本 skill 管"把改完的成果沉淀进底座"——两件事，可前后脚发生。

## When To Use

- PM 在 main 上聊定一个方向 / 顺手改了点东西（小到不值得起完整设计-build 流程），想把"产品现在变成什么样 / 为什么这么定 / 还差什么 / 探了哪些视觉"收一下。
- PM 显式说「沉淀一下」「记一下」「归位」。
- AI 在回 PM 的某一轮里识别到收敛点（聊定 / 改完）且真有耐久产出时，**主动提议**记录；PM 点头后走本流程。
- **不适用**：要完整设计 / 建造 → `/pmai-design` / `/pmai-build`；只是在 main 改一处文件 → `/pmai-quick-fix`；已经在完整工作里推进 → 回原 `/pmai-build` 或用 `/pmai-status` 恢复。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: record"
```

本 skill 从**主仓 main** 触发（cwd 在主仓根、分支 = main）。若当前在隔离工作区内 → 告诉 PM「这轮仍在完整 build 里，回原 build 会话继续；迷路时发 /pmai-status」，退出。

## Workflow

### 步骤 1：识别沉淀什么（两道闸）

从最近这段工作 / 讨论里，按四类盘一下有没有耐久产出。**两道闸都要过才提**：

- **闸①·收敛点**：只在「聊定了 / 改完了」这种收敛时刻沉淀，不逐条沉淀（PM 还在来回讨论时不打断）。
- **闸②·有耐久产出**：只在真有新事实 / 新决策理路 / 新变体时沉淀；纯文字微调、还没定的方向、临时想法 → **不沉淀**。

两道闸有一道不过 → 不动，告诉 PM 一句「这次没有需要归位的耐久产出，继续就好」，退出（不空跑、不编）。

> 判断准度做不到 100%（人在环，不追全自动）。AI 拿不准"算不算耐久产出"时，宁可问 PM 一句，不擅自沉淀也不擅自跳。

### 步骤 2：按四类分流（@读共享参考）

**@读 `skills/_shared/record-routing.md`**，按四类把本次产出分流，**重量随产出缩放**——多数轻档只动 ①：

| 类 | 这次有没有 | 落点 |
|---|---|---|
| ① 耐久事实（现状 / 规则 / 稳定结构）| 多数轻档有 | `PRODUCT-STATE.md`（+ 按需 `PRODUCT-RULES.md` / `docs/modules/`）|
| ② 理路（为什么这么拼）| 真有跨文件整体意图才有 | `docs/decisions/<日期>-<slug>.md`（@读 `_shared/decision-record.md` 判门槛 + 写法）|
| ③ 遗留（想做没做的）| 有就记 | `TODO.md` 加一条**自包含**（建议目标 + 涉及文件）|
| ④ 探索变体（mock）| 这次探过视觉草图才有 | `mockups/manifest.json` 加一条 → 重生成看版 |

**顺手补索引**：本次新建了 `docs/decisions/<…>.md` / 新 mock 等 → 确认 `docs/INDEX.md` 或对应索引里能找到它；`PRODUCT-STATE.md` 只写当前产品现状，不再兼职总索引。

### 步骤 3：落盘（main 文档白名单内）

轻记录直接写 main 上的底座文件。当前 `check-branch.sh` 允许 main 直接写 `docs/**` 与 `mockups/**`，业务代码仍必须走 build worktree；本 skill 不需要 marker 门控。

用 **Edit / Write** 写各落点：

- ① `PRODUCT-STATE.md`：patch 真正变了的行（当前功能 / 主原型现状 / mock→真）。**PRODUCT-STATE 是唯一现状写入点**——轻记录是它的轻量同构原子写，不是"随手改活文档"。
- ② 真有理路 → 按 `$PMAI_HOME/templates/decision-record.md.tmpl` 写 `docs/decisions/<日期>-<slug>.md`。
- ③ 有遗留 → 往 `TODO.md` 加一行（带一句话自包含）。
- ④ 探了变体 → 往 `mockups/manifest.json` 的 `variants` 加一条，然后重生成看版：
  ```bash
  python3 "$PMAI_HOME/scripts/gen-mock-board.py" "$REPO_ROOT"
  ```

### 步骤 4：切两挡 commit（F3：纯静默档 vs 需审档）

按这次实际动了什么，分两挡：

**(a) 纯静默档**——只 ①（PRODUCT-STATE 补一句 / docs/INDEX.md 补指针 / 纯文字订正），无理路、无新变体、无规则变化：AI **静默写 + 单独 commit**，回执一行，**不强制总审**（套确认门只给路径的惯例）。

**(b) 需审档**——碰了 ② 决策记录 / ④ 新变体 / 改了 `PRODUCT-RULES` / `docs/modules`：写完**呈 PM 总审 diff**（`git -C "$REPO_ROOT" diff` 给 PM 看动了哪些），PM `通过 / 改`。打回 → 按反馈改后重审。

通过（或静默档直接）后 commit —— **只 add 沉淀动过的文档，不卷入 PM 其它 WIP**：

```bash
# 只 add 本次记录实际动的文件（逐个列，不用 git add -A）
git -C "$REPO_ROOT" add PRODUCT-STATE.md   # + 本次实际动的其它落点
git -C "$REPO_ROOT" commit -m "记录: <一句话本次归位了什么>"

```

### 步骤 5：回执

给 PM 一行回执（**PM 视图语言，不出内部词**，见 record-routing §PM 话术纪律）：

```
✅ 已归位（<short-hash>）：现状补了 <一句>{；遗留进待办；探的几版视觉留看版了}。
```

需审档若 PM 打回则不 commit、按反馈改。

## Rules

- 从主仓 main 触发（cwd 主仓根、分支 main）；在 build worktree 内 → 引导走对应收尾流程，不在此处理。
- **两道闸**：只在收敛点 + 只在有耐久产出时记录；一道不过 → 不动 + 告诉 PM 一句，不空跑不编造。
- 四类分流 @读 `_shared/record-routing.md`（单一真相源）；理路冻结 @读 `_shared/decision-record.md`；**重量随产出缩放**，多数轻档只动 PRODUCT-STATE。
- **写入边界**：只写 `docs/**`、`mockups/**` 等记录落点；不借 record 修改业务代码。
- **单独 commit、不卷 WIP**：`git add` 逐个列本次记录动的文件，禁 `git add -A`；commit message 一律 `记录: <一句话>`。
- **F3 切两挡**：纯静默档（补一句 / 挂索引 / 纯订正）静默写 + 回执一行不强制总审；需审档（决策记录 / 新变体 / 改规则·模块）才总审 diff。
- **PM 话术纪律**（F-G4）：回执 / 提议只用 PM 视图语言，不出现"四类分流 / 出口①②③④ / manifest / featured / 冻结档 / 索引展开层"等内部词。
- **防腐铁律不破**：轻记录是 PRODUCT-STATE 的合法原子写入口之一（与 landed 后自动文档编译并列），不是退回"随手改活文档"；写入仍是收敛点触发的原子动作。
