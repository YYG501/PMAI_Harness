"""Parse whether a documented decision has been superseded.

The parser is shared by every consumer that reads PMAI decision documents so
the build context and landed terminology map cannot disagree about status.
"""

from __future__ import annotations

import re


ASSERTION_BOUNDARY_CHARS = frozenset("，,。；;！？?：:")
ASSERTION_CONNECTORS = ("结论为", "结论是", "但是", "不过", "然而", "而是", "而且", "并且", "同时", "另外", "但", "且")
ENGLISH_ASSERTION_CONNECTORS = ("however", "but", "yet")
ASSERTION_BRACKETS = {
    "《": "》",
    "「": "」",
    "『": "』",
    "（": "）",
    "(": ")",
    "【": "】",
    "[": "]",
    "“": "”",
    "‘": "’",
    '"': '"',
}
QUOTED_CONTENT_BRACKETS = {key: ASSERTION_BRACKETS[key] for key in ("《", "「", "『", "“", "‘", '"')}
STATE_QUESTION_CUES = ("是否", "会否", "能否", "是不是", "有没有", "何时", "为什么", "为何", "怎么", "如何")
STATE_QUESTION_SUFFIXES = ("吗", "么", "嘛", "呢")
STATE_QUESTION_PREFIXES = ("已经被", "现已被", "已被", "被", "已经由", "现已由", "已由", "由")
DEPRECATION_QUESTION_PREFIXES = (
    "已经废弃",
    "现已废弃",
    "已废弃",
    "废弃",
    "已经作废",
    "现已作废",
    "已作废",
    "作废",
    "不再有效",
)
NEGATED_PASSIVE_CUES = (
    "未被",
    "尚未被",
    "并未被",
    "从未被",
    "未曾被",
    "不曾被",
    "没有被",
    "不会被",
    "并非被",
    "不是被",
    "不应被",
    "无需被",
    "不可被",
    "不能被",
)
ACTIVE_NEGATED_PASSIVE_CUES = (
    "未被",
    "尚未被",
    "并未被",
    "从未被",
    "未曾被",
    "不曾被",
    "没有被",
    "并非被",
    "不是被",
)
ACTIVE_NEGATED_NAMED_CUES = (
    "未由",
    "尚未由",
    "并未由",
    "从未由",
    "未曾由",
    "不曾由",
    "没有由",
    "并非由",
    "不是由",
)
NON_FINAL_PASSIVE_CUES = (
    "被提议",
    "被建议",
    "被计划",
    "被考虑",
    "被讨论",
    "被问及",
    "被询问",
    "被拒绝",
    "可能被",
    "也许被",
    "或许被",
    "预计被",
    "预计会被",
    "准备被",
    "拟被",
    "将被",
    "将会被",
    "即将被",
    "应被",
    "应该被",
    "应当被",
    "待被",
)
UNCERTAIN_CUES = ("可能", "也许", "或许", "待确认", "待讨论", "有待确认", "有待讨论")
ACTIVE_STATE_CUES = ("恢复有效", "恢复为有效", "恢复生效", "重新生效", "仍有效", "仍然有效", "继续有效")
STATE_QUESTION_DIRECT_PREFIXES = (*DEPRECATION_QUESTION_PREFIXES, *ACTIVE_STATE_CUES)
INHERITED_STATE_PREFIXES = (
    "已经被",
    "现已被",
    "已被",
    "被",
    "已经由",
    "现已由",
    "已由",
    "由",
    *NEGATED_PASSIVE_CUES,
    *NON_FINAL_PASSIVE_CUES,
    "已经废弃",
    "现已废弃",
    "已废弃",
    "废弃",
    "已经作废",
    "现已作废",
    "已作废",
    "作废",
    "不再有效",
    "有效",
    "当前有效",
    *ACTIVE_STATE_CUES,
    "取消作废",
    "撤销作废",
    "解除废弃",
)
STATE_ASSERTION_MODIFIERS = r"(?:(?:正式|真正|明确|完全|彻底|实际|实质上))*"
NEGATED_DEPRECATION_RE = re.compile(
    r"(?:未|尚未|并未|从未|未曾|不曾|没有|并非|不是|不应|无需|不可|不能)"
    rf"(?:已经|现已|已)?{STATE_ASSERTION_MODIFIERS}(?:废弃|作废)|"
    rf"(?:并非|不是|尚未){STATE_ASSERTION_MODIFIERS}不再有效"
)
ACTIVE_NEGATED_DEPRECATION_RE = re.compile(
    r"(?:未|尚未|并未|从未|未曾|不曾|没有|并非|不是)"
    rf"(?:已经|现已|已)?{STATE_ASSERTION_MODIFIERS}(?:废弃|作废)|"
    rf"(?:并非|不是|尚未){STATE_ASSERTION_MODIFIERS}不再有效"
)
NORMATIVE_NEGATED_DEPRECATION_RE = re.compile(
    r"(?:不得|禁止|严禁|防止)[^，,。；;！？?：:]{0,24}(?:废弃|作废)$"
)
ENGLISH_STATE_ADVERB = r"(?:now|already|formally|officially|explicitly|fully|effectively|still)"
ENGLISH_SUPERSEDED_RE = re.compile(
    r"^(?:"
    r"(?:superseded|deprecated)(?:\s+by\b.*)?|"
    r"(?:(?!decision\b)[a-z0-9][a-z0-9'_-]*\s+){0,12}decision\b\s+"
    rf"(?:"
    rf"(?:is|was|are|were|remains|remained)\s+(?:{ENGLISH_STATE_ADVERB}\s+)*|"
    rf"(?:has|have|had)\s+(?:{ENGLISH_STATE_ADVERB}\s+)*been\s+"
    rf"(?:{ENGLISH_STATE_ADVERB}\s+)*|"
    rf"(?:{ENGLISH_STATE_ADVERB}\s+)*"
    rf")"
    r"(?:superseded|deprecated)(?:\s+by\b.*)?"
    r")$",
    re.IGNORECASE,
)
ENGLISH_QUESTION_RE = re.compile(
    r"^\s*(?:is|was|are|were|has|have|can|could|should|would|will|may|might|if)\b|"
    r"\bwhether\b",
    re.IGNORECASE,
)
ENGLISH_NON_FINAL_RE = re.compile(
    r"\b(?:not|never|may|might|could|should|would|possibly|perhaps|proposed|suggested|planned|considered|pending)\b",
    re.IGNORECASE,
)
ENGLISH_ACTIVE_RE = re.compile(
    r"^(?:(?:this\s+)?decision\s+)?"
    r"(?:(?:is|was|remains|remained)\s+)?(?:still\s+)?(?:active|current|valid)$",
    re.IGNORECASE,
)
ENGLISH_ACTIVE_NEGATED_RE = re.compile(
    r"^(?:(?:this\s+)?decision\s+)?"
    r"(?:"
    r"(?:(?:is|was|remains|remained)\s+)(?:still\s+)?(?:not(?:\s+yet)?|never)\s+|"
    r"(?:still\s+)?(?:not(?:\s+yet)?|never)(?:\s+been)?\s+|"
    r"(?:has|have|had)\s+(?:not(?:\s+yet)?|never)\s+been\s+"
    r")"
    r"(?:superseded|deprecated)(?:\s+by\b.*)?$",
    re.IGNORECASE,
)
ENGLISH_REACTIVATED_RE = re.compile(
    r"\b(?:reinstated|reactivated|valid\s+again|active\s+again)\b",
    re.IGNORECASE,
)
ENGLISH_NON_ASSERTIVE_STATE_RE = re.compile(
    r"\b(?:if|when|whenever|once|before|after)\b[^.;:!?]*\b(?:superseded|deprecated)\b|"
    r"\b(?:superseded|deprecated)\b\s+(?:if|when|whenever|before|after)\b",
    re.IGNORECASE,
)
CHINESE_CONDITIONAL_STATE_RE = re.compile(
    r"如果|一旦|(?:^|决定|规则|方案|状态)(?:当(?!前|期)|若(?!干))"
)
CURRENT_DECISION_RE = re.compile(r"^(?:(?:本|该|此)(?:项)?决定|当前决定)")
ENGLISH_CURRENT_DECISION_RE = re.compile(
    r"^(?:decision|(?:this|current|the\s+current|present)\s+decision)\b",
    re.IGNORECASE,
)
ENGLISH_INHERITED_STATE_RE = re.compile(
    r"^(?:"
    r"superseded|deprecated|active|current|valid|reinstated|reactivated|"
    r"is|was|are|were|has|have|had|remains|remained|still|now|already|formally|officially"
    r")\b",
    re.IGNORECASE,
)
BODY_STATUS_LINE_RE = re.compile(
    r"^(?:[-*]\s*)?(?:状态|status)\s*[：:]\s*(.+)$",
    re.IGNORECASE,
)
UNRESOLVED_DECISION_PARTICIPANTS = (
    r"(?:(?:由\s*)?(?:PM|产品(?:经理)?|法务|业务|研发|设计|团队|相关方)"
    r"(?:\s*(?:和|与|及|、|/)\s*"
    r"(?:PM|产品(?:经理)?|法务|业务|研发|设计|团队|相关方))*\s*)?"
)
UNRESOLVED_DECISION_RE = re.compile(
    rf"(?:尚未|还未|未|待|尚待|仍需|需要|继续)\s*{UNRESOLVED_DECISION_PARTICIPANTS}"
    r"(?:进一步)?\s*(?:确认|决定|回答|拍板|定稿|讨论|评估|研究)|"
    r"(?:暂无|尚无|没有|未形成)(?:明确)?(?:结论|决定)|"
    r"(?:有待)(?:进一步)?(?:确认|讨论)|待定|未定|不确定|未知|"
    r"(?:后续|稍后|之后)(?:再)?(?:讨论|确认|决定|评估)|"
    r"\b(?:pending|undecided|unconfirmed|unknown|tbd|todo|not\s+yet\s+"
    r"(?:confirmed|decided|answered)|to\s+be\s+(?:confirmed|decided|answered))\b",
    re.IGNORECASE,
)
DECISION_LABEL_RE = re.compile(
    r"^(?:结论|决定|最终方案|拍板结果|PM\s*回答)\s*[：:]\s*\S+",
    re.IGNORECASE,
)
DECISION_METADATA_RE = re.compile(
    r"^(?:业务术语|术语|用户角色|角色)\s*[：:]",
    re.IGNORECASE,
)
CANDIDATE_CONTEXT_RE = re.compile(
    r"^(?:候选(?:答案|方案)?|备选(?:答案|方案)?|可选方案|选项|背景|问题描述)"
    r"(?:\s*[A-Z0-9一二三四五六七八九十]+)?\s*(?:[：:]|$)",
    re.IGNORECASE,
)
CANDIDATE_OPTION_RE = re.compile(
    r"^(?:[A-Z]|\d+|[一二三四五六七八九十]+)\s*[.)、：:]",
    re.IGNORECASE,
)
def _strip_markup(value: str) -> str:
    value = re.sub(r"<!--.*?-->", "", value, flags=re.DOTALL)
    value = re.sub(r"[`*_~]", "", value)
    value = re.sub(r"<br\s*/?>", " ", value, flags=re.IGNORECASE)
    value = value.strip().strip('"“”「」『』')
    return re.sub(r"\s+", " ", value).strip()


def _yet_modifies_negated_state(value: str, *, clause_start: int, yet_index: int) -> bool:
    """Keep `not yet superseded` together while retaining contrastive `yet`."""
    cursor = yet_index
    while cursor > clause_start and value[cursor - 1].isspace():
        cursor -= 1
    not_start = cursor - len("not")
    if (
        not_start < clause_start
        or value[not_start:cursor].lower() != "not"
        or (not_start > clause_start and value[not_start - 1].isalnum())
    ):
        return False

    cursor = yet_index + len("yet")
    while cursor < len(value) and value[cursor].isspace():
        cursor += 1
    if value[cursor : cursor + len("been")].lower() == "been" and (
        cursor + len("been") == len(value)
        or not value[cursor + len("been")].isalnum()
    ):
        cursor += len("been")
        while cursor < len(value) and value[cursor].isspace():
            cursor += 1
    return any(
        value[cursor : cursor + len(state)].lower() == state
        and (
            cursor + len(state) == len(value)
            or not value[cursor + len(state)].isalnum()
        )
        for state in ("superseded", "deprecated")
    )


def assertion_clauses(value: str) -> list[tuple[str, bool]]:
    """Split assertions once, preserving whether a clause ended as a question."""
    clauses: list[tuple[str, bool]] = []
    bracket_stack: list[str] = []
    start = 0
    index = 0
    while index < len(value):
        char = value[index]
        if bracket_stack and char == bracket_stack[-1]:
            bracket_stack.pop()
            index += 1
            continue
        if char in ASSERTION_BRACKETS:
            bracket_stack.append(ASSERTION_BRACKETS[char])
            index += 1
            continue
        if bracket_stack:
            index += 1
            continue
        if char in ASSERTION_BOUNDARY_CHARS:
            boundary_start = index
            while index < len(value) and value[index] in ASSERTION_BOUNDARY_CHARS:
                index += 1
            clause = value[start:boundary_start].strip()
            if clause:
                clauses.append((clause, any(marker in value[boundary_start:index] for marker in "?？")))
            start = index
            continue
        connector = next((item for item in ASSERTION_CONNECTORS if value.startswith(item, index)), None)
        if connector is None:
            connector = next(
                (
                    item
                    for item in ENGLISH_ASSERTION_CONNECTORS
                    if value.startswith(item, index)
                    and (index == 0 or not value[index - 1].isalnum())
                    and (index + len(item) == len(value) or not value[index + len(item)].isalnum())
                ),
                None,
            )
            if connector == "yet" and _yet_modifies_negated_state(
                value,
                clause_start=start,
                yet_index=index,
            ):
                connector = None
        if connector:
            clause = value[start:index].strip()
            if clause:
                clauses.append((clause, False))
            index += len(connector)
            start = index
            continue
        index += 1
    clause = value[start:].strip()
    if clause:
        clauses.append((clause, False))
    return clauses


def mask_quoted_content(value: str) -> str:
    """Hide quoted decision names so their wording cannot become status evidence."""
    masked = list(value)
    bracket_stack: list[str] = []
    for index, char in enumerate(value):
        if bracket_stack:
            masked[index] = " "
            if char == bracket_stack[-1]:
                bracket_stack.pop()
            elif char in QUOTED_CONTENT_BRACKETS:
                bracket_stack.append(QUOTED_CONTENT_BRACKETS[char])
            continue
        if char in QUOTED_CONTENT_BRACKETS:
            bracket_stack.append(QUOTED_CONTENT_BRACKETS[char])
            masked[index] = " "
    return "".join(masked)


def has_passive_replacement(value: str) -> bool:
    passive_index = value.find("被")
    return passive_index >= 0 and value.find("取代", passive_index + 1) >= 0


def has_named_replacer(value: str) -> bool:
    for marker in ("已经由", "现已由", "已由"):
        marker_index = value.find(marker)
        if marker_index >= 0 and value.find("取代", marker_index + len(marker)) >= 0:
            return True
    start = 0
    while True:
        marker_index = value.find("由", start)
        if marker_index < 0:
            return False
        if (marker_index == 0 or value.endswith(("决定", "结论", "规则", "方案", "策略"), 0, marker_index)) \
            and value.find("取代", marker_index + 1) >= 0:
            return True
        start = marker_index + 1


def has_active_negated_named_replacement(value: str) -> bool:
    for cue in ACTIVE_NEGATED_NAMED_CUES:
        cue_index = value.find(cue)
        if cue_index >= 0 and value.find("取代", cue_index + len(cue)) >= 0:
            return True
    return False


def is_state_question(value: str) -> bool:
    replacement_index = value.rfind("取代")
    for cue in STATE_QUESTION_CUES:
        start = 0
        while True:
            cue_index = value.find(cue, start)
            if cue_index < 0:
                break
            remainder_start = cue_index + len(cue)
            if value.startswith(STATE_QUESTION_DIRECT_PREFIXES, remainder_start):
                return True
            if value.startswith(STATE_QUESTION_PREFIXES, remainder_start) \
                and replacement_index >= remainder_start:
                return True
            start = remainder_start
    if value.endswith(STATE_QUESTION_SUFFIXES):
        statement = value[:-1]
        return (
            has_passive_replacement(statement)
            or has_named_replacer(statement)
            or any(marker in statement for marker in ("废弃", "作废", "不再有效"))
            or any(marker in statement for marker in ACTIVE_STATE_CUES)
            or ENGLISH_SUPERSEDED_RE.search(statement) is not None
        )
    return False


def is_question_text(value: str) -> bool:
    """Recognize question-shaped decision text, including status questions without punctuation."""
    cleaned = _strip_markup(value).strip()
    cleaned = re.sub(r"^(?:#{1,6}\s+|[-*+]\s+|\d+[.)、]\s*)", "", cleaned, count=1)
    cleaned = re.sub(r"^D\d+[.、：:\s-]*", "", cleaned, count=1, flags=re.IGNORECASE)
    if not cleaned:
        return False
    compact = re.sub(r"\s+", "", cleaned)
    return (
        cleaned.endswith(("?", "？"))
        or compact.startswith(STATE_QUESTION_CUES)
        or is_state_question(compact)
        or ENGLISH_QUESTION_RE.search(cleaned.lower()) is not None
    )


def decision_is_question(title: str, body: str) -> bool:
    """Reject unresolved questions without discarding sections with a conclusion."""
    body_has_question = any(
        is_question_text(line)
        for line in body.splitlines()
        if _strip_markup(line).strip()
    )
    if not is_question_text(title) and not body_has_question:
        return False
    return not body_has_decision_resolution(body)


def is_reactivated(value: str, lowered: str) -> bool:
    if any(cue in value for cue in ACTIVE_STATE_CUES) or ENGLISH_REACTIVATED_RE.search(lowered):
        return True
    for state in ("不再有效状态", "废弃状态", "作废状态", "废弃结论", "作废结论"):
        state_index = value.find(state)
        if state_index < 0:
            continue
        remainder = value[state_index + len(state) :]
        if any(action in remainder for action in ("解除", "撤销", "取消")):
            return True
    return any(phrase in value for phrase in ("取消作废", "撤销作废", "解除废弃"))


def has_deprecation_assertion(value: str) -> bool:
    """Require deprecation to be asserted, not merely name a deprecated object."""
    status = r"(?:已经|现已|已)?(?:废弃|作废)|不再有效"
    return re.search(rf"(?:{status})(?:了)?$", value) is not None or re.search(
        rf"[（(【\[](?:{status})(?:了)?[）)】\]]$",
        value,
    ) is not None


def is_non_assertive_state_context(value: str, lowered: str) -> bool:
    """Reject conditions, timelines and attribute labels that only mention a status."""
    has_chinese_state = any(marker in value for marker in ("取代", "废弃", "作废", "不再有效"))
    if has_chinese_state and CHINESE_CONDITIONAL_STATE_RE.search(value):
        return True
    if re.search(r"(?:取代|废弃|作废|不再有效)(?:时|前|后|的)", value):
        return True
    return ENGLISH_NON_ASSERTIVE_STATE_RE.search(lowered) is not None


def assertion_clause_status(clause: str, *, question: bool) -> bool | None:
    semantic_clause = mask_quoted_content(clause)
    compact = re.sub(r"\s+", "", semantic_clause)
    lowered = semantic_clause.lower().strip()
    passive_replacement = has_passive_replacement(compact)
    named_replacer = has_named_replacer(compact)
    active_negated_named_replacement = has_active_negated_named_replacement(compact)
    replacement = passive_replacement or named_replacer or active_negated_named_replacement
    deprecation = has_deprecation_assertion(compact)
    english_superseded = ENGLISH_SUPERSEDED_RE.search(lowered) is not None
    english_active_negated = ENGLISH_ACTIVE_NEGATED_RE.fullmatch(lowered) is not None
    has_state = replacement or deprecation or english_superseded or english_active_negated

    if question or is_state_question(compact) or ENGLISH_QUESTION_RE.search(lowered):
        return None
    if is_non_assertive_state_context(compact, lowered):
        return None
    if english_active_negated:
        return False
    if has_state and (
        any(cue in compact for cue in UNCERTAIN_CUES)
        or ENGLISH_NON_FINAL_RE.search(lowered)
        or (passive_replacement and any(cue in compact for cue in NON_FINAL_PASSIVE_CUES))
    ):
        return None
    if is_reactivated(compact, lowered):
        return False
    if passive_replacement and any(cue in compact for cue in ACTIVE_NEGATED_PASSIVE_CUES):
        return False
    if active_negated_named_replacement:
        return False
    if passive_replacement and any(cue in compact for cue in NEGATED_PASSIVE_CUES):
        return None
    if deprecation and NORMATIVE_NEGATED_DEPRECATION_RE.search(compact):
        return None
    if deprecation and ACTIVE_NEGATED_DEPRECATION_RE.search(compact):
        return False
    if deprecation and NEGATED_DEPRECATION_RE.search(compact):
        return None
    if ENGLISH_ACTIVE_RE.fullmatch(lowered) or compact in {"有效", "当前有效"}:
        return False
    if replacement or deprecation or english_superseded:
        return True
    return None


def _clause_targets_current_decision(clause: str, *, first: bool) -> bool:
    if first:
        return True
    semantic_clause = mask_quoted_content(clause).strip()
    compact = re.sub(r"\s+", "", semantic_clause)
    lowered = semantic_clause.lower()
    if CURRENT_DECISION_RE.match(compact) or ENGLISH_CURRENT_DECISION_RE.match(lowered):
        return True
    if compact.startswith(INHERITED_STATE_PREFIXES):
        return True
    return ENGLISH_INHERITED_STATE_RE.match(lowered) is not None


def asserted_status(value: str) -> bool | None:
    status: bool | None = None
    cleaned = _strip_markup(value).lower()
    cleaned = re.sub(r"^d\d+[.、：:\s-]*", "", cleaned, count=1, flags=re.IGNORECASE)
    for index, (clause, question) in enumerate(assertion_clauses(cleaned)):
        if not _clause_targets_current_decision(clause, first=index == 0):
            continue
        clause_status = assertion_clause_status(clause, question=question)
        if clause_status is not None:
            status = clause_status
    return status


def _normalise_body_line(raw_line: str) -> str:
    line = _strip_markup(raw_line).strip().rstrip("。.!！")
    return re.sub(r"^(?:[-*+]\s+|\d+[.)、]\s*)", "", line, count=1)


def _body_line_asserted_status(line: str) -> bool | None:
    lowered = line.lower()
    match = BODY_STATUS_LINE_RE.match(line)
    if match:
        payload = match.group(1)
    elif re.match(r"^(?:superseded|deprecated)\s+by\b", lowered):
        payload = lowered
    else:
        match = CURRENT_DECISION_RE.match(line)
        if match:
            payload = line[match.end() :].strip()
        elif ENGLISH_CURRENT_DECISION_RE.match(line):
            payload = line
        else:
            return None
    return asserted_status(payload)


def body_asserted_status(body: str) -> bool | None:
    """Return the last explicit status assertion about the current decision."""
    status: bool | None = None
    for raw_line in body.splitlines():
        line_status = _body_line_asserted_status(_normalise_body_line(raw_line))
        if line_status is not None:
            status = line_status
    return status


def body_has_decision_resolution(body: str) -> bool:
    """Return whether the last substantive body signal closes the decision."""
    resolved = False
    in_candidate_block = False
    for raw_line in body.splitlines():
        is_list_item = re.match(r"^\s*(?:[-*+]|\d+[.)、])\s+", raw_line) is not None
        line = _normalise_body_line(raw_line)
        if not line:
            continue

        if DECISION_METADATA_RE.match(line):
            continue
        if is_question_text(line) or UNRESOLVED_DECISION_RE.search(line):
            resolved = False
            continue
        if _body_line_asserted_status(line) is not None:
            resolved = True
            in_candidate_block = False
            continue
        if CANDIDATE_CONTEXT_RE.match(line):
            in_candidate_block = True
            continue
        if CANDIDATE_OPTION_RE.match(line) or (in_candidate_block and is_list_item):
            continue
        if DECISION_LABEL_RE.match(line):
            resolved = True
            in_candidate_block = False
            continue
        if in_candidate_block:
            in_candidate_block = False
    return resolved


def decision_is_superseded(title: str, body: str) -> bool:
    status: bool | None = True if "~~" in title else asserted_status(title)
    body_status = body_asserted_status(body)
    if body_status is not None:
        status = body_status
    return status is True
