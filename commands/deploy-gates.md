---
description: Post-merge deploy checklist for a task — reads gates from the notes, checks current state read-only, outputs ordered commands for me to run
argument-hint: <task-name> [--prod]
---
Build the deploy checklist for task `$ARGUMENTS` (dev unless `--prod`). Notes:
`~/code/<workspace>/tasks/_notes/<task>.md`.
READ-ONLY: never run a service deploy, `aws ssm put-parameter`, scaling, DDL/DML or a force deploy — those are my call.
Read SSM names only, never values (no `--with-decryption`). Every `--profile prod` command asks me first.

Steps:
1. **What ships**: from the notes + `gh pr list --state all --head <branch>` per worktree (`wt-ls <task>`), list
   merged PRs per repo and base (dev / main). Unmerged PRs → say so; their gates are not due yet.
2. **Collect gates** from the notes (gates/deploy/DDL/SSM sections and Handoff "Gates" lines) and from the merged
   diffs (`gh pr diff <n> --name-only`, then read only what's needed):
   - affected services = `services/<svc>/` dirs touched → each needs a deploy;
   - new/changed env vars read in code (`configService.get`, `process.env`) → SSM params;
   - migrations / `*.sql` / new legacy-database columns or rows → DDL/DML gates; check each against the `database-migrations`
     skill (expand → backfill in batches → contract; NOT NULL/rename never in one step; old code still running must
     read the new shape; a rollback SQL for every DML) and write the missing step into the checklist — for the legacy Oracle database use
     its principles only (no `CONCURRENTLY`/transactional DDL; `CREATE INDEX … ONLINE`, DDL auto-commits);
   - api-contracts version bump → must be published before backend/FE that depend on it;
   - BFF changes → regenerated openapi.json committed.
3. **Order**: dependency order — contracts publish → data/DDL → SSM → providers (downstream services) →
   consumers (BFFs) → frontend. Respect any order written in the notes; flag conflicts.
4. **Check current state** (read-only, in parallel):
   - SSM: `with-env <svc> --print` or `aws ssm get-parameters-by-path … --query 'Parameters[].Name'` → present?
   - ECS: `aws ecs describe-services` → running task-def revision/image and when it rolled out; is it newer than
     the merge? (dev uses `:latest` and won't re-pull → needs a forced redeploy of `<svc>`; prod is digest-pinned,
     so a push alone may not roll out.) New SSM params need a new task anyway.
   - api-contracts: published version vs the version the backend `package.json` pins.
   - DDL/data: a read-only `ro-sql`/`ro-pg` SELECT proving whether the column/row exists.
5. **Output** an ordered checklist: `☑` already true (with the evidence), `☐` to do with the exact command for me
   to copy, and "wait for N" where a step depends on an earlier one. DML/DDL as full SQL blocks with a SELECT
   preview and expected row count. After deploying, the verification to run (endpoint call, log grep via
   `svc-logs <svc> --since 15m --grep ERROR`).
6. Write the checklist into the notes under `## Deploy gates (<env>, <date>)`, replacing an older checklist for
   the same env. When I later say a step is done, tick it there. Overwrite `## Current state → next action` with the
   next unticked step.
7. **Board**: after writing the checklist: `board sync <task>`. Deployed is set only after step 8 passes.
8. **Smoke on the deployed env** (once the deploy/promotion is done and I say so): for each changed endpoint/screen
   run the happy-path rows of the notes' `## Cases` (or the AC) against the deployed env — API calls with your QA
   helper for APIs (dev only; prod = read-only GETs I approve), plus `svc-logs <svc> --since 15m --grep 'ERROR|Exception'`.
   Record `## Smoke (<env>, <date>)` in the notes: case · result · evidence. Any failure → STOP, keep Deployed
   unchanged, propose `/debug-prod <svc>`. All pass → `board set <task> Deployed Dev|Prod` and `board sync`.
