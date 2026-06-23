#!/usr/bin/env python3
"""check-open-questions.py — 未决问题闸门 lint 脚本

把「未决问题闸门（硬规则）」从 prose 防御抽出成机器校验。
历史 prose 入口曾在旧阶段门 skill；当前由 design / project-questioning 等调用。

适用对象：含 `## 未决问题` section 的产出文档（当前最严格落地在 analysis.md，
其他 stage 类似产出可比照适用）。

判定逻辑：
- 找 `## 未决问题` section（二级标题）
- 在该 section 内找所有 `**PM 回答：**` 行
- 判断每条 `**PM 回答：**` 之后是否有非空内容（同行后接文字 OR 后续行非空非新 section）
- 任一未答 → 退出 1 + 输出未答题号 / 行号到 stdout
- 全部已答（或 section 写"本次工作无未决问题"）→ 退出 0

注意：
- section 缺失 → 退出 0（许多 stage 文档没这 section，本脚本只在文档真有 section 时校验）
- "本次工作无未决问题" 显式声明也视为已答
- 只检测 `**PM 回答：**` 前缀；如果产出文档用了别的占位符（如 `**回答：**`）需要先把模板改齐再跑

用法:
  python3 scripts/check-open-questions.py <doc-file>
  python3 scripts/check-open-questions.py <doc-file> --quiet   # 只看 exit code，不打印未答清单
  python3 scripts/check-open-questions.py <doc-file> --require-section   # 缺 section 必须 fail

--require-section 模式：
  默认模式下「缺 `## 未决问题` section」静默退出 0 —— 对大多数 stage 文档是对的
  （它们没这 section）。但 strategy 把未决问题写进专用暂存文件后对它跑闸门，
  缺 section = 闸门形同虚设。该模式下缺 section 必须 fail（exit 1），不静默放行。

退出码:
  0  全部已答（或 section 不存在且未加 --require-section / section 内显式声明无未决问题）
  1  有未答（stdout 列出未答题号 / 行号）；或 --require-section 下缺 section
  2  参数错误 / 文件不存在
"""

import argparse
import re
import sys
from pathlib import Path

# `## 未决问题` 二级标题匹配（容忍前后空白 / 中文标点）
H2_OPEN_QUESTIONS = re.compile(r"^##\s+未决问题\s*$")
# 下一个二级标题（任何 ## 开头），用于界定 section 范围
H2_ANY = re.compile(r"^##\s+")
# 题目标题（### Q1: xxx）
Q_HEADER = re.compile(r"^###\s+(Q\d+)[:：]\s*(.*)$")
# `**PM 回答：**` 前缀（容忍中英冒号 + 全/半角空格）
PM_ANSWER_PREFIX = re.compile(r"^\*\*PM\s*回答\s*[:：]\*\*\s*(.*)$")
# section 内显式声明无未决问题
NO_OPEN_QUESTIONS = re.compile(r"本\s*(次工作|轮工作|工作)\s*无未决问题")


def find_section(lines):
    """返回 (start_idx, end_idx) 半开区间；section 不存在 → 返回 None。"""
    start = None
    for i, line in enumerate(lines):
        if H2_OPEN_QUESTIONS.match(line):
            start = i + 1  # section body 从下一行起
            break
    if start is None:
        return None

    end = len(lines)
    for j in range(start, len(lines)):
        if H2_ANY.match(lines[j]):
            end = j
            break
    return (start, end)


def is_answer_filled(lines, answer_idx, section_end):
    """判断第 answer_idx 行的 `**PM 回答：**` 是否已填内容。

    判定：
    - 同行 prefix 之后还有非空字符 → 已填
    - 否则看后续行：直到下一个 ### / ## / `**PM 回答：**` 之间，是否有任一非空行 → 已填
    """
    m = PM_ANSWER_PREFIX.match(lines[answer_idx])
    if not m:
        return False  # 不该走到这

    # 同行有内容 → 已填
    inline = m.group(1).strip()
    if inline:
        return True

    # 看后续行
    for k in range(answer_idx + 1, section_end):
        line = lines[k]
        # 遇到下一个题目 / 下一个 PM 回答 / 上级标题 → 中止
        if Q_HEADER.match(line) or PM_ANSWER_PREFIX.match(line) or H2_ANY.match(line):
            break
        if line.strip():
            return True
    return False


def find_open_questions(path):
    """返回未答列表 [(question_id, question_title, answer_line_no), ...]。"""
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")

    section = find_section(lines)
    if section is None:
        return []  # section 不存在 → 不触发闸门

    start, end = section

    # 显式声明无未决问题 → 全部视为已答
    section_body = "\n".join(lines[start:end])
    if NO_OPEN_QUESTIONS.search(section_body):
        return []

    unanswered = []
    current_q = ("?", "(未识别题目)")
    for i in range(start, end):
        line = lines[i]
        qm = Q_HEADER.match(line)
        if qm:
            current_q = (qm.group(1), qm.group(2).strip())
            continue
        if PM_ANSWER_PREFIX.match(line):
            if not is_answer_filled(lines, i, end):
                unanswered.append((current_q[0], current_q[1], i + 1))  # 1-based line no
    return unanswered


def main():
    parser = argparse.ArgumentParser(description="未决问题闸门 lint")
    parser.add_argument("doc", help="文档路径（如 analysis.md）")
    parser.add_argument("--quiet", action="store_true", help="只看 exit code，不打印")
    parser.add_argument(
        "--require-section",
        action="store_true",
        help="缺 `## 未决问题` section 时 fail（不静默放行）—— strategy 暂存文件用",
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

    if args.require_section:
        lines = path.read_text(encoding="utf-8").split("\n")
        if find_section(lines) is None:
            if not args.quiet:
                print(
                    f"⚠️ {path.name} 缺 `## 未决问题` section —— --require-section "
                    "模式下闸门不放行。请在文档里加 `## 未决问题` section "
                    "（无未决项则写「本次工作无未决问题」）。"
                )
            sys.exit(1)

    unanswered = find_open_questions(path)

    if not unanswered:
        if not args.quiet:
            print(f"✅ {path.name} 未决问题闸门通过（无未决项 / 全部已答）")
        sys.exit(0)

    if not args.quiet:
        print(f"⚠️ {path.name} 有 {len(unanswered)} 个未决问题需要 PM 先回答：")
        for qid, title, lineno in unanswered:
            print(f"  - {qid}（line {lineno}）：{title}")
    sys.exit(1)


if __name__ == "__main__":
    main()
