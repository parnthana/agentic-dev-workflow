# /qa learning checklist — one bug pattern per line; /qa reads it every run and turns matching lines into cases
# Format: - [YYYY-MM-DD] <area>: <what broke> → check: <how to check>
# Generic starters from real escapes (domain details removed). Add your own via /escape.
- BFF errors: a bare 500 means unhandled in the BFF, 502 means upstream → check: force an upstream failure; the UI shows a handled error and the BFF answers 502, not 500
- generated API client: a dev-only optional param shifts positional args when prod regenerates the client → check: changed fetchers are called with named options; diff the contract against the prod branch
- links in previews: a website stored without a scheme renders as a relative href → check: every external link resolves to http(s)://
- OpenAPI: a new header/query param without an explicit `required: false` is published as required → check: run a breaking-change diff (oasdiff) against the base
- error relay: the exception filter drops upstream `details` → check: a 4xx with details reaches the client with them
- status swallowing: `validateStatus < 500` hides 401/403 → check: point the upstream at a 403; the feature must log, not show empty data
- fail-soft upstream: a short-deadline lookup falls back silently → check: make the upstream slow/down; the UI must not look like a real "not found"
- idempotency: the same entry from two sources creates two live rows → check: run the entry twice; one live row
- DB dates: date parsing that depends on session NLS works in a SQL client but fails in the service driver → check: run changed date filters once through the real service
- time windows: the last day of a window is not covered without truncating to the day → check: test with today = window end
- numeric DTO that drives real output: no min/max → check: send out-of-range, negative and zero; expect 400 and nothing written
- derived file + server-owned field in a JSON column: old code reads the new row shape → check: read rows written by the new code through the deployed old code; plan deploy order + rollback
- filtered lists with keepPreviousData: the count beside the filter shows the previous key's total while loading → check: apply an uncached filter; show a placeholder while loading

## Review
# Patterns a pre-PR review should look for in a diff; added by escape analysis (leaked at: Review missed).
# Format: - [YYYY-MM-DD] <pattern> → look for: <what in the diff>
- Prisma `updateMany`/`deleteMany` result used as rows → look for: the return value indexed or mapped (it is `{ count }`)
- Prisma interactive `$transaction` with network calls or loops inside → look for: awaits on non-`tx` clients in the callback (default 5 s timeout)
- migrations → look for: `migrate dev` used against shared envs, edits to an applied migration, NOT NULL or rename in one step (expand → backfill → contract)
- same model wrote and reviewed the change → look for: every branch (mock/sandbox, fail-soft fallback, legacy vs new row, dev vs prod config) has its own test; a fix applied to one path but not its twin
- responsive: an in-flow `w-max whitespace-nowrap` row widens the mobile layout viewport → check: at 375 px, `window.innerWidth` stays 375
- fan-out reads: per-page `Promise.all` over a large pool saturates the DB connection pool → check: open the largest real record and count requests per query key
