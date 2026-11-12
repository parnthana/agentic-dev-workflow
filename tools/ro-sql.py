#!/usr/bin/env python3
"""ro-sql — READ-ONLY queries against an Oracle database.

Read-only is enforced twice: only a single SELECT / WITH statement is accepted, and the session runs
SET TRANSACTION READ ONLY first, so Oracle itself rejects any write (ORA-01456). The statement check alone is
not enough (a SELECT can call a function that writes); the transaction mode alone is not enough (it would let
an agent attempt DDL/DML and see the error). Keep both.

Credentials are never stored by this tool and never hard-coded. Either:
  * environment: RO_SQL_HOST, RO_SQL_USER, RO_SQL_PASSWORD, optional RO_SQL_PORT (1521),
    RO_SQL_SERVICE (service name) and/or RO_SQL_SID; or
  * RO_SQL_SECRET_CMD: a shell command that prints ONE JSON object on stdout with the keys
    host, user, password and optionally port, service, sid. It runs with RO_ENV=<dev|prod> in its environment,
    so one command can fetch per-environment secrets from whatever vault you use. Environment variables,
    when set, win over the command's values.

usage: ro-sql --env dev|prod "<SQL>" [--max N] [--csv|--json]
       ro-sql --env dev|prod -f query.sql
Requires: pip install oracledb
"""
import argparse, csv, datetime, decimal, json, os, re, subprocess, sys

import oracledb


def die(msg, code=2):
    print(f"ro-sql: {msg}", file=sys.stderr)
    sys.exit(code)


def only_select(sql: str) -> str:
    s = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)          # block comments
    s = re.sub(r"--[^\n]*", " ", s).strip().rstrip(";").strip()
    if not s:
        die("empty query")
    if ";" in s:
        die("one statement only")
    if not re.match(r"(?is)^(select|with)\b", s):
        die("read-only: only SELECT / WITH queries (run writes through a privileged client, on purpose)")
    return s


def cell(v):
    if v is None:
        return None
    if isinstance(v, (datetime.datetime, datetime.date)):
        return v.isoformat(sep=" ") if isinstance(v, datetime.datetime) else v.isoformat()
    if isinstance(v, decimal.Decimal):
        return int(v) if v == v.to_integral_value() else float(v)
    if isinstance(v, oracledb.LOB):
        return v.read()
    if isinstance(v, bytes):
        return v.hex()
    return v


def credentials(env: str) -> dict:
    cfg = {}
    cmd = os.environ.get("RO_SQL_SECRET_CMD")
    if cmd:
        try:
            out = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True,
                                 env={**os.environ, "RO_ENV": env}, timeout=30).stdout
            cfg = json.loads(out)
        except (subprocess.SubprocessError, ValueError) as ex:
            die(f"RO_SQL_SECRET_CMD failed: {type(ex).__name__}")   # never echo output: it may hold the password
    e = os.environ
    pick = lambda key, env_name: e.get(env_name) or cfg.get(key)
    return dict(host=pick("host", "RO_SQL_HOST"), port=pick("port", "RO_SQL_PORT") or "1521",
                user=pick("user", "RO_SQL_USER"), password=pick("password", "RO_SQL_PASSWORD"),
                sid=pick("sid", "RO_SQL_SID"), service=pick("service", "RO_SQL_SERVICE"))


def main():
    ap = argparse.ArgumentParser(prog="ro-sql")
    ap.add_argument("--env", required=True, choices=["dev", "prod"])
    ap.add_argument("sql", nargs="?")
    ap.add_argument("-f", "--file")
    ap.add_argument("--max", type=int, default=200, help="max rows printed (default 200)")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--csv", action="store_true")
    g.add_argument("--json", action="store_true")
    a = ap.parse_args()

    sql = open(a.file).read() if a.file else a.sql
    if not sql:
        die('give "<SQL>" or -f file.sql')
    sql = only_select(sql)

    c = credentials(a.env)
    if not (c["host"] and c["user"] and c["password"]):
        die("no credentials — set RO_SQL_HOST/USER/PASSWORD or RO_SQL_SECRET_CMD (see the docstring)")

    params = dict(user=c["user"], password=c["password"], tcp_connect_timeout=8)
    dsns = []
    if c["service"]:
        dsns.append(oracledb.makedsn(c["host"], int(c["port"]), service_name=c["service"]))
    dsns.append(oracledb.makedsn(c["host"], int(c["port"]), sid=c["sid"] or c["service"] or "ORCL"))
    conn, err = None, None
    for dsn in dsns:
        try:
            conn = oracledb.connect(dsn=dsn, **params)
            break
        except oracledb.Error as ex:
            err = ex
    if conn is None:
        hint = " (is the VPN connected?)" if a.env == "prod" else ""
        die(f"connect failed{hint}: {str(err).splitlines()[0]}", 1)

    # prod reads are cap-limited to 30 s so a bad plan can't load the live database
    conn.call_timeout = 30_000 if a.env == "prod" else 120_000
    cur = conn.cursor()
    cur.execute("SET TRANSACTION READ ONLY")
    try:
        cur.execute(sql)
    except oracledb.Error as ex:
        die(str(ex).splitlines()[0], 1)
    cols = [d[0] for d in cur.description]
    rows = [[cell(v) for v in r] for r in cur.fetchmany(a.max + 1)]
    more = len(rows) > a.max
    rows = rows[: a.max]
    conn.rollback()
    conn.close()

    if a.json:
        print(json.dumps([dict(zip(cols, r)) for r in rows], ensure_ascii=False, default=str, indent=1))
    elif a.csv:
        w = csv.writer(sys.stdout)
        w.writerow(cols)
        w.writerows(rows)
    else:
        txt = [["" if v is None else str(v).replace("\n", " ")[:80] for v in r] for r in rows]
        width = [max([len(c)] + [len(r[i]) for r in txt]) for i, c in enumerate(cols)]
        print("  ".join(c.ljust(width[i]) for i, c in enumerate(cols)))
        print("  ".join("-" * w for w in width))
        for r in txt:
            print("  ".join(v.ljust(width[i]) for i, v in enumerate(r)))
    sys.stdout.flush()
    print(f"-- {len(rows)} row(s){' (more — raise --max)' if more else ''} · {a.env}", file=sys.stderr)


if __name__ == "__main__":
    main()
