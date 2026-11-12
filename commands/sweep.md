---
description: Sweep all tasks — wt-ls + PR state from the notes, grouped into ready-to-close / waiting / stale / never pushed / broken; proposes commands, deletes nothing
argument-hint: [--stale-days 14] [--weekly]
---
Sweep every task under `~/code/<workspace>/tasks/` (`$ARGUMENTS`: `--stale-days N`, default 14).
READ-ONLY (except the weekly status update below): never run `wt-done`, `gclean`, push, commit or discard anything — propose the commands.

Steps:
1. `wt-ls` → every task, its worktrees (repo/name), branch and state (dirty N, unpushed, no upstream,
   upstream gone, setup running/failed).
2. For each task read `~/code/<workspace>/tasks/_notes/<task>.md`: `## Current state → next action` first, then PR numbers
   and anything marked blocked/waiting (later dated sections supersede earlier ones). For each worktree branch get the PR state, run in parallel per repo from its main checkout
   (`~/code/<workspace>/<repo>`):
   `gh pr list --state all --head <branch> --json number,state,baseRefName,createdAt,mergedAt,url`
   (fall back to the numbers in the notes with `gh pr view <n> --json state,createdAt,mergedAt`).
   A missing main PR is fine when the notes say the change is dev-only.
3. Group each task into the FIRST bucket that fits:
   - ❌ **broken** — setup failed, or a worktree path is missing.
   - 📝 **unfinished local work** — dirty, unpushed, or no upstream (never pushed). Show what (e.g. "dirty 4").
     Age = days since the last commit, or since the newest modified file for dirty work
     (`git -C <wt> status --porcelain | awk '{print $2}' | xargs stat -f %m`). **Older than 3 days → prefix 🔴** and
     put it first: that work exists only on this machine.
   - 🐢 **stale** — an OPEN PR older than the stale-days limit, or no commit for that long. Show age in days.
   - ⏳ **waiting** — PRs open within the limit; say which one (dev / main) and whether dev is merged yet.
   - 🚚 **merged, not deployed** — every PR MERGED but the board's Deployed field is None/Dev (or the notes have
     unticked deploy gates). Next action: `/deploy-gates <task>` (dev, then `--prod`).
   - ✅ **ready to close** — every PR MERGED (or CLOSED with a reason in the notes), Deployed = Prod (or the notes say
     why no deploy is needed), all worktrees clean.
   Independently of the bucket, flag 📏 **outcome due**: tasks (live notes AND archived `~/notes/tasks/*.md`) whose
   `## Outcome` has `result: pending` and whose prod deploy / board Finished date (`board list` shows `fin:`) is ≥ 7
   days ago → next action `/outcome <task>`. Closed tasks with Deployed=Prod, Kind Feature/Bug and no `## Outcome` at
   all → list once as "no success signal" (propose one with `/outcome <task>`).
   Independently of the bucket, flag ❓ **waiting on PM** when the notes' `## Cases` has `needs-PM` rows: show the count
   and the age of the oldest open question (its `/cases` date). These block QA coverage — list them in their own block.
4. Also list main-checkout clutter: in each `~/code/<workspace>/<repo>` main checkout, `git status --short`
   (should be clean, on `dev`).

5. **Board**: `board list` → (a) 📋 **backlog**: Todo items whose task has no worktree yet (priority order);
   (b) mismatches: a task with worktrees but no board item → propose `board start <task>`; a task closed
   (no worktree, notes archived in ~/notes/tasks/) whose items aren't Done → propose `board done <task>`;
   PR items whose PR is not on the board's task → propose `board pr`; Kind=Chore tickets from `/triage` DATA
   verdicts (SQL for me to run) older than 3 days → list them as "SQL not confirmed run".

Output: one compact block per bucket, one line per task: `task · repo PRs with ✓/open · the one next action`.
Next actions are commands for me: `/finish-task <task>` for ✅; `/deploy-gates <task>` for 🚚; "send the PM questions
(notes `## Open questions (PM)`)" for ❓; `cd <worktree> && git push -u …` or
"decide: keep or drop" for 📝; `wt-setup <dir>` for ❌; review/merge reminders for 🐢.
If `~/notes/escapes.md` exists: one line "escapes (30 days): N — by stage …" counted by `leaked at`; the most
frequent stage is where the process leaks — name it.
**Weekly status update** (on Mondays, or with `--weekly`; once per week — skip if the board already has one dated
this week): write 5–10 lines in the team's language — shipped last 7 days (tickets whose Finished is in the window, by Kind), in
progress, blocked (🔴 / ❓ / 🚚), outcomes measured this week (task · Met/Partial/Not met · before → after), escapes this week by leak stage — and post it with
`board status-update - <ON_TRACK|AT_RISK|OFF_TRACK>` (AT_RISK when any 🔴, any P0 open > 7 days, or an escape this
week; OFF_TRACK when a P0 is blocked). The only write this command makes.
End with the 📋 backlog block, then counts per bucket and the board URL (`board url`). Do not write anything to the notes; the weekly status update is the only write.
