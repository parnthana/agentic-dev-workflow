<!-- Escape analysis — shared by /triage (step 9), /escape, /pr (step 9 watch loop) and /qa (fix loop 7.5b).
     Every real bug found AFTER the code was written goes through this, wherever it was found, so /cases and /qa
     learn from all of them, not only from the ones a user reported. Do it while the evidence is fresh. -->

## Escape analysis — why did the system let this bug through?

Input: the bug (file:line of the faulty code + what goes wrong) and **found by**, one of:
`user` (prod/dev report, /triage) · `ci` (red check on a PR) · `review` (PR review comment) · `qa` (/qa ❌, task-owned) ·
`self` (found while coding/verify, after the code was already committed).

Skip when the bug never left a WIP commit of the same session (a typo fixed before /verify is not an escape).

a. **Origin**: `git log -L`/`git blame` on the faulty lines (both `origin/dev` and `origin/main`; for an open PR, the
   PR branch) → commit → PR (`gh pr list --search <sha> --state all`) → task name from the branch (`feat/<task>`) →
   its notes (`tasks/_notes/<task>.md` or archived `~/notes/tasks/<task>.md`). No PR/task found, or the code predates
   the task flow (before you adopted this workflow) → `Pre-system`, skip to d.
b. **Where it leaked** — check the notes in this order and take the FIRST that fits:
   - `No case` — `## Cases` (or the AC) has no row covering this situation;
   - `Wrong expectation` — a row exists but its expected result was wrong (PM/brief/legacy reading);
   - `No test` — the row is agreed but has no automated test (no `C<id>` in a test name — see /build) and /qa didn't
     cover it either;
   - `Case not tested` — the row exists and is right, but `## QA run` coverage didn't include it (not run, blocked,
     needs-PM left open, or no /qa at all);
   - `Test passed wrongly` — a test or QA marked it pass (check the evidence: wrong data state, mocked upstream,
     fail-soft fallback hid it, wrong env);
   - `Review missed` — visible in the PR diff and nothing above applies;
   - `Deploy/config` — code right, env wrong (SSM, missing deploy, `:latest` not re-pulled, order of deploys);
   - `Legacy/data` — legacy writer or bad existing rows, not our change.
c. **Close the hole** (always one concrete line, never "be more careful"):
   - `No case` / `Wrong expectation` → one line in `~/.claude/qa-product-gaps.md` naming the dimension/state that
     was missing (with `why: <this bug>`);
   - `No test` → the regression test itself (named with the case id) + one line in `~/.claude/qa-checklist.md` if the
     kind of case tends to go untested;
   - `Case not tested` / `Test passed wrongly` → one line in `~/.claude/qa-checklist.md` with the exact check, and if
     the cause was the QA method (e.g. fallback hid it) say which step of qa*.md should change — propose the edit;
   - `Review missed` → the pattern as one line in `~/.claude/qa-checklist.md` under `## Review`
     (patterns a pre-PR review should look for);
   - `Deploy/config` → a gate line for `/deploy-gates` (propose the edit).
d. **Record**: append one line to `~/notes/escapes.md`
   (header `| date | bug | found by | origin task / PR | leaked at | hole closed by |`):
   `| <date> | <task or ticket> | <found by> | <origin task> #<PR> | <leaked at> | <file:line you added> |`.
   If the bug has a board ticket: `board set <ticket-task> "Leaked at" <value>`.
e. **Gold item** (only `No case` / `Wrong expectation` with an origin task — skip `Pre-system` and every other stage):
   every such escape becomes a regression test for /cases. In `evals/fixtures/cases-gold/`:
   - `briefs/<id>.md` — the origin task's goal/AC/brief as it stood BEFORE the bug: cut lines from the notes, never
     paraphrase; drop any line edited or added after the bug (dated entries, "SUPERSEDED", fixes, the title if it
     was rewritten). No customer personal data. `briefs/` is git-ignored (internal data): also append
     the `sed -n` lines that rebuild it to `make_briefs.sh`, then `shasum -a 256 briefs/<id>.md >> briefs.sha256`.
   - append to `gold.yaml` `items:` — `id`, `brief: briefs/<id>.md`, `missed` (1–2 sentences), `criterion` (strict:
     name the specific source/reader/rule/value; say what does NOT count — restating the brief's own rule, a
     neighbouring case, a generic "other readers" line), `evidence` (escapes.md row + notes/PR file:line),
     `loo_tags: [<the why-tag of the gap line written in c>]` (so arm C drops it), `status: draft`.
   Draft only: the author knows the answer, so leaks and loose criteria slip in. run_eval.py skips drafts until I
   read the brief + criterion and set `status: ready`. Do not run the eval here.

Report one line: `escape: found by <x> · origin <task> #<PR> · leaked at <stage> · hole closed by <file:line>`
(+ `· gold item <id> (draft)` when e ran).
