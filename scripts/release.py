#!/usr/bin/env python3
"""Prepare, verify, and publish a PMAI generator release."""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import subprocess
import sys
from pathlib import Path


SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
VERSION_HEADING_RE = re.compile(r"^##\s+v(\d+\.\d+\.\d+)(?:\s|$)")
NO_UNRELEASED_TEXT = "（暂无未发布变更）"


class ReleaseError(RuntimeError):
    pass


def git(root: Path, *args: str, capture: bool = False) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=root,
        text=True,
        capture_output=capture,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise ReleaseError(f"git {' '.join(args)} 失败{(': ' + detail) if detail else ''}")
    return result.stdout.strip() if capture else ""


def repo_root() -> Path:
    root = Path.cwd().resolve()
    try:
        detected = Path(git(root, "rev-parse", "--show-toplevel", capture=True)).resolve()
    except ReleaseError as exc:
        raise ReleaseError("必须在 PMAI 生成器 Git 仓根目录执行 release") from exc
    if detected != root:
        raise ReleaseError(f"当前目录不是 Git 仓根目录：{root}")
    for required in ("VERSION", "CHANGELOG.md", "bin/pmai", "scripts/release-gate-preflight.py"):
        if not (root / required).is_file():
            raise ReleaseError(f"当前仓不是 PMAI 生成器仓，缺少 {required}")
    return root


def normalize_version(raw: str) -> tuple[str, tuple[int, int, int]]:
    value = raw.strip()
    if value.startswith("v"):
        value = value[1:]
    match = SEMVER_RE.fullmatch(value)
    if not match:
        raise ReleaseError(f"版本必须是 X.Y.Z 或 vX.Y.Z：{raw}")
    parts = tuple(int(item) for item in match.groups())
    return value, parts


def read_version(root: Path) -> tuple[str, tuple[int, int, int]]:
    try:
        return normalize_version((root / "VERSION").read_text(encoding="utf-8"))
    except OSError as exc:
        raise ReleaseError(f"无法读取 VERSION：{exc}") from exc


def resolve_target(root: Path, version: str | None, bump: str | None) -> tuple[str, tuple[int, int, int]]:
    current_text, current = read_version(root)
    if version and bump:
        raise ReleaseError("--version 和 --bump 只能选一个")
    if version:
        target_text, target = normalize_version(version)
    else:
        if not bump:
            raise ReleaseError("需要 --version vX.Y.Z 或 --bump patch|minor|major")
        major, minor, patch = current
        if bump == "major":
            target = (major + 1, 0, 0)
        elif bump == "minor":
            target = (major, minor + 1, 0)
        else:
            target = (major, minor, patch + 1)
        target_text = ".".join(str(item) for item in target)
    if target <= current:
        raise ReleaseError(f"目标版本 v{target_text} 必须高于当前 v{current_text}")
    return target_text, target


def section_bounds(lines: list[str], heading: str) -> tuple[int, int]:
    start = next((index for index, line in enumerate(lines) if line.rstrip("\n") == heading), None)
    if start is None:
        raise ReleaseError(f"CHANGELOG.md 缺少 {heading} section")
    end = next(
        (index for index in range(start + 1, len(lines)) if lines[index].startswith("## ")),
        len(lines),
    )
    return start, end


def meaningful_unreleased(body: str) -> bool:
    for line in body.splitlines():
        value = line.strip()
        if not value or value.startswith("<!--") or value == NO_UNRELEASED_TEXT:
            continue
        return True
    return False


def version_section_body(text: str, target: str) -> str | None:
    lines = text.splitlines()
    target_tuple = normalize_version(target)[1]
    start = None
    for index, line in enumerate(lines):
        match = VERSION_HEADING_RE.match(line.rstrip("\n"))
        if match and normalize_version(match.group(1))[1] == target_tuple:
            start = index
            break
    if start is None:
        return None
    end = next((index for index in range(start + 1, len(lines)) if lines[index].startswith("## ")), len(lines))
    return "\n".join(lines[start + 1 : end]).strip()


def prepare_files(root: Path, target: str, release_date: str) -> int:
    changelog_path = root / "CHANGELOG.md"
    try:
        text = changelog_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ReleaseError(f"无法读取 CHANGELOG.md：{exc}") from exc
    lines = text.splitlines(keepends=True)
    start, end = section_bounds(lines, "## 未发布")
    body = "".join(lines[start + 1 : end]).strip()
    if not meaningful_unreleased(body):
        raise ReleaseError("## 未发布 没有可归档的变更，拒绝创建空版本")
    if version_section_body(text, target) is not None:
        raise ReleaseError(f"CHANGELOG.md 已存在 v{target} section")

    replacement = (
        "## 未发布\n\n"
        f"{NO_UNRELEASED_TEXT}\n\n"
        f"## v{target} — {release_date}\n\n"
        f"{body}\n\n"
    )
    new_text = "".join(lines[:start]) + replacement + "".join(lines[end:])
    try:
        changelog_path.write_text(new_text, encoding="utf-8")
        (root / "VERSION").write_text(f"{target}\n", encoding="utf-8")
    except OSError as exc:
        raise ReleaseError(f"写入 release 文件失败：{exc}") from exc
    return len([line for line in body.splitlines() if line.strip()])


def ensure_clean(root: Path) -> None:
    if git(root, "status", "--porcelain", capture=True):
        raise ReleaseError("工作区有未提交改动，release 操作要求先收口")


def ensure_main(root: Path) -> None:
    branch = git(root, "branch", "--show-current", capture=True)
    if branch not in {"main", "master"}:
        raise ReleaseError(f"release 只能从 main/master 执行，当前是 {branch or 'detached HEAD'}")


def ensure_tag_absent(root: Path, target: str) -> None:
    tag = f"v{target}"
    if subprocess.run(["git", "rev-parse", "--verify", f"refs/tags/{tag}"], cwd=root, capture_output=True).returncode == 0:
        raise ReleaseError(f"本地已经存在 {tag}")


def release_check(root: Path, target: str) -> None:
    current_text, _ = read_version(root)
    target_text, _ = normalize_version(target)
    if target_text != current_text:
        raise ReleaseError(f"发布目标 v{target_text} 与当前 VERSION v{current_text} 不一致")
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    if version_section_body(changelog, target_text) is None:
        raise ReleaseError(f"CHANGELOG.md 缺少 v{target_text} section")
    lines = changelog.splitlines(keepends=True)
    start, end = section_bounds(lines, "## 未发布")
    if meaningful_unreleased("".join(lines[start + 1 : end])):
        raise ReleaseError("release commit 仍有未发布变更，先运行 pmai release prepare")
    ensure_clean(root)
    ensure_main(root)
    ensure_tag_absent(root, target_text)


def prepare_command(args: argparse.Namespace) -> int:
    root = repo_root()
    ensure_clean(root)
    ensure_main(root)
    target, _ = resolve_target(root, args.version, args.bump)
    ensure_tag_absent(root, target)
    release_date = args.date or dt.datetime.utcnow().date().isoformat()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", release_date):
        raise ReleaseError(f"--date 必须是 YYYY-MM-DD：{release_date}")
    entries = prepare_files(root, target, release_date)
    try:
        git(root, "add", "VERSION", "CHANGELOG.md")
        git(root, "commit", "-m", f"release: v{target}")
    except ReleaseError:
        # 保留候选文件，避免把提交钩子或用户配置的失败吞掉。
        raise
    print(f"已准备 release v{target}，归档 {entries} 行未发布变更。")
    print("下一步：运行 pmai release publish（先执行 stable release gate，再推送 main 和 Tag）。")
    return 0


def check_command(args: argparse.Namespace) -> int:
    root = repo_root()
    if args.version or args.bump:
        target, _ = resolve_target(root, args.version, args.bump)
        changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
        start, end = section_bounds(changelog.splitlines(keepends=True), "## 未发布")
        if not meaningful_unreleased("".join(changelog.splitlines(keepends=True)[start + 1 : end])):
            raise ReleaseError("## 未发布 没有可归档的变更")
        print(f"候选版本：v{target}")
    else:
        print("版本与 CHANGELOG 预检通过。")
        target, _ = read_version(root)
        release_check(root, target)
        print(f"release v{target} 结构预检通过。")
    return 0


def run_release_gate(root: Path) -> None:
    gate = root / "tests" / "run-release-gate.sh"
    if not gate.is_file():
        raise ReleaseError(f"缺少 stable release gate：{gate}")
    result = subprocess.run(["bash", str(gate)], cwd=root, check=False)
    if result.returncode != 0:
        raise ReleaseError("stable release gate 未通过，未创建 Tag 或推送")


def ensure_remote_tag_absent(root: Path, target: str) -> None:
    tag = f"v{target}"
    result = subprocess.run(
        ["git", "ls-remote", "--exit-code", "--tags", "origin", f"refs/tags/{tag}"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode == 0:
        raise ReleaseError(f"远端已经存在 {tag}")
    if result.returncode != 2:
        detail = (result.stderr or result.stdout or "").strip()
        raise ReleaseError(f"无法确认远端 Tag 是否存在{(': ' + detail) if detail else ''}")


def ensure_remote_ready(root: Path, branch: str) -> None:
    try:
        git(root, "fetch", "origin", branch)
    except ReleaseError as exc:
        raise ReleaseError("无法确认 origin/main，拒绝发布") from exc
    head = git(root, "rev-parse", "HEAD", capture=True)
    remote = git(root, "rev-parse", f"origin/{branch}", capture=True)
    if head == remote:
        return
    if subprocess.run(["git", "merge-base", "--is-ancestor", remote, head], cwd=root).returncode != 0:
        raise ReleaseError("origin/main 含有本地未合并的新提交，先拉取并解决后再发布")


def publish_command(args: argparse.Namespace) -> int:
    root = repo_root()
    current, _ = read_version(root)
    target, _ = normalize_version(args.version or current)
    release_check(root, target)
    branch = git(root, "branch", "--show-current", capture=True)
    ensure_remote_ready(root, branch)
    ensure_remote_tag_absent(root, target)
    print(f"→ 运行 stable release gate（v{target}）")
    run_release_gate(root)
    git(root, "push", "origin", branch)
    tag = f"v{target}"
    git(root, "tag", "-a", tag, "-m", f"PMAI {tag}")
    git(root, "push", "origin", tag)
    print(f"已发布 {tag}：main 和 Tag 已推送。GitHub Actions 将在 Tag 上创建 Release。")
    return 0


def notes_command(args: argparse.Namespace) -> int:
    root = repo_root()
    target, _ = normalize_version(args.version)
    current, _ = read_version(root)
    if current != target:
        raise ReleaseError(f"Tag v{target} 与 VERSION v{current} 不一致")
    text = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    body = version_section_body(text, target)
    if body is None:
        raise ReleaseError(f"CHANGELOG.md 缺少 v{target} section")
    print(body)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="PMAI generator release workflow")
    sub = parser.add_subparsers(dest="command", required=True)

    prepare = sub.add_parser("prepare", help="archive unreleased changes, bump VERSION, and commit a candidate")
    prepare_group = prepare.add_mutually_exclusive_group(required=True)
    prepare_group.add_argument("--version")
    prepare_group.add_argument("--bump", choices=("patch", "minor", "major"))
    prepare.add_argument("--date")
    prepare.set_defaults(func=prepare_command)

    check = sub.add_parser("check", help="check a candidate or the current release commit")
    check_group = check.add_mutually_exclusive_group()
    check_group.add_argument("--version")
    check_group.add_argument("--bump", choices=("patch", "minor", "major"))
    check.set_defaults(func=check_command)

    publish = sub.add_parser("publish", help="run the stable gate, push main, and push the release tag")
    publish.add_argument("--version")
    publish.set_defaults(func=publish_command)

    notes = sub.add_parser("notes", help="print the versioned CHANGELOG body")
    notes.add_argument("--version", required=True)
    notes.set_defaults(func=notes_command)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ReleaseError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
