#!/usr/bin/env python3
"""checks-spec diff 引擎（§7.C 统一引擎，吸收自 prototype-live-align）。

一个**参照物无关**的对比引擎：拿一份 checks-spec（每页 must_have_text /
must_check_buttons[disabled] / must_cover_states）+ 两份抓取产物（reference / local），
对比出 P0/P1/P2 差异报告。三个消费场景共用同一引擎、只换参照物：

  - **覆盖审计**：checks 从 req-plan 范围清单派生；local = build 出的 prototype（reference 可空，只查 local 有没有 must-haves）
  - **对齐线上（§7.B）**：checks + reference = 爬线上真实产品；local = prototype
  - **站点爬（§7.A）**：checks + reference = 爬目标站；local = 重建出的 prototype

checks-spec schema 见 `skills/_shared/checks-spec.md`。抓取产物（reference/local）
由 caller 用 gstack `/browse` 抓出（每 check 一份 `<check_id>.json`，最小字段
url / title / textPreview / buttons[{text,disabled}]）。

用法：
    checks-diff.py --plan <checks-spec.json> --artifacts <dir> --report <out.md> [--todo <out.md>] [--fail-on-p0]
  artifacts 目录下放 reference/<check_id>.json + local/<check_id>.json（reference 缺省 = 仅查 local must-haves）。
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Issue:
    severity: str  # P0/P1/P2
    check_id: str
    title: str
    detail: str


# 单个抓取产物 JSON 解析失败的哨兵：文件在但非合法 JSON。返回它（而非抛 SystemExit），
# 让 build() 对该 check 报 P0、不崩掉整份报告（与 shape 错误的处理对齐）。
PARSE_ERROR = object()


def load_json(path: Path):
    """读单个抓取产物：缺 → None；非法 JSON → PARSE_ERROR 哨兵（不抛、由 caller 决定）。"""
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return PARSE_ERROR


def _read_plan(plan_path: Path) -> dict[str, Any]:
    """读 checks-spec 计划（operator 输入）—— 解析失败 fail-loud 友好报错，不抛裸 traceback。"""
    try:
        return json.loads(plan_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"[checks-diff] 计划文件 JSON 解析失败: {plan_path}\n{exc}")


def _btn_text(text: Any) -> str:
    return "" if text is None else str(text).strip()


def button_disabled_map(artifact: dict[str, Any]) -> dict[str, bool]:
    result: dict[str, bool] = {}
    buttons = artifact.get("buttons", []) or []
    if not isinstance(buttons, list):  # 抓取产物畸形（buttons 不是数组）→ 当空，不崩
        buttons = []
    for btn in buttons:
        if not isinstance(btn, dict):
            continue
        text = _btn_text(btn.get("text"))
        if text and text not in result:
            result[text] = bool(btn.get("disabled", False))
    return result


def compare_check(
    check: dict[str, Any],
    reference: dict[str, Any] | None,
    local: dict[str, Any] | None,
) -> list[Issue]:
    """对比单个 check。reference 可空（=覆盖审计场景，只查 local 有没有 must-haves）。"""
    issues: list[Issue] = []
    cid = str(check.get("id", "unknown"))

    # reference 畸形（非 dict，如顶层数组 / 错误对象）→ 当作无 reference（退覆盖审计模式）
    if reference is not None and not isinstance(reference, dict):
        reference = None

    if local is None:
        issues.append(Issue("P0", cid, "缺少本地抓取", f"未找到 local/{cid}.json"))
        return issues
    if not isinstance(local, dict):
        # 合法 JSON 但 shape 错（顶层数组 / 字符串 / null）→ 报 P0、不让单个畸形产物崩掉整份报告
        issues.append(Issue("P0", cid, "本地抓取畸形", f"local/{cid}.json 顶层不是 JSON 对象（应为 {{url,title,textPreview,buttons}}）"))
        return issues

    local_text = str(local.get("textPreview", ""))
    ref_text = str(reference.get("textPreview", "")) if reference else None

    # must_have_text：local 必须有；有 reference 时只报「reference 有而 local 缺」，
    # 无 reference（覆盖审计）时直接报 local 缺失。
    for token in check.get("must_have_text", []) or []:
        token = str(token).strip()
        if not token or token in local_text:
            continue
        if ref_text is None or token in ref_text:
            issues.append(Issue("P1", cid, "文案缺失", f"本地缺少文案：{token}"))

    local_buttons = button_disabled_map(local)
    ref_buttons = button_disabled_map(reference) if reference else None

    for expected in check.get("must_check_buttons", []) or []:
        text = _btn_text(expected.get("text"))
        if not text:
            continue
        if ref_buttons is not None and text not in ref_buttons:
            issues.append(Issue("P1", cid, "参照按钮未命中", f"参照抓取未找到按钮：{text}（确认抓取时机）"))
            continue
        if text not in local_buttons:
            issues.append(Issue("P0", cid, "本地按钮缺失", f"本地抓取未找到按钮：{text}"))
            continue
        exp_disabled = expected.get("disabled")
        if isinstance(exp_disabled, bool) and local_buttons[text] != exp_disabled:
            issues.append(Issue("P0", cid, "按钮禁用态不一致",
                               f"按钮[{text}] 期望 disabled={exp_disabled}，本地为 {local_buttons[text]}"))
        if ref_buttons is not None and ref_buttons.get(text) != local_buttons[text]:
            issues.append(Issue("P1", cid, "参照与本地按钮态不一致",
                               f"按钮[{text}] 参照 disabled={ref_buttons[text]}，本地 disabled={local_buttons[text]}"))

    if check.get("must_cover_states", []) or []:
        states = ", ".join(str(s) for s in check["must_cover_states"])
        issues.append(Issue("P2", cid, "状态覆盖需人工确认", f"在页面演示并人工确认状态覆盖：{states}"))

    # 无任何可执行断言 → 别让它静默算「无差异」（防假「全过」信心）
    if not (check.get("must_have_text") or check.get("must_check_buttons") or check.get("must_cover_states")):
        issues.append(Issue("P2", cid, "无可执行断言",
                           "该 check 未声明 must_have_text / must_check_buttons / must_cover_states——引擎未验证任何结构，勿据此判「无差异」"))

    return issues


def render_report(plan: dict[str, Any], issues: list[Issue]) -> str:
    grouped = defaultdict(list)
    for i in issues:
        grouped[i.severity].append(i)
    out = [f"# checks-diff 报告（{plan.get('module', 'unknown')}）", "", "## 统计", ""]
    out += [f"- P0: {len(grouped['P0'])}", f"- P1: {len(grouped['P1'])}",
            f"- P2: {len(grouped['P2'])}", f"- 总计: {len(issues)}", ""]
    out += ["## 明细", "", "| 级别 | 检查项 | 问题 | 详情 |", "|---|---|---|---|"]
    if not issues:
        out.append("| - | - | 无差异 | - |")
    for i in issues:
        out.append(f"| {i.severity} | {i.check_id} | {i.title} | {i.detail.replace('|', '/')} |")
    out += ["", "## 建议顺序", "",
            "1. 先 P0（结构/按钮缺失、禁用态错误）。",
            "2. 再 P1（核心文案与交互差异）。",
            "3. 最后 P2（视觉细节与状态演示补齐）。",
            "",
            "> 视觉细则（sticky/横滚/禁 native alert·confirm 用包装组件/留白密度/四态覆盖）"
            "照项目 `docs/DESIGN.md` + `工程结构约束-*.md`，本引擎只查结构/文案/按钮态。", ""]
    return "\n".join(out) + "\n"


def render_todo(plan: dict[str, Any], issues: list[Issue]) -> str:
    by_check: dict[str, list[Issue]] = defaultdict(list)
    for i in issues:
        by_check[i.check_id].append(i)
    out = [f"# Patch TODO（{plan.get('module', 'unknown')}）", ""]
    for check in plan.get("checks", []) or []:
        cid = str(check.get("id", "unknown"))
        out += [f"## [{cid}] {check.get('level', '?')} / {check.get('kind', 'page')}", ""]
        if cid not in by_check:
            out += ["- [ ] 无自动差异，人工复核视觉细节", ""]
            continue
        for i in by_check[cid]:
            out.append(f"- [ ] [{i.severity}] {i.title}：{i.detail}")
        if check.get("must_cover_states"):
            out.append(f"- [ ] 演示状态覆盖：{', '.join(str(s) for s in check['must_cover_states'])}")
        out.append("")
    return "\n".join(out) + "\n"


def build(plan_path: Path, artifacts_root: Path) -> list[Issue]:
    plan = _read_plan(plan_path)
    checks = plan.get("checks", []) or []
    if not checks:
        raise SystemExit("[checks-diff] 计划中 checks 为空")
    issues: list[Issue] = []
    for check in checks:
        cid = str(check.get("id", "")).strip()
        if not cid:
            issues.append(Issue("P0", "unknown", "计划字段错误", "check.id 为空"))
            continue
        # cid 拼进 artifacts 路径，且 checks-spec 可由爬站/线上 AI 派生 → 防路径穿越：
        # 仅允许字母数字 . _ -（regex 已排除 / \），并禁 . / .. 当组件名。
        if cid in {".", ".."} or not re.fullmatch(r"[A-Za-z0-9._-]+", cid):
            issues.append(Issue("P0", cid, "计划字段错误",
                               f"check.id 含非法字符（仅允许字母数字 . _ -，禁路径分隔与 ..）：{cid}"))
            continue
        ref = load_json(artifacts_root / "reference" / f"{cid}.json")
        if ref is PARSE_ERROR:
            ref = None  # 畸形 reference → 退覆盖审计模式（只查 local must-haves）
        local = load_json(artifacts_root / "local" / f"{cid}.json")
        if local is PARSE_ERROR:
            issues.append(Issue("P0", cid, "本地抓取畸形", f"local/{cid}.json 非合法 JSON（解析失败），单条不崩整份报告"))
            continue
        issues.extend(compare_check(check, ref, local))
    return issues


def main() -> int:
    p = argparse.ArgumentParser(description="checks-spec diff 引擎")
    p.add_argument("--plan", required=True, help="checks-spec JSON 路径")
    p.add_argument("--artifacts", required=True, help="抓取产物根目录（reference/ + local/）")
    p.add_argument("--report", required=True, help="输出报告 .md")
    p.add_argument("--todo", help="输出 patch TODO .md（可选）")
    p.add_argument("--fail-on-p0", action="store_true", help="有 P0 时返回非零退出码")
    args = p.parse_args()

    plan_path, artifacts_root = Path(args.plan), Path(args.artifacts)
    if not plan_path.exists():
        raise SystemExit(f"[checks-diff] 计划文件不存在：{plan_path}")

    plan = _read_plan(plan_path)
    issues = build(plan_path, artifacts_root)

    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(render_report(plan, issues), encoding="utf-8")
    print(f"[checks-diff] 报告：{report_path}")
    if args.todo:
        todo_path = Path(args.todo)
        todo_path.parent.mkdir(parents=True, exist_ok=True)
        todo_path.write_text(render_todo(plan, issues), encoding="utf-8")
        print(f"[checks-diff] TODO：{todo_path}")

    p0 = sum(1 for i in issues if i.severity == "P0")
    print(f"[checks-diff] issue 总数：{len(issues)}，P0：{p0}")
    return 2 if (args.fail_on_p0 and p0 > 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())
