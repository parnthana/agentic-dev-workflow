---
description: Triage a reported data/behaviour problem for one customer/order/user — known causes first, read-only DB/search evidence, code path, verdict + a reply in the reporter's language
argument-hint: <ids, e.g. customer=123 order=456 user=U789> <symptom…> [--prod]
---
Triage `$ARGUMENTS`: ids (customer id, order id, user id, public code, email, nanoId…) plus the symptom someone reported.
Dev data unless `--prod`, or when the report is about prod data (a user saw it on the live site) — prod reads via the
`ro-*` tools are pre-approved, no need to ask (VPN, tiny results, no personal-data dumps).
READ-ONLY: never write to a DB, SSM or ECS, never edit code here — a fix becomes SQL or a `/task` proposal for me.

If ids or the symptom are missing or ambiguous, ask me one short question first.

Steps:
1. **Known already?** Search the project notes/wiki (`<your wiki>/index.md`, if you keep one)
   with grep for the symptom words, tables and screens involved. If something matches, test that explanation FIRST
   before inventing new theories.
2. **Locate the screen → endpoint → code path.** Which FE screen shows it, which BFF endpoint, which service
   method, which query. Name file:line. Use grep, not a file-by-file read. Broad search across many files →
   one Sonnet subagent (Explore), conclusions + file:line only.
3. **Get the real data** (independent queries in parallel):
   - Legacy Oracle database: `ro-sql dev|prod "<SELECT …>"` — always filter on the customer id together with any
     per-company row id; unsure of a key or column → look it up in ALL_CONS_COLUMNS / ALL_TAB_COLUMNS, never guess.
   - Postgres: `ro-pg <service> [--prod] "<SELECT …>"`.
   - Search: `ro-es dev|prod <index>/_search '{…}'` — check which cluster the service's config really points at.
   - Use `--max` small; select only the columns you need.
   - Mandatory: run at least one query for these ids before step 5. Code alone shows what COULD happen, not what
     happened to this customer. Run each query as its own Bash call (`ro-sql dev "…"` alone, not chained with
     ls/cat/cd) — a refused combined command says nothing about the query tool. Only when the query call itself
     fails (tool refused, no VPN, no access) the verdict is `UNKNOWN`:
     name the leading hypothesis with file:line and give the exact query that would decide it.
4. **Compare**: what the code would return for this data vs what the user saw. Reproduce the exact query
   the code runs with these ids when possible.
5. **Verdict** — exactly one, with the evidence (query + rows, file:line). `DATA` and `BUG` need query rows; without
   them it is `UNKNOWN` (step 3):
   - `DATA` — bad/legacy rows → write the fix SQL for me to run (SELECT preview first, then the DML, with
     the customer id in every WHERE; note the row count it should touch). Never run it.
   - `BUG` — code is wrong → root cause, file:line, the fix in one paragraph, and the `/task <name> <repos>`
     command to start it.
   - `WORKS-AS-DESIGNED` — explain the rule that produces what they saw.
   - `INFRA` — service/deploy problem → hand off to `/debug-prod <service>`.
   - `UNKNOWN` — what you checked, what's still missing, the next query.
6. **Reply in the reporter's language** for whoever reported it (support/sales/PM): 3–6 lines, no jargon, no table/column names,
   what happened + what we'll do / what they should do. Put it in a fenced block so I can copy it.
7. **Keep what's durable**: a new gotcha, column meaning or legacy quirk → one note in your project notes/wiki
   (update an existing one instead of duplicating). One-off facts about this customer are not durable knowledge.

8. **Board** (verdict `BUG`; and every `DATA` verdict — the SQL I must run is follow-up work, `--kind Chore`, title
   "run fix SQL: <what>", the SQL path/summary in the body; I close it with `board done <task>` once run): `board add <task-name> <P0|P1|P2> "<title>"
   "<cause + file:line + evidence query>"` — the task name you proposed for `/task`, so `/task` later picks up the
   same item. Priority: P0 = prod data wrong / users blocked now, P1 = wrong but has a workaround, P2 = cosmetic.
   No customer personal data in the item (ids are fine). Add `--kind Bug` (or `Chore` for a data fix).

9. **Escape analysis** (verdict `BUG`, and `DATA` caused by our code) — follow `~/.claude/escape.md` with
   `found by: user`. It is how /cases and /qa get stricter.

Report: verdict (one line) · evidence · cause · fix/next step · reply in the reporter's language · notes changes · escape: origin, leaked
at, hole closed by.
Then tell me this session can be closed.
