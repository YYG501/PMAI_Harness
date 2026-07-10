#!/usr/bin/env python3
"""Build and validate the post-land PMAI documentation coverage map."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


VALID_KINDS = {"object", "action", "state", "permission", "page", "term", "rule", "fact", "index", "mockup"}
VALID_STATUSES = {"pending", "covered", "no-change"}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"文件不存在: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"JSON 不合法: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"JSON 顶层必须是对象: {path}")
    return value


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def repo_root_for(module_dir: Path, override: str | None) -> Path:
    if override:
        return Path(override).expanduser().resolve()
    try:
        root = subprocess.check_output(
            ["git", "-C", str(module_dir), "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if root:
            return Path(root)
    except (OSError, subprocess.CalledProcessError):
        pass
    resolved = module_dir.resolve()
    if resolved.parent.name == "modules" and resolved.parent.parent.name == "docs":
        return resolved.parent.parent.parent
    raise SystemExit(f"无法定位仓库根目录: {module_dir}")


def rel(repo_root: Path, path: Path) -> str:
    return path.resolve().relative_to(repo_root.resolve()).as_posix()


def git_lines(repo_root: Path, *args: str) -> list[str]:
    try:
        output = subprocess.check_output(
            ["git", "-C", str(repo_root), *args],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return []
    return [line for line in output.splitlines() if line.strip()]


def git_success(repo_root: Path, *args: str) -> bool:
    try:
        subprocess.run(
            ["git", "-C", str(repo_root), *args],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def item_id(kind: str, name: str, destination: str) -> str:
    return hashlib.sha256(f"{kind}\0{name}\0{destination}".encode("utf-8")).hexdigest()[:12]


def coverage_item(
    kind: str,
    name: str,
    destination: str,
    reason: str,
    required: bool = True,
    status: str = "pending",
    note: str = "",
) -> dict:
    return {
        "id": item_id(kind, name, destination),
        "kind": kind,
        "name": name,
        "destination": destination,
        "reason": reason,
        "required": required,
        "status": status,
        "note": note,
    }


def output_path(repo_root: Path, module_dir: Path, override: str | None) -> Path:
    if override:
        candidate = Path(override).expanduser()
        return candidate if candidate.is_absolute() else repo_root / candidate
    return repo_root / ".pm-workflow" / "audits" / module_dir.name / "doc-impact.json"


def load_build(module_dir: Path) -> dict:
    meta = read_json(module_dir / ".work-meta.json")
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit(".work-meta.json 缺少 build 合同。")
    return build


def delta_signals(build: dict) -> tuple[set[str], set[str]]:
    kinds: set[str] = set()
    surfaces: set[str] = set()
    for delta in build.get("accepted_deltas", []) if isinstance(build.get("accepted_deltas"), list) else []:
        if not isinstance(delta, dict):
            continue
        kinds.add(str(delta.get("kind", "")))
        values = delta.get("affected_surfaces", [])
        if isinstance(values, list):
            surfaces.update(str(value) for value in values)
    return kinds, surfaces


def cmd_init(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir).expanduser().resolve()
    repo_root = repo_root_for(module_dir, args.repo_root)
    build = load_build(module_dir)
    base = args.base or build.get("baseline_sha")
    head = args.head or build.get("landed_commit") or "HEAD"
    changed_files = git_lines(repo_root, "diff", "--name-only", str(base), str(head)) if base else []
    module_rel = rel(repo_root, module_dir)
    kinds, surfaces = delta_signals(build)
    items = [
        coverage_item(
            "fact",
            f"{module_dir.name} 当前规格",
            f"{module_rel}/spec.md",
            "实现落地主线后，模块规格必须与当前产品行为一致",
        ),
        coverage_item(
            "fact",
            f"{module_dir.name} 当前产品状态",
            "PRODUCT-STATE.md",
            "当前产品事实只能在实现落地后更新",
        ),
        coverage_item(
            "rule",
            "跨模块现行规则",
            "PRODUCT-RULES.md",
            "确认 landed diff 是否改变跨模块产品行为；不影响时明确标记无需更新",
        ),
        coverage_item(
            "term",
            "产品定位与业务术语",
            "PRODUCT.md",
            "确认新增对象、角色和术语是否需要进入长期词典；不影响时明确标记无需更新",
        ),
        coverage_item(
            "rule",
            "设计与交互基线",
            "DESIGN.md",
            "确认最终实现是否形成可复用视觉或交互规则；不影响时明确标记无需更新",
        ),
        coverage_item(
            "fact",
            "后续事项",
            "TODO.md",
            "确认本轮是否明确留下未实现范围；没有时明确标记无需更新",
        ),
        coverage_item(
            "index",
            "模块索引",
            "docs/modules/INDEX.md",
            "确认模块或功能型规格索引是否变化；不影响时明确标记无需更新",
        ),
        coverage_item(
            "index",
            "文档总索引",
            "docs/INDEX.md",
            "确认是否新增文档类别或入口；不影响时明确标记无需更新",
        ),
    ]

    if build.get("accepted_deltas"):
        items.append(
            coverage_item(
                "rule",
                f"{module_dir.name} build 期间确认的决定",
                f"{module_rel}/decisions.md",
                "build 期间 PM 接受的产品变化必须留下决定依据",
            )
        )
    if (repo_root / "mockups" / "manifest.json").exists():
        items.append(
            coverage_item(
                "mockup",
                "设计稿看版状态",
                "mockups/manifest.json",
                "确认本轮是否吸收了设计稿；未吸收时明确标记无需更新",
            )
        )

    for index, delta in enumerate(build.get("accepted_deltas", []), 1):
        if not isinstance(delta, dict):
            continue
        delta_kind = str(delta.get("kind") or "fact")
        if delta_kind not in VALID_KINDS:
            delta_kind = "fact"
        delta_surfaces = [
            str(value)
            for value in delta.get("affected_surfaces", [])
            if isinstance(value, str)
        ]
        destination = next(
            (value for value in delta_surfaces if value.endswith((".md", ".json"))),
            f"{module_rel}/decisions.md",
        )
        items.append(
            coverage_item(
                delta_kind,
                str(delta.get("summary") or f"build 期间确认的变化 {index}"),
                destination,
                "PM 在 build 期间确认的产品变化必须有正式文档落点",
            )
        )

    payload = {
        "schema_version": 1,
        "created_at": now_iso(),
        "module": module_rel,
        "implementation_commit": build.get("implementation_commit"),
        "landed_commit": build.get("landed_commit"),
        "base": base,
        "head": head,
        "changed_files": changed_files,
        "items": items,
    }
    path = output_path(repo_root, module_dir, args.output)
    write_json(path, payload)
    print(path)


def find_item(payload: dict, item_id_value: str) -> dict:
    items = payload.get("items")
    if not isinstance(items, list):
        raise SystemExit("doc impact items 必须是数组。")
    for item in items:
        if isinstance(item, dict) and item.get("id") == item_id_value:
            return item
    raise SystemExit(f"找不到 doc impact item: {item_id_value}")


def cmd_add(args: argparse.Namespace) -> None:
    path = Path(args.map).expanduser()
    payload = read_json(path)
    if args.kind not in VALID_KINDS:
        raise SystemExit(f"未知影响类型: {args.kind}")
    item = coverage_item(args.kind, args.name, args.destination, args.reason or "最终差异影响该产品事实")
    items = payload.setdefault("items", [])
    if not isinstance(items, list):
        raise SystemExit("doc impact items 必须是数组。")
    if not any(isinstance(existing, dict) and existing.get("id") == item["id"] for existing in items):
        items.append(item)
    write_json(path, payload)
    print(item["id"])


def cmd_cover(args: argparse.Namespace) -> None:
    path = Path(args.map).expanduser()
    payload = read_json(path)
    item = find_item(payload, args.item)
    if args.status not in {"covered", "no-change"}:
        raise SystemExit("cover status 只能是 covered 或 no-change。")
    if args.status == "no-change" and not args.note:
        raise SystemExit("标记 no-change 时必须说明为什么无需修改文档。")
    item["status"] = args.status
    if args.file:
        item["destination"] = args.file
    item["note"] = args.note or ""
    item["checked_at"] = now_iso()
    write_json(path, payload)
    print(json.dumps(item, ensure_ascii=False))


def cmd_validate(args: argparse.Namespace) -> None:
    path = Path(args.map).expanduser()
    payload = read_json(path)
    items = payload.get("items")
    if not isinstance(items, list) or not items:
        raise SystemExit("文档影响地图为空，不能完成文档收尾。")
    bad = []
    for item in items:
        if not isinstance(item, dict):
            bad.append("<invalid-item>")
            continue
        status = item.get("status")
        if status not in VALID_STATUSES or (item.get("required", True) and status == "pending"):
            bad.append(f"{item.get('name', '?')} -> {item.get('destination', '?')}")
        if status == "no-change" and not item.get("note"):
            bad.append(f"{item.get('name', '?')} 缺少无需修改说明")
    if bad:
        raise SystemExit("文档影响尚未覆盖：" + "；".join(bad))
    payload["validated_at"] = now_iso()
    write_json(path, payload)
    print(json.dumps({"status": "pass", "items": len(items)}, ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="cmd", required=True)
    init = sub.add_parser("init")
    init.add_argument("module_dir")
    init.add_argument("--repo-root")
    init.add_argument("--base")
    init.add_argument("--head")
    init.add_argument("--output")
    init.set_defaults(func=cmd_init)

    add = sub.add_parser("add")
    add.add_argument("map")
    add.add_argument("--kind", required=True, choices=sorted(VALID_KINDS))
    add.add_argument("--name", required=True)
    add.add_argument("--destination", required=True)
    add.add_argument("--reason")
    add.set_defaults(func=cmd_add)

    cover = sub.add_parser("cover")
    cover.add_argument("map")
    cover.add_argument("--item", required=True)
    cover.add_argument("--status", required=True, choices=("covered", "no-change"))
    cover.add_argument("--file")
    cover.add_argument("--note")
    cover.set_defaults(func=cmd_cover)

    validate = sub.add_parser("validate")
    validate.add_argument("map")
    validate.set_defaults(func=cmd_validate)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        args.func(args)
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"❌ {exc.code}", file=sys.stderr)
            return 1
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
