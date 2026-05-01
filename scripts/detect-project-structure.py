#!/usr/bin/env python3
"""探测项目工程结构：prototype / system / hybrid / framework / unknown。

读 templates/工程结构约束.schema.json，扫描项目（**用 `git ls-files` 取
tracked 列表**避免 pathlib.glob 在大仓 IO 退化），按 signal globs 做
fnmatch 命中，输出多维度报告 + 总判定 + 置信度 + 实际证据。

第五档 framework 是本项目（PM-AI-Workflow）这种生成器 / 纯工具仓的兜底
档：scan_roots（src/ / prototypes/src/ / apps/*/src/）下完全没 ts/tsx
文件 → 判 framework，不走 prototype/system 二元约束。

判定规则：
    system_signals_hit ≥ 2 + prototype-friendly_signals_hit == 0  → system
    system_signals_hit ≥ 1 + prototype-friendly_signals_hit ≥ 1  → hybrid
    system_signals_hit == 0 + prototype-friendly_signals_hit ≥ 1 → prototype
    scan_roots 下无任何 ts/tsx 文件                              → framework
    其余                                                          → unknown

置信度：根据 hit 数 + 反向 signal 缺失情况线性叠加（详见
`compute_judgment`）。

用法：
    python3 scripts/detect-project-structure.py [--repo PATH] [--json]

退出码：
    0 = 探测成功（判定 + 置信度写到 stdout）
    1 = repo 错（非 git 仓 / schema 不存在）
    2 = 用法错
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from pathlib import Path
from typing import Optional

REPO_ROOT_DEFAULT = Path(__file__).resolve().parent.parent
SCHEMA_REL = "templates/工程结构约束.schema.json"

VALID_JUDGMENTS = ("prototype", "system", "hybrid", "framework", "unknown")


def git_ls_files(repo: Path) -> list[str]:
    """tracked + 未删除文件列表。比 pathlib.glob('**/*') 快 N 倍且
    自动排除 .gitignore 路径（含 node_modules / .next / dist）。"""
    try:
        out = subprocess.check_output(
            ["git", "-C", str(repo), "ls-files"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    return [line for line in out.splitlines() if line.strip()]


def expand_brace(pattern: str) -> list[str]:
    """简单 brace 展开：`*.{ts,tsx}` → [`*.ts`, `*.tsx`]。
    fnmatch 不支持 brace，先手动展开。"""
    if "{" not in pattern:
        return [pattern]
    pre, rest = pattern.split("{", 1)
    if "}" not in rest:
        return [pattern]
    inner, post = rest.split("}", 1)
    parts = inner.split(",")
    return [pre + p.strip() + post for p in parts]


def matches_pattern(path: str, pattern: str) -> bool:
    """fnmatch.fnmatch 默认不把 `/` 当分隔符，对 `**` 也不严格。
    我们的 schema 用 `**/foo/*.tsx` 这种形式，靠 fnmatchcase 足够：
    `**` 会匹配任意路径含 `/`。"""
    for expanded in expand_brace(pattern):
        if fnmatch.fnmatchcase(path, expanded):
            return True
    return False


def matches_excludes(path: str, excludes: list[str]) -> bool:
    return any(matches_pattern(path, exc) for exc in excludes)


def is_under_scan_roots(path: str, scan_roots: list[str]) -> bool:
    """path 是否落在 scan_roots 下。
    scan_roots 用 dir 前缀（如 `src/`）或 glob（如 `apps/*/src/`）。"""
    for root in scan_roots:
        if "*" in root:
            # glob：`apps/*/src/` → 拿 prefix `apps/` 然后看 path 后续段
            # 简化：把 root 当 fnmatch 前缀（root 末尾 `/` → root + `**`）
            pat = root.rstrip("/") + "/**"
            if matches_pattern(path, pat):
                return True
        else:
            if path.startswith(root):
                return True
    return False


def detect(repo: Path, schema: dict) -> dict:
    excludes = schema.get("scan_excludes", [])
    scan_roots = schema.get("scan_roots_default", [])

    all_files = git_ls_files(repo)
    if not all_files:
        return {
            "judgment": "unknown",
            "confidence": 0.0,
            "signals": {},
            "scan_roots_used": scan_roots,
            "scan_roots_files_count": 0,
            "ts_files_under_roots": 0,
            "recommendation": "git ls-files 返回空——非 git 仓或空仓",
        }

    candidate_files = [
        f for f in all_files
        if is_under_scan_roots(f, scan_roots) and not matches_excludes(f, excludes)
    ]

    ts_under_roots = [f for f in candidate_files if f.endswith((".ts", ".tsx"))]

    signal_results: dict[str, dict] = {}
    for sid, sdef in schema["signals"].items():
        matches: list[str] = []
        for pattern in sdef["globs"]:
            for f in candidate_files:
                if matches_pattern(f, pattern):
                    if f not in matches:
                        matches.append(f)
        signal_results[sid] = {
            "present": len(matches) > 0,
            "match_count": len(matches),
            "matches": matches[:5],  # 前 5 个证据
            "implies": sdef.get("implies"),
        }

    judgment, confidence, reason = compute_judgment(signal_results, ts_under_roots)

    return {
        "judgment": judgment,
        "confidence": round(confidence, 2),
        "signals": signal_results,
        "scan_roots_used": scan_roots,
        "scan_roots_files_count": len(candidate_files),
        "ts_files_under_roots": len(ts_under_roots),
        "recommendation": format_recommendation(judgment, confidence, reason),
    }


def compute_judgment(
    signal_results: dict, ts_under_roots: list[str]
) -> tuple[str, float, str]:
    sys_hits = sum(
        1 for r in signal_results.values()
        if r["present"] and r["implies"] == "system"
    )
    proto_hits = sum(
        1 for r in signal_results.values()
        if r["present"] and r["implies"] == "prototype-friendly"
    )

    # framework 第三档：scan_roots 下完全没 ts/tsx → 不是产品代码仓
    if len(ts_under_roots) == 0 and sys_hits == 0 and proto_hits == 0:
        return ("framework", 0.7, "scan_roots 下无 ts/tsx 文件——生成器/工具仓")

    if sys_hits >= 2 and proto_hits == 0:
        # 强 system 信号且无 prototype-friendly 反向：高置信
        return ("system", min(1.0, 0.5 + sys_hits * 0.15), f"system signals: {sys_hits}")

    if sys_hits >= 1 and proto_hits >= 1:
        return (
            "hybrid",
            0.5 + 0.05 * (sys_hits + proto_hits),
            f"system: {sys_hits} + prototype-friendly: {proto_hits} 共存",
        )

    if sys_hits >= 1 and proto_hits == 0:
        # 单 system signal 命中信心不够
        return ("hybrid", 0.45, f"system signals: {sys_hits}（弱信号，可能误判）")

    if sys_hits == 0 and proto_hits >= 1:
        return (
            "prototype",
            min(1.0, 0.5 + proto_hits * 0.2),
            f"prototype-friendly signals: {proto_hits}, 无 system 抽象",
        )

    return ("unknown", 0.3, "无 signal 命中且 scan_roots 下有 ts/tsx 文件")


def format_recommendation(judgment: str, confidence: float, reason: str) -> str:
    if confidence >= 0.7:
        return f"{judgment}（高置信，{reason}）→ 自动写入 CLAUDE.md「工程结构约束」段"
    if confidence >= 0.4:
        return f"{judgment}（中置信，{reason}）→ 输出报告 + 提示 PM 复核"
    return f"{judgment}（低置信，{reason}）→ 走 PM 显式选择路径"


def load_schema(schema_path: Path) -> Optional[dict]:
    if not schema_path.exists():
        return None
    try:
        with schema_path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except json.JSONDecodeError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect project engineering structure")
    parser.add_argument(
        "--repo",
        type=Path,
        default=REPO_ROOT_DEFAULT,
        help=f"Repo root（默认 {REPO_ROOT_DEFAULT}）",
    )
    parser.add_argument(
        "--schema",
        type=Path,
        default=None,
        help=f"Schema 路径（默认 <repo>/{SCHEMA_REL}）",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="输出 JSON（机读）",
    )
    args = parser.parse_args()

    repo = args.repo.resolve()
    schema_path = args.schema if args.schema else (repo / SCHEMA_REL)
    schema = load_schema(schema_path)
    if schema is None:
        print(f"❌ schema 不可读: {schema_path}", file=sys.stderr)
        return 1

    result = detect(repo, schema)

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    j = result["judgment"]
    c = result["confidence"]
    print(f"判定：{j}（置信度 {c}）")
    print(f"建议：{result['recommendation']}")
    print()
    print(f"扫描根目录：{result['scan_roots_used']}")
    print(f"  扫描到 {result['scan_roots_files_count']} 个文件，含 {result['ts_files_under_roots']} 个 ts/tsx")
    print()
    print("Signal 命中：")
    for sid, r in result["signals"].items():
        if r["present"]:
            print(f"  ✓ {sid}（implies={r['implies']}, {r['match_count']} 命中）")
            for m in r["matches"]:
                print(f"      {m}")
        else:
            print(f"  · {sid}（implies={r['implies']}, 未命中）")

    return 0


if __name__ == "__main__":
    sys.exit(main())
