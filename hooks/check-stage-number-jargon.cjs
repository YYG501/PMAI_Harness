#!/usr/bin/env node
// check-stage-number-jargon — PreToolUse(Bash) hook
//
// 触发：git commit，且本次新增（"+" 开头的 diff 行）落在 skills/**/*.md prose 里，
//       并引入了裸 stage 号：`stage <N>` / `Stage <N>`。
//
// 为什么挡：stage 号是内部状态标记（stages.py 自述「不再 PM-facing」），却历史地漏进
//   ① runtime AI 读来做推进决策的 SKILL prose、② 打给 PM 看的 banner。runtime AI 把
//   概念步号 / 旧 7-stage 实现号当成单工作 stage 号去推进状态机 → 推过头一格。
//   prose 里引用阶段一律用名字（范围确认 / build / 复审 / 沉淀），裸 stage 号只准出现在
//   .py / .sh 代码和 .work-meta.json 字段里。本 hook 让这条纪律回不去。
//
// allowlist（放行）：
//   - 代码块内（```…``` fence；按 working-tree 全文定位行号判断是否落在 fence 区间）
//   - 代码标识符：MAX_STAGE / STAGE_\w+ / stage_\w+ / {stage} / {MAX_STAGE} 等
//     （从行里剔除这些 token 后再检测裸 stage 号）
//   - .work-meta.json 字段名引用（"stage" 字段；不是 `stage <数字>` 形态，本就不命中）
//
// 行为：deny 拦下 commit，列具体行 + 改法（裸 stage 号 → 阶段名）。
//       逃生舱：commit message 含 [skip-stage-check] → 放行。
//
// 失败开放：异常 / 拿不到 diff → 放行（hook bug 不该挡住 commit）。

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// 只管 skills/ 下的 .md（runtime AI 读 SKILL prose 的地方）
function inScope(file) {
  return file.startsWith('skills/') && file.endsWith('.md');
}

// 裸 stage 号：stage / Stage 后跟可选空白再跟数字
const BARE_STAGE = /\bstage\s*\d/i;

// 代码标识符 token：从行里剔除后再判裸号，避免误伤代码 f-string / 变量名
const CODE_IDENT = [
  /\bMAX_STAGE\b/g,
  /\bSTAGE_[A-Z_]+\b/g,      // STAGE_NAMES / STAGE_OUTPUT_FILES …
  /\bstage_[a-z_]+\b/gi,     // stage_num / stage_name …
  /\{[^}]*stage[^}]*\}/gi,   // {stage} / {MAX_STAGE} / Stage {stage}/{MAX_STAGE} 占位
];

function stripCodeIdents(s) {
  let out = s;
  for (const re of CODE_IDENT) out = out.replace(re, ' ');
  return out;
}

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

// 读 working-tree 全文，算出每行是否落在 ```…``` fence 内 → 返回 Set<行内容>（在 fence 内的去重内容）
// 用行内容匹配（diff -U0 不给行号），命中行内容若属于 fence 内集合则放行。
const fenceCache = new Map();
function fenceLineSet(repoRoot, file) {
  if (fenceCache.has(file)) return fenceCache.get(file);
  const set = new Set();
  try {
    const full = fs.readFileSync(path.join(repoRoot, file), 'utf8');
    const lines = full.split('\n');
    let inFence = false;
    for (const ln of lines) {
      if (/^\s*```/.test(ln)) {
        inFence = !inFence;
        continue; // fence 标记行本身不算 prose
      }
      if (inFence) set.add(ln);
    }
  } catch {
    // 读不到全文 → 不放行（保守）
  }
  fenceCache.set(file, set);
  return set;
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
    if (cmd.includes('[skip-stage-check]')) process.exit(0);

    const repoRoot = (git('rev-parse --show-toplevel') || '').trim() || process.cwd();

    // staged + worktree（git commit -a 场景）的 unified diff
    let diff = git('diff --cached -U0');
    if (/\s-[a-z]*a[a-z]*\b/.test(cmd)) {
      diff += '\n' + git('diff -U0');
    }
    if (!diff) process.exit(0);

    const hits = []; // { file, line }
    const blocks = diff.split(/^diff --git /m).slice(1);
    for (const block of blocks) {
      const headerMatch = block.match(/^\+\+\+\s+b\/(.+)$/m);
      if (!headerMatch) continue;
      const file = headerMatch[1];
      if (!inScope(file)) continue;
      // 跳过测试 / fixture
      if (/(?:^|\/)tests?\//.test(file)) continue;
      if (/__fixtures__|\/fixtures\//.test(file)) continue;

      const fenceSet = fenceLineSet(repoRoot, file);
      const lines = block.split('\n');
      for (const ln of lines) {
        if (!ln.startsWith('+') || ln.startsWith('+++')) continue;
        const content = ln.slice(1);
        // 代码块内放行
        if (fenceSet.has(content)) continue;
        // 剔除代码标识符 token 后再判
        const stripped = stripCodeIdents(content);
        if (BARE_STAGE.test(stripped)) {
          hits.push({ file, line: content.trim().slice(0, 200) });
        }
      }
    }

    if (hits.length === 0) process.exit(0);

    const sample = hits.slice(0, 10).map(h =>
      `  ${h.file}\n    + ${h.line}`
    ).join('\n');
    const more = hits.length > 10 ? `\n  ...（还有 ${hits.length - 10} 条命中）` : '';

    const reason = `⚠️ stage 编号检查（check-stage-number-jargon hook）

本次 commit 在 skills/ 的 SKILL prose 里引入了裸 stage 号（stage <N> / Stage <N>）。stage 号是内部状态标记（stages.py 自述「不再 PM-facing」）——runtime AI 读 prose 时会把它当成单工作 stage 号去推进状态机，推过头一格。

命中（前 10 条）：
${sample}${more}

修法：引用阶段一律用名字，不留裸数字——
  - stage 1 → 范围确认（阶段）
  - stage 2 → build（阶段）
  - stage 3 → 复审 / 体验迭代（阶段）
  - stage 4 → 沉淀（阶段）
  - 旧 7-stage 幽灵（stage 4/4A/5/6/7）→ 按对应新机阶段名重写
  - 六步概念号 ↔ 内部 stage 的翻译真相源见 _shared/pm-view/input-flow.md §九 六步框

放行：代码块（\`\`\`…\`\`\`）内的映射表 / 代码示例；代码标识符（MAX_STAGE / STAGE_NAMES / stage_num / {stage}）；.work-meta.json 的 "stage" 字段名。

→ 改完重新 git add + commit。
→ 若确实是不进消费仓的实验 / 历史承接注记，commit message 加 [skip-stage-check] 跳过。

(hook 来源: hooks/check-stage-number-jargon.cjs；禁用方式: 删 .claude/settings.json 里 PreToolUse 对应条目)`;

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
