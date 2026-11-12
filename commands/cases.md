---
description: Case discovery before coding — turn a brief/AC into a case matrix (states × roles × data × time) using legacy, real-data and consistency oracles; open questions for PM in the team's language
argument-hint: <task> [brief path or link…] [--prod-data]
---
Discover the cases for task `$ARGUMENTS` BEFORE implementation (or right after `/task`). The product team often
misses cases; your job is to find them and get each one an agreed expected result. READ-ONLY: no code edits, no
DB writes. Search with grep via Bash. Notes: `~/code/<workspace>/tasks/_notes/<task>.md`.
Data queries: dev by default; `--prod-data` allows small read-only prod COUNT/GROUP BY queries (pre-approved, no need to ask; VPN, never
personal data — distributions only).

Steps:
1. **Inputs**: the notes (goal, AC, decisions), every brief/case library/design linked there or in `$ARGUMENTS`,
   `~/.claude/qa-product-gaps.md` (dimensions), `~/.claude/qa-checklist.md` (past bug patterns), your persistent
   notes for the tables/screens involved, the project wiki for the flow.
2. **Independent pass** (one subagent, model `sonnet`, sees ONLY the brief + AC + qa-product-gaps.md — no code, no
   notes decisions): "list every case a careful PM would need answered, as given/when/then; mark the ones the brief
   does not answer". It returns the list only. Its value is not being anchored on what was built.
3. **Your pass, with three oracles the brief doesn't have**:
   - **Legacy**: what the legacy codebase(s) and the admin tool do for each case — read the code, cite `file:line`.
     Legacy broken or contradictory → mark it, don't copy it.
   - **Real data**: which values/states actually exist (`ro-sql`/`ro-pg`/`ro-es` COUNT … GROUP BY on the columns
     that drive behaviour: NULLs, negatives, sentinels, legacy rows without new columns, multi-row cases). A state
     with rows in prod is a case even if the brief never mentions it.
   - **Consistency**: every other screen/service that shows or uses the same value (grep the field/endpoint
     across backend + frontend) — they must agree after the change.
   - **Data consumers**: when the change writes a new kind of row/value/state into a shared table, index or event,
     run `/impact <task> --plan` and turn every affected reader into a row ("how should <reader> treat the new row?").
   Walk every dimension in qa-product-gaps.md that touches the change; skip the rest explicitly ("n/a: …").
4. **Merge** both passes into the matrix; dedupe; keep it to cases whose expected result could differ (no
   cartesian padding). Each row gets a **source** for its expected result: `AC` · `brief` · `legacy` · `data` ·
   `consistency` · `heuristic` · `PM:<name, date>`. No source → status `needs-PM`, never a guess.
5. **Write into the notes** (edit in place; create the sections once):

```markdown
## Cases
<!-- /cases <date> · N cases · K needs-PM · /qa must give every agreed row a result -->
| id | area | given | when | then (expected) | source | status |
|----|------|-------|------|-----------------|--------|--------|
| C01 | pricing | customer with no tier set, single-plan package | checkout | charged on the base plan, one line item | data (1,200 prod rows) + PM:<name> | agreed |
| C02 | … | … | … | ? | — | needs-PM |

## Open questions (PM)
- Q1 (C02): <one question in the team's language, with the concrete example and the options you see>
```
   Status: `agreed` · `needs-PM` · `out-of-scope (who decided)`. Keep ids stable across reruns (append new ids).
6. **Questions for PM**: one message in the team's language that I can paste to the product team — grouped, numbered, each with a concrete
   example (ids are fine, no personal data) and 2–3 options with your recommendation. Put it in a fenced block.
   When I bring answers back: update the rows (`source: PM:<name, date>`, status `agreed`) and the Decisions section.
6b. **Acceptance criteria back into the goal section** (rewrite on every run and after PM answers): one bullet per
   user-visible outcome the `agreed` rows prove, in the goal section of the notes (`## Goal & acceptance criteria`):
   `- AC1: <who> <does what> on <screen> → <what they see> (C01, C04)`. User terms only — screens, labels, counts,
   messages; never tables, columns, SQL, functions or file names (those stay in the case rows). Keep AC numbers stable
   across reruns; an AC whose rows are all `needs-PM` is written as `- AC3 (pending PM Q2): …`. Rows marked
   `out-of-scope` → one `- Out of scope: … (who decided)` bullet. Also add a `Goal:` line under the title if missing
   (one line, the problem in user terms). The board ticket shows these as its AC and Out of scope sections.
6c. **Success signal** (how we will know it worked, measured ~7 days after the prod deploy by `/outcome`): write
   `## Outcome` in the notes once (keep it on reruns):
   ```markdown
   ## Outcome
   - signal: <one metric that shows the problem is solved — error count, latency p95, usage of the new path, rows fixed>
   - query: `<the exact read-only command: svc-logs … --grep …, ro-pg …, ro-sql …, a log-insights query>`
   - baseline (<date>): <value now, before the change — run it on dev, or on prod via the read-only tools>
   - check: prod deploy + 7 days
   - result: pending
   ```
   Pure refactor / infra / docs → `- signal: n/a (<why>)` and `- result: n/a`. Prefer a signal users feel (errors they
   hit, time they wait, the feature being used) over a code metric.
7. **Board**: `board sync <task>` (the ticket shows the case count and open questions).
8. New dimensions you had to invent that will recur → append one line to `~/.claude/qa-product-gaps.md`
   (format in its header).

Report: N cases (by area) · K needs-PM · the AC list written · the success signal + baseline · what the independent pass found that the brief missed · cases the code
(if any exists yet) already gets wrong · the PM message (in the team's language).
