#!/usr/bin/env python3
"""Build and validate the post-land PMAI documentation coverage map."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

from _lib.candidate_binding import validate_candidate_binding


VALID_KINDS = {"object", "action", "state", "permission", "page", "term", "rule", "fact", "index", "mockup"}
VALID_STATUSES = {"pending", "covered", "no-change"}
SCHEMA_VERSION = 2


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


def load_work(module_dir: Path) -> tuple[dict, dict]:
    meta = read_json(module_dir / ".work-meta.json")
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit(".work-meta.json 缺少 build 合同。")
    return meta, build


def canonical_digest(value: object) -> str:
    return hashlib.sha256(
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()


def resolve_commit(repo_root: Path, value: object, label: str) -> str:
    ref = str(value or "").strip()
    if not ref:
        raise SystemExit(f"{label} 不能为空。")
    result = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "--verify", f"{ref}^{{commit}}"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or f"{label} 不是当前仓库提交：{ref}")
    return result.stdout.strip()


def map_binding(
    repo_root: Path,
    module_dir: Path,
    meta: dict,
    build: dict,
    *,
    base: object | None = None,
    head: object | None = None,
) -> dict:
    candidate_binding = build.get("candidate_binding")
    if candidate_binding is not None:
        try:
            candidate = validate_candidate_binding(repo_root, build)
        except ValueError as exc:
            raise SystemExit(str(exc)) from exc
        expected_base = str(candidate["base_commit"])
        expected_head = str(candidate["source_commit"])
        diff_mode = str(candidate["diff_mode"])
        target_paths = list(candidate["target_paths"])
        candidate_digest = candidate.get("target_tree_digest")
        candidate_binding_digest = candidate.get("binding_digest")
    else:
        expected_base = resolve_commit(
            repo_root, build.get("baseline_sha"), "build.baseline_sha"
        )
        expected_head = resolve_commit(
            repo_root,
            build.get("landed_commit") or build.get("implementation_commit"),
            "build landed/implementation commit",
        )
        diff_mode = "commit-range"
        target = build.get("target")
        target_paths = (
            [str(value) for value in target.get("paths", [])]
            if isinstance(target, dict) and isinstance(target.get("paths"), list)
            else []
        )
        candidate_digest = None
        candidate_binding_digest = None
    base_commit = resolve_commit(repo_root, base or expected_base, "doc impact base")
    head_commit = resolve_commit(repo_root, head or expected_head, "doc impact head")
    if base_commit != expected_base:
        raise SystemExit("doc impact base 与当前 candidate binding 不一致。")
    if head_commit != expected_head:
        raise SystemExit("doc impact head 与当前 candidate binding 不一致。")
    accepted_deltas = build.get("accepted_deltas", [])
    if not isinstance(accepted_deltas, list) or any(
        not isinstance(delta, dict) for delta in accepted_deltas
    ):
        raise SystemExit("build.accepted_deltas 必须是对象数组。")
    binding = {
        "work_id": str(meta.get("id") or ""),
        "module": rel(repo_root, module_dir),
        "implementation_commit": str(build.get("implementation_commit") or ""),
        "landed_commit": str(build.get("landed_commit") or ""),
        "base": base_commit,
        "head": head_commit,
        "approved_source_hash": str(build.get("approved_source_hash") or ""),
        "accepted_deltas_digest": canonical_digest(accepted_deltas),
        "candidate_tree_digest": candidate_digest,
        "candidate_binding_digest": candidate_binding_digest,
        "candidate_diff_mode": diff_mode,
        "candidate_target_paths": target_paths,
    }
    binding["binding_digest"] = canonical_digest(binding)
    return binding


def current_binding_for_map(path: Path, payload: dict) -> tuple[Path, Path, dict]:
    result = subprocess.run(
        ["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise SystemExit(result.stderr.strip() or "无法定位 doc impact 所属仓库。")
    repo_root = Path(result.stdout.strip()).resolve()
    module_value = payload.get("module")
    if not isinstance(module_value, str) or not module_value.strip():
        raise SystemExit("doc impact 缺少 module 绑定。")
    module_path = PurePosixPath(module_value)
    if module_path.is_absolute() or ".." in module_path.parts:
        raise SystemExit("doc impact module 不是安全仓内路径。")
    module_dir = (repo_root / module_value).resolve()
    try:
        module_dir.relative_to(repo_root)
    except ValueError as exc:
        raise SystemExit("doc impact module 逃逸仓库。") from exc
    meta, build = load_work(module_dir)
    return repo_root, module_dir, map_binding(repo_root, module_dir, meta, build)


def validate_current_binding(path: Path, payload: dict) -> dict:
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise SystemExit("doc impact schema 已过期；请先 ensure-current 重建。")
    actual = payload.get("binding")
    if not isinstance(actual, dict):
        raise SystemExit("doc impact 缺少 currentness binding；请先 ensure-current 重建。")
    _, _, expected = current_binding_for_map(path, payload)
    if actual != expected:
        raise SystemExit("doc impact 已过期；当前 work/commit/source/delta 绑定不一致，请先重建。")
    return expected


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


def reconcile_terms(repo_root: Path, module_dir: Path, changed_files: list[str]) -> dict:
    """Run the installed structured term reconciler before building the map."""
    detector = Path(__file__).resolve().parent / "_lib" / "term-detector.py"
    if not detector.is_file():
        raise SystemExit(f"术语对账脚本不存在: {detector}")
    command = [
        sys.executable,
        str(detector),
        str(module_dir),
        str(repo_root),
        "--work-dir",
        str(module_dir),
    ]
    for destination in changed_files:
        path = PurePosixPath(destination)
        parts = path.parts
        is_functional_spec = (
            len(parts) == 3
            and parts[:2] == ("docs", "modules")
            and path.name != "INDEX.md"
            and path.suffix == ".md"
        )
        is_module_spec = (
            len(parts) >= 4
            and parts[:2] == ("docs", "modules")
            and path.name == "spec.md"
        )
        if is_functional_spec or is_module_spec:
            command.extend(["--source", destination])
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "unknown error"
        raise SystemExit(f"术语对账失败: {detail}")
    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"术语对账输出不是合法 JSON: {exc}") from exc
    if not isinstance(result, dict):
        raise SystemExit("术语对账输出顶层必须是对象。")
    return result


def cmd_init(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir).expanduser().resolve()
    repo_root = repo_root_for(module_dir, args.repo_root)
    meta, build = load_work(module_dir)
    binding = map_binding(
        repo_root, module_dir, meta, build, base=args.base, head=args.head
    )
    base = binding["base"]
    head = binding["head"]
    if binding["candidate_diff_mode"] == "approved-target-snapshot":
        changed_files = sorted(
            {
                path
                for target in binding["candidate_target_paths"]
                for path in git_lines(
                    repo_root, "ls-tree", "-r", "--name-only", str(head), "--", target
                )
            }
        )
    else:
        changed_files = git_lines(
            repo_root, "diff", "--name-only", str(base), str(head)
        )
    term_reconciliation = reconcile_terms(repo_root, module_dir, changed_files)
    module_rel = rel(repo_root, module_dir)
    changed_set = set(changed_files)
    items_by_destination: dict[str, dict] = {}

    def add_destination(
        kind: str,
        name: str,
        destination: str,
        reason: str,
        *,
        changed_counts_as_covered: bool = True,
    ) -> None:
        existing = items_by_destination.get(destination)
        if existing is not None:
            if reason not in str(existing["reason"]):
                existing["reason"] = f"{existing['reason']}；{reason}"
            return
        already_changed = changed_counts_as_covered and destination in changed_set
        items_by_destination[destination] = coverage_item(
            kind,
            name,
            destination,
            reason,
            status="covered" if already_changed else "pending",
            note="landed diff 已包含该真相源变化" if already_changed else "",
        )

    add_destination(
        "fact",
        f"{module_dir.name} 当前产品状态",
        "PRODUCT-STATE.md",
        "实现落地主线后，只更新本轮实际交付的产品现状",
    )

    new_terms = [str(value) for value in term_reconciliation.get("new_terms", [])]
    new_roles = [str(value) for value in term_reconciliation.get("new_roles", [])]
    if new_terms or new_roles:
        labels = [f"术语 {value}" for value in new_terms]
        labels.extend(f"角色 {value}" for value in new_roles)
        add_destination(
            "term",
            "、".join(labels),
            "PRODUCT.md",
            "本轮稳定规格或决定出现新的业务术语 / 角色，需对账长期产品词典",
            changed_counts_as_covered=False,
        )

    accepted_deltas = (
        build.get("accepted_deltas", []) if isinstance(build.get("accepted_deltas"), list) else []
    )
    if accepted_deltas:
        add_destination(
            "fact",
            f"{module_dir.name} 当前规格",
            f"{module_rel}/spec.md",
            "build 期间存在 PM 接受的产品变化，规格必须对齐最终目标",
        )
        add_destination(
            "rule",
            f"{module_dir.name} build 期间确认的决定",
            f"{module_rel}/decisions.md",
            "build 期间 PM 接受的产品变化必须留下决定依据",
        )

    for index, delta in enumerate(accepted_deltas, 1):
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
        for destination in delta_surfaces:
            path = PurePosixPath(destination)
            if (
                not destination.endswith((".md", ".json"))
                or path.is_absolute()
                or ".." in path.parts
            ):
                continue
            add_destination(
                delta_kind,
                str(delta.get("summary") or f"build 期间确认的变化 {index}"),
                destination,
                "PM 在 build 期间确认的产品变化必须有正式文档落点",
            )

    durable_root_docs = {
        "PRODUCT.md",
        "PRODUCT-STATE.md",
        "PRODUCT-RULES.md",
        "DESIGN.md",
        "TODO.md",
        "mockups/manifest.json",
    }
    for destination in changed_files:
        if destination in durable_root_docs or (
            destination.startswith("docs/") and destination.endswith(".md")
        ):
            add_destination(
                "fact",
                destination,
                destination,
                "landed diff 已直接更新该正式真相源，自动纳入文档提交核验",
            )

    items = list(items_by_destination.values())

    payload = {
        "schema_version": SCHEMA_VERSION,
        "created_at": now_iso(),
        "module": module_rel,
        "implementation_commit": build.get("implementation_commit"),
        "landed_commit": build.get("landed_commit"),
        "base": base,
        "head": head,
        "binding": binding,
        "changed_files": changed_files,
        "term_reconciliation": term_reconciliation,
        "items": items,
    }
    path = output_path(repo_root, module_dir, args.output)
    write_json(path, payload)
    if not getattr(args, "quiet", False):
        print(path)


def cmd_ensure_current(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir).expanduser().resolve()
    repo_root = repo_root_for(module_dir, args.repo_root)
    path = output_path(repo_root, module_dir, args.output)
    meta, build = load_work(module_dir)
    expected = map_binding(
        repo_root,
        module_dir,
        meta,
        build,
        base=args.base,
        head=args.head,
    )
    if path.is_file():
        payload = read_json(path)
        if payload.get("schema_version") == SCHEMA_VERSION and payload.get("binding") == expected:
            print(json.dumps({"status": "current", "path": str(path)}, ensure_ascii=False))
            return
    args.quiet = True
    cmd_init(args)
    print(json.dumps({"status": "rebuilt", "path": str(path)}, ensure_ascii=False))


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
    validate_current_binding(path, payload)
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
    validate_current_binding(path, payload)
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
    validate_current_binding(path, payload)
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

    ensure = sub.add_parser("ensure-current")
    ensure.add_argument("module_dir")
    ensure.add_argument("--repo-root")
    ensure.add_argument("--base")
    ensure.add_argument("--head")
    ensure.add_argument("--output")
    ensure.set_defaults(func=cmd_ensure_current)

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
