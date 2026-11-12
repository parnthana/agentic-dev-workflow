---
description: Close a finished feature — verify PRs merged, wt-done, then gclean (asks before deleting)
argument-hint: <task-name>
---
Close the task `$ARGUMENTS` following ~/code/<workspace>/CLAUDE.md. Never use `--force` or `gclean -y`
without my explicit OK in this conversation.

Steps:
1. `wt-ls $ARGUMENTS` — if any worktree is dirty, has unpushed commits, or has no upstream (never pushed):
   STOP and report exactly what is pending. "upstream gone (merged?)" is fine — the remote branch was
   deleted after its PR merged; step 2 confirms it. Do not commit, push or discard anything yourself.
2. For each worktree branch, check the PR state: `gh pr list --state all --head <branch> --json number,state,baseRefName,url`.
   Also check the notes have a `## Checks run` entry (from `/verify`) for each merged branch's final commit; if
   not, say so (don't block on it, but call it out).
   Report dev PR + main PR per repo (a main PR may legitimately not exist — the notes say why). If any PR is not
   MERGED: stop and report.
2b. **Deployed?** The board ticket's Deployed field (`board list --task <task>` / notes `## Deploy gates`): not Prod
   and the change runs on a server (backend service, BFF, FE app) → STOP and propose `/deploy-gates $ARGUMENTS`
   (and `--prod`). Close anyway only when I say so, or the notes say no deploy is needed (docs/tests/dev-only); then
   write the reason into Current state.
3. Make sure `~/code/<workspace>/tasks/_notes/$ARGUMENTS.md` has the PR numbers/links and key decisions; add what's missing.
   Read the WHOLE file (not the first screen) — later dated sections supersede earlier ones. Overwrite
   `## Current state → next action` with "Closed <date>: <what shipped>; deployed: <dev/prod/no>".
4. **Keep what was learned** (before the notes are archived) — in your persistent knowledge store (project docs or wiki):
   - durable knowledge from the notes (a gotcha, a data-model meaning, an infra fact, a decision that will matter
     again) → one entry each, indexed; update an existing entry instead of
     duplicating; never copy secrets;
   - the feature itself → one line in a features archive (what shipped, PR numbers, anything still open),
     not in the main index;
   - task-only progress (checks run, temporary blockers) is not durable knowledge — it stays in the archived notes.
   Show me the changes in one short list.
4a. **Brag entry**: `/brag add $ARGUMENTS` (one entry in `~/notes/brag/<year>.md`; at most 2 questions to me — the
   impact number, my role). No `## Outcome` in the notes and the change has user-visible behaviour → propose a
   success signal now (as in `/cases` 6c), so `/outcome` can measure it 7 days after the prod deploy.
4b. **Board**: `board done $ARGUMENTS` (draft + PR items → Done). An abandoned task: same command, and say
   "abandoned" in the features-archive line.
5. `wt-done $ARGUMENTS` (removes the task's worktrees in every repo, archives the notes to ~/notes/tasks/).
6. In each repo's main checkout (`~/code/<workspace>/<repo>`) run `gclean` (dry run) and show me the list.
   Only after I confirm: `gclean -y`.
