# build / close 硬门反馈消化记录（2026-07-01）

<!-- 状态：已消化（待提交 commit hash）；保留作历史档案 -->

## 反馈来源

PM 复盘真实消费仓会话后确认：

- AI 没有规范进入 `/pmai-build`。
- 最后没有走 `/pmai-build-close` 收尾。
- 讨论、文档、mockup、主原型改动混在同一条主会话里推进和提交。
- PM 说“落地”后，AI 自行解释成“小改”，直接改了 `prototype/`，随后又补 `docs/modules/` 并把 `mockups/` 一起提交。

## 消化结果对账表

| # | 反馈类目 | 落地状态 | 落地位置 | 说明 |
|---|---|---|---|---|
| 1 | “落地”不能自动等于改主原型 | 已落地 | `skills/design/SKILL.md`、`skills/design/references/design-method.md`、`templates/AGENTS.md.tmpl` | 增加“落地意图识别”和 prototype 分流门 |
| 2 | 小改边界太松 | 已落地 | `skills/design/SKILL.md`、`skills/build/SKILL.md` | 小改必须 prototype-only，不得同时改 docs/mockups |
| 3 | 混合交付绕过 build/close | 已落地 | `skills/build/SKILL.md`、`skills/build-close/SKILL.md` | 混合交付必须 build → close，close 是唯一收口 |
| 4 | 普通提交缺机器守卫 | 已落地 | `scripts/check-mixed-delivery.py`、`templates/git-hooks/pre-commit.tmpl` | staged 中主原型 + docs/modules/mockups 同时出现时阻断 |
| 5 | 正式 close 需要放行口 | 已落地 | `scripts/close-work.sh`、`skills/build-close/SKILL.md` | close 内部使用 `PMAI_ALLOW_MIXED_DELIVERY=build-close` |
