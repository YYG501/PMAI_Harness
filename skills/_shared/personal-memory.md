# Personal memory（PMAI 内部）

个人经验是用户级、跨项目、只作建议的运行状态。它帮助 PMAI 记住 PM 在真实协作中反复纠正过的判断方式，但不能成为项目事实、产品决定或 Skill 规则。

## 两层记忆与权威边界

- **项目记忆**继续留在消费仓真相源：模块 `decisions.md` / `spec.md`、`PRODUCT-RULES.md`、`DESIGN.md`、`docs/decisions/`、`PRODUCT-STATE.md`。
- **个人经验**保存在 `${PMAI_STATE_HOME:-$HOME/.pmai-state}/personal-memory.sqlite3`，跨消费仓召回。
- **框架进化**不属于记忆。个人经验不得自动修改 `SKILL.md`；只有 PM 明确发起 `/pmai-skill-improve` 后，才能把多次证据带到框架仓做提案、回归和版本化发布。

权威顺序：当前 PM 明确指令与决定、当前项目真相源、PMAI Skill 与安全规则，都高于个人经验。个人经验与任一上层依据冲突时直接忽略。

## 召回

先重新编译并实际消费 context pack，再单独召回个人经验：

```bash
python3 "$PMAI_HOME/scripts/personal-memory.py" recall \
  --context-pack "$CONTEXT_PACK" \
  --query "<本轮目标与当前用户反馈>" \
  --limit 3 \
  --format markdown
```

召回失败、数据库不存在或没有相关经验时静默继续，不能阻塞 design。返回内容只进入 AI 后台检查，不直接展示给 PM，也不进入 context pack 的 `sources`、`input_hashes`、`decisions`、`source_hash` 或 `approved_source_hash`。

AI 使用召回结果前再过滤一次：

1. 与当前项目决定冲突的，丢弃。
2. 当前 Skill 已经明确要求的，不重复注入。
3. 适用条件不成立的，丢弃并在自然收口点记录 `not_applicable`。
4. 最多保留 3 条；把它们转成后台检查，不机械变成 PM 确认题。

## 自动记录

只在高信号纠偏已经闭合时记录：

- PM 明确说“不合理 / 看不懂 / 为什么又问 / 有点乱”，并给出或接受了修正方向；
- PM 指出 AI 忽略了已有事实、旧决定或真实用户路径；
- PM 明确说“以后遇到这种情况都应该……”；
- design 审计发现可重复、可归因的交互或判断问题。

普通产品选择、项目业务事实、临时实现偏好和未闭合争论不进入个人经验。

记录前先归位：

| 判断 | 去向 |
|---|---|
| 只对当前模块成立 | 模块 `decisions.md` / `spec.md` |
| 对当前项目长期成立 | `PRODUCT-RULES.md` / `DESIGN.md` / `docs/decisions/` |
| 跨项目仍成立，且当前 Skill 未明确覆盖 | `disposition=personal`，创建或更新个人经验 |
| 当前 Skill 已经明确覆盖，但本次没有执行 | `disposition=execution_gap`，只留精简证据，不新增重复经验 |

个人经验必须去掉项目名、页面名、客户名和偶然实现词，保留“什么结构条件下适用、过去为什么错、下次检查什么、什么情况不适用”。

使用 stdin 传结构化 JSON，避免把 PM 原话拼进 shell：

```json
{
  "skill": "design",
  "signal": "explicit_correction",
  "disposition": "personal",
  "context_summary": "<去项目名后的结构化上下文>",
  "failed_behavior": "<这次可重复的错误判断>",
  "user_feedback": "<精简后的 PM 纠偏>",
  "corrected_behavior": "<已经闭合的修正方式>",
  "outcome": "<修正后的实际结果>",
  "evidence_ref": "session:<id>",
  "applies_when": "<什么结构条件下适用>",
  "lesson": "<下次应先检查或采用什么判断>",
  "reason": "<过去为什么会错>",
  "boundaries": "<什么情况下不适用>",
  "cues": "<用于召回的少量结构词>"
}
```

```bash
python3 "$PMAI_HOME/scripts/personal-memory.py" capture --stdin
```

`explicit_correction` 首次以低权重参与召回；重复证据自动合并并提高权重。`explicit_generalization` 表示 PM 明确要求以后都这样，立即以高权重生效。新纠正推翻旧经验时传 `supersedes`，旧经验退出召回但保留证据关系。

## 使用结果

召回不等于正确。只在有实际结果时更新：

```bash
python3 "$PMAI_HOME/scripts/personal-memory.py" feedback <memory-id> \
  --result helpful|audit_pass|not_applicable|corrected
```

PM 没有反馈不等于经验已经验证成功；不得仅因“被召回且没有被反驳”就提高权重。

## 用户控制与隐私

用户可用 `pmai memory status/search/show/forget/export` 检查或删除个人经验，但这些命令不进入正常 PM 主流程。

- 不复制完整会话或附件正文，只保留精简证据与来源指针。
- helper 会压缩空白、隐藏用户主目录并遮蔽常见密钥字段。
- 个人经验库不进入 Git，也不写入可升级的 `PMAI_HOME`。
- 存储或召回失败时 fail-open；不得让用户级经验破坏项目正常设计。
