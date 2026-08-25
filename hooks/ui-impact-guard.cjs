#!/usr/bin/env node
// PreToolUse(Edit|Write) guard for high-risk UI layout edits.
// The Python helper follows local imports and reports shared primitive
// constraints before the first page-level edit is allowed.

const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

const MAX_STDIN_BYTES = 4 * 1024 * 1024;
const UI_EXTENSIONS = new Set(['.css', '.jsx', '.js', '.scss', '.tsx', '.ts', '.vue']);
const HIGH_RISK_PATTERN = /\b(?:Dialog|Drawer|Sheet|Popover)\b|className\s*=|(?:max|min)-[wh]-|\b[wh]-\[[^\]]+\]|\b(?:grid|flex|columns|gap)-/;

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

function repoRootFor(cwd) {
  const result = spawnSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {
    encoding: 'utf8',
    timeout: 1200,
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

function firstEdit(repoRoot, target) {
  const changed = spawnSync('git', ['-C', repoRoot, 'diff', 'HEAD', '--quiet', '--', target], {
    encoding: 'utf8',
    timeout: 1200,
  }).status !== 0;
  return !changed;
}

function runInspector(repoRoot, target, proposed) {
  const script = path.join(path.resolve(__dirname, '..'), 'scripts', 'ui-impact.py');
  return spawnSync(
    'python3',
    [script, 'inspect', '--repo-root', repoRoot, '--path', target, '--proposed-text', proposed],
    { cwd: repoRoot, encoding: 'utf8', timeout: 4000 },
  );
}

function main(data) {
  if (data.tool_name !== 'Edit' && data.tool_name !== 'Write') return;
  const input = data.tool_input;
  if (!input || typeof input !== 'object' || Array.isArray(input)) return;
  const rawTarget = input.file_path || input.path;
  if (typeof rawTarget !== 'string' || !rawTarget.trim()) return;
  const target = path.resolve(process.cwd(), rawTarget);
  if (!UI_EXTENSIONS.has(path.extname(target).toLowerCase())) return;
  const proposed = typeof input.new_string === 'string'
    ? input.new_string
    : typeof input.content === 'string' ? input.content : '';
  let existing = '';
  try { existing = fs.readFileSync(target, 'utf8'); } catch { /* new file */ }
  if (!HIGH_RISK_PATTERN.test(`${existing}\n${proposed}`)) return;

  const repoRoot = resolveRepo(data);
  if (!repoRoot) return;
  const result = runInspector(repoRoot, target, proposed);
  if (result.error || !result.stdout.trim()) {
    deny(`UI 影响面检查无法运行，已阻止这次高风险 UI 编辑。\n\n请先运行：python3 "$PMAI_HOME/scripts/ui-impact.py" inspect --repo-root "${repoRoot}" --path "${rawTarget}"\n\n原因：${result.error ? result.error.message : 'helper 返回空结果'}`);
    return;
  }
  let report;
  try { report = JSON.parse(result.stdout); } catch {
    deny('UI 影响面检查返回非法结果，已阻止这次高风险 UI 编辑。');
    return;
  }
  if (firstEdit(repoRoot, target) && report.status === 'needs-review') {
    const refs = (report.primitive_refs || [])
      .map(ref => `${ref.path}: ${(ref.constraints || []).join(', ')}`)
      .join('\n');
    deny(`首次高风险 UI 编辑已被 UI 影响面护栏阻止。\n\n${(report.findings || []).map(item => item.message).join('\n')}\n\n共享 primitive 约束：\n${refs || '未解析到 primitive'}\n\n先确认覆盖关系，并在页面改动中显式处理 cascade；通过后再继续。`);
    return;
  }
  if (report.requires_actual_size) {
    const resolution = report.status === 'limited'
      ? 'primitive 未完全解析，本轮只能记为 limited，不能声称已完成影响面检查。'
      : '共享 primitive / cascade 影响面已解析。';
    allow(`UI 影响面检查${report.status}。${resolution}该改动涉及尺寸/布局，完成后必须在 browser manifest 加入 size 断言，验证实际 computed width / height，而不是只看源码 class。`);
  }
}

let input = '';
let bytes = 0;
const timer = setTimeout(() => process.exit(0), 2500);
process.stdin.on('data', chunk => {
  bytes += chunk.length;
  if (bytes > MAX_STDIN_BYTES) process.exit(0);
  input += chunk.toString('utf8');
});
process.stdin.on('end', () => {
  clearTimeout(timer);
  try {
    const data = JSON.parse(input);
    if (data && typeof data === 'object' && !Array.isArray(data)) main(data);
  } catch {
    process.exit(0);
  }
});
