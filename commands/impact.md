---
description: Blast-radius sweep — from what a change WRITES (tables, columns, new values/states, search index, events, emails) and the APIs it changes, find every reader across backend, frontend, legacy, admin, database objects, search and jobs; mark each affected/ok/unknown
argument-hint: <task> [--plan | --diff] [--prod-data]
---
Map the blast radius of task `$ARGUMENTS`. The goal is to turn "things I didn't think of" into a finite, named list.
READ-ONLY: no code edits, no DB writes. Search with grep via Bash.
Notes: `~/code/<workspace>/tasks/_notes/<task>.md` (archived: `~/notes/tasks/<task>.md`).
Mode: `--plan` (before code: from the brief/AC/`## Cases`/Decisions) · `--diff` (default when worktrees or PRs exist: from the
real diff — the task's PRs via `gh pr diff`, or `git diff <base>...HEAD` in each worktree).

Steps:
0. **Fresh code only**: readers must be read on the CURRENT base — `git fetch` each repo and compare the main
   checkout to `origin/dev` (`origin/main` for api-contracts/admin). Behind → `git pull --ff-only` if it is clean and on
   its base branch, else read through `git show origin/dev:<path>` / `git grep … origin/dev`. Tell every subagent the
   same. (A run on a checkout over a thousand commits stale produced false findings.)
1. **What the change writes / changes** — list each item with its evidence (file:line or notes line):
   - schema changes (DDL, migrations): read them with the `database-migrations` skill — a reader of the OLD
     shape that is still deployed during the rollout is a reader too (rolling deploy: old + new tasks side by side);
   - tables + columns written (INSERT/UPDATE/MERGE/DELETE, repository methods), and **new kinds of values**: sentinels,
     negative ids, new enum/flag/status codes, NULLs where there were none, new row shapes (e.g. a row without an attachment);
   - search-index documents/indices written or re-indexed; events published; emails/notifications; files/object storage; cache keys;
   - API endpoints whose request/response/behaviour changed; shared libs/helpers changed.
2. **Find every reader** of each item (dispatch broad searches to `Explore` subagents, model `sonnet`, in parallel —
   one per area — each told: use grep, return `reader · file:line · what it does with the item` only):
   - backend `~/code/<workspace>/backend/services/**` + `packages/**` (repositories, raw SQL, ORM entities, migrations);
   - frontend `~/code/<workspace>/frontend/apps/**` + `libs/**` (fields of changed APIs, query keys);
   - legacy repos and the admin web (`~/code/<workspace>/admin`);
   - **legacy Oracle database objects** (you, `ro-sql dev`): dependency views for the changed tables
     (`ALL_DEPENDENCIES WHERE REFERENCED_NAME IN (…tables…)`), stored-procedure source search
     (`ALL_SOURCE WHERE UPPER(TEXT) LIKE '%<TABLE>%'`), `ALL_VIEWS`, `ALL_TRIGGERS WHERE TABLE_NAME IN (…)`;
   - search: indexers/sync jobs that read the tables, and every service querying those indices;
   - events/queues/crons: consumers of published events, scheduled jobs touching the tables.
   Prefer readers on the paths users hit (search, lists, counts, badges, exports, emails, reports, admin screens).
   **Give every subagent the task's Decisions and AC verbatim** (from the notes) and tell it: behaviour a Decision
   chose is `by design`, not `wrong`. (A run without them reported 2 of 6 decided behaviours as bugs.)
   Then **re-read yourself every non-ok verdict** before reporting it — subagent verdicts are leads, not findings.
3. **Classify each reader** against the NEW values/shapes (read the reader's code, and when cheap, run its query on dev
   with a real row of the new kind): `ok` (handles it as intended) · `drops` (filters it out — say if that is wanted) ·
   `wrong` (shows/counts/sends something incorrect) · `crashes` · `unknown` (couldn't tell — say what would tell).
   Decide "intended" from the notes' Decisions/AC; no decision → `needs-PM`.
4. **Unreachable readers**: list what you could not inspect (other teams' systems, mobile apps, BI/report SQL, external
   integrations) as named risks, not silence.
5. **Write into the notes** (live task: edit in place; archived task: `~/notes/tasks/<task>/impact-<date>.md`):

```markdown
## Impact (<date>, --diff|--plan)
Writes: <tables/values/search index/events, one line each>
| # | reader | where (file:line / object) | new value seen as | verdict | expected (source) |
|---|--------|----------------------------|-------------------|---------|-------------------|
Unreachable: <named list>
```
   Every `wrong`/`crashes`/`needs-PM` reader becomes a `## Cases` row (status `agreed` or `needs-PM`) so `/qa`'s
   coverage gate tests it. For a shipped task: propose ONE follow-up task covering all `wrong`/`crashes` readers
   (`board add <task>-impact P? "<title>" --kind Bug`) — never fix here.
6. Recurring reader categories you had to discover by hand → one line in your QA product-gaps file (`~/.claude/qa-product-gaps.md`).

Report: what the change writes (short) · readers found per area · verdicts (counts + every non-ok row) · unreachable
list · the follow-up task you propose.
