#!/usr/bin/env node
// Shared PM decision gate hook.
// - UserPromptSubmit records the current user message only against the one
//   displayed, pending gate that existed when the message arrived.
// - PreToolUse blocks decision-file writes and commits that lack a consumable
//   authorization receipt.

const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

const MAX_STDIN_BYTES = 4 * 1024 * 1024;
const EXPLICIT_PMAI_ENTRY_PATTERN = /^(?:\/pmai-|\$pmai-|\/skill:pmai-)[a-z0-9][a-z0-9-]*(?=$|\s)/i;

function repoRootFor(cwd) {
  const result = spawnSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {
    encoding: 'utf8',
    timeout: 1200,
  });
  if (result.status !== 0) return null;
  return (result.stdout || '').trim() || null;
}

function runGate(args, cwd) {
  const script = path.join(path.resolve(__dirname, '..'), 'scripts', 'decision-gate.py');
  return spawnSync('python3', [script, ...args], {
    cwd,
    encoding: 'utf8',
    timeout: 5000,
  });
}

function failureReason(result, fallback) {
  if (result.error && result.error.code === 'ETIMEDOUT') return `${fallback}超时。`;
  if (result.error) return `${fallback}无法启动：${result.error.message}`;
  return (result.stderr || '').trim() || fallback;
}

function deny(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
}

function addContext(text) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext: text,
    },
  }));
}

function resolvedRepo(data) {
  const processCwd = process.cwd();
  const processRepo = repoRootFor(processCwd);
  if (!processRepo) return null;
  if (data.cwd !== undefined && typeof data.cwd !== 'string') return null;
  const payloadCwd = typeof data.cwd === 'string' && data.cwd.trim() ? data.cwd : processCwd;
  const payloadRepo = repoRootFor(payloadCwd);
  if (!payloadRepo || path.resolve(payloadRepo) !== path.resolve(processRepo)) return null;
  return processRepo;
}

function designArtifactFor(repoRoot, rawPath) {
  if (typeof rawPath !== 'string' || !rawPath.trim()) return null;
  const unresolved = path.resolve(process.cwd(), rawPath);
  let absolute;
  try {
    absolute = fs.realpathSync.native(unresolved);
  } catch {
    try {
      absolute = path.join(fs.realpathSync.native(path.dirname(unresolved)), path.basename(unresolved));
    } catch {
      return null;
    }
  }
  let canonicalRoot;
  try {
    canonicalRoot = fs.realpathSync.native(repoRoot);
  } catch {
    return null;
  }
  const relative = path.relative(canonicalRoot, absolute).split(path.sep).join('/');
  const match = /^docs\/modules\/([^/]+)\/(discussion|decisions|spec)\.md$/.exec(relative);
  if (!match) return null;
  return {
    moduleDir: path.join(repoRoot, 'docs', 'modules', match[1]),
    kind: match[2],
  };
}

function projectArtifactFor(repoRoot, rawPath) {
  if (typeof rawPath !== 'string' || !rawPath.trim()) return false;
  const unresolved = path.resolve(process.cwd(), rawPath);
  let absolute;
  try {
    absolute = fs.realpathSync.native(unresolved);
  } catch {
    try {
      absolute = path.join(fs.realpathSync.native(path.dirname(unresolved)), path.basename(unresolved));
    } catch {
      return false;
    }
  }
  let canonicalRoot;
  try {
    canonicalRoot = fs.realpathSync.native(repoRoot);
  } catch {
    return false;
  }
  const relative = path.relative(canonicalRoot, absolute).split(path.sep).join('/');
  return relative === 'PRODUCT.md'
    || relative === '.pm-workflow/proposal.json'
    || /^docs\/proposals\/[^/]+\.md$/.test(relative)
    || relative === 'docs/proposals/INDEX.md';
}

function handlesGitCommit(command) {
  return typeof command === 'string'
    && /\bgit\b(?:\s+-\S+|\s+-C\s+(?:"[^"]+"|'[^']+'|\S+))*\s+commit\b/.test(command);
}

function handlePrompt(data, repoRoot) {
  const prompt = typeof data.prompt === 'string' ? data.prompt.trim() : '';
  if (!prompt || EXPLICIT_PMAI_ENTRY_PATTERN.test(prompt)) return;
  const args = ['observe', '--repo-root', repoRoot, '--message', prompt];
  const sessionId = data.session_id || data.sessionId;
  const messageId = data.message_id || data.messageId || data.user_message_id;
  const transcriptPath = data.transcript_path || data.transcriptPath;
  if (typeof sessionId === 'string' && sessionId.trim()) args.push('--session-id', sessionId);
  if (typeof messageId === 'string' && messageId.trim()) args.push('--message-id', messageId);
  if (typeof transcriptPath === 'string' && transcriptPath.trim()) {
    args.push('--transcript-path', transcriptPath);
  }
  const result = runGate(args, repoRoot);
  if (result.status !== 0) {
    addContext(`DECISION GATE 答复绑定失败（decision-gate-guard hook）\n\n${failureReason(result, '授权收据捕获失败。')}\n在恢复前禁止把本消息解释成产品决定，也不得写决定、提交或进入 ready_to_build。`);
    return;
  }
  let payload;
  try {
    payload = JSON.parse((result.stdout || '').trim());
  } catch {
    addContext('DECISION GATE 答复绑定失败（decision-gate-guard hook）\n\n授权收据捕获返回非法结果。在恢复前禁止写决定、提交或进入 ready_to_build。');
    return;
  }
  if (payload.status === 'none') return;
  if (payload.status === 'ambiguous') {
    addContext(`DECISION GATE 答复归属不唯一（decision-gate-guard hook）\n\n${payload.reason}\n不得猜题或复用本答复；先让 PM 指明当前问题。`);
    return;
  }
  if (payload.status === 'observed') {
    addContext(`DECISION GATE 用户答复候选（decision-gate-guard hook）

本条用户消息只绑定到当时已经展示且仍 pending 的问题：
- gate_id: ${payload.gate_id}
- question_id: ${payload.question_id}
- answer_event_id: ${payload.event_id}
- 问题摘要: ${payload.question_summary}

先判断本消息是否实际回答了该题。若是，必须调用 decision-gate.py answer 选择这个 event；若 PM 转去别的事则保留 pending 或显式 cancel。该 event 不能用于其它问题。没有 answer + consume 收据前，禁止写 decisions.md、提交建造依据或进入 ready_to_build。`);
  }
}

function handlePreTool(data, repoRoot) {
  const toolName = data.tool_name;
  const input = data.tool_input;
  if (!input || typeof input !== 'object' || Array.isArray(input)) return;
  if (toolName === 'Edit' || toolName === 'Write') {
    const filePath = input.file_path || input.path;
    const artifact = designArtifactFor(repoRoot, filePath);
    if (!artifact && projectArtifactFor(repoRoot, filePath)) {
      const result = runGate(['guard-project-write', repoRoot], repoRoot);
      if (result.status !== 0) {
        deny(`PM 决策授权护栏已拒绝写入 Proposal / 产品基线。\n\n${failureReason(result, '缺少可验证的项目级授权窗口。')}\n请先展示当前问题，并让本轮用户答复依次完成 observe → answer；写入完成后再 consume 到对应项目动作。`);
      }
      return;
    }
    if (!artifact) return;
    const command = artifact.kind === 'decisions'
      ? 'guard-authority-write'
      : 'guard-pending-write';
    const result = runGate([command, artifact.moduleDir], repoRoot);
    if (result.status !== 0) {
      deny(`PM 决策授权护栏已拒绝写入 ${artifact.kind}.md。\n\n${failureReason(result, '缺少可验证授权窗口。')}\n请先展示当前问题，并让本轮用户答复依次完成 observe → answer；写好决定后再 consume 到具体 D 编号。`);
    }
    return;
  }
  if (toolName === 'Bash' && handlesGitCommit(input.command)) {
    const result = runGate(['check-staged', '--repo-root', repoRoot], repoRoot);
    if (result.status !== 0) {
      deny(`PM 决策授权护栏已拒绝提交。\n\n${failureReason(result, 'staged 决定缺少授权收据。')}\n每个新增或变化的 D 编号必须由一条已展示问题和一条当时用户消息一次性授权。`);
    }
  }
}

const chunks = [];
let bytes = 0;
const timer = setTimeout(() => process.exit(0), 2000);
process.stdin.on('data', chunk => {
  bytes += chunk.length;
  if (bytes > MAX_STDIN_BYTES) process.exit(0);
  chunks.push(chunk);
});
process.stdin.on('end', () => {
  clearTimeout(timer);
  let data;
  try {
    data = JSON.parse(Buffer.concat(chunks, bytes).toString('utf8'));
  } catch {
    process.exit(0);
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) process.exit(0);
  const repoRoot = resolvedRepo(data);
  if (!repoRoot) process.exit(0);
  if (data.hook_event_name === 'UserPromptSubmit' || data.hookEventName === 'UserPromptSubmit') {
    handlePrompt(data, repoRoot);
  } else if (data.hook_event_name === 'PreToolUse' || data.hookEventName === 'PreToolUse') {
    handlePreTool(data, repoRoot);
  } else if (data.tool_name) {
    handlePreTool(data, repoRoot);
  } else if (typeof data.prompt === 'string') {
    handlePrompt(data, repoRoot);
  }
});
