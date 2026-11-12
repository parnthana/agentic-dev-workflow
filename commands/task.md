---
description: Start a feature — task worktrees (off dev) for the given repos, via wt
argument-hint: <task-name> <repo[,repo…]> [branch] [--brief <path|link>] [--kind Feature|Bug|Chore] [--open] [--per-repo]
---
Start feature work using the task-worktree flow from ~/code/<workspace>/CLAUDE.md.

Arguments: `$ARGUMENTS`
- 1st word = task name (kebab-case). 2nd = comma-separated repos from: backend, frontend, api-contracts (plus any other repo of the workspace).
- Optional 3rd word = branch name (default `feat/<task>`).
- `--open` = afterwards start ONE lead agent for the task in the first listed repo, able to read and edit the
  sibling worktrees — in the team's agent runner / terminal. `--per-repo` = one agent per
  repo instead (only when the parts are truly independent).
- `--brief <path|link>` = a product brief / case library: copy its link into the notes' Goal section, create the
  ticket as `--kind Feature` (unless `--kind` says otherwise), then run `/cases <task>` before `--open`, so the
  coding session starts with the case matrix and the PM questions already sent.
- If the task name or repos are missing or unclear, ask me before doing anything.
- `--kind Bug` (or the goal reads like a bug): before creating anything, make sure there is at least one concrete
  customer id (and record / user ids when the bug is about a specific record or user) that shows the problem. Not in the arguments,
  brief or an existing `/triage` draft → ask me for it once (a bug without an id cannot be reproduced). I may answer
  "none" — then write `customer/record: unknown` and go on.

Steps:
1. For each repo run `wt <task> <repo> [branch]` — feature worktree off origin/dev.
2. Do NOT create the `-main` twins now. They are made later, when the dev side is ready, with
   `wt <task> <repo> [branch] --main` — that cherry-picks the dev branch's commits onto origin/main.
3. Use ONLY `wt`. Never Claude Code's built-in worktree tool or a bare `git worktree add`.
4. The Bash tool resets its working directory, so afterwards use absolute paths:
   `~/code/<workspace>/tasks/<repo>/<task>/…` (by-repo layout).
5. Run `wt-ls <task>` and show me the result.
6. Open `~/code/<workspace>/tasks/_notes/<task>.md` and fill the `Goal:` line under the title — one line, the problem
   in user terms (it becomes the ticket title; ask me if you don't know it). Under `## Goal & acceptance criteria`:
   why / who asked in 1–2 lines, and any AC the brief already states as `- AC1: <what the user sees>` bullets
   (`/cases` completes them). PR numbers and decisions go there as the work proceeds.
   **Bug**: also add, right after that section, only with what is known (no placeholders for unknowns):
   ```markdown
   ## Bug report
   - customer/record: 123 / 45   · reported by: <who, channel, date>
   - steps: 1. … 2. …
   - expected: …  · actual: …
   - frequency: always | sometimes (n/m) · since: <date or deploy, or unknown> · impact: <how many customers/rows>
   ```

6b. **Board**: `board start <task> [P0|P1|P2] "<goal line>"` — moves the task's draft item (e.g. one `/triage`
   or I added earlier with the same task name) to In Progress, or creates it. Ask me the priority only if no draft
   exists; default P1. `board list Todo` first if the name might differ from an existing draft — reuse that name.
   Then `board set <task> Kind <Feature|Bug|Chore|Audit>` (if not set) and, after step 6 wrote the goal,
   `board sync <task>` (ticket body = summary of the notes).

7. If `--open` was given: run `wt-open <task> --lead <first listed repo>` (add `--per-repo` if I asked for it).
   The lead gets `--add-dir` for every sibling worktree, so one agent owns the whole cross-repo change and the
   API contract stays consistent. Pass `--prompt "<first instruction>"` if I gave a starting task.
   Without `--open`, offer it: "start a lead agent for this task? (wt-open <task>)".

This session is the planner: do NOT start the feature work here (this is a main checkout on `dev`).
The work happens in the sessions inside the worktrees.

Finish by listing the worktree paths and their branches, and recommend `/cases <task>` then `/build <task>` (coding) when the
change has product behaviour (skip for pure refactors/infra).
