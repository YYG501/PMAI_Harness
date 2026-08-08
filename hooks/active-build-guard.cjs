#!/usr/bin/env node
// UserPromptSubmit hook: keep natural-language follow-ups inside the current
// PMAI build contract instead of falling through to unscoped generic QA.

const path = require('path');
const { spawnSync } = require('child_process');

const OTHER_WORKFLOW_PATTERN = /^\s*(?:\/|\$|\/skill:)(?:pmai-)?(?:design|direction|init-project|quick-fix|record|feedback|lark-review|lark-sync|mockup|spec-writing|doc-writing|meta)(?:\s|$)/i;

function repoRootFor(cwd) {
  const result = spawnSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {
    encoding: 'utf8',
    timeout: 1500,
  });
  if (result.status !== 0) return null;
  const value = (result.stdout || '').trim();
  return value || null;
}

function readExecutionContext(repoRoot) {
  const pmaiHome = path.resolve(__dirname, '..');
  const script = path.join(pmaiHome, 'scripts', 'status-view.py');
  const result = spawnSync('python3', [script, repoRoot, '--execution-context'], {
    encoding: 'utf8',
    cwd: repoRoot,
    timeout: 3500,
  });
  const stdout = (result.stdout || '').trim();
  if (!stdout) return null;
  try {
    return JSON.parse(stdout);
  } catch {
    return null;
  }
}

function guardText(context) {
  const serialized = JSON.stringify(context, null, 2);
  if (context.status === 'ambiguous') {
    return `ACTIVE BUILD 续接护栏（active-build-guard hook 注入）

当前存在多个可续接的 build。不要猜模块，也不要转成无范围约束的通用 QA；只让 PM 指明本轮要继续看的模块，然后按该模块的 /pmai-build 恢复流程重新读取合同。

只读状态：
${serialized}`;
  }
  if (context.status === 'invalid') {
    return `ACTIVE BUILD 续接护栏（active-build-guard hook 注入）

当前 active build 合同无法安全读取。不要绕过合同做通用 QA，也不要把合同外事项列成产品缺口；按 /pmai-build 恢复路径报告下面的具体合同错误并修复上下文后再继续。

只读状态：
${serialized}`;
  }
  return `ACTIVE BUILD 续接护栏（active-build-guard hook 注入）

当前已有 building / iterating / final_check 中的 build。若 PM 本轮明确开启与它无关的新工作，按新工作的正常入口处理；除此之外，“启动看看”“检查一下”“还有什么问题”“修改当前结果”等自然语言都视为继续当前 /pmai-build，不得转成无范围约束的通用 QA。

继续前必须：
1. 重新读取下面的 target + delivery_policy，并重新编译、实际消费当前模块 context pack。
2. 只按现有 spec、active decisions、accepted deltas、approved paths 和当前 acceptance lane 检查或修改。
3. 对 prototype 继续执行 interactive-simulation：delivery_policy.simulate_by_default 中的真实后端、鉴权、持久化、外部集成等，在没有 active decision 要求真实实现时不是缺口。
4. 规格已有的要求直接作为覆盖要求；规格与 active decisions 没有留下的范围，不得重新包装成 PM 待确认问题。product 仍按 production-implementation 检查。

只读执行上下文（不是新状态）：
${serialized}`;
}

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 4500);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const prompt = typeof data.prompt === 'string' ? data.prompt : '';
    if (OTHER_WORKFLOW_PATTERN.test(prompt)) process.exit(0);

    const cwd = typeof data.cwd === 'string' && data.cwd ? data.cwd : process.cwd();
    const repoRoot = repoRootFor(cwd);
    if (!repoRoot) process.exit(0);
    const context = readExecutionContext(repoRoot);
    if (!context || context.status === 'none') process.exit(0);

    const output = {
      hookSpecificOutput: {
        hookEventName: 'UserPromptSubmit',
        additionalContext: guardText(context),
      },
    };
    process.stdout.write(JSON.stringify(output));
  } catch {
    process.exit(0);
  }
});
