#!/usr/bin/env node
// UserPromptSubmit hook: keep natural-language follow-ups inside the current
// PMAI build contract instead of falling through to unscoped generic QA.

const path = require('path');
const { spawnSync } = require('child_process');

const EXPLICIT_PMAI_ENTRY_PATTERN = /^(?:\/pmai-|\$pmai-|\/skill:pmai-)[a-z0-9][a-z0-9-]*(?=$|\s)/i;
const EXECUTION_CONTEXT_STATUSES = new Set(['none', 'active', 'ambiguous', 'invalid']);
const MAX_STDIN_BYTES = 4 * 1024 * 1024;
const TOTAL_BUDGET_MS = configuredValue('PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS', 7000, 7000);
const DEADLINE_AT_NS = process.hrtime.bigint() + BigInt(TOTAL_BUDGET_MS) * 1_000_000n;

function configuredValue(name, fallback, maximum) {
  const parsed = Number.parseInt(process.env[name] || '', 10);
  const value = Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
  return Math.min(value, maximum);
}

function configuredTimeout(name, fallback, maximum) {
  const remainingNs = DEADLINE_AT_NS - process.hrtime.bigint();
  const remaining = remainingNs > 0n
    ? Number((remainingNs + 999_999n) / 1_000_000n)
    : 1;
  return Math.min(configuredValue(name, fallback, maximum), remaining);
}

function spawnFailure(result, label) {
  if (result.error && result.error.code === 'ETIMEDOUT') {
    return `${label} 超时。`;
  }
  if (result.error) {
    return `${label} 无法启动：${result.error.message}`;
  }
  const stderr = (result.stderr || '').trim().replace(/\s+/g, ' ').slice(0, 500);
  const suffix = stderr ? `：${stderr}` : '。';
  return `${label} 返回非零状态 ${result.status}${suffix}`;
}

function repoRootFor(cwd) {
  const result = spawnSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {
    encoding: 'utf8',
    timeout: configuredTimeout('PMAI_ACTIVE_BUILD_GIT_TIMEOUT_MS', 1000, 1500),
  });
  if (result.status !== 0) {
    return { error: spawnFailure(result, 'Git 仓库定位') };
  }
  const value = (result.stdout || '').trim();
  if (!value) return { error: 'Git 仓库定位返回空路径。' };
  return { value };
}

function readExecutionContext(repoRoot) {
  const pmaiHome = path.resolve(__dirname, '..');
  const script = path.join(pmaiHome, 'scripts', 'status-view.py');
  const result = spawnSync('python3', [script, repoRoot, '--execution-context'], {
    encoding: 'utf8',
    cwd: repoRoot,
    timeout: configuredTimeout('PMAI_ACTIVE_BUILD_STATUS_TIMEOUT_MS', 4500, 5000),
  });
  const stdout = (result.stdout || '').trim();
  let context = null;
  if (stdout) {
    try {
      context = JSON.parse(stdout);
    } catch {
      if (result.status === 0) {
        return { error: '只读 execution context 返回了非法 JSON。' };
      }
    }
  }
  if (result.status !== 0) {
    const contractReason = context && typeof context.reason === 'string'
      ? ` ${context.reason}`
      : '';
    return { error: `${spawnFailure(result, '只读 execution context')}${contractReason}` };
  }
  if (!stdout) return { error: '只读 execution context 返回空输出。' };
  if (!context || typeof context !== 'object' || Array.isArray(context)) {
    return { error: '只读 execution context 必须返回 JSON 对象。' };
  }
  if (!EXECUTION_CONTEXT_STATUSES.has(context.status)) {
    return { error: `只读 execution context 返回未知状态：${String(context.status)}。` };
  }
  return { value: context };
}

function unavailableContext(reason) {
  return `ACTIVE BUILD 续接护栏不可用（active-build-guard hook 注入）

当前项目的只读 build 上下文无法安全取得，不能把异常当成“没有 active build”。先运行 /pmai-status 检查当前工作并修复下面的问题；在上下文恢复前，禁止继续无范围约束的通用 QA 或修改。

原因：${reason}`;
}

function writeHookContext(additionalContext, callback) {
  const output = {
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext,
    },
  };
  process.stdout.write(JSON.stringify(output), callback);
}

function unavailableFromContext(context) {
  const reason = typeof context.reason === 'string' && context.reason.trim()
    ? context.reason.trim()
    : 'active build 合同状态无效。';
  return unavailableContext(reason);
}

function guardText(context) {
  const serialized = JSON.stringify(context, null, 2);
  if (context.status === 'invalid') {
    return unavailableFromContext(context) + `

只读状态：
${serialized}`;
  }
  if (context.status === 'ambiguous') {
    return `ACTIVE BUILD 续接护栏（active-build-guard hook 注入）

当前存在多个可续接的 build。不要猜模块，也不要转成无范围约束的通用 QA；只让 PM 指明本轮要继续看的模块，然后按该模块的 /pmai-build 恢复流程重新读取合同。

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

const inputChunks = [];
let inputBytes = 0;
let inputSettled = false;

function settleInputAsUnavailable(reason) {
  if (inputSettled) return;
  inputSettled = true;
  clearTimeout(stdinTimeout);
  process.stdin.removeAllListeners();
  process.stdin.pause();
  inputChunks.length = 0;
  inputBytes = 0;
  writeHookContext(
    unavailableContext(reason),
    () => process.exit(0),
  );
}

const stdinTimeout = setTimeout(() => {
  settleInputAsUnavailable('宿主 hook 输入在读取期限内未结束。');
}, configuredTimeout('PMAI_ACTIVE_BUILD_STDIN_TIMEOUT_MS', 1500, 2000));
process.stdin.on('data', chunk => {
  if (inputSettled) return;
  inputBytes += chunk.length;
  if (inputBytes > MAX_STDIN_BYTES) {
    settleInputAsUnavailable('宿主 hook 输入超过 4 MiB 上限。');
    return;
  }
  inputChunks.push(chunk);
});
process.stdin.on('error', () => {
  settleInputAsUnavailable('宿主 hook 输入读取失败。');
});
process.stdin.on('end', () => {
  if (inputSettled) return;
  inputSettled = true;
  clearTimeout(stdinTimeout);

  let data;
  try {
    const input = Buffer.concat(inputChunks, inputBytes).toString('utf8');
    data = JSON.parse(input);
  } catch {
    writeHookContext(unavailableContext('宿主 hook 输入不是合法 JSON。'));
    return;
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    writeHookContext(unavailableContext('宿主 hook 输入必须是 JSON 对象。'));
    return;
  }

  try {
    const prompt = typeof data.prompt === 'string' ? data.prompt : '';
    if (EXPLICIT_PMAI_ENTRY_PATTERN.test(prompt.trimStart())) process.exit(0);

    if (data.cwd !== undefined && typeof data.cwd !== 'string') {
      writeHookContext(unavailableContext('宿主 hook cwd 必须是字符串。'));
      return;
    }

    const processCwd = process.cwd();
    const processRepoResult = repoRootFor(processCwd);
    if (processRepoResult.error) {
      writeHookContext(unavailableContext(processRepoResult.error));
      return;
    }
    let repoRoot = processRepoResult.value;
    const payloadCwd = typeof data.cwd === 'string' && data.cwd.trim()
      ? data.cwd
      : processCwd;
    if (path.resolve(payloadCwd) !== path.resolve(processCwd)) {
      const payloadRepoResult = repoRootFor(payloadCwd);
      if (payloadRepoResult.error) {
        writeHookContext(unavailableContext(payloadRepoResult.error));
        return;
      }
      if (path.resolve(payloadRepoResult.value) !== path.resolve(repoRoot)) {
        writeHookContext(unavailableContext(
          '宿主 payload cwd 与 hook 进程所在 Git 仓库不一致。',
        ));
        return;
      }
      repoRoot = payloadRepoResult.value;
    }

    const contextResult = readExecutionContext(repoRoot);
    if (contextResult.error) {
      writeHookContext(unavailableContext(contextResult.error));
      return;
    }
    const context = contextResult.value;
    if (context.status === 'none') process.exit(0);
    writeHookContext(guardText(context));
  } catch {
    writeHookContext(unavailableContext('active-build-guard 处理宿主输入时发生内部错误。'));
  }
});
