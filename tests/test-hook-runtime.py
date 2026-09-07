"""Exercise real hook processes and repository classification on each OS."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ['decision-gate-guard.cjs', 'finalize-route-guard.cjs']


class HookRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pmai-hook-runtime-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.consumer = self.repo('consumer')
        (self.consumer / '.pm-workflow').mkdir()
        (self.consumer / '.pm-workflow/config.yml').write_text('version: 1\n')
        self.ordinary = self.repo('ordinary')
        self.generator = self.repo('generator')
        for name in ['RUNTIME.md', 'CLAUDE.md', 'skills/init-project/SKILL.md']:
            target = self.generator / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('PMAI\n')
        # Use this test's Python for the real identity resolver. Other Python
        # subprocesses are controlled failures/results, not real Agent evals.
        self.preload = self.base / 'subprocess.cjs'
        self.preload.write_text('''
const cp = require('child_process');
const original = cp.spawnSync;
cp.spawnSync = (command, args, options) => {
  const mode = process.env.PMAI_TEST_FAILURE;
  const bridged = /[\\\\/]bash\\.exe$/.test(command) && args[4] === 'pmai-python';
  const python = command === 'python3' || bridged;
  const pythonArgs = bridged ? args.slice(5) : args;
  const git = command === 'git' || (/[\\\\/]bash\\.exe$/.test(command) && args[4] === 'pmai-git');
  if ((git && mode === 'git') || (python && mode === 'python'))
    return {status: null, error: Object.assign(new Error('missing'), {code: 'ENOENT'})};
  if (!python) return original(command, args, options);
  if (pythonArgs[0].endsWith('repo-kind.py')) return bridged
    ? original(command, args, options) : original(process.env.PMAI_TEST_PYTHON, args, options);
  if (mode === 'checker') return {status: 2, stdout: '', stderr: 'checker failed'};
  if (mode === 'checker-timeout') return {status: null, error: Object.assign(new Error('timeout'), {code: 'ETIMEDOUT'})};
  if (mode === 'bad-result') return {status: 0, stdout: '{'};
  if (mode === 'unknown-result') return {status: 0, stdout: '{"status":"surprise"}'};
  return {status: 0, stdout: '{"status":"none","active_builds":[]}'};
};
if (process.env.PMAI_TEST_FAILURE === 'stdin')
  process.nextTick(() => process.stdin.emit('error', new Error('fixture')));
''', encoding='utf-8')

    def repo(self, name):
        directory = self.base / name
        directory.mkdir()
        subprocess.run(['git', 'init', '-q', str(directory)], check=True, capture_output=True)
        return directory.resolve()

    def run_hook(self, hook, payload, cwd=None, failure=''):
        env = dict(os.environ, PMAI_TEST_PYTHON=sys.executable, PMAI_TEST_FAILURE=failure)
        command = [shutil.which('node'), '--require', str(self.preload), str(ROOT / 'hooks' / hook)]
        return subprocess.run(command, cwd=cwd or self.consumer, env=env,
                              input=payload, text=True, encoding='utf-8',
                              capture_output=True, timeout=9)

    def tool(self, **updates):
        return json.dumps(dict(hook_event_name='PreToolUse', cwd=str(self.consumer),
                               tool_name='Bash', tool_input={'command': 'git status'}, **updates))

    def assert_blocked(self, result):
        if result.returncode == 2:
            self.assertTrue(result.stderr.strip())
            return
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_bad_input_is_blocked_in_consumer(self):
        for hook in HOOKS:
            for data in ['', '{', '[]', 'null', '123', '{}', '{"prompt":false}']:
                with self.subTest(hook=hook, data=data):
                    self.assert_blocked(self.run_hook(hook, data))

    def test_ordinary_and_generator_are_noop(self):
        for hook in HOOKS:
            for cwd in [self.ordinary, self.generator]:
                result = self.run_hook(hook, '{', cwd=cwd)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, '', ''))

    def test_payload_cannot_select_other_repository(self):
        for hook in HOOKS:
            for value in [str(self.ordinary), None, [], '']:
                payload = json.loads(self.tool())
                payload['cwd'] = value
                self.assert_blocked(self.run_hook(hook, json.dumps(payload)))

    def test_malformed_tool_input_is_blocked(self):
        for hook in HOOKS:
            for value in [None, [], {}, {'command': False}]:
                payload = json.loads(self.tool())
                payload['tool_input'] = value
                self.assert_blocked(self.run_hook(hook, json.dumps(payload)))
            payload['tool_name'] = 'Write'
            payload['tool_input'] = {'file_path': []}
            self.assert_blocked(self.run_hook(hook, json.dumps(payload)))

    def test_conflicting_event_is_blocked(self):
        for hook in HOOKS:
            self.assert_blocked(self.run_hook(hook, self.tool(hookEventName='UserPromptSubmit')))

    def test_dependencies_fail_closed(self):
        for hook in HOOKS:
            for failure in ['git', 'python']:
                self.assert_blocked(self.run_hook(hook, self.tool(), failure=failure))

    def test_oversized_stdin_is_blocked(self):
        for hook in HOOKS:
            self.assert_blocked(self.run_hook(hook, ' ' * (4 * 1024 * 1024 + 1)))

    def test_stdin_error_is_blocked(self):
        for hook in HOOKS:
            self.assert_blocked(self.run_hook(hook, '', failure='stdin'))

    def test_stdin_timeout_exits_before_host_timeout(self):
        for hook in HOOKS:
            env = dict(os.environ, PMAI_TEST_PYTHON=sys.executable)
            process = subprocess.Popen([shutil.which('node'), '--require', str(self.preload),
                                        str(ROOT / 'hooks' / hook)], cwd=self.consumer, env=env,
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                process.wait(timeout=8)
                self.assertEqual(process.returncode, 2)
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()

    def test_checker_failures_block_prompt(self):
        for hook in HOOKS:
            for failure in ['checker', 'checker-timeout', 'bad-result', 'unknown-result']:
                payload = json.dumps({'hook_event_name': 'UserPromptSubmit', 'prompt': '可以提交了'})
                self.assert_blocked(self.run_hook(hook, payload, failure=failure))

    def test_valid_requests_stay_allowed(self):
        for hook in HOOKS:
            for data in [self.tool(), json.dumps({'prompt': '看看进度'})]:
                result = self.run_hook(hook, data)
                self.assertEqual((result.returncode, result.stdout), (0, ''), result.stderr)

    def test_protected_write_checker_failure_is_denied(self):
        result = self.run_hook(HOOKS[0], json.dumps({'tool_name': 'Write',
            'tool_input': {'file_path': str(self.consumer / 'PRODUCT.md')}}), failure='checker')
        self.assert_blocked(result)


if __name__ == '__main__':
    unittest.main()
