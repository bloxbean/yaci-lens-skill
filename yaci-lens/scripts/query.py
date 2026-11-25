#!/usr/bin/env python3
"""Run SQL against the public Cardano lake (Yaci Lens data) with the duckdb Python package.

    python3 scripts/query.py "SELECT count(*) FROM block WHERE date = DATE '2026-11-24'"
    python3 scripts/query.py --csv -f query.sql

Same setup as query.sh: the catalog is attached as `lake` (default database) and `lake_meta`, the session time zone
is UTC, and getvariable('summary') is the summary-pack folder. Needs `pip install "duckdb>=1.5"`.
"""
import argparse
import os
import sys

try:
    import duckdb
except ImportError:
    sys.exit('the duckdb package is missing: pip install "duckdb>=1.5"')

CATALOG = os.environ.get("LENS_CATALOG_URL", "https://data.bloxbean.org/mainnet/v1/catalog.ducklake")
SUMMARY = os.environ.get("LENS_SUMMARY_URL", "https://data.bloxbean.org/mainnet/v1/summary/")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("sql", nargs="?")
    ap.add_argument("-f", "--file")
    ap.add_argument("--csv", action="store_true")
    ap.add_argument("--max-rows", type=int, default=200)
    a = ap.parse_args()
    sql = open(a.file).read() if a.file else a.sql
    if not sql:
        ap.error("give SQL or -f file.sql")
    major, minor = (int(x) for x in duckdb.__version__.split(".")[:2])
    if (major, minor) < (1, 5):
        sys.exit(f"duckdb {duckdb.__version__} is too old for the catalog; need 1.5 or newer")

    con = duckdb.connect()
    con.execute("INSTALL ducklake; LOAD ducklake; SET TimeZone = 'UTC'")
    con.execute(f"SET VARIABLE summary = '{SUMMARY}'")
    con.execute(f"ATTACH '{CATALOG}' AS lake (TYPE ducklake, READ_ONLY)")
    con.execute(f"ATTACH '{CATALOG}' AS lake_meta (READ_ONLY)")
    con.execute("USE lake")

    rel = con.sql(sql)
    if rel is None:
        return
    if a.csv:
        import csv

        w = csv.writer(sys.stdout)
        w.writerow(rel.columns)
        for row in rel.fetchall():
            w.writerow(row)
    else:
        rel.show(max_rows=a.max_rows, max_width=200)


if __name__ == "__main__":
    main()
