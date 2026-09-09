#!/usr/bin/env python3
"""Read-only runtime diagnostics shared by installed doctor and release checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import operator
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = {"python", "git", "bash", "node"}
OPERATORS = {">=": operator.ge, "<=": operator.le, ">": operator.gt,
             "<": operator.lt, "==": operator.eq}
CONSTRAINT = re.compile(r"(>=|<=|==|>|<)(\d+(?:\.\d+){0,2})")
VERSION = re.compile(r"(?<![\w.])v?(\d+)\.(\d+)(?:\.(\d+))?(?!\d)")
NODE_PROBE = """
const fs = require('fs');
const vm = require('vm');
const cp = require('child_process');
if (typeof fs.realpathSync.native !== 'function' ||
    typeof process.hrtime.bigint !== 'function' ||
    typeof cp.spawnSync !== 'function') process.exit(1);
new TextDecoder('utf-8', {fatal: true}).decode(Buffer.from('pmai'));
const hookFiles = fs.readdirSync('hooks').filter(n => n.endsWith('.cjs'));
if (!hookFiles.length) process.exit(1);
for (const name of hookFiles) {
  new vm.Script(fs.readFileSync('hooks/' + name, 'utf8'), {filename: name});
}
process.stdout.write('pmai-node-hooks-ok');
"""


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False).encode("utf-8")).hexdigest()


def constraints(value):
    if not isinstance(value, str) or not value:
        raise ValueError("version constraint must be a nonempty string")
    result = []
    for part in value.split(","):
        match = CONSTRAINT.fullmatch(part.strip())
        if not match:
            raise ValueError("invalid version constraint")
        version = tuple(int(n) for n in match[2].split("."))
        result.append((OPERATORS[match[1]], version + (0,) * (3 - len(version))))
    return result


def version_tuple(value):
    match = VERSION.search(value)
    return tuple(int(n or 0) for n in match.groups()) if match else None


def satisfies(actual, constraint):
    rules = constraints(constraint)
    version = version_tuple(actual)
    return version is not None and all(compare(version, target) for compare, target in rules)


def load_manifest(root):
    manifest = json.loads((root / "config/runtime-manifest.json").read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or set(manifest) != {"schema_version", "requirements", "profiles"}:
        raise ValueError("invalid runtime manifest fields")
    if type(manifest["schema_version"]) is not int or manifest["schema_version"] != 1:
        raise ValueError("unsupported runtime manifest schema")
    requirements, profiles = manifest["requirements"], manifest["profiles"]
    if not isinstance(requirements, dict) or set(requirements) != TOOLS:
        raise ValueError("runtime requirements must cover python, git, bash and node")
    for name, requirement in requirements.items():
        if not isinstance(requirement, dict) or set(requirement) != {"version", "remedy"}:
            raise ValueError("invalid runtime requirement")
        if requirement["version"] is not None:
            constraints(requirement["version"])
        elif name != "node":
            raise ValueError("core runtimes require a minimum version")
        if not isinstance(requirement["remedy"], str) or not requirement["remedy"].strip():
            raise ValueError("runtime requirement lacks a remedy")
    if not isinstance(profiles, dict) or set(profiles) != {"core", "host"}:
        raise ValueError("runtime profiles must be core and host")
    for name, tools in profiles.items():
        if not isinstance(tools, list) or not tools or any(not isinstance(t, str) for t in tools):
            raise ValueError("invalid runtime profile")
        expected = TOOLS - {"node"} if name == "core" else TOOLS
        if set(tools) != expected or len(tools) != len(expected):
            raise ValueError("runtime profile has missing, duplicate or unknown tools")
    return manifest


def run(argv, root):
    try:
        result = subprocess.run(argv, cwd=root, capture_output=True, text=True, timeout=3)
    except FileNotFoundError:
        return "missing", ""
    except subprocess.TimeoutExpired:
        return "timeout", ""
    except (OSError, UnicodeError):
        return "unavailable", ""
    return ("ok" if result.returncode == 0 else "command_failed"), result.stdout.strip()


def snapshot(root, profile):
    manifest = load_manifest(root)
    if profile not in manifest["profiles"]:
        raise ValueError("unknown runtime profile")
    checks = []
    for name in manifest["profiles"][profile]:
        executable = sys.executable if name == "python" else name
        code, output = run([executable, "--version"], root)
        actual = version_tuple(output) if code == "ok" else None
        requirement = manifest["requirements"][name]
        if code == "ok" and actual is None:
            code = "unknown_version"
        if code == "ok" and requirement["version"] and not satisfies(output, requirement["version"]):
            code = "unsupported_version"
        if code == "ok" and name == "node":
            code, marker = run([executable, "-e", NODE_PROBE], root)
            if code == "ok" and marker != "pmai-node-hooks-ok":
                code = "capability_failed"
        checks.append({"name": name, "status": "pass" if code == "ok" else "fail",
                       "code": code, "version": ".".join(map(str, actual)) if actual else None,
                       "required": requirement["version"] or "hook syntax and Node APIs",
                       "remedy": requirement["remedy"] if code != "ok" else ""})
    result = {"schema_version": 1, "manifest_hash": digest(manifest), "profile": profile,
              "platform": sys.platform, "checks": checks,
              "status": "pass" if all(c["status"] == "pass" for c in checks) else "fail"}
    result["snapshot_digest"] = digest(result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "snapshot"])
    parser.add_argument("--profile", choices=["core", "host"], default="core")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        result = snapshot(args.root.resolve(), args.profile)
    except (ValueError, OSError) as exc:
        # Do not echo arbitrary file content or subprocess output into diagnostics.
        result = {"schema_version": 1, "status": "fail", "code": "manifest_invalid",
                  "message": "Runtime manifest is missing or invalid; restore the framework installation.",
                  "error_type": type(exc).__name__}
    if args.json or args.command == "snapshot":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif "checks" in result:
        for check in result["checks"]:
            print(f"{check['name']}: {check['status']} ({check['version'] or check['code']}; "
                  f"requires {check['required']})" + (f". {check['remedy']}" if check['remedy'] else ""))
    else:
        print(result["message"])
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
