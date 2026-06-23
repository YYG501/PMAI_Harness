#!/usr/bin/env python3
"""把旧 7-stage req 的 `.req-meta.json:stage` 重映射到六步（1-4），解除越界。

六步重构后 `MAX_STAGE=4`；旧 7-stage req 的 stage ∈ {5,6,7} 在新引擎下越界
（`STAGE_NAMES` 只有 1-4 → 显示 "?"，req-transition 校验失效）。本脚本一次性把
越界的 stage 值重映射：

    旧 7-stage（仅越界值 stage > MAX_STAGE 才重映射）   → 六步
    5 impl-design                                       → 1 设计
    6 task-loop（build）                                 → 2 build
    7 close                                             → 4 沉淀

**只动数值越界的 stage（> MAX_STAGE）**。旧 stage 1-4（brief/analysis/prd/design）数值不越界、
**且无法可靠区分「旧 7-stage 的 1-4」与「新六步的 1-4」——一律不动**（`new == old` 时 migrate_one
直接 return None，不盖 `migrated_from_7stage` 戳、不污染 stage_history）。

**⚠️ 歧义区（旧 prd/design ↔ 新复审/沉淀）**：旧 7-stage 的 stage 3（prd）/ 4（design）数值恰好
落在新六步的 3（复审）/ 4（沉淀）。一个停在旧 stage 4（design）的 **active** 旧 req，本脚本不动它、
新引擎会把它读成「沉淀=done」且 `req-transition` 禁止从 MAX_STAGE 回退 → 未完成需求被锁成不可逆完成态。
脚本无可靠信号自动区分，跑完会**列出所有 active 且 stage∈{3,4} 的 req 让 PM 手工确认**（不做不安全的自动迁移）。

**幂等**：已带 `migrated_from_7stage` 字段的 req 跳过。支持 `--dry-run`。

**重要 caveat（迁移只动 stage 数值、不动产物）**：closed 旧 req（多数，→ stage 4 沉淀=done）
完全 OK。**in-flight 旧 req**（停在 stage 5/6 → 映射到 1/2）**没有当前流程产物**（spec.md），
不能直接 `/pmai-next` 续跑——建议在旧框架上收尾 / close，或当 done 处理。本脚本只解越界、
不做产物迁移（那是另一件大事，且 PM 的旧 req 基本都已 closed）。

用法：
    python3 migrate-reqs-to-6step.py <repo-or-reqs-dir>            # 真跑
    python3 migrate-reqs-to-6step.py <repo-or-reqs-dir> --dry-run  # 仅预览
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.state import write_json_atomic  # noqa: E402
from _lib.stages import MAX_STAGE  # noqa: E402

# 旧 7-stage → 六步（仅越界值需要；1-4 数值已在范围内不动）
LEGACY_TO_6STEP: dict[int, int] = {5: 1, 6: 2, 7: 4}
STAGE_NAME_HINT = {1: "设计", 2: "build", 3: "复审", 4: "沉淀"}


def _remap(old_stage: int) -> int:
    if old_stage in LEGACY_TO_6STEP:
        return LEGACY_TO_6STEP[old_stage]
    # 超过 7 的异常值兜底成沉淀（done）
    return 4 if old_stage > MAX_STAGE else old_stage


def _is_legacy(meta: dict) -> bool:
    """明显是旧 7-stage：当前 stage 越界，或历史里出现过越界值。"""
    stage = meta.get("stage")
    if isinstance(stage, int) and stage > MAX_STAGE:
        return True
    for h in meta.get("stage_history", []) or []:
        s = h.get("stage")
        if isinstance(s, int) and s > MAX_STAGE:
            return True
    return False


def _iter_meta_files(root: Path):
    """收 root 下所有 .req-meta.json（主仓 + worktrees 的 active/closed）。"""
    seen: set = set()
    for meta in root.rglob(".req-meta.json"):
        # 跳过 node_modules 等噪声目录
        if any(part in {"node_modules", ".next", "dist"} for part in meta.parts):
            continue
        real = meta.resolve()
        if real in seen:
            continue
        seen.add(real)
        yield meta


def migrate_one(meta_file: Path, dry_run: bool) -> dict | None:
    """返回 {req, old, new} 表示迁移了，None 表示跳过（非旧 / 已迁移 / 读失败）。"""
    try:
        meta = json.loads(meta_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(meta, dict):
        return None
    if "migrated_from_7stage" in meta:  # 幂等
        return None
    if not _is_legacy(meta):
        return None

    old = meta.get("stage")
    if not isinstance(old, int):
        return None  # 无 stage 数值可重映射（损坏 / 非 7-stage meta）—— 不动、不盖戳
    new = _remap(old)
    if new == old:
        return None  # 旧 stage 1-4 = 新 stage 1-4，无法可靠区分 → 不动、不盖 migrated_from_7stage、不污染 stage_history
    if not dry_run:
        meta["migrated_from_7stage"] = old
        meta["stage"] = new
        meta.setdefault("stage_history", []).append(
            {
                "stage": new,
                "direction": "migrate-7step",
                "from_stage": old,
                "note": "7-stage → 六步 stage 重映射（migrate-reqs-to-6step.py）",
            }
        )
        write_json_atomic(meta_file, meta)
    return {"req": meta_file.parent.name, "old": old, "new": new}


def scan_ambiguous_active(root: Path) -> list:
    """active（非 closed/cancelled）且 stage∈{3,4} 的 req：旧 prd(3)/design(4) 与新复审(3)/沉淀(4)
    同号、脚本无法可靠区分。这类 req 若实为旧 design、新引擎会读成沉淀=done 且不可回退 → PM 须手工确认。"""
    out, seen = [], set()
    for mf in _iter_meta_files(root):
        try:
            meta = json.loads(mf.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(meta, dict) or "migrated_from_7stage" in meta:
            continue
        if meta.get("status") in {"closed", "cancelled"}:
            continue
        if meta.get("stage") in {3, 4} and mf.parent.name not in seen:
            seen.add(mf.parent.name)
            out.append({"req": mf.parent.name, "stage": meta.get("stage")})
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="迁移旧 7-stage req stage 值到六步")
    parser.add_argument("root", help="消费仓根目录 或 requirements/ 目录")
    parser.add_argument("--dry-run", action="store_true", help="仅预览不写")
    args = parser.parse_args()

    root = Path(args.root).expanduser().resolve()
    if not root.is_dir():
        print(f"Error: 目录不存在：{root}", file=sys.stderr)
        sys.exit(1)

    migrated = [r for mf in _iter_meta_files(root) if (r := migrate_one(mf, args.dry_run))]
    ambiguous = scan_ambiguous_active(root)

    label = "将迁移（dry-run）" if args.dry_run else "已迁移"
    if not migrated:
        print("✓ 没有需要 stage 重映射的旧 7-stage req（stage 值都未越界 / 已迁移）。")
    else:
        print(f"{label} {len(migrated)} 个 stage 越界的旧 7-stage req → 六步：")
        for r in migrated:
            name = STAGE_NAME_HINT.get(r["new"], "")
            print(f"   - {r['req']}: stage {r['old']} → {r['new']}（{name}）")
        if args.dry_run:
            print("\n（dry-run，未写入。去掉 --dry-run 真跑。）")
        else:
            print(
                "\n⚠️ in-flight 旧 req（映射到 stage 1/2）无当前流程产物（spec.md），"
                "不能直接 /pmai-next 续跑——在旧框架收尾 / close 或当 done 处理。"
            )

    # P0-4 歧义区：旧 prd(3)/design(4) 与新复审(3)/沉淀(4) 同号，脚本无法区分 → 列出让 PM 手工确认。
    if ambiguous:
        print(
            "\n⚠️ 歧义需求（active 且 stage∈{3,4}，脚本未动）—— 旧 7-stage 的 prd(3)/design(4) 与"
            "新六步的 复审(3)/沉淀(4) 同号。请逐个确认它们确实在新六步阶段，不是停在旧 prd/design"
            "（后者会被新引擎当成已完成、且 req-transition 不可回退）："
        )
        for a in ambiguous:
            name = STAGE_NAME_HINT.get(a["stage"], "")
            print(f"   - {a['req']}: stage {a['stage']}（{name}？）")


if __name__ == "__main__":
    main()
