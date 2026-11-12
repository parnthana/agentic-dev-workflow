# evals - does the agent follow the command or skill?

A small harness that measures whether a coding agent actually follows a slash command, skill or rule you wrote,
instead of assuming it does. It is a trimmed fork of the skill-comply tool from the
[ECC project](https://github.com/affaan-m/ECC) (MIT, copyright Affaan Mustafa; see `LICENSE`), with a fixed-spec
mode, repeat runs, fixture repos and fake read-only tools added. All fixtures here are synthetic (a fictional
e-commerce app).

## What is measured

1. A **spec** lists the steps the command should produce (for example: search memory first, locate the code,
   fetch data read-only, give exactly one verdict, propose the fix instead of applying it). Each step has a
   `detector.description` and optional `after_step` / `before_step` ordering.
2. Each **scenario** runs `claude -p` in a throwaway sandbox directory and records every tool call (stream-json),
   plus the agent's written answer.
3. An LLM **classifier** maps tool calls and answer text onto spec steps (no regexes). Ordering is then checked
   deterministically.
4. The **report** gives per-step hit counts, a compliance rate per scenario and the full timeline.

Read the timelines, not only the percentage: look at every `Edit` / `Write` call and at what the final answer claims.

## Three strictness levels

Every scenario set has the same incident phrased three ways:

| Level | Prompt | Question it answers |
|---|---|---|
| 1 supportive | names the command and restates its rules | does it work when asked nicely? |
| 2 neutral | a plain bug report, no mention of the command | is it followed unprompted? |
| 3 competing | pushes against the rules ("skip lookups, patch directly, one line") | do the guardrails hold under pressure? |

A rule that only holds at level 1 is a wish, not a guardrail; low level 3 scores are candidates for a hook.

## Layout

- `scripts/` - spec/scenario generation, runner, classifier, grader, report (`python -m scripts.run`).
- `prompts/` - prompts for generation and classification.
- `stubs/tool_stub.py` - fake `ro-sql`, `ro-pg`, `ro-es`, `board`. The runner puts them first on `PATH` in the
  sandbox and feeds them the scenario's `db:` block (SELECTs return rows filtered on `customer_id` /
  `order_id` / `item_id`; writes are refused; joins are not evaluated).
- `fixtures/triage/` - fixed `spec.yaml` + three `scenarios.yaml` entries (order 456 shows different totals on
  the list and detail pages; the planted cause is a missing soft-delete filter).
- `fixtures/cases-gold/` - output-quality eval for a case-discovery command (see below).
- `fixtures/tdd_spec.yaml`, `compliant_trace.jsonl`, `noncompliant_trace.jsonl` - tiny examples of the spec and
  trace shapes.
- `run-evals.sh` - wrapper: private venv with pyyaml, sets `COMPLY_SANDBOX`.

## Run it

Requires Python 3.11+ and the `claude` CLI. Dry run first (generates spec and scenarios, no agent sessions):

```bash
./run-evals.sh --dry-run --gen-model haiku path/to/command.md
```

Fixed spec and hand-written scenarios (preferred, so reruns are comparable; `--repeat 5` gives hit counts like 3/5):

```bash
./run-evals.sh --model sonnet --repeat 5 \
  --spec fixtures/triage/spec.yaml --scenarios fixtures/triage/scenarios.yaml \
  --output report.md path/to/triage-command.md
```

Cost is roughly 3 scenarios x N sessions of the run model. Scenario sessions can run arbitrary commands, so pair
the wrapper with a pre-tool-use hook that denies network, cloud and git-remote commands whenever
`COMPLY_SANDBOX` is set. The runner refuses to start without that variable.

### Scenario file format

`scenarios:` (id, level, level_name, description, prompt), top-level or per-scenario `files:` (relative path to
content, written into each sandbox - put a findable truth in them), and `db:` (data for the fake tools, kept
outside the sandbox so grepping it cannot leak the answer).

## Output-quality eval: case discovery (`fixtures/cases-gold/`)

The process eval above checks that steps happen. This one checks the result: given a brief written before a bug
shipped, does an independent pass produce a case that would have caught it?

```bash
cd fixtures/cases-gold
python3 run_eval.py 3      # items x arms x 3 repetitions; cached in runs/ (delete to redo)
```

- `gold.yaml` - items: brief, the missed case, a strict `criterion`, `loo_tags`.
- Arms: A no heuristics file, B full `gaps.md`, C `gaps.md` minus lines whose `(why: ...)` names the item's own
  incident (leave-one-out, the fair test once a line was learned from that item).
- Every model call uses an empty working directory with no tools and no settings, so project memory cannot leak
  the answer. The judge is an LLM with a clause-by-clause procedure; read its quotes before trusting a score.

## Credit

Upstream: skill-comply from the ECC project, MIT licensed; the original copyright notice is kept in `LICENSE`.
