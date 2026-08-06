#!/usr/bin/env python3
"""Run one shell test suite with a timeout and a validated result summary."""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
from pathlib import Path


SUMMARY_RE = re.compile(
    r"^\s*Passed:\s*(\d+)\s*$.*?^\s*Failed:\s*(\d+)\s*$",
    re.MULTILINE | re.DOTALL,
)


def write_result(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw_temp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp_path = Path(raw_temp)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
    finally:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass


def stop_process_group(process: subprocess.Popen[str]) -> str:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        output, _ = process.communicate(timeout=2)
        return output
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        output, _ = process.communicate()
        return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("--result-file", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    return args


def main() -> int:
    args = parse_args()
    payload: dict[str, object]
    try:
        process = subprocess.Popen(
            args.command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
    except OSError as exc:
        payload = {
            "status": "runner_error",
            "passed": 0,
            "failed": 1,
            "exit_code": None,
            "error": f"无法启动测试套件: {exc}",
        }
        write_result(args.result_file, payload)
        print(f"RUNNER ERROR: {payload['error']}", file=sys.stderr)
        return 1

    timed_out = False
    try:
        output, _ = process.communicate(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        output = stop_process_group(process)

    if output:
        print(output, end="" if output.endswith("\n") else "\n")

    if timed_out:
        payload = {
            "status": "timeout",
            "passed": 0,
            "failed": 1,
            "exit_code": process.returncode,
            "error": f"超过单套超时 {args.timeout:g}s",
        }
    else:
        summaries = SUMMARY_RE.findall(output or "")
        if len(summaries) != 1:
            payload = {
                "status": "malformed",
                "passed": 0,
                "failed": 1,
                "exit_code": process.returncode,
                "error": f"测试摘要格式异常：期望 1 组 Passed/Failed，实际 {len(summaries)} 组",
            }
        else:
            passed, failed = (int(value) for value in summaries[0])
            if passed + failed == 0:
                payload = {
                    "status": "malformed",
                    "passed": 0,
                    "failed": 1,
                    "exit_code": process.returncode,
                    "error": "测试摘要不能同时为 0",
                }
            elif process.returncode == 0 and failed > 0:
                payload = {
                    "status": "malformed",
                    "passed": passed,
                    "failed": failed,
                    "exit_code": process.returncode,
                    "error": "测试报告有失败项，但 suite 退出码为 0",
                }
            elif process.returncode != 0 and failed == 0:
                payload = {
                    "status": "failed",
                    "passed": passed,
                    "failed": 1,
                    "exit_code": process.returncode,
                    "error": "suite 非零退出，但摘要未报告失败项",
                }
            else:
                payload = {
                    "status": "passed" if process.returncode == 0 else "failed",
                    "passed": passed,
                    "failed": failed,
                    "exit_code": process.returncode,
                    "error": "",
                }

    write_result(args.result_file, payload)
    if payload["status"] != "passed":
        print(f"RUNNER ERROR: {payload['error']}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
