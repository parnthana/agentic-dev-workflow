# Product-gap heuristics — read by /cases (case discovery) and /qa (coverage)
# Not bugs in code: questions a brief usually forgets. One dimension per line; add a line whenever a task finds a new gap.
# Format: - <domain>: <dimension / states to enumerate> (why: <the incident it came from>)
# The lines below are generic starters. Replace the examples with your own domain as escapes teach you.

## Account / plan
- plan: no plan · trial (incl. its last day) · paid active · quota exhausted · unlimited · several plans in one window · an old billing window vs the current one · a plan bought but not yet activated
- account level: every value of the tier/level field, including NULL — count real NULLs in prod before assuming none
- user: admin vs member · per-module permissions · per-record scope · support/impersonation session · expired user still listed
- two tenants: every write/read as tenant A on tenant B's ids and the reverse (IDOR)

## Main entity (order, booking, ticket…)
- state: draft · live · expired · offline · hidden/unpublished · created by the legacy flow vs the new flow
- dates: the creation day itself · the last day · renew/extend inside the current cycle · local timezone vs UTC near midnight
- language: each supported language · both

## Related records
- origin: every way a related row is created (user action, search, recommendation, import, legacy junk rows with sentinel ids)
- row state: live · in an old window · dismissed · removed · duplicate of an existing row
- "does the account already have / has it seen this record": list every touchpoint and decide in/out per feature

## Data shape
- 0 rows · 1 row · page boundary · 1000+ · very long text without spaces · missing optional fields · legacy rows missing new columns · duplicates by case
- the same value on several screens (counts, badges, days live, owner name) must agree — list every screen that shows it

## Flow / time
- repeat the action (double submit, retry, same entry from two sources) · two tabs · back/refresh mid-flow · act after the target changed
- side effects: emails (to whom, once, dev redirect), notifications, search index sync, events, money charged / refunded
- undo / cancel / delete: what is left behind, can it be redone, child tables
- filter UI state: per tab vs shared · survives context switch · in the URL or reset on refresh · counts filtered vs unfiltered

## Legacy parity
- what does the legacy system do for this exact case — read its code, cite file:line; legacy broken = decide, don't copy
- does a legacy writer or admin tool still change the same rows after our change

## Data consumers
- a new kind of row/value written to a shared table, index or event (negative ids, sentinels, new flags) → EVERY reader: search, counts, filters, exports, emails, reports, admin, DB views/triggers — run /impact
- templates / save-as-reusable: every per-recipient value in the rendered text, and whether the fill side has a variable for it
- load shape: requests per screen must not grow with data size (fetch-all pages, per-row calls) — test with the biggest real dataset and count upstream calls
- template variables: where a variable can sit — visible text vs inside an HTML attribute (href, mailto:, src)
