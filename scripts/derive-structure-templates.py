#!/usr/bin/env python3
"""派生 templates/工程结构约束-{prototype,system}.md。

读 templates/工程结构约束.schema.json（单一 source of truth），按
signal 的 prototype_action / system_action 字段，分别派生两份 markdown
模板。模板含明显的「自动生成」标头，避免手改漂移。

用法：
    python3 scripts/derive-structure-templates.py             # 派生 → 写文件
    python3 scripts/derive-structure-templates.py --check     # 只校验现有文件 vs schema 一致（CI / golden test 用）

退出码：
    0 = 派生成功 / 一致
    1 = 不一致（--check 模式）或写失败
    2 = schema 校验失败 / 用法错
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = REPO_ROOT / "templates" / "工程结构约束.schema.json"
PROTOTYPE_OUT = REPO_ROOT / "templates" / "工程结构约束-prototype.md"
SYSTEM_OUT = REPO_ROOT / "templates" / "工程结构约束-system.md"

REQUIRED_SIGNAL_FIELDS = {
    "globs",
    "implies",
    "prototype_action",
    "system_action",
    "summary",
}
VALID_ACTIONS = {"forbid", "required", "keep"}
VALID_IMPLIES = {"system", "prototype-friendly"}


def validate_schema(schema: dict) -> list[str]:
    errors: list[str] = []
    if schema.get("schema_version") != 1:
        errors.append(f"schema_version 必须为 1，当前 {schema.get('schema_version')!r}")
    signals = schema.get("signals")
    if not isinstance(signals, dict) or not signals:
        errors.append("signals 必须是非空 dict")
        return errors
    for sid, sdef in signals.items():
        if not isinstance(sdef, dict):
            errors.append(f"signal {sid}: 必须是 dict")
            continue
        missing = REQUIRED_SIGNAL_FIELDS - set(sdef.keys())
        if missing:
            errors.append(f"signal {sid}: 缺字段 {sorted(missing)}")
        if sdef.get("implies") not in VALID_IMPLIES:
            errors.append(
                f"signal {sid}: implies 必须 ∈ {sorted(VALID_IMPLIES)}，当前 {sdef.get('implies')!r}"
            )
        if sdef.get("prototype_action") not in VALID_ACTIONS:
            errors.append(
                f"signal {sid}: prototype_action 必须 ∈ {sorted(VALID_ACTIONS)}"
            )
        if sdef.get("system_action") not in VALID_ACTIONS:
            errors.append(
                f"signal {sid}: system_action 必须 ∈ {sorted(VALID_ACTIONS)}"
            )
        globs = sdef.get("globs")
        if not isinstance(globs, list) or not globs:
            errors.append(f"signal {sid}: globs 必须是非空 list")
    if not isinstance(schema.get("scan_excludes"), list):
        errors.append("scan_excludes 必须是 list")
    if not isinstance(schema.get("scan_roots_default"), list):
        errors.append("scan_roots_default 必须是 list")
    return errors


def render_template(schema: dict, mode: str) -> str:
    """mode = 'prototype' or 'system'"""
    assert mode in {"prototype", "system"}
    action_key = f"{mode}_action"
    title = "原型档（prototype）" if mode == "prototype" else "系统档（system）"

    keep_lines: list[str] = []
    forbid_lines: list[str] = []
    required_lines: list[str] = []

    for sid in sorted(schema["signals"].keys()):
        sdef = schema["signals"][sid]
        action = sdef[action_key]
        # 第一个 glob 作为代表展示给 PM 看
        sample = sdef["globs"][0]
        item = f"- `{sample}` — {sdef['summary']}（signal: {sid}）"
        if action == "keep":
            keep_lines.append(item)
        elif action == "forbid":
            forbid_lines.append(item)
        elif action == "required":
            required_lines.append(item)

    out: list[str] = []
    out.append(f"<!-- AUTO-GENERATED FROM templates/工程结构约束.schema.json — DO NOT EDIT. -->")
    out.append(f"<!-- 改动 schema 后跑 `python3 scripts/derive-structure-templates.py` 重新派生。 -->")
    out.append("")
    out.append(f"## 工程结构约束（{title}）")
    out.append("")
    out.append("> 视觉 token / 颜色 / 间距 / 字号 → 见 DESIGN.md，本段仅管代码组织。")
    out.append("")
    out.append("**原型根目录**：`{prototype-root}`")
    out.append("")
    if keep_lines:
        out.append("**保留**（始终允许）：")
        out.extend(keep_lines)
        out.append("")
    if forbid_lines:
        out.append("**禁止**（本档下不允许）：")
        out.extend(forbid_lines)
        out.append("")
    if required_lines:
        out.append("**应有**（本档下应当出现）：")
        out.extend(required_lines)
        out.append("")
    out.append("**约定**：")
    if mode == "prototype":
        out.append("- 每页 self-contained，假数据写死在文件顶部")
        out.append("- 视觉一致性：DESIGN.md（token 源）+ components/ui（实现）")
        out.append("- 复用靠「复制样板文件改改」，不做抽象组件")
    else:
        out.append("- 共享数据流由 store / context 承载，禁止页面内重复 fetch / dedupe")
        out.append("- 同一交互模式必须抽 hook / Template，避免长尾分叉")
        out.append("- modules/<m>/pages 中间层由路由按业务域聚合")
    out.append("")
    return "\n".join(out)


def load_schema() -> dict:
    if not SCHEMA_PATH.exists():
        print(f"❌ schema 不存在: {SCHEMA_PATH}", file=sys.stderr)
        sys.exit(2)
    with SCHEMA_PATH.open(encoding="utf-8") as fh:
        try:
            return json.load(fh)
        except json.JSONDecodeError as exc:
            print(f"❌ schema JSON 解析失败: {exc}", file=sys.stderr)
            sys.exit(2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Derive 工程结构约束 templates from schema")
    parser.add_argument(
        "--check",
        action="store_true",
        help="只校验现有模板 vs schema 派生结果是否一致（CI / golden test 用）",
    )
    args = parser.parse_args()

    schema = load_schema()
    errors = validate_schema(schema)
    if errors:
        print("❌ schema 校验失败：", file=sys.stderr)
        for e in errors:
            print(f"   - {e}", file=sys.stderr)
        return 2

    proto_text = render_template(schema, "prototype")
    sys_text = render_template(schema, "system")

    if args.check:
        diffs: list[str] = []
        for path, expected in [(PROTOTYPE_OUT, proto_text), (SYSTEM_OUT, sys_text)]:
            if not path.exists():
                diffs.append(f"{path.name}: 不存在")
                continue
            actual = path.read_text(encoding="utf-8")
            if actual != expected:
                diffs.append(f"{path.name}: 与 schema 派生结果不一致")
        if diffs:
            print("❌ 模板与 schema 漂移：", file=sys.stderr)
            for d in diffs:
                print(f"   - {d}", file=sys.stderr)
            print(
                "\n修复：跑 `python3 scripts/derive-structure-templates.py` 重新派生 "
                "并 git add 两份模板。",
                file=sys.stderr,
            )
            return 1
        print("✅ 模板与 schema 一致")
        return 0

    PROTOTYPE_OUT.write_text(proto_text, encoding="utf-8")
    SYSTEM_OUT.write_text(sys_text, encoding="utf-8")
    print(f"✅ 派生完成: {PROTOTYPE_OUT.name} + {SYSTEM_OUT.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
