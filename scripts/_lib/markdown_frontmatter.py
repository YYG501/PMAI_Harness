"""Minimal Markdown frontmatter parsing without any remote-provider dependency."""

from __future__ import annotations

import re


FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n?(.*)\Z", re.DOTALL)
FRONTMATTER_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.-]*):(.*)$")


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    match = FRONTMATTER_RE.match(text)
    if not match:
        return {}, text
    frontmatter: dict[str, str] = {}
    for line in match.group(1).splitlines():
        key_match = FRONTMATTER_KEY_RE.match(line.rstrip())
        if key_match:
            frontmatter[key_match.group(1)] = key_match.group(2).strip()
    return frontmatter, match.group(2)
