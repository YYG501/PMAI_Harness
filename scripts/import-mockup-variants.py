#!/usr/bin/env python3
"""Import external mockup images into PMAI mockups/.

This script is intentionally small: gstack or user-uploaded files produce image
assets elsewhere, then PMAI copies them into the project-local mockups/ ledger.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".svg"}
CHINESE_NUMBERS = {
    "一": 1,
    "二": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
    "十": 10,
}


def _slug(value: str, fallback: str) -> str:
    round_match = re.search(r"第?\s*([0-9]+|[一二三四五六七八九十])\s*轮", value)
    if fallback == "round" and round_match:
        raw = round_match.group(1)
        num = int(raw) if raw.isdigit() else CHINESE_NUMBERS.get(raw)
        if num:
            return f"round-{num}"
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value).strip("-").lower()
    if slug:
        return slug[:80]
    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:8]
    return f"{fallback}-{digest}"


def _load_json(path: Path | None, default: Any) -> Any:
    if not path or not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"JSON 解析失败: {path}: {exc}") from exc


def _concepts_by_letter(raw: Any) -> dict[str, dict[str, str]]:
    if not raw:
        return {}
    if isinstance(raw, dict):
        if "concepts" in raw:
            raw = raw["concepts"]
        else:
            result: dict[str, dict[str, str]] = {}
            for key, value in raw.items():
                if isinstance(value, dict):
                    result[str(key).upper()] = {str(k): str(v) for k, v in value.items()}
                else:
                    result[str(key).upper()] = {"explores": str(value)}
            return result
    if isinstance(raw, list):
        result = {}
        for idx, item in enumerate(raw):
            letter = chr(ord("A") + idx)
            if isinstance(item, dict):
                explicit = str(item.get("letter") or letter).upper()
                result[explicit] = {str(k): str(v) for k, v in item.items()}
            else:
                result[letter] = {"explores": str(item)}
        return result
    return {}


def _variant_letter(path: Path, fallback_index: int) -> str:
    match = re.search(r"variant[-_ ]?([A-Za-z0-9]+)", path.stem, re.IGNORECASE)
    if match:
        return match.group(1).upper()
    if fallback_index < 26:
        return chr(ord("A") + fallback_index)
    return str(fallback_index + 1)


def _discover_images(source_dir: Path | None, explicit_images: list[Path]) -> list[Path]:
    images: list[Path] = []
    if source_dir:
        if not source_dir.is_dir():
            raise SystemExit(f"--source-dir 不是目录: {source_dir}")
        images.extend(
            sorted(
                p
                for p in source_dir.iterdir()
                if p.is_file() and p.suffix.lower() in IMAGE_EXTS
            )
        )
    images.extend(explicit_images)
    deduped: list[Path] = []
    seen: set[Path] = set()
    for image in images:
        resolved = image.expanduser().resolve()
        if not resolved.is_file():
            raise SystemExit(f"图片不存在: {image}")
        if resolved.suffix.lower() not in IMAGE_EXTS:
            raise SystemExit(f"不支持的图片类型: {image}")
        if resolved not in seen:
            deduped.append(resolved)
            seen.add(resolved)
    if not deduped:
        raise SystemExit("没有找到可导入的图片")
    return deduped


def _load_manifest(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"variants": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"mockups/manifest.json 解析失败: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit("mockups/manifest.json 必须是 JSON object")
    variants = data.setdefault("variants", [])
    if not isinstance(variants, list):
        raise SystemExit("mockups/manifest.json 的 variants 必须是数组")
    return data


def _preferred_letter(approved: Any, feedback: Any) -> str | None:
    for raw in (
        approved.get("approved_variant") if isinstance(approved, dict) else None,
        approved.get("preferred") if isinstance(approved, dict) else None,
        feedback.get("preferred") if isinstance(feedback, dict) else None,
    ):
        if raw:
            return str(raw).upper().replace("VARIANT-", "")
    return None


def _comment_for(feedback: Any, letter: str) -> str:
    if not isinstance(feedback, dict):
        return ""
    comments = feedback.get("comments")
    if isinstance(comments, dict) and comments.get(letter):
        return str(comments[letter])
    overall = feedback.get("overall")
    return str(overall) if overall else ""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="把 gstack design-shotgun 或用户上传图片导入 PMAI mockups/"
    )
    parser.add_argument("--repo", required=True, help="消费仓根目录")
    parser.add_argument("--source-dir", help="gstack 本轮 designs 目录，内含 variant-*.png")
    parser.add_argument("--image", action="append", default=[], help="用户上传图片，可重复")
    parser.add_argument("--requirement", required=True, help="需求 / 模块名")
    parser.add_argument("--round", default="第一轮", help="探索轮次")
    parser.add_argument("--concepts", help="方向清单 JSON 文件，可选")
    parser.add_argument("--approved", help="approved.json 路径，可选")
    parser.add_argument("--feedback", help="feedback.json 路径，可选")
    parser.add_argument("--dest-slug", help="mockups/ 下的目标目录名，可选")
    args = parser.parse_args()

    repo = Path(args.repo).expanduser().resolve()
    if not repo.is_dir():
        raise SystemExit(f"--repo 不是目录: {repo}")

    source_dir = Path(args.source_dir).expanduser().resolve() if args.source_dir else None
    explicit_images = [Path(p) for p in args.image]
    images = _discover_images(source_dir, explicit_images)

    concepts = _concepts_by_letter(_load_json(Path(args.concepts), {}) if args.concepts else {})
    approved_path = Path(args.approved) if args.approved else (source_dir / "approved.json" if source_dir else None)
    feedback_path = Path(args.feedback) if args.feedback else (source_dir / "feedback.json" if source_dir else None)
    approved = _load_json(approved_path, {})
    feedback = _load_json(feedback_path, {})
    preferred = _preferred_letter(approved, feedback)

    mockups_dir = repo / "mockups"
    mockups_dir.mkdir(parents=True, exist_ok=True)
    dest_slug = args.dest_slug or _slug(args.requirement, "mockup")
    round_slug = _slug(args.round, "round")
    dest_dir = mockups_dir / dest_slug / round_slug
    dest_dir.mkdir(parents=True, exist_ok=True)

    imported: list[dict[str, Any]] = []
    for idx, image in enumerate(images):
        letter = _variant_letter(image, idx)
        ext = image.suffix.lower()
        target_name = f"variant-{letter}{ext}"
        target = dest_dir / target_name
        if target.exists():
            stamp = datetime.now(timezone.utc).strftime("%H%M%S")
            target = dest_dir / f"variant-{letter}-{stamp}{ext}"
        shutil.copy2(image, target)
        rel_path = target.relative_to(mockups_dir).as_posix()
        concept = concepts.get(letter, {})
        comment = _comment_for(feedback, letter)
        is_featured = preferred == letter
        imported.append(
            {
                "path": rel_path,
                "requirement": args.requirement,
                "title": concept.get("title") or f"方案 {letter}",
                "explores": concept.get("explores") or concept.get("direction") or f"外部设计稿 {letter}",
                "good_parts": comment or concept.get("good_parts") or concept.get("good") or "待 PM 比对",
                "status": "待合并" if is_featured else "活跃",
                "round": args.round,
                "featured": is_featured,
                "retired_note": "",
            }
        )

    manifest_path = mockups_dir / "manifest.json"
    manifest = _load_manifest(manifest_path)
    variants = manifest["variants"]
    by_path = {str(v.get("path")): i for i, v in enumerate(variants) if isinstance(v, dict)}
    for item in imported:
        if item["path"] in by_path:
            variants[by_path[item["path"]]] = item
        else:
            variants.append(item)

    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"IMPORTED: {len(imported)}")
    print(f"MANIFEST: {manifest_path}")
    for item in imported:
        marker = " SELECTED" if item["featured"] else ""
        print(f"- {item['path']}{marker}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
