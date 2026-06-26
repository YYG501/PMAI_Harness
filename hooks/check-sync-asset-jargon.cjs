#!/usr/bin/env node
// check-sync-asset-jargon — PreToolUse(Bash) hook
//
// 触发：git commit，且本次新增（"+" 开头的 diff 行）落在同步资产里
//       （scripts/ skills/ templates/ agents/），并引入了下列任一 pattern：
//
//   - 生成器内部设计任务编号：D13 / D-iii vN / D-i vN / D-iv MN / DN-N 等
//   - 管线小批次编号：delta-N / vp-N / polish-N / RN-CN/HN/MN
//   - 归档路径死链：docs/归档/完成/
//   - 「commit <短 hash> 同类 bug」短引用
//
// 行为：deny 拦下 commit，告诉模型「同步资产里禁出现生成器内部编号」+ 列具体行。
//       逃生舱：commit message 含 [skip-jargon-check] → 放行。
//
// 为什么挡：消费仓 PM 看到这些编号完全不懂；归档路径在消费仓不存在变死链。
//   INVARIANTS I-* 编号是 anchor（消费仓也分发 INVARIANTS.md），不在范围内。
//
// 失败开放：异常 / 拿不到 diff → 放行（hook bug 不该挡住 commit）。

const { execSync } = require('child_process');

const SYNC_DIRS = ['scripts/', 'skills/', 'templates/', 'agents/'];

// 同步资产里禁出现的 pattern；每条 { re, name }
// 注意：只扫新增的「+」行（PR diff 视角），避免老内容被反复拦
const FORBIDDEN = [
  { re: /\bD13\b/, name: 'D13（生成器内部设计任务编号）' },
  { re: /\bD-(?:i+|v)\s*v\d+\b/, name: 'D-iii vN / D-i vN 类设计任务编号' },
  { re: /\bD-iv\s+M\d+\b/, name: 'D-iv MN 子分块编号' },
  { re: /\bD\d+-\d+\b/, name: 'DN-N 类决议编号（如 D9-4）' },
  { re: /\bdelta-\d+\b/, name: 'delta-N 管线小批次编号' },
  { re: /\bvp-\d+\w?\b/, name: 'vp-N 验证 plan 编号' },
  { re: /\bpolish-\d+\b/, name: 'polish-N 小修补编号' },
  { re: /\bR\d+-[CHM]\d+\b/, name: 'RN-CN/HN/MN review 决议编号' },
  { re: /docs\/归档\/完成\//, name: 'docs/归档/完成/ 路径（消费仓不存在 = 死链）' },
  { re: /commit\s+[0-9a-f]{7,8}\s*同类\s*bug/, name: '「commit <短 hash> 同类 bug」短引用（消费仓 git log 不同）' },
];

function git(args) {
  try {
    return execSync(`git ${args}`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return '';
  }
}

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', c => (input += c));
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    if (data.tool_name !== 'Bash') process.exit(0);
    const cmd = (data.tool_input && data.tool_input.command) || '';

    // 只管 git commit
    if (!/\bgit\b(?:\s+-\S+|\s+-C\s+\S+)*\s+commit\b/.test(cmd)) process.exit(0);
    // 逃生舱
    if (cmd.includes('[skip-jargon-check]')) process.exit(0);

    // 拿 staged + worktree（git commit -a 场景）的 unified diff
    let diff = git('diff --cached -U0');
    if (/\s-[a-z]*a[a-z]*\b|\s--all\b/.test(cmd)) {
      diff += '\n' + git('diff -U0');
    }
    if (!diff) process.exit(0);

    // 解析 diff：按 +++ b/<path> 切块；扫块内 + 行
    const hits = []; // { file, line: "+...", pattern: <name> }
    const blocks = diff.split(/^diff --git /m).slice(1);
    for (const block of blocks) {
      const headerMatch = block.match(/^\+\+\+\s+b\/(.+)$/m);
      if (!headerMatch) continue;
      const file = headerMatch[1];
      if (!SYNC_DIRS.some(d => file.startsWith(d))) continue;
      // 跳过测试 / fixture
      if (/(?:^|\/)tests?\//.test(file)) continue;
      if (/__fixtures__|\/fixtures\//.test(file)) continue;

      const lines = block.split('\n');
      for (const ln of lines) {
        if (!ln.startsWith('+') || ln.startsWith('+++')) continue;
        const content = ln.slice(1);
        for (const f of FORBIDDEN) {
          if (f.re.test(content)) {
            hits.push({ file, line: content.trim().slice(0, 200), pattern: f.name });
            break; // 一行一个 hit 即可
          }
        }
      }
    }

    if (hits.length === 0) process.exit(0);

    // 整理 hits 输出
    const sample = hits.slice(0, 10).map(h =>
      `  ${h.file}: ${h.pattern}\n    + ${h.line}`
    ).join('\n');
    const more = hits.length > 10 ? `\n  ...（还有 ${hits.length - 10} 条命中）` : '';

    const reason = `⚠️ 同步资产编号检查（check-sync-asset-jargon hook）

本次 commit 在同步资产（scripts/ skills/ templates/ agents/）里引入了生成器内部编号 / 归档路径死链 / commit hash 短引用 —— 这些到消费仓后 PM 看不懂、路径不存在、git log 对不上。

命中（前 10 条）：
${sample}${more}

修法：
  - 设计任务编号 / vp-N / delta-N / polish-N → 改成语义说明或砍掉（保留 WHY 信息但不留内部 ID）
  - docs/归档/完成/ → 改成"设计文档（生成器仓归档）"或彻底删
  - commit <短 hash> 同类 bug → 改成"同类 bug 防回归"

保留：INVARIANTS I-AD1 / I-CT7 等稳定 anchor（消费仓也分发 INVARIANTS.md）+ 同 SKILL 内部 §章节引用。

→ 修完重新 git add + commit。
→ 若确认这次确实是内部测试 / 设计草稿 / 不进消费仓的实验，commit message 加 [skip-jargon-check] 跳过。

(hook 来源: 项目级 .claude/settings.json / .codex/hooks.json；禁用方式: 删除对应 PreToolUse 条目)`;

    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason: reason,
        },
      })
    );
  } catch {
    process.exit(0); // 失败开放
  }
});
