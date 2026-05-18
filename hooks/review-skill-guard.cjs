#!/usr/bin/env node
// review-skill-guard — UserPromptSubmit hook
//
// 检测用户消息触发 review/audit 类 skill 时，注入"FORCE stance + 反偷工反模式 + 禁 A/B/C 程度门"
// 到 prompt 的 additionalContext 里。
//
// 解决的问题：AI 跑 /plan-ceo-review 等 review skill 时倾向偷工
//（"我只跑了 5/11 sections，要不要补到 A 简化 / B 中等 / C 完整？"），
// 把"是否偷工"的决策推给 PM。
//
// 不修改 gstack skill 文件本身（升级会被覆盖），通过 hook 注入约束达成同等效果。
//
// 触发：用户消息行首匹配 /plan-ceo-review /plan-eng-review /plan-design-review
//       /plan-devex-review /review /qa /qa-only /design-review /devex-review /autoplan
// 行为：注入 additionalContext（advisory，不 block）

const REVIEW_SKILLS_PATTERN = /^\/(?:plan-ceo-review|plan-eng-review|plan-design-review|plan-devex-review|review|qa|qa-only|design-review|devex-review|autoplan)(?:\s|$)/m;

const GUARD_TEXT = `⚠️ REVIEW SKILL 执行强制约束（review-skill-guard hook 注入）

你即将执行 review/audit 类 skill。跑这个 skill 时必须遵守以下硬约束：

## FORCE stance：完整跑，不偷工

1. **按官方 skill 的全部 required sections 跑**（如 11/11 sections，不是 5/11）
2. **禁止给 PM 出"A 简化 / B 中等 / C 完整"程度门** —— 这是把"是否偷工"的决策推给 PM 的反模式
3. **跳过项必须给具体"不适用"原因**：
   - ✅ 具体："消费仓没 telemetry 基础设施"、"项目无 i18n 需求"
   - ❌ 不具体："PM 偏好简单"、"节奏紧张"、"skill 太重"、"务实"
4. **输出末尾必须标完整度**：
   - 例 \`## REVIEW COMPLETE: 11/11 sections\`
   - 例 \`## REVIEW PARTIAL: 8/11 (跳过项 + 具体不适用原因列表)\`

## Common failure modes（自检清单，命中即返工）

- ❌ 把 BLOCKER finding 降级到 WARNING 避免显得苛刻 → 必须保留原 severity
- ❌ "凭精神执行"而非真发起 Skill 工具调用 / 真读文件 / 真跑 grep
- ❌ 自创"实用主义版"/"精简版"/"务实版"包装绕过 required sections
- ❌ 拿 PM 之前说过"简单点"当跳步通用许可证
- ❌ 主动给 PM 出 A/B/C 程度选项让 PM 决定补全到哪一档

## 如果真有 section 不适用

不要出选项门，**默认跑完整版**。判断某 section 真的不适用 → 跑完后在完整度标记的"跳过原因"里写具体不适用原因，PM 觉得多余事后会让你砍。

---
(hook 来源: ~/.claude/hooks/review-skill-guard.cjs；禁用方式: 删除 settings.json 对应条目)`;

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const prompt = data.prompt || '';

    if (!REVIEW_SKILLS_PATTERN.test(prompt)) {
      process.exit(0);
    }

    const output = {
      hookSpecificOutput: {
        hookEventName: 'UserPromptSubmit',
        additionalContext: GUARD_TEXT,
      },
    };

    process.stdout.write(JSON.stringify(output));
  } catch {
    process.exit(0);
  }
});
