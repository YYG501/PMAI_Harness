#!/usr/bin/env python3
"""Validate the skill-eval summary against the evaluator exit status."""

from __future__ import annotations

import argparse
import re
import sys


SUMMARY_RE = re.compile(
    r"^SUMMARY passed=(\d+) failed=(\d+) skipped=(\d+) judge_skipped=(\d+)$"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--exit-code", type=int, required=True)
    args = parser.parse_args()

    matches = [
        match
        for line in sys.stdin.read().splitlines()
        if (match := SUMMARY_RE.fullmatch(line)) is not None
    ]
    if len(matches) != 1:
        print("skill eval 缺少唯一合法 SUMMARY", file=sys.stderr)
        return 2

    passed, failed, skipped, judge_skipped = map(int, matches[0].groups())
    if (failed == 0) != (args.exit_code == 0):
        print(
            f"skill eval SUMMARY 与退出码矛盾: failed={failed} exit={args.exit_code}",
            file=sys.stderr,
        )
        return 2
    print(passed, failed, skipped, judge_skipped)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
