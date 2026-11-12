---
description: Brag doc — keep a dated record of what I shipped, its measured impact and what I learned; turn it into CV bullets, STAR stories and a skill matrix
argument-hint: [add <task>] [--backfill] [--cv [--since YYYY-MM]] [--learned]
---
The brag doc is `~/notes/brag/<year>.md` (private, not in git). One entry per finished task or notable piece of work,
newest first. Read `$ARGUMENTS`:

- `add <task>` (also run by `/finish-task`): draft ONE entry for the task from its notes (`~/code/<workspace>/tasks/_notes/<task>.md`,
  else `~/notes/tasks/<task>.md`), its PRs and any lessons-learned notes written for it. Ask me only for what the notes don't
  have, at most 2 questions in one message (usually: the impact number, my role). Append it.
- `--backfill`: entries for every archived task in `~/notes/tasks/*.md` (and dotfiles tooling work from
  `git -C ~/dotfiles log`) that has no entry yet. Many notes → one `sonnet` subagent per ~25 notes (bulk reading),
  each returns entries in the format below; review every entry against its notes before merging (numbers must
  appear in the notes — else `impact: ? (ask)`). Sort by date, write, then list the entries that need my input.
- `--learned`: append to the year file's `## Learned` section the durable lessons since the last run: lessons-learned
  notes newer than the last `Learned` date, `~/notes/escapes.md` entries, and Decisions with "why" in recently closed
  notes. One line each: lesson · where it came from · date.
- `--cv [--since YYYY-MM]`: write `~/notes/brag/cv-<date>.md` from the entries (and `## Learned`):
  1. **CV bullets** (English), grouped by theme — Performance · Reliability & incidents · Platform & developer
     tooling · Product features · Data & migrations. XYZ form: "<Accomplished X> <measured by Y> <by doing Z>".
     Strong verb first, one line, a number whenever the entry has a measured one (never invent or round up;
     `est.` numbers say "about"). Merge small related entries into one bullet. 3–6 bullets per theme, best first.
  2. **STAR stories** (3–5, English, the hardest / highest-impact entries): Situation · Task · Action · Result, 4–6
     lines each, for interviews.
  3. **Skill matrix**: technology / practice → the entries that prove it (e.g. database performance → C, D).
  **Sanitise everything in this file**: no customer or company names, customer/user ids, internal table/column/service
  names, hostnames, ticket/PR numbers or confidential business figures. Generalise ("an e-commerce platform's merchant
  product", "a legacy relational schema", "~1,000 records"). Then show me the bullets and say which entries had no number.

## Entry format
```markdown
## 2026-11-10 · image-crop-bake · Bug · theme: Product features
- **What:** <what changed for users, in user terms — from Goal / AC>
- **Impact:** <numbers: before → after, rows/companies/users affected, time saved; mark `est.` or `? (ask)`>
- **Outcome:** <Met | Partial | Not met | pending (check <date>) | n/a> — <the measured result from `## Outcome`>
- **Role:** <what I owned: design choice, cross-repo lead, prod incident, migration, review>
- **Tech:** <languages, services, infra, techniques>
- **Learned:** <1–2 lessons; link the lessons note if one was written>
- **Evidence:** <repo#PR …, notes path>
```
Rules: facts come from the notes, PRs, lessons notes and outcome checks — never fill a gap with a guess; keep internal
detail here (the doc is private) and sanitise only in `--cv`. `/outcome` updates the **Outcome** line later.
