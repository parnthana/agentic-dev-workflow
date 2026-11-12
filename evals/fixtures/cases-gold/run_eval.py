"""/cases independent-pass eval: arms A (no gaps), B (full gaps), C (gaps minus the item's own lines). LLM judge."""
import json, re, subprocess, sys, concurrent.futures as cf
from pathlib import Path
import yaml

E = Path(__file__).parent
GAPS = E / "gaps.md"  # heuristics file for arms B and C
CLEAN = ["claude", "-p", "--model", "sonnet", "--tools", "", "--disable-slash-commands", "--strict-mcp-config",
         "--setting-sources", "", "--no-session-persistence"]
EMPTY = E / "empty"  # cwd for claude -p: no project memory, no files to read
EMPTY.mkdir(exist_ok=True)

GEN = """You are a careful product manager reviewing a feature brief before development starts.
List every case a careful PM would need answered, as given / when / then; mark the ones the brief does not answer
with [OPEN]. Return the list only.

=== BRIEF ===
{brief}
{gaps}"""
GAPS_BLOCK = "\n=== DIMENSIONS TO WALK (product-gap heuristics from past incidents) ===\n{text}\n"

JUDGE = """You grade a QA case list against ONE escaped bug.
MISSED CASE: {missed}
COVERED ONLY IF: {criterion}

Procedure:
1. Find the single case in the list closest to the missed case.
2. Check it against EVERY clause of "COVERED ONLY IF". Quote the words that satisfy each clause.
3. Verdict:
   - "covered": every clause is satisfied by explicit words in that case.
   - "partial": the case names the SPECIFIC situation (the specific source / reader / rule / value from the
     criterion) but lacks the expectation or one clause. Naming it inside a long generic list of readers counts
     only if the specific item is named.
   - "no": anything else — including a case that only restates a rule the brief already states, a case about a
     neighbouring situation, or a generic "other screens/readers/edge cases" case.
When unsure between two verdicts, pick the lower one.
Answer ONLY a JSON object: {{"verdict": "covered"|"partial"|"no", "quote": "<closest case, verbatim, max 300 chars>", "reason": "<which clause failed or why all pass, one sentence>"}}

=== CASE LIST ===
{cases}"""


def claude(prompt: str, system: str) -> str:
    r = subprocess.run(CLEAN + ["--system-prompt", system], input=prompt, capture_output=True, text=True,
                       cwd=EMPTY, timeout=600)
    if r.returncode != 0:
        raise RuntimeError(r.stderr[:300])
    return r.stdout.strip()


def gaps_text(arm: str, tags: list[str]) -> str:
    if arm == "A":
        return ""
    lines = GAPS.read_text().splitlines()
    if arm == "C":
        lines = [l for l in lines if not any(t in (re.search(r"\(why: (.*)\)\s*$", l) or [None, ""])[1] for t in tags)]
    return GAPS_BLOCK.format(text="\n".join(lines))


def one(item: dict, arm: str, rep: int) -> dict:
    out = E / "runs" / f"{item['id']}.{arm}.{rep}.json"
    if out.exists():
        return json.loads(out.read_text())
    brief = (E / item["brief"]).read_text()
    cases = claude(GEN.format(brief=brief, gaps=gaps_text(arm, item["loo_tags"])), "You are a careful product manager.")
    raw = claude(JUDGE.format(missed=item["missed"], criterion=item["criterion"], cases=cases), "You are a strict grader.")
    m = re.search(r"\{.*\}", raw, re.S)
    try:
        verdict = json.loads(m.group(0)) if m else {"verdict": "error", "reason": raw[:200]}
    except json.JSONDecodeError:
        verdict = {"verdict": "error", "reason": raw[:200]}
    rec = {"item": item["id"], "arm": arm, "rep": rep, "n_cases": cases.count("\n") + 1, **verdict, "cases": cases}
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(rec, ensure_ascii=False, indent=1))
    print(f"{item['id']:16} {arm} #{rep}: {rec['verdict']}", flush=True)
    return rec


def main(reps: int) -> None:
    all_items = yaml.safe_load((E / "gold.yaml").read_text())["items"]
    items = [i for i in all_items if i.get("status", "draft") == "ready"]  # drafts from /escape wait for review
    drafts = [i["id"] for i in all_items if i.get("status", "draft") != "ready"]
    if drafts:
        print(f"skipping {len(drafts)} draft item(s): {', '.join(drafts)} — review, then set status: ready")
    jobs = [(it, arm, r) for it in items for arm in ("A", "B", "C") if not (arm == "C" and not it["loo_tags"])
            for r in range(1, reps + 1)]
    with cf.ThreadPoolExecutor(6) as ex:
        recs = [f.result() for f in cf.as_completed([ex.submit(one, *j) for j in jobs])]
    score = {"covered": 1, "partial": 0.5}
    print("\nitem             | A (no gaps) | B (full gaps) | C (leave-one-out)")
    for it in items:
        cells = []
        for arm in "ABC":
            rs = [r for r in recs if r["item"] == it["id"] and r["arm"] == arm]
            cells.append(f"{sum(score.get(r['verdict'], 0) for r in rs):.1f}/{len(rs)}" if rs else "—")
        print(f"{it['id']:16} | " + " | ".join(f"{c:^11}" for c in cells))
    for arm in "ABC":
        rs = [r for r in recs if r["arm"] == arm]
        print(f"arm {arm}: {sum(score.get(r['verdict'], 0) for r in rs) / max(len(rs), 1):.0%} of {len(rs)} runs;"
              f" mean cases {sum(r['n_cases'] for r in rs) / max(len(rs), 1):.0f} lines")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 3)
