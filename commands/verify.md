---
description: Lint + test + typecheck only what this worktree changed (nx affected), after a real setup gate; per-project evidence + logs; results into the task notes
argument-hint: [dir] [--quick|--twin] [--force] [--all-targets]
---
Verify the changes in `$ARGUMENTS` (default: the current task worktree). Evidence, not reassurance: report exact
commands, exit codes and log paths; never "fix" failures by weakening tests, lint rules or tsconfig.

**Reuse first (all levels).** Tree clean and the notes' `## Checks run` already has an entry for this repo with the
current HEAD (`git rev-parse --short=10 HEAD`), `dirty no`, and a level at least as strong as asked (full ≥ twin ≥
quick) → report `reused <that entry's date>` and stop. `--force` reruns anyway. So /build → /qa → /pr on one HEAD
runs one full verify, not three.

**Levels.**
- **full** (default; end of `/build`, `/pr`, `/qa`, dev worktree): `nx affected` incl. dependents + contract gates.
- **`--twin`** (the `-main` twin — it holds the same commits cherry-picked, already fully verified on dev): the
  `--quick` checks below, computed against `origin/main`, plus the BFF contract gate (main's OpenAPI base
  differs). Dependents on main are left to the main PR's CI — say so in the report. Entry marked `twin`. Use full
  instead when the cherry-pick needed conflict fixes.
- **`--quick`** (before an ordinary commit): only the projects that OWN a changed file — no dependents, no contract
  gate. Projects: `changed-projects <dir> <base>` (TSV `name · root · changed files`; `-` = outside any project,
  skip). Per project: test = `jest-fast <dir> <p> --findRelatedTests <its changed files>`
  (the helper prints absolute paths — keep them: the target `cd`s into the project, so relative paths find nothing;
  none of them .ts/.tsx/.js → `skipped (no code change)`; "No tests found" for changed code → `zero tests`, not passed); lint = the project's eslint on its changed files only
  (same no-`--fix` rule); typecheck as in step 4. Skip step 5b. Notes entry is marked `quick` (step 7).

**Machine load — every run** (the workstation must stay usable; an unthrottled run can start several Nx targets × many Jest workers):
- Prefix every lint / test / tsc / build / generator command with `nice-run` (low QoS + nice 10 + `NX_PARALLEL=2`),
  e.g. `nice-run node_modules/.bin/nx run <p>:test -- --maxWorkers=4`.
- Jest always gets `--maxWorkers=4`. Tests run through `jest-fast <dir> <p> [jest args]`: the project's own
  test command with ts-jest in transpile-only mode (local wrapper, repo and CI untouched) — same results, much faster
  (measured roughly 20x cold on a large service). Exit 3 (target isn't `cd … && npx jest --config …`) →
  `nice-run node_modules/.bin/nx run <p>:test -- --maxWorkers=4`. Because jest no longer type-checks specs, the tsc
  step must cover changed spec files: when the diff has `*.spec.ts`/`*.e2e-spec.ts` in a project, also run tsc on
  its `tsconfig.spec.json` (else `tsconfig.json` if its `include` covers the spec folder; else say `specs not typechecked`). Never `nx affected`/`run-many` without `nice-run` (it sets `--parallel` 2).
- One project × target at a time is fine; never start a second /verify in parallel (other worktree, other session)
  — `pgrep -fl 'jest|tsc --noEmit'` shows a running one → wait for it or say so.
- A full run expected to take > 1 min: start it with `run_in_background` and carry on; read the logs when notified.

1. **Setup gate** — this worktree's state: `wt-state <dir>`
   → `done` / `running` / `failed: …` / `warn: …` / `none` (in `wt-ls`: done is silent, none shows "setup never ran").
   - `done` → continue.
   - `running` → `wt-state --wait <dir>` run in the background (it blocks up to 5 min, checking THIS worktree only)
     → exit 124 = still running after 5 min: stop and report. Exit 0 → it prints the final state: apply this list
     again (it may have ended in failed/warn).
   - `setup failed: …` or `setup warn: …` (e.g. install failed → node_modules cloned from the main checkout) →
     NOT verified against this branch's lockfile: show the tail of `~/Library/Logs/wt-setup/<repo-folder>__<name>.log`
     and stop, unless I say to continue anyway (then label every result "unverified deps").
   - `none` (made before the setup hook, or with --no-setup) → run `wt-setup <dir>` once, then re-check.
2. **Base & identity**: `git fetch -q origin`; base = `origin/main` for a `-main` twin or a repo without `dev`
   (api-contracts), else `origin/dev`. Record: full `HEAD` SHA, base SHA (`git merge-base HEAD <base>`), and whether
   the tree is dirty (`git status --porcelain` non-empty → the tested code includes uncommitted changes).
3. **Logs**: one folder per run — `~/Library/Logs/verify/<task>/<repo-folder>/<branch with / → _>/<YYYYmmdd-HHMMSS>/`,
   one `<project>.<target>.log` each.
4. **Run** from the worktree root with the repo's Node (mise / `.nvmrc`); call Nx via `node_modules/.bin/nx`
   (not `yarn nx` — yarn may need a registry token just to start).
   - Affected projects: `node_modules/.bin/nx show projects --affected --base=<base>`. None → say so and stop
     (whole monorepo only with `--all-targets`).
   - For each affected project, first look at its resolved targets (`node_modules/.bin/nx show project <p> --json`
     → `.targets` keys) — don't assume lint/test exist.
   - lint / test: `nice-run node_modules/.bin/nx run <p>:<target>` (test: `-- --maxWorkers=4`) per project where the target exists (or
     `nice-run nx affected -t lint test` and split the output per project).
   - **Never run a mutating target**: read the target's command first (`nx show project <p> --json` →
     `.targets.<t>.options.command` / the package.json script it calls). Contains `--fix`, `--write` or `-w` →
     run the underlying tool without that flag (e.g. `npx eslint <globs>`), or report `skipped (target mutates files)`.
     Lint with no ESLint config ("couldn't find a configuration file") → `failed (no config — same on base?)`, check the base.
   - typecheck (no Nx target exists): `nice-run npx tsc --noEmit --incremental --tsBuildInfoFile
     ~/Library/Caches/verify/<repo-folder>/<task>/<project>.tsbuildinfo -p <projectRoot>/<tsconfig>` — the cache
     lives outside the repo (never the default path: tsc would rewrite tracked `dist/tsconfig.tsbuildinfo` files) and
     makes repeat runs fast; `mkdir -p` its folder first. The tsconfig the project's build uses (`tsconfig.app.json` /
     `tsconfig.build.json` / `tsconfig.json`); none → "unavailable". A tsc error that looks stale → rerun once
     after deleting that `.tsbuildinfo`.
   - **api-contracts**: `npm run build`, `npm test`.
   - **BFF contract gates** (the BFF's contract CI workflow, run locally) — only when
     `git diff --name-only <base>...HEAD` or `git status --porcelain` touches `services/<bff-service>/`;
     else `skipped (no BFF change)`. Needs `oasdiff` (`brew install oasdiff`; CI pins a version — note a mismatch).
     First require `git diff --quiet HEAD -- <artifacts>`; uncommitted artifact edits → `skipped`, else they read as drift.
     Artifacts = `services/<bff-service>/openapi.json` +
     `services/<bff-service>/src/infrastructure/swagger/res-routes.generated.json`. Log `<bff-service>.contract.log`.
     1. `node services/<bff-service>/scripts/assert-contracts-version-agreement.mjs` (fails on a local-link pin → `contract-unlink`)
     2. `nice-run node_modules/.bin/nx run-many --target=build --projects=tag:type:package && node_modules/.bin/tsc-alias`
        (= the repo's `build:packages` script, without yarn's token)
     3. drift: in `services/<bff-service>/`,
        `nice-run node -r ts-node/register -r tsconfig-paths/register scripts/generate-openapi.ts`; non-zero = generator
        failure, NOT drift (exit codes: header of `scripts/generate-openapi.ts`). Then `git diff --exit-code -- <artifacts>`;
        a diff = drift: report it and leave the regenerated files in the tree, never commit them unasked.
     4. compat: `git show <base>:services/<bff-service>/openapi.json > <log dir>/base-openapi.json`
        (absent on base → `skipped`, as CI does), then `oasdiff breaking <log dir>/base-openapi.json
        services/<bff-service>/openapi.json --fail-on ERR --deprecation-days-stable 14`.
     Report as one `contract` row: `passed` · `failed (version|generator|drift|breaking)` · `skipped (why)`.
   - **Tree unchanged**: `git status --porcelain` after the run must equal before; anything a tool touched → restore
     it and say so. Changes you did not make (another session editing this worktree) → stop and report.
5. **Status per project × check** — exactly one of:
   `passed` · `failed` (exit ≠ 0) · `unavailable` (no such target / no tsconfig) · `zero tests` (exit 0 but the
   runner ran 0 tests, e.g. `passWithNoTests`, "No tests found") · `skipped` (and why).
   Only `passed` counts as evidence; say plainly when a changed project has no real test coverage.
5b. **Case coverage** (only when the notes have a `## Cases` table): for each `agreed` row, grep the test files changed
   since base (`git diff --name-only <base>...HEAD` matching `*.spec.ts|*.test.ts|*.test.tsx|*.e2e-spec.ts`) for
   `[C<id>]` in a test title. Report `C03 tested (file:line)` · `untested` · `manual: /qa` (as marked in the notes'
   `## Case coverage`). An untested agreed row is not a failure here, but list every one — /pr asks about them.
6. **Report**: table project · lint · test · typecheck · log path; first real error lines for each failure; whether a
   failure also happens on the base (re-run just that target on the base only if unclear). Header line:
   `HEAD <sha> · base <sha> · dirty yes/no · deps <ok/unverified>`.
7. **Notes**: append to `~/code/<workspace>/tasks/_notes/<task>.md` under `## Checks run`: date · repo · HEAD sha ·
   dirty · level (`full` / `twin` / `quick` — the /pr gate takes `full`, or `twin` in a `-main` worktree; never `quick`) · summary (e.g. `lint ✅ test ✅ (12) tsc ✅ — orders-service`) · cases `tested N/M agreed` (untested ids) · log folder.
