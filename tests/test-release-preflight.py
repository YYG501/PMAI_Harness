from pathlib import Path
import importlib.util
import json
import os
import shlex
import sys
import tempfile
import unittest
from unittest.mock import patch
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('preflight', ROOT / 'scripts/release-gate-preflight.py')
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class ReleasePreflightTests(unittest.TestCase):
    def test_custom_adapters_do_not_require_codex_or_openai_key(self):
        environment = dict.fromkeys(preflight.CAPABILITIES, 'python3 custom-adapter.py')
        self.assertEqual(preflight.configured_engines(environment), {})
        self.assertFalse(preflight.needs_default_codex(environment))

    def test_provisioning_checks_runner_and_semantic_judge_independently(self):
        for capability, adapter in [('PMAI_SKILL_EVAL_RUNNER', 'skill-eval-codex-runner.py'),
                                    ('PMAI_SKILL_EVAL_SEMANTIC_JUDGE', 'skill-eval-semantic-judge.py')]:
            environment = dict.fromkeys(preflight.CAPABILITIES, 'python3 custom.py')
            environment[capability] = 'python3 scripts/' + adapter
            self.assertTrue(preflight.needs_default_codex(environment))
            environment.update(PMAI_CODEX_COMMAND='codex --profile ci', PMAI_JUDGE_CODEX_COMMAND='codex --profile judge')
            self.assertTrue(preflight.needs_default_codex(environment))
            environment.update(PMAI_CODEX_COMMAND='custom-codex', PMAI_JUDGE_CODEX_COMMAND='custom-judge')
            self.assertFalse(preflight.needs_default_codex(environment))

    def test_ci_plan_still_rejects_missing_judge(self):
        with self.assertRaisesRegex(ValueError, 'PMAI_SKILL_EVAL_SEMANTIC_JUDGE'):
            preflight.needs_default_codex(dict.fromkeys(preflight.CAPABILITIES[:-1], 'python3 custom.py'))

    def codex_environment(self):
        python = shlex.quote(sys.executable)
        return {
            'PMAI_SKILL_EVAL_RUNNER': python + ' scripts/skill-eval-codex-runner.py',
            'PMAI_SKILL_EVAL_JUDGE': python + ' scripts/skill-eval-readonly-judge.py',
            'PMAI_SKILL_EVAL_SEMANTIC_JUDGE': python + ' scripts/skill-eval-semantic-judge.py',
            'PMAI_CODEX_COMMAND': python,
            'PMAI_JUDGE_CODEX_COMMAND': python,
        }

    def test_cli_without_required_flags_is_blocked(self):
        with patch.object(preflight.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'old CLI', '')):
            with self.assertRaisesRegex(ValueError, 'adapter flags'):
                preflight.check_capabilities(ROOT, self.codex_environment())

    def test_cli_without_authentication_is_blocked(self):
        ready = '--json --ephemeral --approve-for-me --ignore-rules --skip-git-repo-check'
        responses = [subprocess.CompletedProcess([], 0, 'codex test', ''),
                     subprocess.CompletedProcess([], 0, ready, ''),
                     subprocess.CompletedProcess([], 1, '', 'not logged in')]
        with patch.object(preflight.subprocess, 'run', side_effect=responses):
            with self.assertRaisesRegex(ValueError, 'authentication is not ready'):
                preflight.check_capabilities(ROOT, self.codex_environment())

    def test_ready_cli_probes_both_engines_without_running_sessions(self):
        commands = []
        def probe(argv, **kwargs):
            commands.append(argv[1:])
            allowed = [['--version'], ['exec', '--help'], ['login', 'status']]
            self.assertIn(argv[1:], allowed)
            output = 'codex fixture' if argv[-1] == '--version' else '--json --ephemeral --approve-for-me --ignore-rules --skip-git-repo-check'
            return subprocess.CompletedProcess(argv, 0, output, '')
        with patch.object(preflight.subprocess, 'run', side_effect=probe):
            reports = preflight.check_capabilities(ROOT, self.codex_environment())
        self.assertEqual(len(commands), 6)
        self.assertEqual(len(reports), 5)

    def test_checked_in_suite_has_real_cases(self):
        selected = preflight.selected_cases(ROOT, {})
        self.assertGreater(len(selected), 1)
        self.assertIn('natural-language-finalize', selected)

    def test_empty_duplicate_or_reduced_selection_fails(self):
        for value in ['', '  ', 'natural-language-finalize', 'natural-language-finalize ' * 2]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                preflight.selected_cases(ROOT, {'PMAI_SESSION_EVAL_CASES': value})

    def test_unknown_case_fails(self):
        cases = preflight.selected_cases(ROOT, {}) + ['missing-case']
        with self.assertRaises(OSError):
            preflight.selected_cases(ROOT, {'PMAI_SESSION_EVAL_CASES': ' '.join(cases)})

    def test_missing_all_capabilities_named(self):
        with self.assertRaisesRegex(ValueError, ' '.join(preflight.CAPABILITIES)):
            preflight.check_capabilities(ROOT, {})

    def test_missing_semantic_judge_fails(self):
        environment = {key: shlex.quote(sys.executable) for key in preflight.CAPABILITIES[:-1]}
        with self.assertRaisesRegex(ValueError, 'PMAI_SKILL_EVAL_SEMANTIC_JUDGE'):
            preflight.check_capabilities(ROOT, environment)

    def test_missing_executable_or_script_fails(self):
        for command in ['pmai-nonexistent-executable', shlex.quote(sys.executable) + ' nonexistent.py']:
            with self.assertRaises(ValueError):
                preflight.command_ready(command, 'test', ROOT)

    def test_shell_syntax_is_not_executed(self):
        with self.assertRaises(ValueError):
            preflight.command_ready(shlex.quote(sys.executable) + ' && echo token', 'test', ROOT)

    def test_preflight_does_not_execute_arbitrary_adapters(self):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'adapter.py'
            script.write_text('raise RuntimeError("must not execute during preflight")')
            command = f'{shlex.quote(sys.executable)} {shlex.quote(str(script))}'
            reports = preflight.check_capabilities(ROOT, dict.fromkeys(preflight.CAPABILITIES, command))
            self.assertEqual(len(reports), 3)


if __name__ == '__main__':
    unittest.main()
