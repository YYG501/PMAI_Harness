"""Shared recognition for explicit statements that no open questions remain."""

from __future__ import annotations

import re


NO_OPEN_QUESTION_MARKERS = (
    "全部已确认",
    "本轮没有待确认",
    "本次工作无未决问题",
    "本轮工作无未决问题",
    "无待确认事项",
    "没有未决问题",
)


def explicitly_no_open_questions(text: str) -> bool:
    compact = re.sub(r"\s+", "", text)
    return any(marker in compact for marker in NO_OPEN_QUESTION_MARKERS)
