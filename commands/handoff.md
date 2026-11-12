---
description: Write this session's state into the task notes (status, dead ends, open questions, next steps) so it can be closed and picked up cold
argument-hint: [task-name]
---
Hand off the current work so this session can be closed. Task = `$ARGUMENTS`, else the task of the current
worktree (`~/code/<workspace>/tasks/<repo>/<task>` → `<task>`; strip a `-main` suffix). Not in a task worktree and
no name given → ask me. Notes file: `~/code/<workspace>/tasks/_notes/<task>.md`.

Steps:
1. Collect facts, don't recall them: for each of the task's worktrees (`wt-ls <task>`) get branch, last commit
   (`git log -1 --oneline`), `git status --short`, unpushed commits, and PR state (`gh pr list --head <branch>`).
2. Read the existing notes so you add to them instead of repeating them.
3. Append a section (newest at the bottom, keep earlier handoffs):

```markdown
## Handoff <YYYY-MM-DD HH:MM>
- **State:** what is done and verified (tests/`/verify` run? on which commit?), what is half-done.
- **Branches:** repo · branch · last commit · dirty/unpushed · PR #/state.
- **Dead ends:** approaches tried and WHY they failed (with the evidence: query, error, file:line) — so the next
  session does not retry them.
- **Open questions:** what is still unknown + the exact query/command that would answer it.
- **Next steps:** numbered, concrete, first one doable immediately.
- **Files:** path:line of the places being changed.
- **Gates:** new DDL/SSM/deploy-order/prod-SQL needs discovered this session (`/deploy-gates` reads these).
```
   Decisions that hold beyond this session also go in the notes' decisions section, not only the handoff.
   Also OVERWRITE `## Current state → next action` (2–6 lines: state + Next step 1).
4. Uncommitted work: do NOT commit or stash it — list it under State and tell me.
4b. `board sync <task>` so the board ticket shows the new state (skip silently if the task has no ticket).
5. Durable knowledge (gotcha, data-model meaning, infra fact) → the persistent knowledge store (project docs or wiki),
   indexed. Session-only progress stays in the notes.

Finish with: the path of the notes file, the warnings (dirty/unpushed), and the command to pick it up again:
`wt-open <task> --prompt "Read tasks/_notes/<task>.md, last Handoff section, and continue from Next steps"`.
