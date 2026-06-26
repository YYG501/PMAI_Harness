#!/usr/bin/env node
// check-doc-currency — PreToolUse(Bash) hook
//
// 触发：git commit 命令，且本次提交动了框架资产（scripts/ skills/ templates/
//       agents/），但 CHANGELOG.md 不在本次提交里。
// 行为：deny 拦下这一次 commit，把"先更新文档再提交"的提醒喂回模型。
//       逃生舱：commit message 含 [skip-doc-check] → 直接放行。
//
// 解决的问题：框架改动落地后，CHANGELOG「未发布」段 / RUNTIME「当前位置」/
//   docs/INDEX 生命周期常年漂移 —— 因为没有任何东西挂在 git commit 这个收尾点
//   上。这是触发器，不是硬墙：逃生舱在，确认不需要动文档一句话就过。
//
// 失败开放：任何异常 / 拿不到改动集 → 放行（hook bug 不该挡住 commit）。

const { execSync } = require('child_process');
const fs = require('fs');

// 会同步到业务仓、改动通常需要进 CHANGELOG 的目录
const FRAMEWORK_DIRS = ['scripts/', 'skills/', 'templates/', 'agents/'];

function git(args) {
  try {
    return execSync(`git ${args}`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
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
    if (cmd.includes('[skip-doc-check]')) process.exit(0);

    // 本次提交的改动文件集
    let changed = git('diff --cached --name-only').split('\n').filter(Boolean);
    if (/\s-[a-z]*a[a-z]*\b|\s--all\b/.test(cmd)) {
      // git commit -a / -am：补上已跟踪的未暂存改动
      changed = changed.concat(git('diff --name-only').split('\n').filter(Boolean));
    }
    if (changed.length === 0) process.exit(0); // 拿不到改动集 → 放行

    const touchedFramework = changed.some(f =>
      FRAMEWORK_DIRS.some(d => f.startsWith(d))
    );
    if (!touchedFramework) process.exit(0);
    if (changed.includes('CHANGELOG.md')) process.exit(0);

    const reason = `⚠️ 文档新鲜度检查（check-doc-currency hook）

本次 commit 动了框架资产（scripts/ skills/ templates/ agents/ 之一 —— 会同步到业务仓），但 CHANGELOG.md 不在本次提交里。

提交前确认：
1. CHANGELOG.md「未发布」段加了对应条目吗？（业务仓靠它决定是否跑同步）
2. RUNTIME.md「当前位置 / 下一步」需要更新吗？

→ 补完文档，重新 git add + commit。
→ 若确认本次确实不影响业务仓、不需动文档（纯生成器内部改动 / 注释 / 测试微调），commit message 加 [skip-doc-check] 重新提交即可跳过。

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
