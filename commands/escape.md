---
description: Record a bug that got past the process (found in CI, review, QA, by a user, or by me later) — origin task, where it leaked, one concrete line that closes the hole
argument-hint: <file:line or PR/ticket> <what goes wrong> [--found-by user|ci|review|qa|self]
---
Run the escape analysis for `$ARGUMENTS`, following `~/.claude/escape.md` exactly. READ-ONLY on code: the only writes
are the hole-closing line (qa-product-gaps.md / qa-checklist.md / a proposed qa*.md or deploy-gates edit) and the
`~/notes/escapes.md` row. Search with grep via Bash.

- `--found-by` missing → infer it from how the bug reached this session (a PR comment → `review`, a failed check →
  `ci`, a /qa report → `qa`, a support message → `user`); unsure → ask me one short question.
- No file:line yet → locate the faulty code first (grep, `git log -S`); can't locate → stop and say so — an
  escape row without an origin is noise.
- Already in `~/notes/escapes.md` (same origin PR + same faulty lines) → don't add a second row; say so.

Report: the one-line escape summary from escape.md, plus the line you added (path:line).
