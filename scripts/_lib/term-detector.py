#!/usr/bin/env python3
"""term-detector.py — 业务词 / 角色检测器

当前由 `/pmai-build-close` 调用。业务词真正稳定要等 design/build/复审完成后再沉淀；
早期讨论里 PM 用 `**` 多为修辞，detector 信噪比差，故不调。

检测策略（保守，避免 Clippy 风险）：
- 候选业务词来源（仅这两处显式术语标记，不全文 NLP）：
  - 「X」/『X』 (中文引号 — 术语 / 专名专用标记)
  - "X" / "X" (中文双引号)
- **不再扫 markdown 加粗 `**X**`**：中文 markdown 里 `**` 几乎只用于修辞强调
  （"**真正的痛点**" / "**核心**" / "**必须**"），全抓进来 = 噪音爆炸；
  即便偶有真业务词，PM 用 `**` 标的概率远低于裸写
- 角色识别：候选词以「员 / 管理员 / 运营 / 客服 / 财务 / 经理 / 主管」结尾
- 过滤层：
  1. 白名单（whitelist.json，含技术词 + 通用业务/产品词）
  2. PROJECT 已登记（业务术语表 / 用户画像表）
  3. .term-skip.json（本次工作已被 PM 拒绝的）

用法（被 skill 调用）：
  python3 scripts/_lib/term-detector.py <text-file> <repo-root> [--work-dir <work-dir>]

输出 JSON：
{
  "new_terms": ["商品池", "售后单"],
  "new_roles": ["平台审核员"],
  "skipped": ["X"],  // 在 .term-skip.json 里的，PM 已拒绝
  "whitelisted": ["用户"],  // 在白名单的，silent
  "registered": ["管理员"]  // 已在 PROJECT 的
}

调用 skill 据此输出 §2.7 话术（单词 / 多词批量 / 角色）让 PM 处理。
"""
import argparse
import json
import re
import sys
from pathlib import Path


def load_whitelist(repo_root: Path) -> set:
    """Load hardcode whitelist from skills/_shared/term-detector/whitelist.json."""
    wl_path = repo_root / "skills" / "_shared" / "term-detector" / "whitelist.json"
    if not wl_path.exists():
        # 容错：消费仓如未同步该文件，返回 minimal 白名单
        return {"用户", "产品", "数据", "API", "JSON"}
    data = json.loads(wl_path.read_text(encoding="utf-8"))
    terms = set()
    for k, v in data.items():
        if isinstance(v, list):
            terms.update(v)
    return terms


def load_registered(project_path: Path) -> dict:
    """Load registered terms from PRODUCT.md 业务术语表 / 用户画像表."""
    result = {"terms": set(), "roles": set()}
    if not project_path.exists():
        return result
    content = project_path.read_text(encoding="utf-8")

    # 提取 ## 用户画像 表的「角色」列
    m = re.search(r"##\s+用户画像\s*\n(.+?)(?=^##\s|\Z)", content, re.MULTILINE | re.DOTALL)
    if m:
        for line in m.group(1).splitlines():
            if "|" in line and not re.match(r"^\|[\s\-\|]+\|$", line.strip()):
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                if cells and cells[0] not in ("角色", "", "-"):
                    result["roles"].add(cells[0])

    # 提取 ## 业务术语表 表的「术语」列
    m = re.search(r"##\s+业务术语表\s*\n(.+?)(?=^##\s|\Z)", content, re.MULTILINE | re.DOTALL)
    if m:
        for line in m.group(1).splitlines():
            if "|" in line and not re.match(r"^\|[\s\-\|]+\|$", line.strip()):
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                if cells and cells[0] not in ("术语", "", "-"):
                    result["terms"].add(cells[0])

    return result


def load_skip_list(work_dir: Path) -> set:
    """Load .term-skip.json for current work (PM 本次工作已拒绝的词)."""
    skip_path = work_dir / ".term-skip.json"
    if not skip_path.exists():
        return set()
    try:
        data = json.loads(skip_path.read_text(encoding="utf-8"))
        terms = set(data.get("skipped_terms", []))
        terms.update(data.get("skipped_roles", []))
        return terms
    except Exception:
        return set()


def extract_candidates(text: str) -> list:
    """提取候选业务词：「X」 / 『X』 / "X" / "X"。

    刻意不抓 `**X**`（markdown 加粗）—— 中文场景 `**` 几乎只用于修辞强调，
    误报率压倒任何真业务词收益（见模块 docstring）。"""
    candidates = []
    # 中文单引号
    for m in re.finditer(r"「([^「」\n]{2,15})」", text):
        candidates.append(m.group(1).strip())
    # 中文书名号
    for m in re.finditer(r"『([^『』\n]{2,15})』", text):
        candidates.append(m.group(1).strip())
    # 中文双引号
    for m in re.finditer(r"[“”]([^“”\n]{2,15})[“”]", text):
        candidates.append(m.group(1).strip())
    return candidates


def is_role(term: str) -> bool:
    """判断是不是角色词（启发式：以「员 / 管理员 / 运营 / 客服 / 财务 / 经理 / 主管 / 师」结尾）。"""
    role_suffixes = ("员", "运营", "客服", "财务", "经理", "主管", "师")
    return term.endswith(role_suffixes)


def detect(text: str, whitelist: set, registered: dict, skip: set) -> dict:
    """检测文本中的新业务词 / 角色，按四层过滤。"""
    candidates = extract_candidates(text)
    # dedup 保序
    seen = set()
    unique = []
    for c in candidates:
        if c not in seen:
            seen.add(c)
            unique.append(c)

    result = {
        "new_terms": [],
        "new_roles": [],
        "skipped": [],
        "whitelisted": [],
        "registered": [],
    }

    for term in unique:
        if term in whitelist:
            result["whitelisted"].append(term)
            continue
        if term in registered["terms"] or term in registered["roles"]:
            result["registered"].append(term)
            continue
        if term in skip:
            result["skipped"].append(term)
            continue
        if is_role(term):
            result["new_roles"].append(term)
        else:
            result["new_terms"].append(term)

    return result


def main():
    parser = argparse.ArgumentParser(description="Detect new business terms / roles in stage output")
    parser.add_argument("text_file", help="path to file containing the stage output text")
    parser.add_argument("repo_root", help="repository root path")
    parser.add_argument("--work-dir", default=None, help="active work dir (for .term-skip.json)")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    text_path = Path(args.text_file)
    if not text_path.exists():
        print(json.dumps({"error": f"text file not found: {text_path}"}, ensure_ascii=False), file=sys.stderr)
        sys.exit(2)

    text = text_path.read_text(encoding="utf-8")
    whitelist = load_whitelist(repo_root)
    project_path = repo_root / "docs" / "PRODUCT.md"
    registered = load_registered(project_path)

    work_dir = Path(args.work_dir) if args.work_dir else None
    skip = load_skip_list(work_dir) if work_dir else set()

    result = detect(text, whitelist, registered, skip)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
