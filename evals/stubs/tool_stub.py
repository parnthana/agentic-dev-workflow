"""Fake ro-sql / ro-pg / ro-es / board for skill-comply sandbox runs.

runner.py writes a sh wrapper per tool into <sandbox base>/.stubs/ (prepended to PATH for the scenario session);
each wrapper runs this file. Data comes from <sandbox base>/.stubs/db/<scenario id>.json, written from the scenario's
`db:` block, outside the scenario dir so a grep in the sandbox cannot find it. No network, no real database.

db JSON shape: {"sql": {"table": [ {col: val, ...}, ... ]}}
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

WRITE = re.compile(r"\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|GRANT)\b", re.I)
FILTER = re.compile(r"(?:\w+\.)?(customer_id|order_id|item_id)\s*=\s*'?(\d+)'?", re.I)


def load_db(base: Path) -> dict:
    cwd = Path.cwd().resolve()
    try:
        scenario = cwd.relative_to(base.resolve()).parts[0]
    except (ValueError, IndexError):
        return {}
    f = base / ".stubs" / "db" / f"{scenario}.json"
    return json.loads(f.read_text(encoding="utf-8")) if f.is_file() else {}


def table_text(name: str, rows: list[dict]) -> str:
    if not rows:
        return f"-- {name}: no rows selected"
    cols = list(rows[0])
    width = {c: max(len(c), *(len(str(r.get(c, ""))) for r in rows)) for c in cols}
    head = "  ".join(c.ljust(width[c]) for c in cols)
    body = ["  ".join(str(r.get(c, "")).ljust(width[c]) for c in cols) for r in rows]
    return "\n".join([f"-- {name} ({len(rows)} rows)", head, "  ".join("-" * width[c] for c in cols), *body])


def sql(db: dict, args: list[str]) -> int:
    if not args or args[0] not in ("dev", "prod"):
        print('usage: ro-sql dev|prod "<SQL>" [--max N]  |  ro-sql dev|prod --cols <table>')
        return 1
    if args[0] == "prod":
        print("ro-sql: prod is not reachable from this environment. Use dev.")
        return 1
    tables = db.get("sql", {})
    if len(args) >= 3 and args[1] == "--cols":
        rows = tables.get(args[2].lower(), [])
        if not rows:
            print(f"-- no columns found for {args[2].lower()}")
            return 0
        print(f"-- {args[2].lower()} columns\n" + "\n".join(rows[0]))
        return 0
    query = next((a for a in args[1:] if not a.startswith("--")), "")
    if WRITE.search(query):
        print("ERROR: cannot execute a write statement in a read-only transaction")
        return 1
    named = [t for t in tables if re.search(rf"\b{re.escape(t)}\b", query, re.I)]
    if not named:
        print("no rows selected")
        return 0
    filters = {k.lower(): v for k, v in FILTER.findall(query)}
    out = []
    for t in named:
        rows = [r for r in tables[t] if all(str(r[k]) == v for k, v in filters.items() if k in r)]
        out.append(table_text(t, rows))
    if len(named) > 1:
        out.insert(0, "-- note: rows shown per table (filters on customer_id/order_id/item_id applied), joins not evaluated")
    print("\n\n".join(out))
    return 0


def main() -> int:
    base, tool, args = Path(sys.argv[1]), sys.argv[2], sys.argv[3:]
    db = load_db(base)
    if tool == "ro-sql":
        return sql(db, args)
    if tool == "ro-pg":
        print("(0 rows)")
        return 0
    if tool == "ro-es":
        print(json.dumps({"hits": {"total": {"value": 0}, "hits": []}}))
        return 0
    if tool == "board":
        if args[:1] == ["add"]:
            print(f"added: {' '.join(args[1:4])} -> item #101")
        else:
            print("ok")
        return 0
    print(f"{tool}: unknown")
    return 1


if __name__ == "__main__":
    sys.exit(main())
