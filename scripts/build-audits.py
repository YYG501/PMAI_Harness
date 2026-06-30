#!/usr/bin/env python3
"""build 三道审编排 —— 确定性收集 + 合成（模块 build 完成后）。

三道审本身由 build skill 编排 AI 调起：覆盖审计 = `coverage-reviewer` agent /
视觉门 = gstack `/design-review` / 行为审 = 浏览器/脚本化验收。**其中两道是 LLM skill/agent，
无法当子进程脚本调起** —— 所以本脚本不“跑”三道审，只固化能确定性固化的两件事：

  - **resolve**：解析 + 校验输入（模块规格 `spec.md` / `prototype/` / dev 端口），
    建 `.pm-workflow/audits/<模块>/` 内部审计目录，打印 manifest（每道审读什么、把规范化结果写到哪、dev server 复用约定），
    **缺输入 fail-loud**（防对着缺失锚点跑审、防覆盖审计无范围清单可比）。
  - **synthesize**：读 `.pm-workflow/audits/<模块>/` 下三道规范化结果，**校验三道齐全**（漏跑 fail-loud，
    防 AI 漏跑一道还往下走），合成一份 `synthesis.md` 给 PM + 打印机器门禁 summary。

规范化结果 schema（build 跑完每道后写，= 本脚本的输入契约）：
  .pm-workflow/audits/<模块>/coverage.json : {"items":[{"name","status":"built|missing|degraded","note"}]}
  .pm-workflow/audits/<模块>/visual.json   : {"status":"pass|needs-review|limited|skipped","findings":[{"severity":"P0|P1|P2","desc"}]}
  .pm-workflow/audits/<模块>/behavior.json : {"status":"pass|fail|skipped","passed":int,"total":int,"note"}

门禁（gate）只产**给 PM 看的建议**，不替 PM 拍板：clean / needs-review。

用法：
  build-audits.py resolve    <锚点文件> [--repo-root DIR] [--range-list spec.md] [--audit-dir DIR] [--label 模块名]
  build-audits.py synthesize <锚点文件> [--repo-root DIR] [--audit-dir DIR] [--label 模块名] [--fail-on-gate]
  默认锚点就是传入文件，默认审计目录为 `.pm-workflow/audits/<锚点 stem>`。
  build skill 会显式传 `--range-list` / `--audit-dir` / `--label`，把覆盖审计锚到模块规格 spec.md。
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

AUDIT_FILES = {
    "coverage": "coverage.json",
    "visual": "visual.json",
    "behavior": "behavior.json",
}
AUDIT_LABEL = {"coverage": "覆盖审计", "visual": "视觉门", "behavior": "行为审"}


def _die(msg: str, code: int = 2) -> "NoReturn":  # type: ignore[name-defined]
    print(f"[build-audits] {msg}", file=sys.stderr)
    raise SystemExit(code)


def _find_repo_root(anchor_file: Path, override: str | None) -> Path:
    if override:
        return Path(override).expanduser().resolve()
    # 优先 git 顶层（build worktree / 主仓都适用）
    try:
        top = subprocess.check_output(
            ["git", "-C", str(anchor_file.parent), "rev-parse", "--show-toplevel"],
            text=True, stderr=subprocess.DEVNULL,
        ).strip()
        if top:
            return Path(top)
    except Exception:
        pass
    # 回退：向上找含 .pm-workflow 的祖先
    for parent in [anchor_file.parent, *anchor_file.parents]:
        if (parent / ".pm-workflow").is_dir():
            return parent
    return anchor_file.parent


def _audit_dir(repo_root: Path, anchor_file: Path, override: str | None = None) -> Path:
    # 默认：.pm-workflow/audits/<anchor.stem>。build skill 通常传 --audit-dir
    # 显式锚定模块名（如 .pm-workflow/audits/<模块>）。
    if override:
        p = Path(override).expanduser()
        return p if p.is_absolute() else (repo_root / p)
    return repo_root / ".pm-workflow" / "audits" / anchor_file.stem


def _range_list(anchor_file: Path, override: str | None = None) -> Path:
    # 默认把传入锚点本身作为覆盖审计范围。build skill 会显式传模块 spec.md。
    if override:
        return Path(override).expanduser()
    return anchor_file


def _dev_ports(repo_root: Path) -> list[str]:
    """从 .pm-workflow/config.yml 取 dev_server.ports（轻量解析，不引 yaml 依赖）。

    兼容两种写法：inline（`ports: [3000, 5173]`）与 YAML block list（`ports:` 下方
    缩进 `- 3000`）。后者是 pm-workflow.config.yml.tmpl 的默认格式，旧版只认 inline
    会把默认配置解析成空端口、让 resolve fail-loud。
    """
    cfg = repo_root / ".pm-workflow" / "config.yml"
    if not cfg.exists():
        return []
    ports: list[str] = []
    in_dev = False
    in_ports_block = False
    for raw in cfg.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0:
            in_dev = stripped.startswith("dev_server:")
            in_ports_block = False
            continue
        if in_ports_block:
            if stripped.startswith("- "):  # 收 block list 项
                ports.append(stripped[2:].strip().strip("'\""))
                continue
            in_ports_block = False  # 同级出现别的键 → block 结束（不 continue，落下面键处理）
        if in_dev and stripped.startswith("ports:"):
            rest = stripped[len("ports:"):].strip()
            if rest.startswith("[") and rest.endswith("]"):
                ports = [p.strip().strip("'\"") for p in rest[1:-1].split(",") if p.strip()]
                break  # inline 一行拿全
            in_ports_block = True  # 准备收下面缩进的 block list 项
            continue
    return [p for p in ports if p]


def _load_audit(path: Path, key: str) -> dict[str, Any]:
    if not path.exists():
        _die(f"三道审不完整：{AUDIT_LABEL[key]}未跑（缺 {path}）。"
             f"三道审必须全跑过、各写一份规范化结果，才能合成给 PM。")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _die(f"{AUDIT_LABEL[key]}结果非法 JSON：{path}\n{exc}")
    if not isinstance(data, dict):
        _die(f"{AUDIT_LABEL[key]}结果顶层应为 JSON 对象：{path}")
    return data


def _validate_audit_shapes(cov: dict, vis: dict, beh: dict) -> None:
    """三道审结果的关键数组必须是对象列表（防畸形 LLM 输出在合成时 AttributeError）。
    fail-loud 点名哪道审不合 schema，而不是抛裸 traceback。"""
    items = cov.get("items", [])
    if not isinstance(items, list) or any(not isinstance(i, dict) for i in items):
        _die("覆盖审计结果 coverage.json 的 items 应为对象数组（每项 {name,status,note}）")
    findings = vis.get("findings", [])
    if not isinstance(findings, list) or any(not isinstance(f, dict) for f in findings):
        _die("视觉门结果 visual.json 的 findings 应为对象数组（每项 {severity,desc}）")


def cmd_resolve(anchor_file: Path, repo_root: Path,
                range_list_override: str | None = None,
                audit_dir_override: str | None = None) -> int:
    range_list = _range_list(anchor_file, range_list_override)
    prototype = repo_root / "prototype"
    audit_dir = _audit_dir(repo_root, anchor_file, audit_dir_override)
    ports = _dev_ports(repo_root)

    problems = []
    if not range_list.exists():
        problems.append(f"范围清单不存在：{range_list}（覆盖审计无锚点，先产模块规格 spec.md）")
    if not prototype.is_dir():
        problems.append(f"主原型目录不存在：{prototype}（视觉门 / 行为审无可审页面）")
    if not ports:
        problems.append(f"未解析到 dev 端口（{repo_root}/.pm-workflow/config.yml 的 dev_server.ports 缺）")
    if problems:
        _die("输入校验失败（fail-loud，先补齐再跑三道审）：\n  - " + "\n  - ".join(problems))

    audit_dir.mkdir(parents=True, exist_ok=True)
    cov = audit_dir / AUDIT_FILES["coverage"]
    vis = audit_dir / AUDIT_FILES["visual"]
    beh = audit_dir / AUDIT_FILES["behavior"]

    print(f"[build-audits] 输入已校验，内部审计目录已就绪：{audit_dir}")
    print("按下面 manifest 跑三道审，各写规范化结果：")
    print()
    print(f"  ① 覆盖审计（coverage-reviewer agent，静态读码、不需 dev server）")
    print(f"     范围清单：{range_list}")
    print(f"     原型代码：{prototype}")
    print(f"     → 写 {cov}")
    print(f"        schema: {{\"items\":[{{\"name\",\"status\":\"built|missing|degraded\",\"note\"}}]}}")
    print()
    print(f"  ② 视觉门（gstack /design-review，只截图不改；复用同一次 dev server）")
    print(f"     对照：{repo_root / 'docs' / 'DESIGN.md'}")
    print(f"     → 写 {vis}")
    print(f"        schema: {{\"status\":\"pass|needs-review|limited|skipped\",\"findings\":[{{\"severity\":\"P0|P1|P2\",\"desc\"}}]}}")
    print()
    print(f"  ③ 行为审（浏览器/脚本化验收；复用同一次 dev server）")
    print(f"     → 写 verify/report.md + 本道规范化结果 {beh}")
    print(f"        schema: {{\"status\":\"pass|fail|skipped\",\"passed\":int,\"total\":int,\"note\"}}")
    print()
    print(f"  dev server：覆盖审计不需要；视觉门 + 行为审**复用 build 阶段启动的同一个**"
          f"（端口候选 {', '.join(ports)}），别各起各的。")
    print(f"  三道都写完 → 跑 `build-audits.py synthesize {anchor_file}` 合成一份给 PM。")
    return 0


def _render_synthesis(label_name: str, cov: dict, vis: dict, beh: dict) -> tuple[str, dict]:
    cov_items = cov.get("items", []) or []
    missing = [i for i in cov_items if i.get("status") == "missing"]
    degraded = [i for i in cov_items if i.get("status") == "degraded"]
    built = [i for i in cov_items if i.get("status") == "built"]

    findings = vis.get("findings", []) or []
    by_sev = {"P0": [], "P1": [], "P2": []}
    for f in findings:
        by_sev.get(str(f.get("severity", "P2")), by_sev["P2"]).append(f)

    beh_status = str(beh.get("status", "skipped"))
    beh_passed, beh_total = beh.get("passed", 0), beh.get("total", 0)

    gate = "clean"
    if missing or degraded or findings or beh_status == "fail":
        gate = "needs-review"

    out = [f"# 三道审合成报告 — {label_name}", ""]
    out += ["## 一句话", ""]
    if gate == "clean":
        out.append("三道审均无待办：覆盖齐、视觉无不一致、行为跑通。可看 demo 拍板。")
    else:
        bits = []
        if missing:
            bits.append(f"漏建 {len(missing)} 项")
        if degraded:
            bits.append(f"降级占位 {len(degraded)} 项")
        if findings:
            bits.append(f"视觉待办 {len(findings)} 条")
        if beh_status == "fail":
            bits.append("行为审有流程没跑通")
        out.append("有待办：" + "、".join(bits) + "。下面按道列出，建议改的项见末尾。")
    out += [""]

    out += ["## ① 覆盖审计（建全没）", ""]
    out.append(f"- 建了：{len(built)} 项 / 丢了：{len(missing)} 项 / 降级占位：{len(degraded)} 项")
    for i in missing:
        out.append(f"  - 丢了：{i.get('name','?')}{('（' + i['note'] + '）') if i.get('note') else ''}")
    for i in degraded:
        out.append(f"  - 降级占位：{i.get('name','?')}{('（' + i['note'] + '）') if i.get('note') else ''}")
    out += [""]

    out += ["## ② 视觉门（长得对不对）", ""]
    if not findings:
        out.append("- 无视觉不一致。")
    else:
        for sev in ("P0", "P1", "P2"):
            for f in by_sev[sev]:
                out.append(f"  - [{sev}] {f.get('desc','?')}")
    out += [""]

    out += ["## ③ 行为审（跑得通不通）", ""]
    label = {"pass": "✅ 通过", "fail": "❌ 有流程没跑通", "skipped": "⏭ 跳过（非 UI）"}.get(beh_status, beh_status)
    out.append(f"- {label}（{beh_passed}/{beh_total} 流程通过）"
               + (f"：{beh['note']}" if beh.get("note") else ""))
    out += [""]

    out += ["## 建议改的项（PM 勾哪些改）", ""]
    suggestions = []
    for i in missing:
        suggestions.append(f"补建：{i.get('name','?')}")
    for i in degraded:
        suggestions.append(f"补实：{i.get('name','?')}（现是占位）")
    for sev in ("P0", "P1", "P2"):
        for f in by_sev[sev]:
            suggestions.append(f"视觉：{f.get('desc','?')}")
    if beh_status == "fail":
        suggestions.append("修行为审没跑通的流程（详见 verify/report.md）")
    if not suggestions:
        out.append("- 无 —— 三道审都通过，等你看 demo 拍板。")
    else:
        for s in suggestions:
            out.append(f"- [ ] {s}")
    out += [""]

    summary = {
        "label": label_name,
        "coverage": {"built": len(built), "missing": len(missing), "degraded": len(degraded)},
        "visual": {"P0": len(by_sev["P0"]), "P1": len(by_sev["P1"]), "P2": len(by_sev["P2"]),
                   "total": len(findings)},
        "behavior": {"status": beh_status, "passed": beh_passed, "total": beh_total},
        "gate": gate,
    }
    return "\n".join(out) + "\n", summary


def cmd_synthesize(anchor_file: Path, repo_root: Path, fail_on_gate: bool,
                   audit_dir_override: str | None = None,
                   label: str | None = None) -> int:
    audit_dir = _audit_dir(repo_root, anchor_file, audit_dir_override)
    cov = _load_audit(audit_dir / AUDIT_FILES["coverage"], "coverage")
    vis = _load_audit(audit_dir / AUDIT_FILES["visual"], "visual")
    beh = _load_audit(audit_dir / AUDIT_FILES["behavior"], "behavior")
    _validate_audit_shapes(cov, vis, beh)

    report, summary = _render_synthesis(label or anchor_file.stem, cov, vis, beh)
    out_path = audit_dir / "synthesis.md"
    out_path.write_text(report, encoding="utf-8")
    print(f"[build-audits] 合成报告：{out_path}")
    print(json.dumps(summary, ensure_ascii=False))
    if fail_on_gate and summary["gate"] != "clean":
        return 3
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="build 三道审编排（resolve / synthesize）")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("resolve", "synthesize"):
        sp = sub.add_parser(name)
        sp.add_argument("anchor_file")
        sp.add_argument("--repo-root", default=None)
        # build skill 用这几个显式锚定，**敲死锚点、不再"实施时择一"**：
        sp.add_argument("--range-list", default=None,
                        help="覆盖审计锚点路径（build skill 传模块规格 spec.md；默认用传入锚点）")
        sp.add_argument("--audit-dir", default=None,
                        help="内部审计结果目录（build skill 按模块名锚定；默认 .pm-workflow/audits/<锚点 stem>）")
        sp.add_argument("--label", default=None,
                        help="合成报告标题用的名字（build skill 传模块名；默认用锚点文件名）")
        if name == "synthesize":
            sp.add_argument("--fail-on-gate", action="store_true",
                            help="gate != clean 时返回非零（默认 0，门禁仅作给 PM 的建议）")
    args = p.parse_args()

    anchor_file = Path(args.anchor_file).expanduser()
    if not anchor_file.exists():
        _die(f"锚点文件不存在：{anchor_file}（传模块规格 spec.md 或等价范围锚点，用于定位仓根）")
    anchor_file = anchor_file.resolve()
    repo_root = _find_repo_root(anchor_file, args.repo_root)

    if args.cmd == "resolve":
        return cmd_resolve(anchor_file, repo_root, args.range_list, args.audit_dir)
    return cmd_synthesize(anchor_file, repo_root, args.fail_on_gate, args.audit_dir, args.label)


if __name__ == "__main__":
    raise SystemExit(main())
