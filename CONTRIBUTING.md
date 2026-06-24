# Contributing

PMAI is a small framework generator. Keep changes tight, because files under
`scripts/`, `skills/`, `templates/`, `agents/`, and `hooks/` ship into consumer
repos.

## Before You Change Code

1. Read `CLAUDE.md` for repository rules and current product positioning.
2. Read `RUNTIME.md` for current state and known open work.
3. If you touch consumer-facing assets, update `CHANGELOG.md` in the same commit.

## Verify

Run the full suite:

```bash
bash tests/run-all.sh
```

For install and exposure changes, also run:

```bash
bash bin/pmai --help
bash bin/pmai status
bash bin/pmai doctor
```

If you want to test the installed user-facing CLI rather than this repo-local
copy, run:

```bash
~/.pmai/bin/pmai status
~/.pmai/bin/pmai doctor
```

## Reporting Problems

Use the GitHub bug report template. Include:

- PMAI command or slash skill used.
- Exact terminal output.
- Whether you ran repo-local `bash bin/pmai ...` or installed `~/.pmai/bin/pmai ...`.
- `bash tests/run-all.sh` result if the issue is in this generator repo.
