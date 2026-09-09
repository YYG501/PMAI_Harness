#!/usr/bin/env python3
"""Validate the release suite and local executables without running an Agent."""
from pathlib import Path
import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CAPABILITIES = ('PMAI_SKILL_EVAL_RUNNER', 'PMAI_SKILL_EVAL_JUDGE', 'PMAI_SKILL_EVAL_SEMANTIC_JUDGE')


def selected_cases(root, environment):
    manifest = json.loads((root / 'evals/release-suite.json').read_text(encoding='utf-8'))
    required = manifest.get('session_cases')
    if manifest.get('schema_version') != 1 or not isinstance(required, list) or not required:
        raise ValueError('release suite must contain session cases')
    if any(not isinstance(item, str) or not item for item in required) or len(set(required)) != len(required):
        raise ValueError('release suite contains invalid or duplicate cases')
    supplied = environment.get('PMAI_SESSION_EVAL_CASES')
    selected = supplied.split() if supplied is not None else list(required)
    if not selected or len(set(selected)) != len(selected):
        raise ValueError('release case selection is empty or duplicated')
    if not set(required).issubset(selected):
        raise ValueError('release selection cannot omit required core cases')
    for name in selected:
        if not name.replace('-', '').isalnum():
            raise ValueError('invalid release case id')
        case = json.loads((root / 'evals/cases' / f'{name}.json').read_text(encoding='utf-8'))
        if case.get('id') != name or case.get('layer') != 'session' or not case.get('harness') or not case.get('judge', {}).get('rubric'):
            raise ValueError(f'release case lacks a session harness or rubric: {name}')
    return selected


def command_ready(value, label, root):
    argv = shlex.split(value)
    if not argv:
        raise ValueError(f'{label}: empty command')
    executable = shutil.which(argv[0])
    if not executable:
        raise ValueError(f'{label}: executable unavailable')
    # Eval executes argv directly, so shell syntax must not masquerade as a
    # provisioned command. Never echo arbitrary command text or credentials.
    if any(item in {'|', '||', '&&', ';', '>'} for item in argv):
        raise ValueError(f'{label}: shell composition is not supported')
    for item in argv[1:]:
        if item.endswith('.py') and not (root / item).is_file():
            raise ValueError(f'{label}: Python adapter file unavailable')
    return argv, {'capability': label, 'executable': executable}


def configured_engines(environment):
    missing = [key for key in CAPABILITIES if not environment.get(key, '').strip()]
    if missing:
        raise ValueError('missing ' + ' '.join(missing))
    engines = {}
    for key in CAPABILITIES:
        argv = shlex.split(environment[key])
        names = {Path(item).name for item in argv}
        if 'skill-eval-codex-runner.py' in names:
            engines['PMAI_CODEX_COMMAND'] = environment.get('PMAI_CODEX_COMMAND') or 'codex'
        if 'skill-eval-semantic-judge.py' in names:
            engines['PMAI_JUDGE_CODEX_COMMAND'] = environment.get('PMAI_JUDGE_CODEX_COMMAND') or 'codex'
    return engines


def needs_default_codex(environment):
    return any(shlex.split(command)[:1] == ['codex'] for command in configured_engines(environment).values())


def check_capabilities(root, environment):
    engines = configured_engines(environment)
    reports = []
    for key in CAPABILITIES:
        _, report = command_ready(environment[key], key, root)
        reports.append(report)
    for key, value in engines.items():
        argv, report = command_ready(value, key, root)
        version = subprocess.run([*argv, '--version'], cwd=root, capture_output=True, text=True, timeout=10)
        help_result = subprocess.run([*argv, 'exec', '--help'], cwd=root, capture_output=True, text=True, timeout=10)
        required_flags = ('--json', '--ephemeral', '--approve-for-me', '--ignore-rules', '--skip-git-repo-check')
        if version.returncode or help_result.returncode or any(flag not in help_result.stdout for flag in required_flags):
            raise ValueError(f'{key}: CLI version does not satisfy the checked-in adapter flags')
        auth = subprocess.run([*argv, 'login', 'status'], cwd=root, capture_output=True, timeout=10)
        if auth.returncode:
            raise ValueError(f'{key}: CLI authentication is not ready')
        report['version'] = version.stdout.strip()[:160]
        reports.append(report)
    return reports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases-only', action='store_true')
    parser.add_argument('--ci-plan', action='store_true', help='print required default CLI provisioning without executing adapters')
    args = parser.parse_args()
    try:
        cases = selected_cases(ROOT, os.environ)
        if args.cases_only:
            print(' '.join(cases))
            return 0
        if args.ci_plan:
            print('needs_codex=' + str(needs_default_codex(os.environ)).lower())
            return 0
        env_check = subprocess.run([sys.executable, str(ROOT / 'scripts/environment-check.py'), 'check', '--profile', 'host', '--root', str(ROOT), '--json'], cwd=ROOT, capture_output=True, text=True, timeout=30)
        if env_check.returncode:
            raise ValueError('runtime requirements failed; run scripts/environment-check.py check --profile host')
        runtime = json.loads(env_check.stdout)
        if not isinstance(runtime, dict) or runtime.get('status') != 'pass' or not runtime.get('checks'):
            raise ValueError('runtime checker returned no passing evidence')
        capabilities = check_capabilities(ROOT, os.environ)
        revision = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
        dirty = bool(subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'], text=True))
        print(json.dumps({'schema_version': 1, 'framework_revision': revision, 'dirty': dirty,
                          'session_cases': cases, 'capabilities': capabilities, 'environment': runtime}, ensure_ascii=False))
        return 0
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        print(f'Release gate blocked: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
