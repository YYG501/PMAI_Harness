// Shared transport/identity boundary for consumer decision and finalize hooks.
// Repository identity remains owned by scripts/repo-kind.py. No payload can
// choose the checkout whose protected actions are being authorized.
const fs = require('fs');
const path = require('path');
const { spawnSync, nativePath } = require('./host-process.cjs');

const MAX_STDIN_BYTES = 4 * 1024 * 1024;
const DEADLINE = process.hrtime.bigint() + 7_000_000_000n;

function remainingMs(maximum) {
  const remaining = DEADLINE - process.hrtime.bigint();
  if (remaining <= 0n) throw new Error('护栏总校验预算已超时。');
  return Math.min(maximum, Math.max(1, Number(remaining / 1_000_000n)));
}

function runCommand(command, args, options = {}) {
  return spawnSync(command, args, {
    ...options, encoding: 'utf8', windowsHide: true,
    timeout: remainingMs(options.timeout || 1200),
    maxBuffer: MAX_STDIN_BYTES,
  });
}

function requireSuccess(result, label) {
  if (result.error && result.error.code === 'ETIMEDOUT') throw new Error(`${label}超时。`);
  if (result.error) throw new Error(`${label}无法启动（${result.error.code || 'unknown'}）。`);
  if (result.status !== 0) throw new Error(`${label}失败（退出状态 ${result.status}）。`);
  return (result.stdout || '').trim();
}

function canonicalRoot(cwd) {
  const value = requireSuccess(runCommand('git', ['-C', cwd, 'rev-parse', '--show-toplevel']), 'Git 仓库定位');
  if (!value) throw new Error('Git 仓库定位返回空路径。');
  return fs.realpathSync.native(value);
}

function consumerRoot() {
  // A non-Git directory can still have a PMAI identity; classify it before
  // deciding to ignore this invocation. Git/identity failures stay explicit.
  const cwd = process.cwd();
  const git = runCommand('git', ['-C', cwd, 'rev-parse', '--show-toplevel']);
  let root = cwd;
  if (git.status === 0) {
    const value = (git.stdout || '').trim();
    if (!value) throw new Error('Git 仓库定位返回空路径。');
    root = fs.realpathSync.native(value);
  } else if (git.error || !/not a git repository/i.test(git.stderr || '')) {
    requireSuccess(git, 'Git 仓库定位');
  }
  const script = path.join(__dirname, '..', 'scripts', 'repo-kind.py');
  const text = requireSuccess(runCommand('python3', [script, '--repo-root', root, '--json']), 'PMAI 仓库身份校验');
  const identity = JSON.parse(text);
  if (!identity || identity.schema_version !== 1
    || !['generator', 'consumer', 'uninitialized'].includes(identity.repo_kind)
    || typeof identity.repo_root !== 'string'
    || fs.realpathSync.native(nativePath(identity.repo_root)) !== root) {
    throw new Error('PMAI 仓库身份校验返回非法结果。');
  }
  if (identity.repo_kind !== 'consumer') return null;
  if (git.status !== 0) throw new Error('PMAI 消费仓没有可验证的 Git 根目录。');
  return root;
}

function eventFor(data) {
  const explicit = data.hook_event_name || data.hookEventName;
  if (explicit) {
    if (!['UserPromptSubmit', 'PreToolUse'].includes(explicit)) throw new Error('未知 Hook 事件。');
    if (data.hook_event_name && data.hookEventName && data.hook_event_name !== data.hookEventName) {
      throw new Error('Hook 事件字段冲突。');
    }
    return explicit;
  }
  if (typeof data.tool_name === 'string') return 'PreToolUse';
  if (typeof data.prompt === 'string') return 'UserPromptSubmit';
  throw new Error('Hook 输入缺少可验证事件。');
}

function validateEvent(data, event) {
  if (event === 'UserPromptSubmit') {
    if (typeof data.prompt !== 'string') throw new Error('用户消息必须是字符串。');
    return;
  }
  if (typeof data.tool_name !== 'string' || !data.tool_name.trim()
    || !data.tool_input || typeof data.tool_input !== 'object' || Array.isArray(data.tool_input)) {
    throw new Error('工具调用缺少有效名称或输入。');
  }
  const input = data.tool_input;
  if (data.tool_name === 'Bash' && (typeof input.command !== 'string' || !input.command.trim())) {
    throw new Error('Bash 调用缺少命令。');
  }
  if (['Edit', 'Write'].includes(data.tool_name)) {
    const target = input.file_path || input.path;
    if (typeof target !== 'string' || !target.trim()) throw new Error('文件修改缺少目标路径。');
  }
}

function runHook({ name, onPrompt, onPreTool }) {
  let finished = false;
  let event = null;
  let timer;
  const fail = error => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    const reason = `${name} 无法完成校验：${error.message || '未知错误'} 请修复输入或运行环境后重试，保留当前 checkpoint。`;
    // With no trustworthy event, an exit-2 hook error is safer than emitting
    // a fabricated PreToolUse response to a possible UserPromptSubmit call.
    if (event === 'PreToolUse') {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: {
        hookEventName: event, permissionDecision: 'deny', permissionDecisionReason: reason,
      } }), () => process.exit(0));
    } else {
      process.stderr.write(reason + '\n', () => process.exit(2));
    }
  };
  let root;
  try {
    root = consumerRoot();
    if (!root) return; // Known ordinary/generator repositories need no stdin.
  } catch (error) { fail(error); return; }
  const chunks = [];
  let bytes = 0;
  try {
    timer = setTimeout(() => fail(new Error('宿主 Hook 输入读取超时。')), remainingMs(2000));
  } catch (error) { fail(error); return; }
  process.stdin.on('error', () => fail(new Error('宿主 Hook 输入读取失败。')));
  process.stdin.on('data', chunk => {
    if (finished) return;
    bytes += chunk.length;
    if (bytes > MAX_STDIN_BYTES) { fail(new Error('宿主 Hook 输入超过 4 MiB。')); return; }
    chunks.push(chunk);
  });
  process.stdin.on('end', () => {
    if (finished) return;
    clearTimeout(timer);
    try {
      let data;
      try { data = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { throw new Error('宿主 Hook 输入不是有效 JSON。'); }
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('宿主 Hook 输入必须是对象。');
      event = eventFor(data);
      validateEvent(data, event);
      if (data.cwd !== undefined && (typeof data.cwd !== 'string' || !data.cwd.trim())) {
        throw new Error('宿主 cwd 必须是非空路径。');
      }
      if (canonicalRoot(data.cwd || process.cwd()) !== root) throw new Error('宿主 cwd 与实际工作仓不一致。');
      if (event === 'UserPromptSubmit') onPrompt(data, root);
      else onPreTool(data, root);
      finished = true;
    } catch (error) { fail(error); }
  });
}

module.exports = { runHook, runCommand, requireSuccess };
