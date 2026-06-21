#!/usr/bin/env python3
"""把 `requirements/active|closed/<req>/` 迁到 `docs/modules/<模块>/`（lifecycle 迁移批 2 用）.

lifecycle 迁移计划（docs/设计/lifecycle迁移计划.md）①：取消 `requirements/active|closed/`
整棵树，把 req 的状态/文档搬进 `docs/modules/<模块>/`（三件套 + `.req-meta.json`）。
本脚本是那次原子切换（批 2）的**一次性搬家工具**，仿 `migrate-reqs-to-6step.py` 写法：

- **--dry-run 默认**：不传 `--apply` 一律只预览、绝不写盘（防误跑）。
- **幂等**：目标模块目录已存在且 `.req-meta.json` 在场 → 跳过（再跑不重复搬）。
- **歧义区列出**：模块名无法可靠从 req name 派生（或多 req 撞同一模块名）→ 不搬、
  列出让 PM 用 `--map <req>=<模块>` 手工指定。

模块名来源（lifecycle 计划 §7 待 PM 拍 #4，本脚本两条都支持，PM 给优先）：
  1. `--map req-001-foo=能力匹配卡`：PM 显式指定（权威，绕过歧义判定）。
  2. 从 req name 派生：`req-001-能力匹配卡` → 模块名 `能力匹配卡`（去掉 `req-NNN-` 前缀）。
     派生失败（前缀剥不出名字 / 名字为空）→ 列入歧义区，不搬。

**搬什么 / 不搬什么**（本脚本只搬「真相源文档 + 状态」，附件另走批 6）：
  - 搬：`.req-meta.json`、`*.md`（brief / req-plan / spec / discussion / decisions 等）。
  - 不搬（留接口、本脚本不动）：`attachments/`（→ 批 6 docs/inputs/）、`tasks/`（task dormant）。
  搬不动的子目录会列在每条迁移结果里（PM 知道哪些没跟着走）。

用法：
    python3 migrate-reqs-to-modules.py <repo>                       # dry-run（默认，只看）
    python3 migrate-reqs-to-modules.py <repo> --map req-001-x=模块A # 指定模块名（dry-run）
    python3 migrate-reqs-to-modules.py <repo> --apply               # 真跑（写盘）
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

# req 目录名前缀：req-001-<name>。剥掉 `req-NNN-` 得模块名候选。
_REQ_PREFIX_RE = re.compile(r"^req-\d{3,}-(.+)$")

# 搬家时跳过的子目录（附件走批 6、task dormant）。
_SKIP_SUBDIRS = {"attachments", "tasks"}


def _derive_module_name(req_dir_name: str, meta: dict) -> str | None:
    """从 req 目录名 / meta 派生模块名候选；派生不出返回 None（→ 歧义区）。"""
    m = _REQ_PREFIX_RE.match(req_dir_name)
    if m and m.group(1).strip():
        return m.group(1).strip()
    # fallback：meta.name 非空也可作模块名
    name = (meta.get("name") or "").strip() if isinstance(meta, dict) else ""
    return name or None


def _iter_req_dirs(repo: Path):
    """枚举 `requirements/active/*` + `requirements/closed/*` 下含 `.req-meta.json` 的 req 目录。

    返回 (req_dir, meta, origin) 三元组，origin ∈ {"active","closed"}（仅追溯用）。
    """
    for origin in ("active", "closed"):
        base = repo / "requirements" / origin
        if not base.is_dir():
            continue
        for req_dir in sorted(base.iterdir()):
            if not req_dir.is_dir():
                continue
            meta_file = req_dir / ".req-meta.json"
            if not meta_file.exists():
                continue
            try:
                meta = json.loads(meta_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                meta = {}
            yield req_dir, meta if isinstance(meta, dict) else {}, origin


def _parse_map(pairs: list[str]) -> dict[str, str]:
    """`--map req-001-x=模块A` × N → {req_dir_name: 模块名}。"""
    out: dict[str, str] = {}
    for p in pairs:
        if "=" not in p:
            print(f"Error: --map 需 <req>=<模块> 形式，收到：{p!r}", file=sys.stderr)
            sys.exit(2)
        k, v = p.split("=", 1)
        k, v = k.strip(), v.strip()
        if not k or not v:
            print(f"Error: --map 两侧都不能为空：{p!r}", file=sys.stderr)
            sys.exit(2)
        out[k] = v
    return out


def _copied_files_in(req_dir: Path) -> list[Path]:
    """req 目录下要搬的顶层文件（.req-meta.json + *.md）。"""
    files: list[Path] = []
    meta_file = req_dir / ".req-meta.json"
    if meta_file.exists():
        files.append(meta_file)
    for f in sorted(req_dir.glob("*.md")):
        files.append(f)
    return files


def _skipped_subdirs_in(req_dir: Path) -> list[str]:
    """req 目录下跳过没搬的子目录（附件 / task）。"""
    out: list[str] = []
    for child in sorted(req_dir.iterdir()):
        if child.is_dir() and child.name in _SKIP_SUBDIRS:
            out.append(child.name)
    return out


def plan_migration(repo: Path, name_map: dict[str, str]):
    """返回 (migrations, ambiguous)。

    migrations: [{req, module, origin, dest, files, skipped, already}]
    ambiguous:  [{req, reason}]
    """
    migrations: list[dict] = []
    ambiguous: list[dict] = []
    modules_root = repo / "docs" / "modules"

    # 先按目标模块名分组，检测「多 req 撞同一模块名」
    pending: list[tuple[Path, dict, str, str]] = []  # (req_dir, meta, origin, module)
    module_claims: dict[str, list[str]] = {}

    for req_dir, meta, origin in _iter_req_dirs(repo):
        req_name = req_dir.name
        module = name_map.get(req_name) or _derive_module_name(req_name, meta)
        if not module:
            ambiguous.append({
                "req": req_name,
                "reason": "无法从 req 名派生模块名，请用 --map " + req_name + "=<模块名> 指定",
            })
            continue
        pending.append((req_dir, meta, origin, module))
        module_claims.setdefault(module, []).append(req_name)

    for req_dir, meta, origin, module in pending:
        req_name = req_dir.name
        claimants = module_claims.get(module, [])
        # 多 req 撞同一模块名 且 PM 没在 --map 里逐个指定 → 歧义（除非 PM 给了这条的 map）
        if len(claimants) > 1 and req_name not in name_map:
            ambiguous.append({
                "req": req_name,
                "reason": f"模块名「{module}」被多个 req 抢（{', '.join(claimants)}），"
                          f"请用 --map 逐个指定不同模块名",
            })
            continue

        dest = modules_root / module
        # 幂等：目标模块已存在 .req-meta.json → 跳过
        already = (dest / ".req-meta.json").exists()
        migrations.append({
            "req": req_name,
            "module": module,
            "origin": origin,
            "dest": dest,
            "files": _copied_files_in(req_dir),
            "skipped": _skipped_subdirs_in(req_dir),
            "already": already,
            "src": req_dir,
        })

    return migrations, ambiguous


def apply_migration(m: dict) -> None:
    """真搬：建目标模块目录，copy 顶层文件（.req-meta.json + *.md）。

    用 copy 不用 move：批 2 原子切换才删旧路径（瘦身=缩活跃集不删，过渡期双存）。
    """
    dest: Path = m["dest"]
    dest.mkdir(parents=True, exist_ok=True)
    for f in m["files"]:
        shutil.copy2(f, dest / f.name)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="把 requirements/active|closed/<req>/ 迁到 docs/modules/<模块>/（dry-run 默认）",
    )
    parser.add_argument("repo", help="消费仓根目录")
    parser.add_argument(
        "--apply", action="store_true",
        help="真跑写盘（不传则只 dry-run 预览，绝不写）",
    )
    parser.add_argument(
        "--map", action="append", default=[], metavar="req=模块",
        help="显式指定某 req 的目标模块名（可多次），如 --map req-001-foo=能力匹配卡",
    )
    args = parser.parse_args()

    repo = Path(args.repo).expanduser().resolve()
    if not repo.is_dir():
        print(f"Error: 目录不存在：{repo}", file=sys.stderr)
        sys.exit(1)

    name_map = _parse_map(args.map)
    migrations, ambiguous = plan_migration(repo, name_map)

    to_do = [m for m in migrations if not m["already"]]
    already = [m for m in migrations if m["already"]]

    dry = not args.apply
    label = "将迁移（dry-run）" if dry else "已迁移"

    if not to_do:
        print("✓ 没有需要迁移的 req（requirements/ 为空 / 全部已在 docs/modules/ 落地）。")
    else:
        print(f"{label} {len(to_do)} 个 req → docs/modules/：")
        for m in to_do:
            rel_dest = m["dest"].relative_to(repo)
            print(f"   - {m['req']}（{m['origin']}）→ {rel_dest}")
            print(f"       搬 {len(m['files'])} 个文件："
                  + ", ".join(f.name for f in m["files"]))
            if m["skipped"]:
                print(f"       ⚠️ 跳过子目录（本脚本不搬，另走附件/task 批）："
                      + ", ".join(m["skipped"]))
            if not dry:
                apply_migration(m)
        if dry:
            print("\n（dry-run，未写入。加 --apply 真跑。旧 requirements/ 路径不删，"
                  "由批 2 原子切换收口。）")
        else:
            print("\n✓ 已 copy 到 docs/modules/（旧 requirements/ 保留，由批 2 删）。")

    if already:
        print(f"\n↺ 跳过 {len(already)} 个已在 docs/modules/ 落地的 req（幂等）：")
        for m in already:
            print(f"   - {m['req']} → {m['dest'].relative_to(repo)}（.req-meta.json 已在）")

    if ambiguous:
        print("\n⚠️ 歧义 req（未迁移，需 PM 用 --map 指定模块名）：")
        for a in ambiguous:
            print(f"   - {a['req']}：{a['reason']}")


if __name__ == "__main__":
    main()
