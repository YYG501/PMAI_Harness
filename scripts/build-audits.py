#!/usr/bin/env python3
"""build 三道审编排 —— 确定性收集 + 合成（六步「建」完，task-execute 步骤 7.3）。

三道审本身由 task-execute 编排 AI 调起：覆盖审计 = `coverage-reviewer` agent /
视觉门 = gstack `/design-review` / 行为审 = `task-verify`。**那两道是 LLM skill/agent，
无法当子进程脚本调起** —— 所以本脚本不“跑”三道审，只固化能确定性固化的两件事：

  - **resolve**：解析 + 校验输入（范围清单 `req-plan.md` / `prototype/` / dev 端口），
    建 `audits/` 目录，打印 manifest（每道审读什么、把规范化结果写到哪、dev server 复用约定），
    **缺输入 fail-loud**（防对着缺失锚点跑审、防覆盖审计无范围清单可比）。
  - **synthesize**：读 `audits/` 下三道规范化结果，**校验三道齐全**（漏跑 fail-loud，
    防 AI 漏跑一道还往下走），合成一份 `synthesis.md` 给 PM + 打印机器门禁 summary。

规范化结果 schema（task-execute 跑完每道后写，= 本脚本的输入契约）：
  audits/coverage.json : {"items":[{"name","status":"built|missing|degraded","note"}]}
  audits/visual.json   : {"findings":[{"severity":"P0|P1|P2","desc"}]}    (findings 空 = 视觉通过)
  audits/behavior.json : {"status":"pass|fail|skipped","passed":int,"total":int,"note"}

门禁（gate）只产**给 PM 看的建议**，不替 PM 拍板：clean / needs-review。

用法：
  build-audits.py resolve    <task-file> [--repo-root DIR]
  build-audits.py synthesize <task-file> [--repo-root DIR] [--fail-on-gate]
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


def _find_repo_root(task_file: Path, override: str | None) -> Path:
    if override:
        return Path(override).expanduser().resolve()
    # 优先 git 顶层（task 在 task worktree 里）
    try:
        top = subprocess.check_output(
            ["git", "-C", str(task_file.parent), "rev-parse", "--show-toplevel"],
            text=True, stderr=subprocess.DEVNULL,
        ).strip()
        if top:
            return Path(top)
    except Exception:
        pass
    # 回退：向上找含 .pm-workflow 的祖先
    for parent in [task_file.parent, *task_file.parents]:
        if (parent / ".pm-workflow").is_dir():
            return parent
    return task_file.parent


def _audit_dir(repo_root: Path, task_file: Path) -> Path:
    return repo_root / ".pm-workflow" / "tasks" / task_file.stem / "audits"


def _range_list(task_file: Path) -> Path:
    # task 文件住 <req-dir>/tasks/task-NNN.md → 范围清单 = <req-dir>/req-plan.md
    return task_file.parent.parent / "req-plan.md"


def _dev_ports(repo_root: Path) -> list[str]:
    """从 .pm-workflow/config.yml 取 dev_server.ports（轻量解析，不引 yaml 依赖）。"""
    cfg = repo_root / ".pm-workflow" / "config.yml"
    if not cfg.exists():
        return []
    ports: list[str] = []
    in_dev = False
    for raw in cfg.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0:
            in_dev = stripped.startswith("dev_server:")
            continue
        if in_dev and stripped.startswith("ports:"):
            rest = stripped[len("ports:"):].strip()
            if rest.startswith("[") and rest.endswith("]"):
                ports = [p.strip().strip("'\"") for p in rest[1:-1].split(",") if p.strip()]
            break
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


def cmd_resolve(task_file: Path, repo_root: Path) -> int:
    range_list = _range_list(task_file)
    prototype = repo_root / "prototype"
    audit_dir = _audit_dir(repo_root, task_file)
    ports = _dev_ports(repo_root)

    problems = []
    if not range_list.exists():
        problems.append(f"范围清单不存在：{range_list}（覆盖审计无锚点，先回范围确认产 req-plan.md）")
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

    print("[build-audits] 输入已校验，audits/ 已就绪。按下面 manifest 跑三道审，各写规范化结果：")
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
    print(f"        schema: {{\"findings\":[{{\"severity\":\"P0|P1|P2\",\"desc\"}}]}}（空 findings = 通过）")
    print()
    print(f"  ③ 行为审（task-verify 驱动 /browse 确定性路径；复用同一次 dev server）")
    print(f"     → task-verify 写 verify/report.md + 本道规范化结果 {beh}")
    print(f"        schema: {{\"status\":\"pass|fail|skipped\",\"passed\":int,\"total\":int,\"note\"}}")
    print()
    print(f"  dev server：覆盖审计不需要；视觉门 + 行为审**复用 task-execute 步骤 4 起的同一个**"
          f"（端口候选 {', '.join(ports)}），别各起各的。")
    print(f"  三道都写完 → 跑 `build-audits.py synthesize {task_file}` 合成一份给 PM。")
    return 0


def _render_synthesis(task_stem: str, cov: dict, vis: dict, beh: dict) -> tuple[str, dict]:
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

    out = [f"# 三道审合成报告 — {task_stem}", ""]
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
        "task": task_stem,
        "coverage": {"built": len(built), "missing": len(missing), "degraded": len(degraded)},
        "visual": {"P0": len(by_sev["P0"]), "P1": len(by_sev["P1"]), "P2": len(by_sev["P2"]),
                   "total": len(findings)},
        "behavior": {"status": beh_status, "passed": beh_passed, "total": beh_total},
        "gate": gate,
    }
    return "\n".join(out) + "\n", summary


def cmd_synthesize(task_file: Path, repo_root: Path, fail_on_gate: bool) -> int:
    audit_dir = _audit_dir(repo_root, task_file)
    cov = _load_audit(audit_dir / AUDIT_FILES["coverage"], "coverage")
    vis = _load_audit(audit_dir / AUDIT_FILES["visual"], "visual")
    beh = _load_audit(audit_dir / AUDIT_FILES["behavior"], "behavior")

    report, summary = _render_synthesis(task_file.stem, cov, vis, beh)
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
        sp.add_argument("task_file")
        sp.add_argument("--repo-root", default=None)
        if name == "synthesize":
            sp.add_argument("--fail-on-gate", action="store_true",
                            help="gate != clean 时返回非零（默认 0，门禁仅作给 PM 的建议）")
    args = p.parse_args()

    task_file = Path(args.task_file).expanduser()
    if not task_file.exists():
        _die(f"task 文件不存在：{task_file}")
    task_file = task_file.resolve()
    repo_root = _find_repo_root(task_file, args.repo_root)

    if args.cmd == "resolve":
        return cmd_resolve(task_file, repo_root)
    return cmd_synthesize(task_file, repo_root, args.fail_on_gate)


if __name__ == "__main__":
    raise SystemExit(main())
