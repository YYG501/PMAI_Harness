# vendored `mattpocock/skills`

This directory contains the small set of upstream skills used as the design
interview reference for PMAI. It is a snapshot of
`mattpocock/skills` at commit
`0ab1b63a410a03d3627979a109c8695de27af954` (2026-08-20).

Included components:

- `grilling`: design-tree, frontier-round interviewing, and fact/decision separation;
- `domain-modeling`: terminology, boundary scenarios, and domain consistency checks;
- `grill-with-docs`: the upstream composition of those two skills;
- `prototype`: throwaway logic and UI validation when conversation is insufficient;
- `grill-me`: the upstream entry alias.

PMAI does not expose these files as separate user-facing commands. The
PMAI design skill adapts their method to PMAI's Proposal, decision receipt,
module-document, and build contracts. The snapshot is kept locally so the
framework remains reproducible and does not depend on a user's checkout or
network access at runtime.

The upstream project is MIT licensed; see `LICENSE`.
