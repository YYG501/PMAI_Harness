"""Parse the current structured open-question section in a PMAI document."""

from __future__ import annotations

import re
from typing import NamedTuple


NO_OPEN_QUESTION_MARKERS = frozenset(
    {
        "全部已确认",
        "本次全部已确认",
        "本轮全部已确认",
        "本项目全部已确认",
        "本次没有待确认",
        "本次没有待确认事项",
        "本轮没有待确认",
        "本轮没有待确认事项",
        "本次工作无未决问题",
        "本轮工作无未决问题",
        "本项目无未决问题",
        "无待确认事项",
        "没有未决问题",
    }
)

OPEN_QUESTION_HEADINGS = ("未决问题", "待确认问题")
H2_OPEN_QUESTIONS = re.compile(
    rf"^##\s+({'|'.join(map(re.escape, OPEN_QUESTION_HEADINGS))})\s*$"
)
H2_ANY = re.compile(r"^##\s+")
MARKDOWN_HEADING = re.compile(r"^#{1,6}\s+")
Q_HEADER = re.compile(r"^###\s+(Q\d+)\s*[:：]\s*(.*)$", re.IGNORECASE)
PM_ANSWER_PREFIX = re.compile(r"^\*\*PM\s*回答\s*[:：]\*\*\s*(.*)$", re.IGNORECASE)
UNSTRUCTURED_QUESTION_MARKERS = ("待确认", "未决", "待回答", "TODO", "FIXME")
HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
FENCE_OPEN = re.compile(r"^[ \t]{0,3}(`{3,}|~{3,})(.*)$")
UNRESOLVED_PARTICIPANTS = (
    r"(?:(?:由\s*)?(?:PM|产品(?:经理)?|法务|业务|研发|设计|团队|相关方)"
    r"(?:\s*(?:和|与|及|、|/)\s*"
    r"(?:PM|产品(?:经理)?|法务|业务|研发|设计|团队|相关方))*\s*)?"
)
UNRESOLVED_ANSWER = re.compile(
    r"^(?:"
    r"(?:TODO|TBD|FIXME)(?=$|\s|[:：\-—]).*|"
    r"(?:待定|未定|不确定|未知)|"
    r"(?:暂无|尚无|没有|未形成)(?:明确)?(?:结论|决定|答案)?|"
    rf"(?:尚未|还未|未|待|尚待|仍需|需要|继续)\s*{UNRESOLVED_PARTICIPANTS}"
    r"(?:进一步)?\s*"
    r"(?:确认|决定|回答|拍板|定稿|填写|补充|讨论|评估|研究).*"
    r"|(?:稍后|之后|后续)(?:再)?(?:确认|决定|回答|拍板|定稿|填写|补充|整理).*"
    r")$",
    re.IGNORECASE,
)
INVALID_SECTION_TITLE = "开放问题 section 缺少可验证的问题或明确的无未决声明"


class OpenQuestion(NamedTuple):
    question_id: str
    title: str
    question_line: int
    answer_line: int | None
    text: str
    answered: bool

    @property
    def report_line(self) -> int:
        return self.answer_line or self.question_line


class OpenQuestionSection(NamedTuple):
    heading: str
    heading_line: int
    questions: tuple[OpenQuestion, ...]
    explicitly_none: bool

    @property
    def unresolved(self) -> tuple[OpenQuestion, ...]:
        if self.explicitly_none:
            return ()
        if not self.questions:
            return (
                OpenQuestion(
                    question_id="?",
                    title=INVALID_SECTION_TITLE,
                    question_line=self.heading_line,
                    answer_line=None,
                    text=INVALID_SECTION_TITLE,
                    answered=False,
                ),
            )
        return tuple(question for question in self.questions if not question.answered)


def _normalise_declaration(text: str) -> str | None:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if len(lines) != 1:
        return None

    value = re.sub(r"^(?:[-+*]|\d+[.)、])\s+", "", lines[0]).strip()
    for marker in ("**", "__"):
        if value.startswith(marker) and value.endswith(marker) and len(value) > len(marker) * 2:
            value = value[len(marker) : -len(marker)].strip()

    value = value.rstrip("。.!！").strip()
    if (value.startswith("（") and value.endswith("）")) or (
        value.startswith("(") and value.endswith(")")
    ):
        value = value[1:-1].strip().rstrip("。.!！").strip()
    return re.sub(r"\s+", "", value)


def explicitly_no_open_questions(text: str) -> bool:
    declaration = _normalise_declaration(text)
    return declaration in NO_OPEN_QUESTION_MARKERS if declaration is not None else False


def _mask_html_comments(text: str) -> str:
    """Hide comments while preserving newlines and source line numbers."""
    output: list[str] = []
    cursor = 0
    while cursor < len(text):
        start = text.find("<!--", cursor)
        if start < 0:
            output.append(text[cursor:])
            break
        output.append(text[cursor:start])
        end = text.find("-->", start + 4)
        end = len(text) if end < 0 else end + 3
        output.append("".join("\n" if char == "\n" else " " for char in text[start:end]))
        cursor = end
    return "".join(output)


def _visible_markdown_lines(text: str) -> list[str]:
    """Return visible Markdown lines with fenced examples blanked in place."""
    lines = _mask_html_comments(text).split("\n")
    visible: list[str] = []
    fence_char = ""
    fence_length = 0
    for line in lines:
        match = FENCE_OPEN.match(line)
        if fence_char:
            visible.append("")
            if match:
                marker, remainder = match.groups()
                if marker[0] == fence_char and len(marker) >= fence_length and not remainder.strip():
                    fence_char = ""
                    fence_length = 0
            continue
        if match:
            marker = match.group(1)
            fence_char = marker[0]
            fence_length = len(marker)
            visible.append("")
            continue
        visible.append(line)
    return visible


def _current_section(lines: list[str]) -> tuple[str, int, int, int] | None:
    """Return the last open-question H2 as the current section."""
    matches: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = H2_OPEN_QUESTIONS.match(line)
        if match:
            matches.append((index, match.group(1)))
    if not matches:
        return None

    heading_index, heading = matches[-1]
    start = heading_index + 1
    end = len(lines)
    for index in range(start, len(lines)):
        if H2_ANY.match(lines[index]):
            end = index
            break
    return heading, heading_index, start, end


def _answer_text(lines: list[str], answer_index: int, block_end: int) -> str:
    match = PM_ANSWER_PREFIX.match(lines[answer_index])
    if match is None:
        return ""

    answer_lines = [match.group(1)]

    for index in range(answer_index + 1, block_end):
        line = lines[index]
        if MARKDOWN_HEADING.match(line) or PM_ANSWER_PREFIX.match(line):
            break
        answer_lines.append(line)
    return "\n".join(answer_lines)


def _answer_is_filled(lines: list[str], answer_index: int, block_end: int) -> bool:
    value = HTML_COMMENT.sub("", _answer_text(lines, answer_index, block_end))
    value = re.sub(r"[`*_~]", "", value)
    value = re.sub(r"\s+", " ", value).strip().rstrip("。.!！").strip()
    if not value or value in {"-", "/"}:
        return False
    return UNRESOLVED_ANSWER.fullmatch(value) is None


def _is_unstructured_question(line: str) -> bool:
    stripped = line.strip()
    if not stripped or MARKDOWN_HEADING.match(stripped) or PM_ANSWER_PREFIX.match(stripped):
        return False
    return stripped.endswith(("?", "？")) or any(
        marker in stripped for marker in UNSTRUCTURED_QUESTION_MARKERS
    )


def parse_current_open_questions(text: str) -> OpenQuestionSection | None:
    """Parse only the latest `未决问题` / `待确认问题` H2 section.

    Structured Q blocks are resolved only by a non-empty `PM 回答`.  Free-form
    question lines remain a compatibility fallback for older discussion files,
    but content outside the current section is never treated as unresolved.
    """
    lines = _visible_markdown_lines(text)
    section = _current_section(lines)
    if section is None:
        return None
    heading, heading_index, start, end = section
    section_body = "\n".join(lines[start:end])
    explicitly_none = explicitly_no_open_questions(section_body)

    headers: list[tuple[int, re.Match[str]]] = []
    for index in range(start, end):
        match = Q_HEADER.match(lines[index])
        if match:
            headers.append((index, match))

    questions: list[OpenQuestion] = []
    for position, (question_index, match) in enumerate(headers):
        block_end = headers[position + 1][0] if position + 1 < len(headers) else end
        answer_index = next(
            (
                index
                for index in range(question_index + 1, block_end)
                if PM_ANSWER_PREFIX.match(lines[index])
            ),
            None,
        )
        questions.append(
            OpenQuestion(
                question_id=match.group(1).upper(),
                title=match.group(2).strip(),
                question_line=question_index + 1,
                answer_line=answer_index + 1 if answer_index is not None else None,
                text=lines[question_index].strip()[:500],
                answered=(
                    bool(match.group(2).strip())
                    and _answer_is_filled(lines, answer_index, block_end)
                    if answer_index is not None
                    else False
                ),
            )
        )

    fallback_end = headers[0][0] if headers else end
    for index in range(start, fallback_end):
        if not _is_unstructured_question(lines[index]):
            continue
        stripped = lines[index].strip()
        questions.append(
            OpenQuestion(
                question_id="?",
                title=re.sub(r"^[-+*]\s+", "", stripped)[:500],
                question_line=index + 1,
                answer_line=None,
                text=stripped[:500],
                answered=False,
            )
        )

    return OpenQuestionSection(
        heading=heading,
        heading_line=heading_index + 1,
        questions=tuple(questions),
        explicitly_none=explicitly_none,
    )
