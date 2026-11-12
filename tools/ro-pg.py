#!/usr/bin/env python3
"""ro-pg — READ-ONLY queries against a PostgreSQL database.

Read-only is enforced twice: only a single SELECT / WITH / SHOW / TABLE / VALUES / EXPLAIN (not ANALYZE)
statement is accepted, and the session runs with default_transaction_read_only=on, so Postgres itself
rejects any write (including writes hidden in a CTE or a volatile function).

Connection is never stored or hard-coded. Either:
  * environment: RO_PG_URL (postgres://…) or RO_PG_HOST, RO_PG_DB, RO_PG_USER, RO_PG_PASSWORD (+ RO_PG_PORT),
    optional RO_PG_SCHEMA (put first on search_path); or
  * RO_PG_SECRET_CMD: a shell command that prints ONE JSON object with either `url`, or host/db/user/password
    (+ optional port, schema). It runs with RO_ENV=<dev|prod> and RO_SERVICE=<--service value> in its
    environment so one command can resolve any service's database from your vault.
    Environment variables, when set, win over the command's values.

usage: ro-pg [--env dev|prod] [--service NAME] "<SQL>" [--max N] [--csv|--json]
       ro-pg -f query.sql
Requires: pip install "psycopg[binary]"
"""
import argparse, csv, datetime, decimal, json, os, re, subprocess, sys, urllib.parse, uuid

import psycopg


def die(msg, code=2):
    print(f"ro-pg: {msg}", file=sys.stderr)
    sys.exit(code)


def only_read(sql: str) -> str:
    s = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    s = re.sub(r"--[^\n]*", " ", s).strip().rstrip(";").strip()
    if not s:
        die("empty query")
    if ";" in s:
        die("one statement only")
    if not re.match(r"(?is)^(select|with|show|table|values|explain)\b", s):
        die("read-only: only SELECT / WITH / SHOW / EXPLAIN (writes go through a migration or a privileged client)")
    if re.match(r"(?is)^explain\b.*\banalyze\b", s):
        die("EXPLAIN ANALYZE executes the statement — use plain EXPLAIN")
    return s


def cell(v):
    if isinstance(v, (datetime.datetime, datetime.date, datetime.time)):
        return v.isoformat(sep=" ") if isinstance(v, datetime.datetime) else v.isoformat()
    if isinstance(v, decimal.Decimal):
        return int(v) if v == v.to_integral_value() else float(v)
    if isinstance(v, uuid.UUID):
        return str(v)
    if isinstance(v, (bytes, memoryview)):
        return bytes(v).hex()
    return v


def secret(env: str, service: str) -> dict:
    cmd = os.environ.get("RO_PG_SECRET_CMD")
    if not cmd:
        return {}
    try:
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True, timeout=30,
                             env={**os.environ, "RO_ENV": env, "RO_SERVICE": service}).stdout
        return json.loads(out)
    except (subprocess.SubprocessError, ValueError) as ex:
        die(f"RO_PG_SECRET_CMD failed: {type(ex).__name__}")   # never echo output: it may hold the password


def conninfo(env: str, service: str):
    """RO_PG_URL (Prisma-style params stripped) or RO_PG_HOST/PORT/DB/USER/PASSWORD → (conninfo, schema)."""
    e, cfg = os.environ, secret(env, service)
    url = e.get("RO_PG_URL") or cfg.get("url")
    schema = e.get("RO_PG_SCHEMA") or cfg.get("schema")
    if url:
        u = urllib.parse.urlsplit(url)
        q = dict(urllib.parse.parse_qsl(u.query))
        schema = schema or q.pop("schema", None)
        keep = {k: v for k, v in q.items() if k in ("sslmode", "sslrootcert", "application_name")}
        url = urllib.parse.urlunsplit((u.scheme.replace("postgresql+asyncpg", "postgresql"), u.netloc, u.path,
                                       urllib.parse.urlencode(keep), ""))
        return url, schema
    pick = lambda key, env_name: e.get(env_name) or cfg.get(key)
    host, db, user, pw = pick("host", "RO_PG_HOST"), pick("db", "RO_PG_DB"), pick("user", "RO_PG_USER"), pick("password", "RO_PG_PASSWORD")
    if not all([host, db, user, pw]):
        die("no connection — set RO_PG_URL, RO_PG_HOST/DB/USER/PASSWORD, or RO_PG_SECRET_CMD (see the docstring)")
    return psycopg.conninfo.make_conninfo(host=host, port=pick("port", "RO_PG_PORT") or "5432",
                                          dbname=db, user=user, password=pw), schema


def main():
    ap = argparse.ArgumentParser(prog="ro-pg")
    ap.add_argument("--env", default="dev", choices=["dev", "prod"])
    ap.add_argument("--service", default="", help="passed to RO_PG_SECRET_CMD as RO_SERVICE; also shown in the footer")
    ap.add_argument("sql", nargs="?")
    ap.add_argument("-f", "--file")
    ap.add_argument("--max", type=int, default=200)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--csv", action="store_true")
    g.add_argument("--json", action="store_true")
    a = ap.parse_args()

    sql = open(a.file).read() if a.file else a.sql
    if not sql:
        die('give "<SQL>" or -f file.sql')
    sql = only_read(sql)

    info, schema = conninfo(a.env, a.service)
    # prod reads are cap-limited to 30 s so a bad plan can't load the live database
    prod = a.env == "prod"
    opts = f"-c default_transaction_read_only=on -c statement_timeout={30000 if prod else 120000}"
    if schema:
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", schema):
            die("schema name must be a plain identifier")
        opts += f" -c search_path={schema},public"
    try:
        conn = psycopg.connect(info, options=opts, connect_timeout=8, application_name="ro-pg")
    except psycopg.Error as ex:
        die(f"connect failed (prod usually needs the VPN): {str(ex).strip().splitlines()[0]}", 1)
    with conn:
        cur = conn.cursor()
        try:
            cur.execute(sql)
        except psycopg.Error as ex:
            die(str(ex).strip().splitlines()[0], 1)
        cols = [d.name for d in cur.description] if cur.description else []
        rows = [[cell(v) for v in r] for r in cur.fetchmany(a.max + 1)] if cols else []
        conn.rollback()
    more = len(rows) > a.max
    rows = rows[: a.max]

    if a.json:
        print(json.dumps([dict(zip(cols, r)) for r in rows], ensure_ascii=False, default=str, indent=1))
    elif a.csv:
        w = csv.writer(sys.stdout)
        w.writerow(cols)
        w.writerows(rows)
    else:
        txt = [["" if v is None else (json.dumps(v, ensure_ascii=False, default=str) if isinstance(v, (dict, list)) else str(v)).replace("\n", " ")[:80] for v in r] for r in rows]
        width = [max([len(c)] + [len(r[i]) for r in txt]) for i, c in enumerate(cols)]
        print("  ".join(c.ljust(width[i]) for i, c in enumerate(cols)))
        print("  ".join("-" * w for w in width))
        for r in txt:
            print("  ".join(v.ljust(width[i]) for i, v in enumerate(r)))
    sys.stdout.flush()
    print(f"-- {len(rows)} row(s){' (more — raise --max)' if more else ''} · {a.service or 'db'} · {a.env}", file=sys.stderr)


if __name__ == "__main__":
    main()
