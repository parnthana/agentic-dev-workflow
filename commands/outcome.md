---
description: Measure whether a shipped task did what it was for — rerun its success-signal query ~7 days after deploy, record before → after in the notes, the board and the brag doc
argument-hint: <task> [--now]
---
Check the outcome of task `$ARGUMENTS`. READ-ONLY on data (the query tools are read-only); writes only the notes,
the board field and the brag entry.

1. Notes: `~/code/<workspace>/tasks/_notes/<task>.md`, else the archived `~/notes/tasks/<task>.md`. Read `## Outcome`:
   `signal`, `query`, `baseline`, `check`, `result`. No `## Outcome` or no signal → propose one (what would show the
   problem is solved: an error count, latency p95, usage of the new path, rows fixed), ask me to confirm it, write
   it; when the baseline can no longer be measured, say so and record `baseline: unknown`.
2. Too early (less than 7 days since the prod deploy — board Finished date / notes Deploy gates) and no `--now` →
   say when it is due and stop.
3. Run the query for the same window length as the baseline:
   - dev or prod via `svc-logs --prod`, `ro-pg --prod`, `ro-sql prod`, `ro-es prod`: run it (pre-approved, read-only);
     CloudWatch Logs Insights on prod log groups (raw `aws --profile prod`) still asks me. Counts and percentiles only, never personal data.
   - Latency: measure from the services' structured request logs (response-time field) via Logs Insights, mind the
     prod log retention window; for a before/after comparison use the same window length on both sides.
4. Judge: **Met** (the signal moved as intended, e.g. errors 0 / p95 under target / the new path used) ·
   **Partial** (moved, not enough, or only some cases seen in traffic) · **Not met** (no change or worse) ·
   **n/a**. Also count `~/notes/escapes.md` entries whose origin is this task — any escape → at most Partial, say why.
5. Write:
   - notes `## Outcome`: `- result (<date>): <Met|Partial|Not met> — <before> → <after> (<window>)` (keep the
     earlier lines; a recheck adds a line);
   - board: `board set <task> Outcome <Met|Partial|Not met|n/a>`, then `board sync <task>`;
   - brag doc (`~/notes/brag/<year>.md`): the task entry's **Outcome** line, and **Impact** when the measurement gives
     a better number than the estimate (`est.` → measured).
6. Not met / Partial → propose the follow-up (a `/triage`, or a new task with `board add … --kind Bug`), don't
   create it.

Report: signal · before → after · verdict · what was written.
