#!/usr/bin/env node
// Route PM finalization language to the single resumable finalize runner.
// A short-lived marker bridges UserPromptSubmit and the following tool calls;
// lifecycle state remains owned by .work-meta.json and finalize-work.py.

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const MAX_STDIN_BYTES = 4 * 1024 * 1024;
const MARKER_TTL_MS = 2 * 60 * 60 * 1000;
const FINALIZE_LANGUAGE = /(?:可以提交|可以合并|提交吧|合进去吧|合并吧|定稿|这版可以了|可以了[，,\s]*(?:提交|合并))/;
const NEGATED_FINALIZE_LANGUAGE = /(?:不要|先别|暂不|不能|不.?要).{0,8}(?:提交|合并|定稿)/;
const RUNNER_COMMAND = /(?:finalize-candidate\.py|finalize-work\.py)/;
const POST_RUNNER_COMMAND = /(?:close-work\.sh|build-contract\.py\s+(?:validate-land|docs-complete|docs-fail|resume-iteration))/;
const SEMANTIC_SCRIPT_CHECKS = {
  "prototype-boundary.py": "prototype-boundary",
  "coverage-evidence.py": "coverage",
};
const SEMANTIC_CHECKS = new Set(["prototype-boundary", "coverage", "scope-coverage", "migration", "security"]);
const SHELL_CHAIN = /[;&|]/;
const READ_COMMAND = /^(?:\s*(?:git\s+(?:status|diff|show|log|branch|rev-parse)|pwd|ls(?:\s|$)|find\s|rg\s|grep\s|sed\s|cat\s|head\s|tail\s|stat\s|which\s|command\s|printf\s|echo\s|true\s*$))/;
const BLOCKED_COMMAND = /(?:\bgit\b[^\n]*\b(?:commit|merge|rebase|cherry-pick|add|reset|restore|clean)\b|(?:pnpm|npm|yarn|bun)\s+(?:run\s+)?(?:test|typecheck|build|lint|dev|start)\b|(?:final-validation|browser-acceptance|prototype-boundary|coverage-evidence)\.py|\b(?:browse|playwright)\b)/;
const MUTATING_PYTHON = /\bpython3?\b[^\n]*(?:\.py|\s-c\s)/;

function repoRootFor(cwd) {
  const result = spawnSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {
    encoding: 'utf8', timeout: 1200,
  });
  if (result.status !== 0) return null;
  return (result.stdout || '').trim() || null;
}

function resolveRepo(data) {
  const processCwd = process.cwd();
  const processRepo = repoRootFor(processCwd);
  if (!processRepo) return null;
  if (data.cwd !== undefined && typeof data.cwd !== 'string') return null;
  const payloadCwd = typeof data.cwd === 'string' && data.cwd.trim() ? data.cwd : processCwd;
  const payloadRepo = repoRootFor(payloadCwd);
  if (!payloadRepo || path.resolve(payloadRepo) !== path.resolve(processRepo)) return null;
  return processRepo;
}

function sessionId(data) {
  const value = data.session_id || data.sessionId || data.thread_id || data.threadId;
  return typeof value === 'string' && value.trim() ? value.trim() : 'anonymous';
}

function markerDir() {
  return process.env.PMAI_FINALIZE_INTENT_DIR || path.join(os.tmpdir(), 'pmai-finalize-intents');
}

function markerPath(repoRoot, id) {
  const digest = crypto.createHash('sha256').update(`${path.resolve(repoRoot)}\n${id}`).digest('hex');
  return path.join(markerDir(), `${digest}.json`);
}

function writeMarker(repoRoot, id, moduleDir, prompt) {
  const destination = markerPath(repoRoot, id);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const temporary = `${destination}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify({
    schema_version: 1,
    repo_root: path.resolve(repoRoot),
    module_dir: moduleDir,
    session_id: id,
    prompt,
    observed_at: new Date().toISOString(),
  }, null, 2) + '\n');
  fs.renameSync(temporary, destination);
}

function updateMarker(repoRoot, id, updates) {
  const file = markerPath(repoRoot, id);
  let marker;
  try {
    marker = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
  if (!marker || typeof marker !== 'object' || Array.isArray(marker)) return null;
  Object.assign(marker, updates);
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(marker, null, 2) + '\n');
  fs.renameSync(temporary, file);
  return marker;
}

function removeMarker(repoRoot, id) {
  try { fs.unlinkSync(markerPath(repoRoot, id)); } catch { /* already cleared */ }
}

function readMarker(repoRoot, id) {
  const candidates = [markerPath(repoRoot, id)];
  if (id === 'anonymous') {
    try {
      for (const name of fs.readdirSync(markerDir())) {
        if (name.endsWith('.json')) candidates.push(path.join(markerDir(), name));
      }
    } catch { /* no marker directory */ }
  }
  for (const file of candidates) {
    try {
      const marker = JSON.parse(fs.readFileSync(file, 'utf8'));
      const time = Date.parse(marker.observed_at || '');
      if (marker.repo_root === path.resolve(repoRoot) && Number.isFinite(time)
        && Date.now() - time <= MARKER_TTL_MS) return marker;
      if (Number.isFinite(time) && Date.now() - time > MARKER_TTL_MS) fs.unlinkSync(file);
    } catch { /* ignore stale or malformed temporary marker */ }
  }
  return null;
}

function activeContext(repoRoot) {
  const script = path.join(path.resolve(__dirname, '..'), 'scripts', 'active-build-context.py');
  const result = spawnSync('python3', [script, repoRoot], {
    cwd: repoRoot, encoding: 'utf8', timeout: 4500,
  });
  try { return JSON.parse((result.stdout || '').trim()); } catch { return null; }
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

function allow(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'allow',
      permissionDecisionReason: reason,
    },
  }));
}

function addPromptContext(text) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext: text,
    },
  }));
}

function handlePrompt(data, repoRoot) {
  const prompt = typeof data.prompt === 'string' ? data.prompt.trim() : '';
  if (!prompt || NEGATED_FINALIZE_LANGUAGE.test(prompt) || !FINALIZE_LANGUAGE.test(prompt)) {
    removeMarker(repoRoot, sessionId(data));
    return;
  }
  const context = activeContext(repoRoot);
  if (!context || context.status !== 'active' || !Array.isArray(context.active_builds)
    || context.active_builds.length !== 1) {
    removeMarker(repoRoot, sessionId(data));
    return;
  }
  const work = context.active_builds[0];
  const moduleDir = path.join(repoRoot, work.module || '');
  writeMarker(repoRoot, sessionId(data), moduleDir, prompt);
  addPromptContext(`FINALIZE 路由已锁定：PM 已明确授权“${prompt}”。\n\n下一步必须直接调用 finalize-candidate.py（中断恢复调用 finalize-work.py）；不要先手工跑 test/typecheck/build、提交或 merge。统一 runner 会只执行缺失 checkpoint，失败后从同一游标恢复。`);
}

function missingSemanticChecks(marker) {
  const metaPath = path.join(marker.module_dir || '', '.work-meta.json');
  try {
    const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
    const build = meta && meta.build;
    const acceptance = build && build.acceptance;
    const checks = Array.isArray(acceptance && acceptance.final_checks)
      ? acceptance.final_checks.map(String)
      : [];
    const evidence = new Set(
      Array.isArray(acceptance && acceptance.evidence)
        ? acceptance.evidence.map(item => String(item && item.name || ''))
        : [],
    );
    return checks.filter(name => SEMANTIC_CHECKS.has(name) && !evidence.has(name));
  } catch {
    return null;
  }
}

function semanticCheckForCommand(command) {
  for (const [script, check] of Object.entries(SEMANTIC_SCRIPT_CHECKS)) {
    if (command.includes(script)) return check;
  }
  if (/build-contract\.py\s+record-evidence/.test(command)) {
    const match = command.match(/(?:^|\s)--name\s+([^\s"']+)/);
    return match ? match[1] : null;
  }
  return null;
}

function handlePreTool(data, repoRoot) {
  if (data.tool_name !== 'Bash') return;
  const command = data.tool_input && data.tool_input.command;
  if (typeof command !== 'string' || !command.trim()) return;
  const marker = readMarker(repoRoot, sessionId(data));
  if (!marker) return;
  const runnerStarted = Boolean(marker.runner_started_at);
  if (RUNNER_COMMAND.test(command)) {
    if (SHELL_CHAIN.test(command)) {
      deny('FINALIZE 硬路由只允许单独调用统一 runner；请拆开 shell 链，避免 runner 和手工检查/提交混跑。');
      return;
    }
    if (!runnerStarted) updateMarker(repoRoot, sessionId(data), { runner_started_at: new Date().toISOString() });
    allow('FINALIZE 统一入口已识别；继续使用同一 runner，不要在旁边手工拼接检查或 merge。');
    return;
  }
  if (runnerStarted) {
    const semanticCheck = semanticCheckForCommand(command);
    if (semanticCheck) {
      if (SHELL_CHAIN.test(command)) {
        deny('FINALIZE 硬路由只允许单独执行语义 evidence；请拆开 shell 链，完成后再重跑 runner。');
        return;
      }
      const missing = missingSemanticChecks(marker);
      if (missing && missing.includes(semanticCheck)) {
        allow(`FINALIZE runner 已启动；仅放行当前仍缺失的 ${semanticCheck} evidence。完成后重跑同一 runner。`);
        return;
      }
      if (missing && !missing.length) {
        deny('FINALIZE runner 已完成语义 evidence；不要重复执行已通过检查，请重跑 finalize-work.py 继续恢复。');
        return;
      }
    }
    if (POST_RUNNER_COMMAND.test(command) && !BLOCKED_COMMAND.test(command)) {
      if (SHELL_CHAIN.test(command)) {
        deny('FINALIZE 硬路由只允许单独执行恢复 checkpoint；请拆开 shell 链。');
        return;
      }
      allow('FINALIZE runner 已启动；允许执行恢复 checkpoint，继续复用已通过证据。');
      return;
    }
  }
  if (BLOCKED_COMMAND.test(command)
    || (MUTATING_PYTHON.test(command) && !READ_COMMAND.test(command))) {
    deny(`FINALIZE 硬路由已阻止手工收尾。\n\nPM 已明确授权定稿/提交/合并，必须先调用 finalize-candidate.py；finalize-work.py 只用于中断恢复。不要先单独跑检查、browser、commit 或 merge，runner 会复用已通过证据并只补缺失项。`);
    return;
  }
  if (POST_RUNNER_COMMAND.test(command)) {
    deny('FINALIZE 硬路由要求先启动统一 runner；只有 runner 已返回后才允许恢复 checkpoint。');
    return;
  }
}

let input = '';
let bytes = 0;
const timer = setTimeout(() => process.exit(0), 3000);
process.stdin.on('data', chunk => {
  bytes += chunk.length;
  if (bytes > MAX_STDIN_BYTES) process.exit(0);
  input += chunk.toString('utf8');
});
process.stdin.on('end', () => {
  clearTimeout(timer);
  try {
    const data = JSON.parse(input);
    if (!data || typeof data !== 'object' || Array.isArray(data)) process.exit(0);
    const repoRoot = resolveRepo(data);
    if (!repoRoot) process.exit(0);
    if (data.hook_event_name === 'UserPromptSubmit' || data.hookEventName === 'UserPromptSubmit') {
      handlePrompt(data, repoRoot);
    } else if (data.hook_event_name === 'PreToolUse' || data.hookEventName === 'PreToolUse' || data.tool_name) {
      handlePreTool(data, repoRoot);
    }
  } catch { /* fail open for malformed host payloads */ }
});
