---
description: Open the PRs for a task — dev PR from the feature worktree, main PR from the -main twin (only if main needs it)
argument-hint: <task-name> [repo,…]
---
Open the pull requests for task `$ARGUMENTS` (first word = task; optional comma-separated repos, default = every
repo the task has a worktree in). Follow ~/code/<workspace>/CLAUDE.md. Opening PRs is outward-facing: show me the
full plan (branches, bases, titles, bodies) and wait for my OK before the first `gh pr create`.

For each repo:
1. `wt-ls <task>` — the dev worktree must be clean and pushed (push with `git push -u` if it only lacks an
   upstream and I agree). Never push or open a PR from a main checkout.
2. **Docs check** (backend repo): for every service the diff touches (`git diff --name-only origin/dev...HEAD`),
   confirm SERVICE.md, the Postman collection (new/changed endpoints), the FE API guide (BFF endpoints) and the
   API contract doc (shape changes) were updated, and api-contracts' version was bumped if it changed — per the
   "Backend changes — always" list in ~/code/<workspace>/CLAUDE.md. Missing → stop and list them; don't open PRs.
2b. **Checks**: the notes' latest `## Checks run` entry for this branch must name its current HEAD (`git rev-parse
    --short=10 HEAD`) with `dirty no`. Missing, older commit, or dirty → run `/verify` now (it appends a new entry;
    it reuses a matching entry by itself). The `-main` twin before its PR: `/verify --twin` (full if the cherry-pick
    needed conflict fixes). Any ❌ → stop and report (don't open PRs on red).
2c. **Cases gate** (also enforced by the PreToolUse guard on `gh pr create`, which asks me when it fails):
    - the notes have a `## Cases` table with no `needs-PM` rows, or a line `Cases: n/a — <reason>, user OK <date>`;
    - every `agreed` row is `tested` (a `[C<id>]` test in the diff) or `manual: /qa` with a pass in the latest
      `## QA run`; take the coverage from the latest `/verify` entry, re-run step 5b of /verify if it is older than HEAD.
    Any gap → STOP and list it (missing matrix / needs-PM ids / untested ids). Go on only when I explicitly allow
    skipping in this conversation; then record it in the notes (`Cases: n/a — …, user OK <date>`, or under
    `## Case coverage`: `C05 skipped — user OK <date>: <reason>`) and put the skipped ids in the PR body.
2d. **Self-review** (once per task, on the dev branch diff `origin/dev...HEAD`; again on the twin only if the
    cherry-pick needed conflict fixes). Size it by `git diff --shortstat origin/dev...HEAD` (non-test lines):
    **small** (< 150 changed lines, no new endpoint/DTO/migration) → ONE agent, `pr-review-toolkit:code-reviewer`, told to
    also cover silent failures and whether the tests fail for the case they name; **otherwise** the full set below,
    agents in parallel (one message), each given the diff, the notes' Decisions +
    AC verbatim, `~/.claude/qa-checklist.md` (whole file — its `## Review` section first), and in its brief: "search
    with grep via Bash; return findings as file:line + one line each, no file contents":
    - `pr-review-toolkit:silent-failure-hunter` — always (swallowed errors, fail-soft fallbacks, `validateStatus < 500`);
    - `pr-review-toolkit:pr-test-analyzer` — always (do the tests fail for the bug/case they name? untested branches);
    - `pr-review-toolkit:code-reviewer` — always; `pr-review-toolkit:type-design-analyzer` only for new DTOs/types/schemas;
    - `typescript-reviewer` (~/.claude/agents) — when the diff has `.ts`/`.tsx` (async correctness, Node
      security, type holes); tell it to skip style nits the repo's lint already owns.
    Re-read every finding yourself before acting (agent verdicts are leads). Real bug in task code → fix with a
    regression test, commit, then `~/.claude/escape.md` with `found by: review`. Behaviour a Decision chose = not a
    finding. Any fix commit moves HEAD → redo 2b (`/verify` on the new HEAD) and 2c. Show me the list
    (fixed / rejected + why); open PRs only after that.
3. **Dev PR**: head = the dev worktree's branch, base = `dev` (repos without a `dev` branch, like api-contracts:
   base = `main`, one PR only, done). Skip if `gh pr list --head <branch> --state all` already shows one.
4. **Does main need it?** Before any main PR, check in this order and tell me the answer:
   a. **Does the affected feature exist on main?** Look at the files the change MODIFIES (not the ones it adds):
      if those exist on `origin/main` (`git cat-file -e origin/main:<path>`), the feature is on main. Newly ADDED
      files (a helper, a test, a migration) are normal for a fix and say nothing either way — they go to main with
      the fix. If the modified files are missing on main / the feature module is dev-only → no main PR; never pull
      dev-only files into main.
   b. **Can main reach it?** Read main's callers of the changed code; if main's path can't hit the bug (already
      guarded, different flow), say so and skip the main PR.
   Unsure → ask me, don't guess.
5. **Main PR** (only if 4 says yes): `wt <task> <repo> --main` creates/syncs the `-main` twin by cherry-picking the
   dev branch's own commits (stop and report on conflicts). Run `/verify --twin` in the twin (main's
   base can differ; full if the cherry-pick needed conflict fixes), push, then head = the twin's branch, base = `main`.
6. Titles: conventional commit, same for both — `type(scope): summary`, suffix ` [dev]` / ` [main]`.
   Body: what & why (short), how it was tested (incl. the latest `/qa` coverage line, or "no /qa run"; open
   `needs-PM` cases listed by id), deploy gates (DDL, SSM, flags), and for the main PR
   `Dev PR: #<n>` (dev PR body gets `Main PR: #<n>` added after). End every body with the attribution lines from
   the current system reminder, if any.
7. Write both PR numbers + URLs into `~/code/<workspace>/tasks/_notes/<task>.md` under the existing `## PRs` (no second
   heading), and overwrite `## Current state → next action` (PRs open, checks, what merges first).
8. **Board**: `board pr <task> <every PR url opened or found>` (adds them to the team board, Task=<task>,
   In Progress), then `board sync <task>` (ticket body gets the PR list + checks). Fails (network/auth/rate
   limit) → say so, don't block.

Finish with a table: repo · dev PR · main PR (or "not needed: <reason>") · checks status (`gh pr checks`).

9. **Watch CI** (offer once; on yes): `/loop` self-paced (~8 min, matched to CI length) on these PRs until every
   check is final and the PR is approved or has review comments:
   - a red check → read its log (`gh run view --log-failed`), fix in the worktree with a regression test if it is a
     real bug, `/verify`, commit; **push only after I OK it** (say what you'll push) — then keep watching;
   - every real bug found this way (a red check that is not flaky/infra, or a review comment I agree is a bug) →
     after the fix, run the escape analysis (`~/.claude/escape.md`, `found by: ci|review`) — one row per bug;
   - review comments → summarise each (file:line, ask, your proposed reply/fix) via superpowers:receiving-code-review;
     never reply on GitHub or resolve threads without my OK;
   - all green + no open comments → stop the loop and tell me which PR is ready to merge (dev first).
