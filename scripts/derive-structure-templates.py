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
CUSTOM_OUT = REPO_ROOT / "templates" / "工程结构约束-custom.md"

# 实现深度 prose 段落（4.5d.2：自然语言指引，不是结构化 enum）。
# 每档对应一组 paragraph，AI 在 task-execute 读这段做实现指引；PM 看这段
# 决定是否手改（删 auto-detected 标后视为手填，框架不再覆盖）。
DEPTH_GUIDANCE = {
    "prototype": [
        ("数据层", "默认 mock 静态数据（写死 JSON 在文件顶部）。不调真实接口、不写持久化层。"),
        ("权限层", "默认不做权限校验。任何角色都能看任何页面，无登录态、无权限矩阵。"),
        ("会话层", "默认不做 session 守护。无 session timeout、无失效跳登录、无 token 刷新、无并发登录踢出；登录页等相关页面只做静态呈现。"),
        ("API 契约", "默认不调外部接口。前端写死假数据；如需展示 loading 用 setTimeout 模拟。"),
        ("测试", "默认不写单测、e2e、集成测试。靠 PM 走查 + /qa 工具人肉验收。"),
        ("边界态", "默认主路径 loading + 成功两态即可。错误态 / 空态 / 部分态等不必实现。"),
        ("多端覆盖", "默认单端（PM 在 init 后于本段补「单端：tenant」之类的具体端名）。"),
        ("演示路径", "默认仅主路径（happy path）。分支路径、edge case 等 PM 不在 task-plan 显式拆 task 就不实现。"),
    ],
    "system": [
        ("数据层", "真实持久化（IndexedDB / 后端 API / 数据库），跨页状态由 store / context 承载。"),
        ("权限层", "完整权限矩阵：登录态 + 角色 + 资源访问控制。每个页面 / 操作有显式权限校验。"),
        ("会话层", "完整 session 守护：session timeout + 失效跳登录 + token 刷新 + 并发登录踢出；登录页含完整鉴权流与异常态。"),
        ("API 契约", "完整 API 定义（OpenAPI / GraphQL schema）+ 真实后端联调。前端不写假数据。"),
        ("测试", "完整测试覆盖:纯函数 ≥ 80% 单测；关键交互 e2e；引用稳定性测试覆盖核心 reducer / store。"),
        ("边界态", "全部边界态（loading / empty / error / partial / success / retry / timeout）。"),
        ("多端覆盖", "按 PM 在 init 时定的端数实现（单端 / 双端 / 三端齐全）。三端时复用同 store / hook 但 UI 各端独立。"),
        ("演示路径", "全路径（含分支 + edge case）。每个用户决策点都有对应实现。"),
    ],
}

# 文档输出深度 prose 段落（控制 task 文件「执行区」工程内容的展开深度）。
# AI 在 task-spec 写 task 单文件 typed contract 的执行区时读这段。
# delta-3：task-spec 双→单文件塌缩后，工程内容是 task 文件「执行区」、无独立 .engineering.md，
# 行数 lint（check-engineering-doc-size.py）随之退场。
# custom 档不预设（等真实 custom 项目实证后再写规则）。
DOC_DEPTH_GUIDANCE = {
    "prototype": [
        ("强制引用规则", "上游已定义的类型/接口/函数签名/产品行为禁止重写——直接写「参见 prd.md §X.Y」或「参见 implementation-design.md HOW-NN」。"),
        ("执行区·实现规格", "只列「差异点 / 复用点」，不再贴完整签名。"),
        ("执行区·约束与易错", "默认精简；视觉规范细则沿用 docs/DESIGN.md，不展开。"),
        ("执行区·工程层验收", "只列主路径 happy path，不展开错误/空/部分态。"),
    ],
    "system": [],  # 留空 → 渲染 placeholder。等真实 system 项目实证后回来写规则。
}

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
    """mode = 'prototype' / 'system' / 'custom'

    custom 档不读 schema，直接派生 placeholder 模板让 PM 自由编辑。
    prototype/system 档读 schema 的 signals 渲染「代码组织」段，再附 prose
    深度指引（来自 DEPTH_GUIDANCE，按 PM-DX 自然语言而不是 enum 表）。
    """
    if mode == "custom":
        return _render_custom_template()
    assert mode in {"prototype", "system"}
    action_key = f"{mode}_action"
    title = "原型档（prototype）" if mode == "prototype" else "系统档（system）"

    keep_lines: list[str] = []
    forbid_lines: list[str] = []
    required_lines: list[str] = []

    for sid in sorted(schema["signals"].keys()):
        sdef = schema["signals"][sid]
        action = sdef[action_key]
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
    out.append(f"<!-- 改动 schema 或 DEPTH_GUIDANCE 后跑 `python3 scripts/derive-structure-templates.py` 重新派生。 -->")
    out.append("")
    out.append(f"## 工程结构约束（{title}）")
    out.append("")
    out.append("> 视觉 token / 颜色 / 间距 / 字号 → 见 DESIGN.md，本段管代码组织 + 实现深度指引。")
    out.append("")
    out.append("**原型根目录（PM 必填）**：`<改成实际路径，例：prototypes/ 或 src/ 或 apps/web/src/>`")
    out.append("")

    out.append("### 代码组织")
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

    out.append("### 实现深度指引")
    out.append("")
    out.append("> 以下是 task-execute 阶段 AI 写代码时的深度参考。PM 可手改任意条；")
    out.append("> 删除上方 auto-detected 标后视为 PM 手填，框架不再覆盖。")
    out.append("")
    for label, prose in DEPTH_GUIDANCE[mode]:
        out.append(f"- **{label}**：{prose}")
    out.append("")

    out.append("### 文档输出深度指引")
    out.append("")
    out.append("> 以下是 task-spec 阶段 AI 写 task 单文件 typed contract「执行区」工程内容时的深度参考。")
    out.append("> PM 可手改任意条；删除上方 auto-detected 标后视为 PM 手填，框架不再覆盖。")
    out.append("")
    if DOC_DEPTH_GUIDANCE[mode]:
        for label, prose in DOC_DEPTH_GUIDANCE[mode]:
            out.append(f"- **{label}**：{prose}")
    else:
        out.append("_PM 填_：本档下 task 文件「执行区」工程内容的深度参考。")
        out.append("等到第一个真实 system 项目跑出来后基于实证写规则；现在留空。")
        out.append("常见维度：强制引用规则（避免重写上游）、各执行区段展开深度。")
    out.append("")

    out.append("### 约定")
    out.append("")
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


def _render_custom_template() -> str:
    """custom 档：不读 schema，给 PM 自由编辑骨架。"""
    out: list[str] = []
    out.append(f"<!-- AUTO-GENERATED FROM scripts/derive-structure-templates.py — DO NOT EDIT 本注释。 -->")
    out.append(f"<!-- custom 档：PM 自由编辑下方各 section 的内容。 -->")
    out.append("")
    out.append("## 工程结构约束（自定义档 custom）")
    out.append("")
    out.append("> custom 档不预设深度，PM 自由 prose 描述本项目的代码组织 + 实现深度。")
    out.append("> AI 在 task-execute 读这段做实现指引——写得越具体，AI 跑偏概率越低。")
    out.append("")
    out.append("**原型根目录（PM 必填）**：`<改成实际路径，例：prototypes/ 或 src/ 或 apps/web/src/>`")
    out.append("")
    out.append("### 代码组织")
    out.append("")
    out.append("_PM 填_：本项目代码组织规则（如「保留 components/ui，禁止抽 Template」之类）。")
    out.append("可参考 `templates/工程结构约束-prototype.md` / `工程结构约束-system.md` 的格式。")
    out.append("")
    out.append("### 实现深度指引")
    out.append("")
    out.append("_PM 填_：task-execute 阶段 AI 写代码的深度参考，自然语言描述即可。")
    out.append("常见维度：数据层 / 权限层 / API 契约 / 测试 / 边界态 / 多端 / 演示路径。")
    out.append("")
    out.append("### 约定")
    out.append("")
    out.append("_PM 填_：本项目特有的代码 / 设计约定。")
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
    custom_text = render_template(schema, "custom")

    outputs = [
        (PROTOTYPE_OUT, proto_text),
        (SYSTEM_OUT, sys_text),
        (CUSTOM_OUT, custom_text),
    ]

    if args.check:
        diffs: list[str] = []
        for path, expected in outputs:
            if not path.exists():
                diffs.append(f"{path.name}: 不存在")
                continue
            actual = path.read_text(encoding="utf-8")
            if actual != expected:
                diffs.append(f"{path.name}: 与 schema/DEPTH_GUIDANCE 派生结果不一致")
        if diffs:
            print("❌ 模板漂移：", file=sys.stderr)
            for d in diffs:
                print(f"   - {d}", file=sys.stderr)
            print(
                "\n修复：跑 `python3 scripts/derive-structure-templates.py` 重新派生 "
                "并 git add 三份模板。",
                file=sys.stderr,
            )
            return 1
        print("✅ 模板与 schema/DEPTH_GUIDANCE 一致")
        return 0

    for path, text in outputs:
        path.write_text(text, encoding="utf-8")
    print(f"✅ 派生完成: {', '.join(p.name for p, _ in outputs)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
