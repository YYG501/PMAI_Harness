#!/usr/bin/env python3
"""check-open-questions.py — 未决问题闸门 lint 脚本

把「未决问题闸门（硬规则）」从 prose 防御抽出成机器校验。
历史 prose 入口曾在旧阶段门 skill；当前由 design / project-questioning 等调用。

适用对象：含 `## 未决问题` 或 `## 待确认问题` section 的产出文档（当前最严格落地在 analysis.md，
其他 stage 类似产出可比照适用）。

判定逻辑：
- 找当前 `## 未决问题` / `## 待确认问题` section（二级标题）
- 在该 section 内按 `### Qn` 配对 `**PM 回答：**`
- 判断每道题是否有答案（同行后接文字 OR 后续行非空非新 section）
- 任一未答 → 退出 1 + 输出未答题号 / 行号到 stdout
- 全部已答（或 section 写"本次工作无未决问题"）→ 退出 0

注意：
- section 缺失 → 退出 0（许多 stage 文档没这 section，本脚本只在文档真有 section 时校验）
- "本次工作无未决问题" 显式声明也视为已答
- 结构化问题必须有 `**PM 回答：**`；如果产出文档用了别的占位符（如 `**回答：**`）需要先把模板改齐再跑

用法:
  python3 scripts/check-open-questions.py <doc-file>
  python3 scripts/check-open-questions.py <doc-file> --quiet   # 只看 exit code，不打印未答清单
  python3 scripts/check-open-questions.py <doc-file> --require-section   # 缺 section 必须 fail

--require-section 模式：
  默认模式下「缺开放问题 section」静默退出 0 —— 对大多数 stage 文档是对的
  （它们没这 section）。但 direction 把未决问题写进专用暂存文件后对它跑闸门，
  缺 section = 闸门形同虚设。该模式下缺 section 必须 fail（exit 1），不静默放行。

退出码:
  0  全部已答（或 section 不存在且未加 --require-section / section 内显式声明无未决问题）
  1  有未答（stdout 列出未答题号 / 行号）；或 --require-section 下缺 section
  2  参数错误 / 文件不存在
"""

import argparse
import sys
from pathlib import Path

from _lib.open_questions import parse_current_open_questions


def main():
    parser = argparse.ArgumentParser(description="未决问题闸门 lint")
    parser.add_argument("doc", help="文档路径（如 analysis.md）")
    parser.add_argument("--quiet", action="store_true", help="只看 exit code，不打印")
    parser.add_argument(
        "--require-section",
        action="store_true",
        help="缺 `## 未决问题` / `## 待确认问题` section 时 fail——direction 暂存文件用",
    )
    args = parser.parse_args()

    path = Path(args.doc)
    if not path.is_file():
        print(f"❌ 文件不存在: {args.doc}", file=sys.stderr)
        print(
            "   修复：检查路径拼写。"
            "若探索结论 / 待答问题文档还没生成，先跑 /pmai-design 段①探索（产出 discussion.md）。",
            file=sys.stderr,
        )
        sys.exit(2)

    text = path.read_text(encoding="utf-8")
    section = parse_current_open_questions(text)
    if args.require_section:
        if section is None:
            if not args.quiet:
                print(
                    f"⚠️ {path.name} 缺 `## 未决问题` / `## 待确认问题` section "
                    "—— --require-section 模式下闸门不放行。请在文档里加开放问题 section "
                    "（无未决项则写「本次工作无未决问题」）。"
                )
            sys.exit(1)

    unanswered = section.unresolved if section is not None else ()

    if not unanswered:
        if not args.quiet:
            print(f"✅ {path.name} 未决问题闸门通过（无未决项 / 全部已答）")
        sys.exit(0)

    if not args.quiet:
        print(f"⚠️ {path.name} 有 {len(unanswered)} 个未决问题需要 PM 先回答：")
        for question in unanswered:
            print(
                f"  - {question.question_id}（line {question.report_line}）："
                f"{question.title}"
            )
    sys.exit(1)


if __name__ == "__main__":
    main()
