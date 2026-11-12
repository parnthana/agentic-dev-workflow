---
description: Implement a task case by case — every agreed `## Cases` row gets a red-then-green test named with its id ([C03]), minimal code, one commit per case group; coverage table into the notes
argument-hint: <task> [C01,C04… | --remaining] [--repo backend|frontend|…]
---
Implement task `$ARGUMENTS` inside its task worktree(s) (`~/code/<workspace>/tasks/<repo>/<task>`), never in a main
checkout. Notes: `~/code/<workspace>/tasks/_notes/<task>.md`. Search with grep via Bash. Follow
superpowers:test-driven-development for each case; this command decides WHAT is tested, that skill decides HOW.

## 0. Gates — stop with the reason if one fails
1. `wt-state <dir>` = `done` for every worktree you will edit (same gate as /verify step 1).
2. `## Cases` exists with at least one `agreed` row. Missing → stop: "run `/cases <task>` first". The only way past is
   my explicit OK in this conversation; then write `Cases: n/a — <reason>, user OK <date>` under the notes' title
   (the /pr gate and the PreToolUse guard read that line) and build from the AC instead.
3. `needs-PM` rows: never implement a guess. List them, build everything else, and leave a `// TODO(C07): needs-PM`
   only where the code must branch on the answer.
4. Cross-repo task: contract first (api-contracts), then backend, then frontend (workspace CLAUDE.md lead-agent rule).

## 1. Choose the test level (in your head — no plan section in the notes)
Scope: `agreed` rows in `$ARGUMENTS` ids, `--remaining` = rows without a test yet, default = all agreed.
Pick the lowest test level that can fail for the reason the case describes: logic → unit; SQL / repository / state →
integration against the service's existing test setup; guards/pipes/wiring → e2e spec. Rows that share one code path
may share one test file, never one assertion. A case no automated test can reach (visual, third-party) →
`manual: /qa` — /qa must then cover it.

## 2. Per case (or small group of cases on one code path)
1. **Red**: write the test first, title starting with the id: `it('[C03] customer with no tier set is charged on the base plan', …)`.
   One id per test; several tests per id are fine. Run only that file
   (`jest-fast <worktree> <project> <absolute file path>`; exit 3 → `nice-run node_modules/.bin/nx run <project>:test -- <file> --maxWorkers=4`) and confirm it fails *for the reason in the case* — not
   on a typo, import or missing fixture. Paste the failing assertion line.
2. **Green**: minimal code in the layer that is wrong. No refactors, no extra features, no speculative options.
3. Run the file again (green), then `/verify --quick` (related tests, lint and tsc of the owning projects, throttled).
4. Commit test + code together: `feat(<scope>): <case summary> [C03]` (or `fix`), with the session's attribution
   lines. Never push.
Max 3 attempts per case; still red → stop that case, mark it `blocked (why)` in `## Case coverage`, go on with the next.

Schema change (migration, legacy-database DDL, backfill): follow the `database-migrations` skill — expand/contract,
batched backfill, apply migrations with the deploy command never the dev-generation command outside a local DB, never edit an applied migration;
put each DDL/DML step and its order into the notes as a deploy gate. Legacy database: the skill's PRINCIPLES apply, its
syntax may not (check what the engine supports for online index builds; if DDL auto-commits, there is no transactional DDL).

Data truth: when the expected result depends on real rows (sentinels, NULLs, legacy shapes named in the case source
`data`), build the fixture from the real shape (`ro-sql dev` / `ro-pg` read-only), not an idealised one.

## 3. After the last case
1. Backend "always" docs for the touched services (SERVICE.md, Postman, FE guide, API contract doc, api-contracts
   version) — update them now, or list them as owed under Current state.
2. `/verify` — full (dependents + contract gates; it also reports case coverage).
3. Write `## Case coverage` in the notes (overwrite):
   `| id | test (file:line) | status |` — status `tested` · `manual: /qa` · `blocked (why)` · `needs-PM`.
   Derive it from the code: `git diff <base>...HEAD` test files grepped for `\[C[0-9]+\]`, not from memory.
4. Overwrite `## Current state → next action` (what is built, what is left, next = `/qa <task>` or `/pr <task>`).

Report: cases built (ids) · tested vs manual vs blocked · commits · anything owed (docs, needs-PM).
