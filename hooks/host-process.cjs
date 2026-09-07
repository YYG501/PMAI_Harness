// Explicit Windows/Cygwin process boundary used only by PMAI hooks.
const path = require('path');
const childProcess = require('child_process');

function runtimeRoot() {
  return process.platform === 'win32' ? process.env.PMAI_WINDOWS_RUNTIME : null;
}

function convertPath(value, mode, timeout = 800) {
  const root = runtimeRoot();
  if (!root || typeof value !== 'string') return value;
  const needsConversion = mode === '-w' ? value.startsWith('/') : /^(?:[A-Za-z]:[\\/]|\\\\)/.test(value);
  if (!needsConversion) return value;
  const result = childProcess.spawnSync(path.join(root, 'bin', 'cygpath.exe'), [mode, value], {
    encoding: 'utf8', timeout, windowsHide: true,
  });
  if (result.status !== 0 || !result.stdout.trim()) throw new Error('Windows/Cygwin 路径转换失败。');
  return result.stdout.trim();
}

function nativePath(value) { return convertPath(value, '-w'); }

function spawnSync(command, args, options = {}) {
  const root = runtimeRoot();
  if (!root) return childProcess.spawnSync(command, args, options);
  const deadline = process.hrtime.bigint() + BigInt(options.timeout || 5000) * 1_000_000n;
  const remaining = maximum => {
    const value = Number((deadline - process.hrtime.bigint()) / 1_000_000n);
    if (value <= 0) throw new Error('Windows 宿主进程校验超时。');
    return Math.min(maximum, value);
  };
  if (command === 'python3') {
    // Use the Cygwin PATH so test shims and installed Python selection remain
    // observable. Native Windows Node cannot execute Cygwin symlink launchers.
    const converted = args.map(value => convertPath(value, '-u', remaining(800)));
    return childProcess.spawnSync(path.join(root, 'bin', 'bash.exe'),
      ['--noprofile', '--norc', '-c', 'exec python3 "$@"', 'pmai-python', ...converted],
      { ...options, timeout: remaining(options.timeout || 5000), windowsHide: true });
  }
  const converted = command === 'git'
    ? args.map(value => convertPath(value, '-u', remaining(800))) : args;
  const result = command === 'git'
    ? childProcess.spawnSync(path.join(root, 'bin', 'bash.exe'),
      ['--noprofile', '--norc', '-c', 'exec git "$@"', 'pmai-git', ...converted],
      { ...options, timeout: remaining(options.timeout || 5000), windowsHide: true })
    : childProcess.spawnSync(command, converted, {
      ...options, timeout: remaining(options.timeout || 5000), windowsHide: true,
    });
  if (command === 'git' && args.includes('--show-toplevel') && result.status === 0) {
    result.stdout = convertPath(String(result.stdout).trim(), '-w', remaining(800)) + '\n';
  }
  return result;
}

module.exports = { spawnSync, nativePath };
